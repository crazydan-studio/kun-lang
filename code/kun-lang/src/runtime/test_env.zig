const std = @import("std");
const env_mod = @import("env.zig");
const value_mod = @import("value.zig");

const Frame = env_mod.Frame;
const Value = value_mod.Value;

test "frame lookup returns null for unknown name" {
    var frame = Frame{ .bindings = .empty, .parent = null, .primitives = null };
    try std.testing.expectEqual(@as(?Value, null), frame.lookup("x"));
}

test "frame bind and lookup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var frame = Frame{ .bindings = .empty, .parent = null, .primitives = null };
    try frame.bindings.put(allocator, "x", Value{ .int = 42 });

    const val = frame.lookup("x");
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(i64, 42), val.?.int);
}

test "frame chain lookup traverses parent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parent = Frame{ .bindings = .empty, .parent = null, .primitives = null };
    try parent.bindings.put(allocator, "parent_var", Value{ .int = 10 });

    var child = Frame{ .bindings = .empty, .parent = &parent, .primitives = null };
    try child.bindings.put(allocator, "child_var", Value{ .int = 20 });

    try std.testing.expectEqual(@as(i64, 10), child.lookup("parent_var").?.int);
    try std.testing.expectEqual(@as(i64, 20), child.lookup("child_var").?.int);
    try std.testing.expectEqual(@as(?Value, null), child.lookup("unknown"));
}

test "frame shadowing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parent = Frame{ .bindings = .empty, .parent = null, .primitives = null };
    try parent.bindings.put(allocator, "x", Value{ .int = 1 });

    var child = Frame{ .bindings = .empty, .parent = &parent, .primitives = null };
    try child.bindings.put(allocator, "x", Value{ .int = 2 });

    try std.testing.expectEqual(@as(i64, 2), child.lookup("x").?.int);
}
