const std = @import("std");
const typed = @import("../ast/typed.zig");
const defer_mod = @import("defer.zig");

const DeferStack = defer_mod.DeferStack;

test "defer stack init empty" {
    var stack = DeferStack.init(std.testing.allocator);
    defer stack.deinit();
    try std.testing.expect(stack.isEmpty());
}

test "defer stack push and isEmpty" {
    var stack = DeferStack.init(std.testing.allocator);
    defer stack.deinit();

    const e = try std.testing.allocator.create(typed.TypedExpr);
    e.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    try stack.push(e);
    try std.testing.expect(!stack.isEmpty());
    std.testing.allocator.destroy(e);
}

test "defer stack pop returns last pushed LIFO" {
    var stack = DeferStack.init(std.testing.allocator);
    defer stack.deinit();

    const e1 = try std.testing.allocator.create(typed.TypedExpr);
    e1.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const e2 = try std.testing.allocator.create(typed.TypedExpr);
    e2.* = .{ .int_literal = .{ .value = 2, .type_ = 0, .span = undefined } };

    try stack.push(e1);
    try stack.push(e2);

    const popped = stack.pop();
    try std.testing.expect(popped != null);
    try std.testing.expectEqual(@as(i64, 2), popped.?.int_literal.value);
    std.testing.allocator.destroy(@constCast(popped.?));

    const popped2 = stack.pop();
    try std.testing.expect(popped2 != null);
    try std.testing.expectEqual(@as(i64, 1), popped2.?.int_literal.value);
    std.testing.allocator.destroy(@constCast(popped2.?));
}

test "defer stack pop on empty returns null" {
    var stack = DeferStack.init(std.testing.allocator);
    defer stack.deinit();
    try std.testing.expectEqual(@as(?*const typed.TypedExpr, null), stack.pop());
}

test "defer stack LIFO order" {
    var stack = DeferStack.init(std.testing.allocator);
    defer stack.deinit();

    const e1 = try std.testing.allocator.create(typed.TypedExpr);
    e1.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const e2 = try std.testing.allocator.create(typed.TypedExpr);
    e2.* = .{ .int_literal = .{ .value = 2, .type_ = 0, .span = undefined } };
    const e3 = try std.testing.allocator.create(typed.TypedExpr);
    e3.* = .{ .int_literal = .{ .value = 3, .type_ = 0, .span = undefined } };

    try stack.push(e1);
    try stack.push(e2);
    try stack.push(e3);

    const p3 = stack.pop().?;
    try std.testing.expectEqual(@as(i64, 3), p3.int_literal.value);
    std.testing.allocator.destroy(@constCast(p3));
    const p2 = stack.pop().?;
    try std.testing.expectEqual(@as(i64, 2), p2.int_literal.value);
    std.testing.allocator.destroy(@constCast(p2));
    const p1 = stack.pop().?;
    try std.testing.expectEqual(@as(i64, 1), p1.int_literal.value);
    std.testing.allocator.destroy(@constCast(p1));
    try std.testing.expect(stack.isEmpty());
}
