const std = @import("std");

pub fn ConcurrentQueue(comptime ValueType: type) type {
    return struct {
        pub const Node = struct {
            next: ?*Node = null,
            data: ?ValueType,

            pub fn sentinel(allocator: std.mem.Allocator) !*Node {
                const self = try allocator.create(Node);
                self.* = .{ .data = null };

                return self;
            }

            pub fn init(allocator: std.mem.Allocator, data: ValueType) !*Node {
                const self = try allocator.create(Node);
                self.* = .{ .data = data };

                return self;
            }

            pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
                allocator.destroy(self);
            }
        };
        
        head: std.atomic.Value(*Node),
        tail: std.atomic.Value(*Node),
        sentinel: *Node,
        len: std.atomic.Value(usize),

        const Self = @This();

        pub fn init(sentinel: *Node) Self {
            return .{
                .head = std.atomic.Value(*Node).init(sentinel),
                .tail = std.atomic.Value(*Node).init(sentinel),
                .sentinel = sentinel,
                .len = std.atomic.Value(usize).init(0),
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.sentinel.deinit(allocator);
        }

        /// Enqueue entry
        pub fn enqueue(self: *Self, new_node: *Node) void {
            var tail: *Node = undefined;
            var backoff: u64 = 1;

            while (true) {
                tail = self.tail.load(.acquire);
                const next_opt = tail.next;

                if (next_opt) |next| {
                    _ = self.tail.cmpxchgStrong(tail, next, .release, .monotonic);
                }
                else {
                    if (@cmpxchgWeak(?*Node, &tail.next, next_opt, new_node, .release, .monotonic) == null) {
                        break;
                    }
                }

                // Wait for a while (Exponential Back-off)
                std.time.sleep(backoff);
                backoff = @min(backoff * 2, 100);
            }

            _ = self.tail.cmpxchgWeak(tail, new_node, .release, .monotonic);
            _ = self.len.fetchAdd(1, .release);
        }

        /// Dequeue entry
        pub fn dequeue(self: *Self) ?*Node {
            var backoff: u64 = 1;

            while (true) {
                const head = self.head.load(.acquire);
                const tail = self.tail.load(.acquire);
                const next_opt = head.next;

                if (head == tail) {
                    if (next_opt) |next| {
                        _ = self.tail.cmpxchgStrong(tail, next, .release, .monotonic);
                    }
                    else {
                        if (self.tail.cmpxchgStrong(tail,  self.sentinel, .release, .monotonic) == null) {
                            return null;
                        }
                    }                  
                }
                else {
                    const next = if (next_opt) |x| x.next else null;
                    if (@cmpxchgWeak(?*Node, &head.next, next_opt, next, .acq_rel, .monotonic) == null) {
                        if (next_opt) |x| {
                            _ = self.tail.cmpxchgStrong(x, self.sentinel, .acq_rel, .monotonic);
                        }

                        _ = self.len.fetchSub(1, .acq_rel);
                        return next_opt;
                    }
                }

                // Wait for a while (Exponential Back-off)
                std.time.sleep(backoff);
                backoff = @min(backoff * 2, 100); 
            }
        }

        pub fn hasEntry(self: *Self) bool {
            return self.length() > 0;
        }

        pub fn length(self: Self) usize {
            return self.len.load(.acquire);
        }
    };
}

const TestsQueue = ConcurrentQueue(u32);

test "dequeue from empty" {
    const allocator = std.testing.allocator;
    var q = TestsQueue.init(try TestsQueue.Node.sentinel(allocator));
    defer q.deinit(allocator);

    try std.testing.expectEqual(0, q.length());
    try std.testing.expectEqual(null, q.dequeue());
}

test "single thread" {
    const allocator = std.testing.allocator;
    var q = TestsQueue.init(try TestsQueue.Node.sentinel(allocator));
    defer q.deinit(allocator);

    try std.testing.expectEqual(0, q.length());

    const e1 = enqueue: {
        const node = try TestsQueue.Node.init(allocator, 11);
        q.enqueue(node);
        try std.testing.expectEqual(q.length(), 1);
        break:enqueue node;
    };
    defer e1.deinit(allocator);

    const e2 = enqueue: {
        const node = try TestsQueue.Node.init(allocator, 22);
        q.enqueue(node);
        try std.testing.expectEqual(q.length(), 2);
        break:enqueue node;
    };
    defer e2.deinit(allocator);

    const e3 = enqueue: {
        const node = try TestsQueue.Node.init(allocator, 33);
        q.enqueue(node);
        try std.testing.expectEqual(q.length(), 3);
        break:enqueue node;
    };
    defer e3.deinit(allocator);

    dequeue: {
        const node = q.dequeue();
        try std.testing.expect(node != null);
        try std.testing.expect(node.?.data != null);
        try std.testing.expectEqual(11, node.?.data.?);
        try std.testing.expectEqual(q.length(), 2);
        break:dequeue;
    }
    dequeue: {
        const node = q.dequeue();
        try std.testing.expect(node != null);
        try std.testing.expect(node.?.data != null);
        try std.testing.expectEqual(22, node.?.data.?);
        try std.testing.expectEqual(q.length(), 1);
        break:dequeue;
    }
    dequeue: {
        const node = q.dequeue();
        try std.testing.expect(node != null);
        try std.testing.expect(node.?.data != null);
        try std.testing.expectEqual(33, node.?.data.?);
        try std.testing.expectEqual(q.length(), 0);
        break:dequeue;
    }
    dequeue: {
        const node = q.dequeue();
        try std.testing.expectEqual(null, node);
        try std.testing.expectEqual(q.length(), 0);
        break:dequeue;
    }
}

const SyncObject = struct {
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,

    pub fn init() SyncObject {
        return .{
            .mutex = std.Thread.Mutex{},
            .condition = std.Thread.Condition{},
        };
    }
};

fn runEnqueue(allocator: std.mem.Allocator, q: *TestsQueue, sync_obj: *SyncObject, enqueue_count: usize) !void {
    for (0..enqueue_count) |_| {
        std.time.sleep(1);
        sync_obj.mutex.lock();
        defer sync_obj.mutex.unlock();
        const node = try TestsQueue.Node.init(allocator, 42);
        q.enqueue(node);
        sync_obj.condition.broadcast();
    }
}

test "multi thread" {
    const allocator = std.testing.allocator;
    var q = TestsQueue.init(try TestsQueue.Node.sentinel(allocator));
    defer q.deinit(allocator);

    try std.testing.expectEqual(0, q.length());
    
    var sync_obj = SyncObject.init();

    const th1 = try std.Thread.spawn(.{.allocator = allocator}, runEnqueue, .{allocator, &q, &sync_obj, 2});
    const th2 = try std.Thread.spawn(.{.allocator = allocator}, runEnqueue, .{allocator, &q, &sync_obj, 2});
    const th3 = try std.Thread.spawn(.{.allocator = allocator}, runEnqueue, .{allocator, &q, &sync_obj, 2});

    dequeue: {
        sync_obj.mutex.lock();
        defer sync_obj.mutex.unlock();

        while (!q.hasEntry()) {
            sync_obj.condition.wait(&sync_obj.mutex);
        }
    
        try std.testing.expectEqual(true, q.hasEntry());
        const node = q.dequeue();
        defer node.?.deinit(allocator);

        try std.testing.expect(node != null);
        try std.testing.expect(node.?.data != null);
        break:dequeue;
    }
    dequeue: {
        sync_obj.mutex.lock();
        defer sync_obj.mutex.unlock();

        while (!q.hasEntry()) {
            sync_obj.condition.wait(&sync_obj.mutex);
        }
    
        try std.testing.expectEqual(true, q.hasEntry());
        const node = q.dequeue();
        defer node.?.deinit(allocator);
        
        try std.testing.expect(node != null);
        try std.testing.expect(node.?.data != null);
        break:dequeue;
    }
    dequeue: {
        sync_obj.mutex.lock();
        defer sync_obj.mutex.unlock();

        while (!q.hasEntry()) {
            sync_obj.condition.wait(&sync_obj.mutex);
        }
    
        try std.testing.expectEqual(true, q.hasEntry());
        const node = q.dequeue();
        defer node.?.deinit(allocator);
        
        try std.testing.expect(node != null);
        try std.testing.expect(node.?.data != null);
        break:dequeue;
    }
    dequeue: {
        sync_obj.mutex.lock();
        defer sync_obj.mutex.unlock();

        while (!q.hasEntry()) {
            sync_obj.condition.wait(&sync_obj.mutex);
        }
    
        try std.testing.expectEqual(true, q.hasEntry());
        const node = q.dequeue();
        defer node.?.deinit(allocator);
        
        try std.testing.expect(node != null);
        try std.testing.expect(node.?.data != null);
        break:dequeue;
    }
    dequeue: {
        sync_obj.mutex.lock();
        defer sync_obj.mutex.unlock();

        while (!q.hasEntry()) {
            sync_obj.condition.wait(&sync_obj.mutex);
        }
    
        try std.testing.expectEqual(true, q.hasEntry());
        const node = q.dequeue();
        defer node.?.deinit(allocator);
        
        try std.testing.expect(node != null);
        try std.testing.expect(node.?.data != null);
        break:dequeue;
    }
    dequeue: {
        sync_obj.mutex.lock();
        defer sync_obj.mutex.unlock();

        while (!q.hasEntry()) {
            sync_obj.condition.wait(&sync_obj.mutex);
        }
    
        try std.testing.expectEqual(true, q.hasEntry());
        const node = q.dequeue();
        defer node.?.deinit(allocator);
        
        try std.testing.expect(node != null);
        try std.testing.expect(node.?.data != null);
        break:dequeue;
    }
    dequeue: {
        const node = q.dequeue();
        try std.testing.expectEqual(null, node);
        try std.testing.expectEqual(q.length(), 0);
        break:dequeue;
    }

    th1.join();
    th2.join();
    th3.join();
}