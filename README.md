# zig-concurrent-queue
Lock free/wait free conncurrent queue for Zig.

This queue is built with Michael Scott algorithm.

https://www.cs.rochester.edu/u/scott/papers/1996_PODC_queues.pdf

## Requirement

* Zig (https://ziglang.org/): version 0.14.0 or latter

## Installation

```
zig fetch --save=concurrent_queue https://github.com/ritalin/zig-concurrent-queue
```

Build setup:
```zig
const dep = b.dependency("concurrent_queue", .{});

const exe = b.addExecutable(...);
exe.root_module.addImport("concurrent_queue", dep.module("concurrent_queue"));
```

## Example

```zig
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
```

> [!WARNING]
> This queue is not synchronization automatically between threads.
> Therefore, you need to use the synchronization primitive (`std.Thread.Condition`, `std.Thread.Semaphore`, etc ) yourself.
