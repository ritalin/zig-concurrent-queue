const std = @import("std");

pub usingnamespace @import("./ConcurrentQueue.zig");

test "btest entry point" {
    std.testing.refAllDecls(@This());
}
