const std = @import("std");
const ConcurrentQueue = @import("concurrent_queue").ConcurrentQueue(i32);

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var q = ConcurrentQueue.init(try ConcurrentQueue.Node.sentinel(allocator));
    defer q.deinit(allocator);

    const nd_1 = try ConcurrentQueue.Node.init(allocator, 10);
    defer nd_1.deinit(allocator);
    q.enqueue(nd_1);

    const nd_2 = try ConcurrentQueue.Node.init(allocator, 20);
    defer nd_2.deinit(allocator);
    q.enqueue(nd_2);

    const nd_3 = try ConcurrentQueue.Node.init(allocator, 30);
    defer nd_3.deinit(allocator);
    q.enqueue(nd_3);

    if (q.dequeue()) |node| {
        std.debug.print("node#1: {?}\n", .{node.data});
    }
    if (q.dequeue()) |node| {
        std.debug.print("node#2: {?}\n", .{node.data});
    }
    if (q.dequeue()) |node| {
        std.debug.print("node#3: {?}\n", .{node.data});
    }
    if (q.dequeue()) |_| {
        unreachable;
    }
}