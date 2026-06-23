const std = @import("std");
const ast = @import("../ast/ast.zig");
const effect_mod = @import("effect.zig");
const error_mod = @import("error.zig");

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

test "checkPureFunctionBody no effect" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const body = ast.Expr{ .int_literal = .{ .value = 42, .span = undefined } };
    try effect_mod.checkPureFunctionBody(std.testing.allocator, &body, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "checkPureFunctionBody with effect returns error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "hi", .span = undefined } };
    const body = ast.Expr{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    try effect_mod.checkPureFunctionBody(std.testing.allocator, &body, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "checkLetInPurity effect in binding emits error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "hi", .span = undefined } };
    const val = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val);
    val.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const bindings = [_]ast.Binding{
        .{ .name = "f", .value = val, .span = undefined },
    };
    const body = ast.Expr{ .int_literal = .{ .value = 42, .span = undefined } };
    try effect_mod.checkLetInPurity(std.testing.allocator, &bindings, &body, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "checkLetInPurity effect in body emits error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const val = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val);
    val.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const bindings = [_]ast.Binding{
        .{ .name = "x", .value = val, .span = undefined },
    };
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "hi", .span = undefined } };
    const body = ast.Expr{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    try effect_mod.checkLetInPurity(std.testing.allocator, &bindings, &body, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "checkEmptyBody empty do emits error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const body = ast.Expr{ .do_block = .{ .body = &.{}, .result = null, .span = undefined } };
    try effect_mod.checkEmptyBody(std.testing.allocator, &body, "do", &errors);
    try std.testing.expect(errors.hasErrors());
}

test "checkEmptyBody empty let_in emits error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const body = ast.Expr{ .let_in = .{ .bindings = &.{}, .body = undefined, .span = undefined } };
    try effect_mod.checkEmptyBody(std.testing.allocator, &body, "let", &errors);
    try std.testing.expect(errors.hasErrors());
}

test "checkEmptyBody non-empty do no error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const int_lit = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(int_lit);
    int_lit.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const stmts = [_]ast.Stmt{
        .{ .kind = .{ .expr = int_lit }, .span = undefined },
    };
    const body = ast.Expr{ .do_block = .{ .body = &stmts, .result = null, .span = undefined } };
    try effect_mod.checkEmptyBody(std.testing.allocator, &body, "do", &errors);
    try std.testing.expect(!errors.hasErrors());
}
