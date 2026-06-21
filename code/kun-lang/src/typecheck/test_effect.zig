const std = @import("std");
const ast = @import("../ast/ast.zig");
const effect_mod = @import("effect.zig");

test "hasEffectInExpr do_block" {
    const expr = ast.Expr{ .do_block = .{ .body = &.{}, .result = null, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "hasEffectInExpr IO.println call" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "hi", .span = undefined } };
    const expr = ast.Expr{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "hasEffectInExpr Cmd.exec call" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "Cmd.exec", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .ident = .{ .name = "cmd", .span = undefined } };
    const expr = ast.Expr{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "hasEffectInExpr pure expr" {
    const expr = ast.Expr{ .int_literal = .{ .value = 42, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "hasEffectInExpr Cmd.withEnv is not effect" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "Cmd.withEnv", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .ident = .{ .name = "cmd", .span = undefined } };
    const expr = ast.Expr{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "hasEffectInExpr if_expr with effect in then" {
    const cond = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(cond);
    cond.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const then_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(then_expr);
    then_expr.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const else_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(else_expr);
    else_expr.* = .{ .int_literal = .{ .value = 0, .span = undefined } };
    const expr = ast.Expr{ .if_expr = .{ .cond = cond, .then = then_expr, .else_ = else_expr, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "hasEffectInExpr effect in binary_op left" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const left = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(left);
    left.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const right = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(right);
    right.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const expr = ast.Expr{ .binary_op = .{ .op = .add, .left = left, .right = right, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "checkDuplicateBindings no duplicates" {
    const bindings = [_]ast.Binding{
        .{ .name = "x", .value = undefined, .span = undefined },
        .{ .name = "y", .value = undefined, .span = undefined },
        .{ .name = "z", .value = undefined, .span = undefined },
    };
    try std.testing.expect(!try effect_mod.checkDuplicateBindings(std.testing.allocator, &bindings));
}

test "checkDuplicateBindings found duplicate" {
    const bindings = [_]ast.Binding{
        .{ .name = "x", .value = undefined, .span = undefined },
        .{ .name = "y", .value = undefined, .span = undefined },
        .{ .name = "x", .value = undefined, .span = undefined },
    };
    try std.testing.expect(try effect_mod.checkDuplicateBindings(std.testing.allocator, &bindings));
}
