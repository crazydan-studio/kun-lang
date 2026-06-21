const std = @import("std");
const error_mod = @import("error.zig");
const ErrorList = error_mod.ErrorList;

test "error list init empty" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try std.testing.expect(!errors.hasErrors());
}

test "error list add and hasErrors" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    try errors.add(std.testing.allocator, .{ .mismatch = .{ .expected = 0, .found = 1, .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error list multiple adds" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    try errors.add(std.testing.allocator, .{ .unbound_variable = "x" });
    try errors.add(std.testing.allocator, .{ .infinite_type = undefined });
    try std.testing.expect(errors.hasErrors());
    try std.testing.expectEqual(@as(usize, 2), errors.items.items.len);
}
