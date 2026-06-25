const std = @import("std");
const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");
const pattern_mod = @import("pattern.zig");
const env_mod = @import("env.zig");

const TypeEnv = env_mod.TypeEnv;

fn makeEnv() !TypeEnv {
    return try TypeEnv.init(std.testing.allocator);
}

test "checkExhaustive empty branches returns missing" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const branches: [0]typed.Branch = .{};
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, 0, &branches);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 1), result.?.len);
    try std.testing.expectEqualStrings("_", result.?[0]);
}

test "checkExhaustive wildcard returns null" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .wildcard = undefined }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, 0, &branches);
    try std.testing.expectEqual(@as(?[][]const u8, null), result);
}

test "checkExhaustive ident variable treated as wildcard" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "x", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, 0, &branches);
    try std.testing.expectEqual(@as(?[][]const u8, null), result);
}

test "checkExhaustive only uppercase ident returns missing" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "Ok", .span = undefined } }, .body = body, .type_ = 0 },
        .{ .pattern = .{ .ident = .{ .name = "Err", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, 0, &branches);
    try std.testing.expect(result != null);
}

test "checkExhaustive mixed adt and wildcard" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "Ok", .span = undefined } }, .body = body, .type_ = 0 },
        .{ .pattern = .{ .wildcard = undefined }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, 0, &branches);
    try std.testing.expectEqual(@as(?[][]const u8, null), result);
}

test "narrowType wildcard returns scrutinee type" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const pat = ast.Pattern{ .wildcard = undefined };
    const narrowed = try pattern_mod.narrowType(pat, 5, &env, std.testing.allocator);
    try std.testing.expectEqual(@as(typed.TypeId, 5), narrowed);
}

test "narrowType guard delegates to inner" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const inner = try std.testing.allocator.create(ast.Pattern);
    defer std.testing.allocator.destroy(inner);
    inner.* = .{ .wildcard = undefined };
    const pat = ast.Pattern{ .guard = .{ .inner = inner, .cond = undefined, .span = undefined } };
    const narrowed = try pattern_mod.narrowType(pat, 7, &env, std.testing.allocator);
    try std.testing.expectEqual(@as(typed.TypeId, 7), narrowed);
}

test "checkExhaustive with two variants no wildcard" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "True", .span = undefined } }, .body = body, .type_ = 0 },
        .{ .pattern = .{ .ident = .{ .name = "False", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, 0, &branches);
    try std.testing.expect(result != null);
}

test "narrowType literal returns scrutinee type" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const lit = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(lit);
    lit.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const pat = ast.Pattern{ .literal = lit };
    const narrowed = try pattern_mod.narrowType(pat, 3, &env, std.testing.allocator);
    try std.testing.expectEqual(@as(typed.TypeId, 3), narrowed);
}

test "narrowType tuple pattern" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const nil_pat = ast.Pattern{ .ident = .{ .name = "Nil", .span = undefined } };
    const n_pat = ast.Pattern{ .ident = .{ .name = "n", .span = undefined } };
    const items = try std.testing.allocator.alloc(ast.Pattern, 2);
    defer std.testing.allocator.free(items);
    items[0] = nil_pat;
    items[1] = n_pat;
    const pat = ast.Pattern{ .tuple = .{ .items = items, .span = undefined } };
    const narrowed = try pattern_mod.narrowType(pat, 0, &env, std.testing.allocator);
    try std.testing.expectEqual(@as(typed.TypeId, 0), narrowed);
}

test "checkExhaustive True False without wildcard is non-exhaustive" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "True", .span = undefined } }, .body = body, .type_ = 0 },
        .{ .pattern = .{ .ident = .{ .name = "False", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, 0, &branches);
    try std.testing.expect(result != null);
}

test "checkExhaustive single variant True covers Bool" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "True", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, 0, &branches);
    try std.testing.expect(result != null);
}

test "checkExhaustive ADT all variants covered" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const opt_ty = try env.registerType(std.testing.allocator, .{ .adt = .{
        .name = "Option",
        .variants = &.{
            .{ .name = "Some", .payload = &.{env_mod.int_type} },
            .{ .name = "None", .payload = &.{} },
        },
    } });
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "Some", .span = undefined } }, .body = body, .type_ = 0 },
        .{ .pattern = .{ .ident = .{ .name = "None", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, opt_ty, &branches);
    try std.testing.expectEqual(@as(?[][]const u8, null), result);
}

test "checkExhaustive ADT missing variant" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const opt_ty = try env.registerType(std.testing.allocator, .{ .adt = .{
        .name = "Option",
        .variants = &.{
            .{ .name = "Some", .payload = &.{env_mod.int_type} },
            .{ .name = "None", .payload = &.{} },
        },
    } });
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "Some", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, opt_ty, &branches);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 1), result.?.len);
    try std.testing.expectEqualStrings("None", result.?[0]);
}

test "checkExhaustive bool type both variants exhaustive" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "True", .span = undefined } }, .body = body, .type_ = 0 },
        .{ .pattern = .{ .ident = .{ .name = "False", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, env_mod.bool_type, &branches);
    try std.testing.expectEqual(@as(?[][]const u8, null), result);
}

test "checkExhaustive bool type only True is non-exhaustive" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "True", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, env_mod.bool_type, &branches);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 1), result.?.len);
}

test "checkExhaustive bool type with wildcard is exhaustive" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .wildcard = undefined }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, env_mod.bool_type, &branches);
    try std.testing.expectEqual(@as(?[][]const u8, null), result);
}

test "narrowType Nil on nilable returns scrutinee" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const nil_int = try env.registerType(std.testing.allocator, .{ .nilable = env_mod.int_type });
    const pat = ast.Pattern{ .ident = .{ .name = "Nil", .span = undefined } };
    const narrowed = try pattern_mod.narrowType(pat, nil_int, &env, std.testing.allocator);
    try std.testing.expectEqual(nil_int, narrowed);
}

test "narrowType variable on nilable narrows to inner" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const nil_int = try env.registerType(std.testing.allocator, .{ .nilable = env_mod.int_type });
    const pat = ast.Pattern{ .ident = .{ .name = "x", .span = undefined } };
    const narrowed = try pattern_mod.narrowType(pat, nil_int, &env, std.testing.allocator);
    try std.testing.expectEqual(env_mod.int_type, narrowed);
}

test "narrowType uppercase ident on ADT returns scrutinee" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const opt_ty = try env.registerType(std.testing.allocator, .{ .adt = .{
        .name = "Option",
        .variants = &.{
            .{ .name = "Some", .payload = &.{env_mod.int_type} },
            .{ .name = "None", .payload = &.{} },
        },
    } });
    const pat = ast.Pattern{ .ident = .{ .name = "Some", .span = undefined } };
    const narrowed = try pattern_mod.narrowType(pat, opt_ty, &env, std.testing.allocator);
    try std.testing.expectEqual(opt_ty, narrowed);
}

test "narrowType lowercase ident on ADT returns scrutinee" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const opt_ty = try env.registerType(std.testing.allocator, .{ .adt = .{
        .name = "Option",
        .variants = &.{
            .{ .name = "Some", .payload = &.{env_mod.int_type} },
            .{ .name = "None", .payload = &.{} },
        },
    } });
    const pat = ast.Pattern{ .ident = .{ .name = "val", .span = undefined } };
    const narrowed = try pattern_mod.narrowType(pat, opt_ty, &env, std.testing.allocator);
    try std.testing.expectEqual(opt_ty, narrowed);
}

test "narrowType variant pattern on ADT narrows to payload" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const opt_ty = try env.registerType(std.testing.allocator, .{ .adt = .{
        .name = "Option",
        .variants = &.{
            .{ .name = "Some", .payload = &.{env_mod.int_type} },
            .{ .name = "None", .payload = &.{} },
        },
    } });
    const pat = ast.Pattern{ .variant = .{ .name = "Some", .inner = null, .span = undefined } };
    const narrowed = try pattern_mod.narrowType(pat, opt_ty, &env, std.testing.allocator);
    try std.testing.expectEqual(env_mod.int_type, narrowed);
}

test "narrowType variant pattern without payload on ADT returns scrutinee" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const opt_ty = try env.registerType(std.testing.allocator, .{ .adt = .{
        .name = "Option",
        .variants = &.{
            .{ .name = "Some", .payload = &.{env_mod.int_type} },
            .{ .name = "None", .payload = &.{} },
        },
    } });
    const pat = ast.Pattern{ .variant = .{ .name = "None", .inner = null, .span = undefined } };
    const narrowed = try pattern_mod.narrowType(pat, opt_ty, &env, std.testing.allocator);
    try std.testing.expectEqual(opt_ty, narrowed);
}

test "narrowType bool True ident returns scrutinee" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const pat = ast.Pattern{ .ident = .{ .name = "True", .span = undefined } };
    const narrowed = try pattern_mod.narrowType(pat, env_mod.bool_type, &env, std.testing.allocator);
    try std.testing.expectEqual(env_mod.bool_type, narrowed);
}

test "narrowType bool False ident returns scrutinee" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const pat = ast.Pattern{ .ident = .{ .name = "False", .span = undefined } };
    const narrowed = try pattern_mod.narrowType(pat, env_mod.bool_type, &env, std.testing.allocator);
    try std.testing.expectEqual(env_mod.bool_type, narrowed);
}

test "narrowType boolean literal pattern" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const lit = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(lit);
    lit.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const pat = ast.Pattern{ .literal = lit };
    const narrowed = try pattern_mod.narrowType(pat, env_mod.bool_type, &env, std.testing.allocator);
    try std.testing.expectEqual(env_mod.bool_type, narrowed);
}

test "narrowType record pattern" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const fields = try std.testing.allocator.alloc(ast.RecordPatternField, 1);
    defer std.testing.allocator.free(fields);
    fields[0] = .{ .name = "x", .pattern = .{ .wildcard = undefined }, .span = undefined };
    const pat = ast.Pattern{ .record = fields };
    const narrowed = try pattern_mod.narrowType(pat, 5, &env, std.testing.allocator);
    try std.testing.expectEqual(@as(typed.TypeId, 5), narrowed);
}

test "narrowType or-pattern" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const left = try std.testing.allocator.create(ast.Pattern);
    defer std.testing.allocator.destroy(left);
    left.* = .{ .wildcard = undefined };
    const right = try std.testing.allocator.create(ast.Pattern);
    defer std.testing.allocator.destroy(right);
    right.* = .{ .wildcard = undefined };
    const pat = ast.Pattern{ .or_ = .{ .left = left, .right = right, .span = undefined } };
    const narrowed = try pattern_mod.narrowType(pat, 7, &env, std.testing.allocator);
    try std.testing.expectEqual(@as(typed.TypeId, 7), narrowed);
}

test "narrowType guard pattern with nil literal on nilable" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const nil_int = try env.registerType(std.testing.allocator, .{ .nilable = env_mod.int_type });
    const lit = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(lit);
    lit.* = .{ .nil_literal = undefined };
    const pat = ast.Pattern{ .literal = lit };
    const narrowed = try pattern_mod.narrowType(pat, nil_int, &env, std.testing.allocator);
    try std.testing.expectEqual(nil_int, narrowed);
}

test "narrowType guard pattern delegates to inner" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const nil_int = try env.registerType(std.testing.allocator, .{ .nilable = env_mod.int_type });
    const inner = try std.testing.allocator.create(ast.Pattern);
    defer std.testing.allocator.destroy(inner);
    inner.* = .{ .ident = .{ .name = "x", .span = undefined } };
    const pat = ast.Pattern{ .guard = .{ .inner = inner, .cond = undefined, .span = undefined } };
    const narrowed = try pattern_mod.narrowType(pat, nil_int, &env, std.testing.allocator);
    try std.testing.expectEqual(env_mod.int_type, narrowed);
}

test "checkExhaustive int type with no wildcard" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const lit = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(lit);
    lit.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .literal = lit }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, env_mod.int_type, &branches);
    try std.testing.expect(result != null);
}

test "checkExhaustive string type with wildcard is exhaustive" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .wildcard = undefined }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, env_mod.string_type, &branches);
    try std.testing.expectEqual(@as(?[][]const u8, null), result);
}

test "checkExhaustive nilable type with Nil only" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const nil_int = try env.registerType(std.testing.allocator, .{ .nilable = env_mod.int_type });
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "Nil", .span = undefined } }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, nil_int, &branches);
    try std.testing.expect(result != null);
}

test "checkExhaustive nilable type with Nil and wildcard" {
    var env = try makeEnv();
    defer env.deinit(std.testing.allocator);
    const nil_int = try env.registerType(std.testing.allocator, .{ .nilable = env_mod.int_type });
    const body = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const branches = [_]typed.Branch{
        .{ .pattern = .{ .ident = .{ .name = "Nil", .span = undefined } }, .body = body, .type_ = 0 },
        .{ .pattern = .{ .wildcard = undefined }, .body = body, .type_ = 0 },
    };
    const result = try pattern_mod.checkExhaustive(std.testing.allocator, &env, nil_int, &branches);
    try std.testing.expectEqual(@as(?[][]const u8, null), result);
}
