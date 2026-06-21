const std = @import("std");
const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");
const pattern_mod = @import("pattern.zig");

test "checkExhaustive empty branches returns missing" {
    const branches: [0]typed.Branch = .{};
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, 0, &branches);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 1), result.?.len);
    try std.testing.expectEqualStrings("_", result.?[0]);
}

test "checkExhaustive wildcard returns null" {
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .wildcard = undefined }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, 0, &branches);
    try std.testing.expectEqual(@as(?[][]const u8, null), result);
}

test "checkExhaustive ident variable treated as wildcard" {
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "x", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, 0, &branches);
    try std.testing.expectEqual(@as(?[][]const u8, null), result);
}

test "checkExhaustive only uppercase ident returns missing" {
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "Ok", .span = undefined } }, .body = body, .type_ = 0 },
        .{ .pattern = .{ .ident = .{ .name = "Err", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, 0, &branches);
    try std.testing.expect(result != null);
}

test "checkExhaustive mixed adt and wildcard" {
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "Ok", .span = undefined } }, .body = body, .type_ = 0 },
        .{ .pattern = .{ .wildcard = undefined }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, 0, &branches);
    try std.testing.expectEqual(@as(?[][]const u8, null), result);
}

test "narrowType wildcard returns scrutinee type" {
    const pat = ast.Pattern{ .wildcard = undefined };
    const narrowed = try pattern_mod.narrowType(pat, 5, {}, std.testing.allocator);
    try std.testing.expectEqual(@as(typed.TypeId, 5), narrowed);
}

test "narrowType guard delegates to inner" {
    const inner = try std.testing.allocator.create(ast.Pattern);
    defer std.testing.allocator.destroy(inner);
    inner.* = .{ .wildcard = undefined };
    const pat = ast.Pattern{ .guard = .{ .inner = inner, .cond = undefined, .span = undefined } };
    const narrowed = try pattern_mod.narrowType(pat, 7, {}, std.testing.allocator);
    try std.testing.expectEqual(@as(typed.TypeId, 7), narrowed);
}

test "checkExhaustive with two variants no wildcard" {
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "True", .span = undefined } }, .body = body, .type_ = 0 },
        .{ .pattern = .{ .ident = .{ .name = "False", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, 0, &branches);
    try std.testing.expect(result != null);
}

test "narrowType literal returns scrutinee type" {
    const lit = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(lit);
    lit.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const pat = ast.Pattern{ .literal = lit };
    const narrowed = try pattern_mod.narrowType(pat, 3, {}, std.testing.allocator);
    try std.testing.expectEqual(@as(typed.TypeId, 3), narrowed);
}

test "narrowType tuple pattern" {
    const nil_pat = ast.Pattern{ .ident = .{ .name = "Nil", .span = undefined } };
    const n_pat = ast.Pattern{ .ident = .{ .name = "n", .span = undefined } };
    const items = try std.testing.allocator.alloc(ast.Pattern, 2);
    defer std.testing.allocator.free(items);
    items[0] = nil_pat;
    items[1] = n_pat;
    const pat = ast.Pattern{ .tuple = .{ .items = items, .span = undefined } };
    const narrowed = try pattern_mod.narrowType(pat, 0, {}, std.testing.allocator);
    try std.testing.expectEqual(@as(typed.TypeId, 0), narrowed);
}

test "checkExhaustive True False without wildcard is non-exhaustive" {
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "True", .span = undefined } }, .body = body, .type_ = 0 },
        .{ .pattern = .{ .ident = .{ .name = "False", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, 0, &branches);
    try std.testing.expect(result != null);
}

test "checkExhaustive single variant True covers Bool" {
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "True", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, 0, &branches);
    try std.testing.expect(result != null);
}
