const std = @import("std");
const ConcurrentQueue = @import("concurrent_queue").ConcurrentQueue(i32);

const SyncObject = struct {
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
};

fn runEnqueue(allocator: std.mem.Allocator, q: *ConcurrentQueue, sync_obj: *SyncObject, value: i32) !void {
    {
        sync_obj.mutex.lock();
        defer sync_obj.mutex.unlock();

        const node = try ConcurrentQueue.Node.init(allocator, value);
        q.enqueue(node);

        sync_obj.cond.broadcast();
        std.time.sleep(1);
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var q = ConcurrentQueue.init(try ConcurrentQueue.Node.sentinel(allocator));
    defer q.deinit(allocator);

    var sync_obj = SyncObject{};

    var th_1 = try std.Thread.spawn(.{.allocator = allocator}, runEnqueue, .{allocator, &q, &sync_obj, 10});
    var th_2 = try std.Thread.spawn(.{.allocator = allocator}, runEnqueue, .{allocator, &q, &sync_obj, 20});

    dequeue: {
        sync_obj.mutex.lock();
        defer sync_obj.mutex.unlock();

        while (!q.hasEntry()) {
            sync_obj.cond.wait(&sync_obj.mutex);
        }

        if (q.dequeue()) |node| {
            defer node.deinit(allocator);
            std.debug.print("node#1: {?}\n", .{node.data});
        }
        break:dequeue;
    }
    dequeue: {
        sync_obj.mutex.lock();
        defer sync_obj.mutex.unlock();
        
        while (!q.hasEntry()) {
            sync_obj.cond.wait(&sync_obj.mutex);
        }

        if (q.dequeue()) |node| {
            defer node.deinit(allocator);
            std.debug.print("node#2: {?}\n", .{node.data});
        }
        break:dequeue;
    }
    dequeue: {
        if (q.dequeue()) |_| {
            unreachable;
        }
        break:dequeue;
    }

    th_1.join();
    th_2.join();
}