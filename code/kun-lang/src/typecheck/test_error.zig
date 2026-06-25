const std = @import("std");
const ast = @import("../ast/ast.zig");
const error_mod = @import("error.zig");
const ErrorList = error_mod.ErrorList;
const TypeError = error_mod.TypeError;

test "error type function_apply_arg" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .function_apply_arg = .{ .func_name = "map", .expected = 1, .found = 0, .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type function_apply_arg with valid span" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const span = ast.Span{ .file = "test.kun", .line_start = 5, .col_start = 10, .line_end = 5, .col_end = 15, .source = "map 1" };
    try errors.add(std.testing.allocator, .{ .function_apply_arg = .{ .func_name = "map", .expected = 1, .found = 0, .span = span } });
    try std.testing.expect(errors.hasErrors());
    try std.testing.expectEqualStrings("test.kun", errors.items.items[0].function_apply_arg.span.file);
    try std.testing.expectEqual(@as(u32, 5), errors.items.items[0].function_apply_arg.span.line_start);
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

test "error type command_not_consumed with span" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const span = ast.Span{ .file = "test.kun", .line_start = 10, .col_start = 0, .line_end = 10, .col_end = 8, .source = "Cmd.echo" };
    try errors.add(std.testing.allocator, .{ .command_not_consumed = .{ .cmd_name = "echo", .span = span } });
    try std.testing.expect(errors.hasErrors());
    try std.testing.expectEqual(@as(u32, 10), errors.items.items[0].command_not_consumed.span.line_start);
    try std.testing.expectEqualStrings("echo", errors.items.items[0].command_not_consumed.cmd_name);
}

test "error type stream_not_consumed" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .stream_not_consumed = undefined });
    try std.testing.expect(errors.hasErrors());
}

test "error type stream_not_consumed with span" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const span = ast.Span{ .file = "test.kun", .line_start = 3, .col_start = 0, .line_end = 3, .col_end = 10, .source = "stream |> f" };
    try errors.add(std.testing.allocator, .{ .stream_not_consumed = span });
    try std.testing.expect(errors.hasErrors());
    try std.testing.expectEqual(@as(u32, 3), errors.items.items[0].stream_not_consumed.line_start);
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

test "error type pure_unit_return with span" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const span = ast.Span{ .file = "test.kun", .line_start = 1, .col_start = 0, .line_end = 1, .col_end = 20, .source = "do\n  42\n" };
    try errors.add(std.testing.allocator, .{ .pure_unit_return = .{ .func_name = "compute", .span = span } });
    try std.testing.expect(errors.hasErrors());
    try std.testing.expectEqualStrings("compute", errors.items.items[0].pure_unit_return.func_name);
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

test "error type unused_binding" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .unused_binding = .{ .name = "unused", .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type unused_result" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .unused_result = undefined });
    try std.testing.expect(errors.hasErrors());
}

test "error type pure_expr_last" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .pure_expr_last = undefined });
    try std.testing.expect(errors.hasErrors());
}

test "error type mismatch" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .mismatch = .{ .expected = 0, .found = 3, .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type not_a_function" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .not_a_function = .{ .found = 0, .span = undefined } });
    try std.testing.expect(errors.hasErrors());
}

test "error type unbound_variable with span" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const span = ast.Span{ .file = "test.kun", .line_start = 2, .col_start = 5, .line_end = 2, .col_end = 17, .source = "undefined_var" };
    try errors.add(std.testing.allocator, .{ .unbound_variable = .{ .name = "undefined_var", .span = span } });
    try std.testing.expect(errors.hasErrors());
    try std.testing.expectEqualStrings("undefined_var", errors.items.items[0].unbound_variable.name);
    try std.testing.expectEqual(@as(u32, 2), errors.items.items[0].unbound_variable.span.line_start);
}

test "error type multiple errors in list" {
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try errors.add(std.testing.allocator, .{ .mismatch = .{ .expected = 0, .found = 1, .span = undefined } });
    try errors.add(std.testing.allocator, .{ .duplicate_binding = .{ .name = "x", .span = undefined } });
    try errors.add(std.testing.allocator, .{ .unused_binding = .{ .name = "y", .span = undefined } });
    try std.testing.expect(errors.hasErrors());
    try std.testing.expectEqual(@as(usize, 3), errors.items.items.len);
}
