const std = @import("std");
const value_mod = @import("value.zig");
const Value = value_mod.Value;

pub const Frame = struct {
    bindings: std.StringHashMapUnmanaged(Value),
    parent: ?*Frame,
    primitives: ?*anyopaque,

    pub fn lookup(self: *const Frame, name: []const u8) ?Value {
        var current: ?*const Frame = self;
        while (current) |frame| {
            if (frame.bindings.get(name)) |val| return val;
            current = frame.parent;
        }
        return null;
    }

    pub fn bind(self: *Frame, allocator: std.mem.Allocator, name: []const u8, val: Value) !void {
        try self.bindings.put(allocator, name, val);
    }
};
