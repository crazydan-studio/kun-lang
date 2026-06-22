const std = @import("std");
const error_mod = @import("error.zig");
const ErrorList = error_mod.ErrorList;
const TypeError = error_mod.TypeError;

test "error type function_apply_arg" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .function_apply_arg = .{ .func_name = "map", .expected = 1, .found = 0, .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type if_branch_mismatch" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .if_branch_mismatch = .{ .then_type = 0, .else_type = 3, .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type too_many_args" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .too_many_args = .{ .func_type = 1, .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type effect_callback_mismatch" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .effect_callback_mismatch = .{ .func_name = "iter", .param = 0, .result = 6, .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type nilable_used_as_t" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .nilable_used_as_t = .{ .expected = 0, .inner_type = 0, .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type redundant_pattern" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .redundant_pattern = .{ .pattern = "_", .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type tuple_index_out_of_range" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .tuple_index_out_of_range = .{ .len = 2, .index = 5, .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type command_not_consumed" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .command_not_consumed = .{ .cmd_name = "echo", .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type stream_not_consumed" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .stream_not_consumed = undefined });
    try std.testing.expect(errors.hasErrors());
}

test "error type recursive_alias_depth" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .recursive_alias_depth = .{ .path = "A -> B -> A", .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type pure_unit_return" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .pure_unit_return = .{ .func_name = "compute", .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type effect_in_let" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .effect_in_let = .{ .called_func = "IO.println", .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type empty_body" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .empty_body = .{ .context = "do", .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type duplicate_binding" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .duplicate_binding = .{ .name = "x", .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}
