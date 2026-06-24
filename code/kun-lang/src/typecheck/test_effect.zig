const std = @import("std");
const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");
const effect_mod = @import("effect.zig");
const error_mod = @import("error.zig");
const env_mod = @import("env.zig");

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

test "Phase4 checkCmdInDo detects effect call outside do block" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkCmdInDo(std.testing.allocator, "IO.println", false, undefined, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "Phase4 checkCmdInDo allows effect call inside do block" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkCmdInDo(std.testing.allocator, "IO.println", true, undefined, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkCmdInDo allows pure call outside do" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkCmdInDo(std.testing.allocator, "List.map", false, undefined, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkPipeCommand all combinations" {
    const cases = [_]struct { is_command: bool, in_do: bool, expect_error: bool }{
        .{ .is_command = true, .in_do = false, .expect_error = true },
        .{ .is_command = true, .in_do = true, .expect_error = false },
        .{ .is_command = false, .in_do = false, .expect_error = false },
        .{ .is_command = false, .in_do = true, .expect_error = false },
    };
    for (cases) |c| {
        var errors = try error_mod.ErrorList.init(std.testing.allocator);
        defer errors.deinit(std.testing.allocator);
        try effect_mod.checkPipeCommand(std.testing.allocator, c.is_command, c.in_do, undefined, &errors);
        try std.testing.expectEqual(c.expect_error, errors.hasErrors());
    }
}

test "Phase4 checkEffectCallback detects bang with pure function" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkEffectCallback(std.testing.allocator, false, true, undefined, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "Phase4 checkEffectCallback bang with effect no error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkEffectCallback(std.testing.allocator, true, true, undefined, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 hasEffectInExpr pipe_reverse with effect right" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const right = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(right);
    right.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const left = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(left);
    left.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const expr = ast.Expr{ .pipe_reverse = .{ .left = left, .right = right, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr compose with effect left" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const ceft = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(ceft);
    ceft.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const right = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(right);
    right.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const expr = ast.Expr{ .compose = .{ .left = ceft, .right = right, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr compose_reverse with effect left" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const ceft = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(ceft);
    ceft.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const right = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(right);
    right.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const expr = ast.Expr{ .compose_reverse = .{ .left = ceft, .right = right, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr pipe with effect left" {
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
    const expr = ast.Expr{ .pipe = .{ .left = left, .right = right, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr list_literal with effect item" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const item = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(item);
    item.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const items = [_]ast.ExprItem{
        .{ .expr = item },
    };
    const expr = ast.Expr{ .list_literal = .{ .items = &items, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr tuple_literal with effect item" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const item = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(item);
    item.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const items = [_]*const ast.Expr{item};
    const expr = ast.Expr{ .tuple_literal = .{ .items = &items, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr record_literal with effect field" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const val = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val);
    val.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const fields = [_]ast.RecordField{
        .{ .name = "f", .value = val },
    };
    const expr = ast.Expr{ .record_literal = .{ .fields = &fields, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr record_access with effect record" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const rec = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(rec);
    rec.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const expr = ast.Expr{ .record_access = .{ .record = rec, .field = "f", .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr call with effect record_access as func" {
    const rec = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(rec);
    rec.* = .{ .ident = .{ .name = "IO", .span = undefined } };
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .record_access = .{ .record = rec, .field = "println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "hi", .span = undefined } };
    const expr = ast.Expr{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr call with non-effect record_access as func" {
    const rec = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(rec);
    rec.* = .{ .ident = .{ .name = "List", .span = undefined } };
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .record_access = .{ .record = rec, .field = "map", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const expr = ast.Expr{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr unary_op with effect operand" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const op = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(op);
    op.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const expr = ast.Expr{ .unary_op = .{ .op = .neg, .operand = op, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 checkUnusedBindings emits error for unused" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const names = [_][]const u8{ "a", "b" };
    const used = [_]bool{ false, false };
    try effect_mod.checkUnusedBindings(std.testing.allocator, &names, &used, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "Phase4 checkUnusedBindings no error for all used" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const names = [_][]const u8{ "a", "b" };
    const used = [_]bool{ true, true };
    try effect_mod.checkUnusedBindings(std.testing.allocator, &names, &used, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkUnusedResult emits error for pure" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkUnusedResult(std.testing.allocator, true, undefined, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "Phase4 checkUnusedResult no error for non-pure" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkUnusedResult(std.testing.allocator, false, undefined, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkPureExprLast emits error for pure" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkPureExprLast(std.testing.allocator, true, undefined, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "Phase4 checkPureExprLast no error for non-pure" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkPureExprLast(std.testing.allocator, false, undefined, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkDoInResult unit result emits error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    var env = try env_mod.TypeEnv.init(std.testing.allocator); defer env.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const typed_result = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(typed_result);
    typed_result.* = .{ .int_literal = .{ .value = 0, .type_ = env_mod.unit_type, .span = undefined } };
    try effect_mod.checkDoInResult(std.testing.allocator, body, typed_result, &env, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "Phase4 checkDoInResult non-unit result no error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    var env = try env_mod.TypeEnv.init(std.testing.allocator); defer env.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const typed_result = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(typed_result);
    typed_result.* = .{ .int_literal = .{ .value = 42, .type_ = env_mod.int_type, .span = undefined } };
    try effect_mod.checkDoInResult(std.testing.allocator, body, typed_result, &env, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkDoInResult nil typed_result no error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    var env = try env_mod.TypeEnv.init(std.testing.allocator); defer env.deinit(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    try effect_mod.checkDoInResult(std.testing.allocator, body, null, &env, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkEffectCallback effect no bang no error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkEffectCallback(std.testing.allocator, true, false, undefined, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkEffectCallback pure no bang no error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkEffectCallback(std.testing.allocator, false, false, undefined, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkDoLetExclusion do in let emits error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const int_lit = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(int_lit);
    int_lit.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const stmts = [_]ast.Stmt{
        .{ .kind = .{ .expr = int_lit }, .span = undefined },
    };
    const do_body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(do_body);
    do_body.* = .{ .do_block = .{ .body = &stmts, .result = null, .span = undefined } };
    const val = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val);
    val.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const bindings = [_]ast.Binding{
        .{ .name = "x", .value = do_body, .span = undefined },
    };
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .let_in = .{ .bindings = &bindings, .body = val, .span = undefined } };
    try effect_mod.checkDoLetExclusion(std.testing.allocator, body, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "Phase4 checkDoLetExclusion let in do emits error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const val = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val);
    val.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const bindings = [_]ast.Binding{
        .{ .name = "x", .value = val, .span = undefined },
    };
    const let_body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(let_body);
    let_body.* = .{ .let_in = .{ .bindings = &bindings, .body = val, .span = undefined } };
    const stmts = [_]ast.Stmt{
        .{ .kind = .{ .expr = let_body }, .span = undefined },
    };
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .do_block = .{ .body = &stmts, .result = null, .span = undefined } };
    try effect_mod.checkDoLetExclusion(std.testing.allocator, body, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "Phase4 checkDoLetExclusion no nesting no error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const val = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val);
    val.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const bindings = [_]ast.Binding{
        .{ .name = "x", .value = val, .span = undefined },
    };
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .let_in = .{ .bindings = &bindings, .body = val, .span = undefined } };
    try effect_mod.checkDoLetExclusion(std.testing.allocator, body, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 hasEffectInExpr map_literal with effect key" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const key = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(key);
    key.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const val2 = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val2);
    val2.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const entries = [_]ast.MapEntry{
        .{ .key = key, .value = val2 },
    };
    const expr = ast.Expr{ .map_literal = .{ .entries = &entries, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr map_literal with effect value" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const key = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(key);
    key.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const val2 = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val2);
    val2.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const entries = [_]ast.MapEntry{
        .{ .key = key, .value = val2 },
    };
    const expr = ast.Expr{ .map_literal = .{ .entries = &entries, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr set_literal with effect item" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const item = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(item);
    item.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const items = [_]*const ast.Expr{item};
    const expr = ast.Expr{ .set_literal = .{ .items = &items, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr record_update with effect field" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const val = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val);
    val.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const rec = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(rec);
    rec.* = .{ .ident = .{ .name = "r", .span = undefined } };
    const fields = [_]ast.RecordField{
        .{ .name = "f", .value = val },
    };
    const expr = ast.Expr{ .record_update = .{ .record = rec, .fields = &fields, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr case_expr with effect in branch" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const branch_body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(branch_body);
    branch_body.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const subj = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(subj);
    subj.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const branches = [_]ast.Branch{
        .{ .pattern = .{ .wildcard = undefined }, .guard = null, .body = branch_body, .is_unbound = false, .span = undefined },
    };
    const expr = ast.Expr{ .case_expr = .{ .subject = subj, .branches = &branches, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr lambda with effect body" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const params = [_]ast.Param{};
    const expr = ast.Expr{ .lambda = .{ .params = &params, .body = body, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr if_expr with effect in else" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const cond = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(cond);
    cond.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const then_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(then_expr);
    then_expr.* = .{ .int_literal = .{ .value = 0, .span = undefined } };
    const else_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(else_expr);
    else_expr.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const expr = ast.Expr{ .if_expr = .{ .cond = cond, .then = then_expr, .else_ = else_expr, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr effect in binary_op right" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const left = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(left);
    left.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const right = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(right);
    right.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const expr = ast.Expr{ .binary_op = .{ .op = .add, .left = left, .right = right, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr list_literal with spread effect" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const spread = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(spread);
    spread.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const items = [_]ast.ExprItem{
        .{ .spread = spread },
    };
    const expr = ast.Expr{ .list_literal = .{ .items = &items, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr compose with effect right" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const left = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(left);
    left.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const right = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(right);
    right.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const expr = ast.Expr{ .compose = .{ .left = left, .right = right, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr compose_reverse with effect right" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const left = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(left);
    left.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const right = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(right);
    right.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const expr = ast.Expr{ .compose_reverse = .{ .left = left, .right = right, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 checkEmptyBody non-empty let_in no error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const int_lit = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(int_lit);
    int_lit.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const bindings = [_]ast.Binding{
        .{ .name = "x", .value = int_lit, .span = undefined },
    };
    const body_val = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body_val);
    body_val.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const body = ast.Expr{ .let_in = .{ .bindings = &bindings, .body = body_val, .span = undefined } };
    try effect_mod.checkEmptyBody(std.testing.allocator, &body, "let", &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkImplicitDo callable" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const body = ast.Expr{ .int_literal = .{ .value = 42, .span = undefined } };
    try effect_mod.checkImplicitDo(std.testing.allocator, &body, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkImplicitDo pure branches emit warning" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const ea = arena.allocator();

    const pure_expr = try ea.create(ast.Expr);
    pure_expr.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const branch1 = ast.Branch{ .pattern = (try heapPattern(ea, ast.Pattern{ .ident = .{ .name = "True", .span = undefined } })).*, .guard = null, .body = pure_expr, .is_unbound = false, .span = undefined };
    const branch2 = ast.Branch{ .pattern = (try heapPattern(ea, ast.Pattern{ .ident = .{ .name = "False", .span = undefined } })).*, .guard = null, .body = pure_expr, .is_unbound = false, .span = undefined };
    const branches = try ea.alloc(ast.Branch, 2);
    branches[0] = branch1;
    branches[1] = branch2;

    const subject = try ea.create(ast.Expr);
    subject.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const case_expr = try ea.create(ast.Expr);
    case_expr.* = .{ .case_expr = .{ .subject = subject, .branches = branches, .span = undefined } };
    const stmts = try ea.alloc(ast.Stmt, 1);
    stmts[0] = .{ .kind = .{ .expr = case_expr }, .span = undefined };
    const body = try ea.create(ast.Expr);
    body.* = .{ .do_block = .{ .body = stmts, .result = null, .span = undefined } };

    var errors = try error_mod.ErrorList.init(allocator);
    defer errors.deinit(allocator);
    try effect_mod.checkImplicitDo(allocator, body, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "Phase4 checkImplicitDo if with effect no error" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const ea = arena.allocator();

    const cond = try ea.create(ast.Expr);
    cond.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const io_ident = try ea.create(ast.Expr);
    io_ident.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try ea.create(ast.Expr);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const effect_call = try ea.create(ast.Expr);
    effect_call.* = .{ .call = .{ .func = io_ident, .arg = arg, .span = undefined } };
    const pure_expr = try ea.create(ast.Expr);
    pure_expr.* = .{ .int_literal = .{ .value = 0, .span = undefined } };
    const if_expr = try ea.create(ast.Expr);
    if_expr.* = .{ .if_expr = .{ .cond = cond, .then = effect_call, .else_ = pure_expr, .span = undefined } };
    const stmts = try ea.alloc(ast.Stmt, 1);
    stmts[0] = .{ .kind = .{ .expr = if_expr }, .span = undefined };
    const body = try ea.create(ast.Expr);
    body.* = .{ .do_block = .{ .body = stmts, .result = null, .span = undefined } };

    var errors = try error_mod.ErrorList.init(allocator);
    defer errors.deinit(allocator);
    try effect_mod.checkImplicitDo(allocator, body, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkImplicitDo if pure both branches emit warning" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const ea = arena.allocator();

    const cond = try ea.create(ast.Expr);
    cond.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const pure1 = try ea.create(ast.Expr);
    pure1.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const pure2 = try ea.create(ast.Expr);
    pure2.* = .{ .int_literal = .{ .value = 0, .span = undefined } };
    const if_expr = try ea.create(ast.Expr);
    if_expr.* = .{ .if_expr = .{ .cond = cond, .then = pure1, .else_ = pure2, .span = undefined } };
    const stmts = try ea.alloc(ast.Stmt, 1);
    stmts[0] = .{ .kind = .{ .expr = if_expr }, .span = undefined };
    const body = try ea.create(ast.Expr);
    body.* = .{ .do_block = .{ .body = stmts, .result = null, .span = undefined } };

    var errors = try error_mod.ErrorList.init(allocator);
    defer errors.deinit(allocator);
    try effect_mod.checkImplicitDo(allocator, body, &errors);
    try std.testing.expect(errors.hasErrors());
}

fn heapPattern(allocator: std.mem.Allocator, p: ast.Pattern) !*const ast.Pattern {
    const ptr = try allocator.create(ast.Pattern);
    ptr.* = p;
    return ptr;
}

test "Phase4 checkStreamConsumption callable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const ea = arena.allocator();

    const do_body = try ea.create(ast.Expr);
    do_body.* = .{ .do_block = .{ .body = &.{}, .result = null, .span = undefined } };

    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkStreamConsumption(std.testing.allocator, do_body, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkCommandConsumption callable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const ea = arena.allocator();

    const do_body = try ea.create(ast.Expr);
    do_body.* = .{ .do_block = .{ .body = &.{}, .result = null, .span = undefined } };

    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkCommandConsumption(std.testing.allocator, do_body, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 isEffectCall via pipe right with effect call" {
    const inner_func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(inner_func);
    inner_func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const inner_arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(inner_arg);
    inner_arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const call_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(call_expr);
    call_expr.* = .{ .call = .{ .func = inner_func, .arg = inner_arg, .span = undefined } };
    const pure = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(pure);
    pure.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const left = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(left);
    left.* = .{ .pipe = .{ .left = pure, .right = call_expr, .span = undefined } };
    const arg2 = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg2);
    arg2.* = .{ .int_literal = .{ .value = 2, .span = undefined } };
    const expr = ast.Expr{ .call = .{ .func = left, .arg = arg2, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 isEffectCall via pipe_reverse left with effect call" {
    const inner_func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(inner_func);
    inner_func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const inner_arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(inner_arg);
    inner_arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const call_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(call_expr);
    call_expr.* = .{ .call = .{ .func = inner_func, .arg = inner_arg, .span = undefined } };
    const pure = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(pure);
    pure.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const left = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(left);
    left.* = .{ .pipe_reverse = .{ .left = call_expr, .right = pure, .span = undefined } };
    const arg2 = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg2);
    arg2.* = .{ .int_literal = .{ .value = 2, .span = undefined } };
    const expr = ast.Expr{ .call = .{ .func = left, .arg = arg2, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 checkDoLetExclusion no nesting compose no error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const left = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(left);
    left.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const right = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(right);
    right.* = .{ .int_literal = .{ .value = 2, .span = undefined } };
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .compose = .{ .left = left, .right = right, .span = undefined } };
    try effect_mod.checkDoLetExclusion(std.testing.allocator, body, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 hasEffectInExpr pipe with pure both sides returns false" {
    const left = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(left);
    left.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const right = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(right);
    right.* = .{ .int_literal = .{ .value = 2, .span = undefined } };
    const expr = ast.Expr{ .pipe = .{ .left = left, .right = right, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr compose with pure both sides returns false" {
    const left = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(left);
    left.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const right = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(right);
    right.* = .{ .int_literal = .{ .value = 2, .span = undefined } };
    const expr = ast.Expr{ .compose = .{ .left = left, .right = right, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr pipe_reverse with pure both sides returns false" {
    const left = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(left);
    left.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const right = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(right);
    right.* = .{ .int_literal = .{ .value = 2, .span = undefined } };
    const expr = ast.Expr{ .pipe_reverse = .{ .left = left, .right = right, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr compose_reverse with pure both sides returns false" {
    const left = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(left);
    left.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const right = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(right);
    right.* = .{ .int_literal = .{ .value = 2, .span = undefined } };
    const expr = ast.Expr{ .compose_reverse = .{ .left = left, .right = right, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr binary_op with pure both sides returns false" {
    const left = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(left);
    left.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const right = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(right);
    right.* = .{ .int_literal = .{ .value = 2, .span = undefined } };
    const expr = ast.Expr{ .binary_op = .{ .op = .add, .left = left, .right = right, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr list_literal with pure items returns false" {
    const item = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(item);
    item.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const items = [_]ast.ExprItem{
        .{ .expr = item },
    };
    const expr = ast.Expr{ .list_literal = .{ .items = &items, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

// --- ternary/range_literal: not yet handled by hasEffectInExpr (Phase 5) ---

test "Phase4 hasEffectInExpr ternary defaults false (not yet handled)" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const cond = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(cond);
    cond.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const then_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(then_expr);
    then_expr.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const else_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(else_expr);
    else_expr.* = .{ .int_literal = .{ .value = 0, .span = undefined } };
    const expr = ast.Expr{ .ternary = .{ .cond = cond, .then = then_expr, .else_ = else_expr, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr range_literal defaults false (not yet handled)" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const from_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(from_expr);
    from_expr.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const to_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(to_expr);
    to_expr.* = .{ .int_literal = .{ .value = 10, .span = undefined } };
    const expr = ast.Expr{ .range_literal = .{ .from = from_expr, .to = to_expr, .step = null, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

// --- record_update effect coverage ---

test "Phase4 hasEffectInExpr record_update base record not checked current" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const rec = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(rec);
    rec.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const val = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val);
    val.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const fields = [_]ast.RecordField{
        .{ .name = "x", .value = val },
    };
    const expr = ast.Expr{ .record_update = .{ .record = rec, .fields = &fields, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr record_update pure base effect field" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const rec = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(rec);
    rec.* = .{ .int_literal = .{ .value = 0, .span = undefined } };
    const val = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val);
    val.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const fields = [_]ast.RecordField{
        .{ .name = "x", .value = val },
    };
    const expr = ast.Expr{ .record_update = .{ .record = rec, .fields = &fields, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr record_update pure all returns false" {
    const rec = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(rec);
    rec.* = .{ .int_literal = .{ .value = 0, .span = undefined } };
    const val = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val);
    val.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const fields = [_]ast.RecordField{
        .{ .name = "x", .value = val },
    };
    const expr = ast.Expr{ .record_update = .{ .record = rec, .fields = &fields, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

// --- lambda pure body ---

test "Phase4 hasEffectInExpr lambda with pure body returns false" {
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const params = [_]ast.Param{};
    const expr = ast.Expr{ .lambda = .{ .params = &params, .body = body, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

// --- case_expr pure coverage ---

test "Phase4 hasEffectInExpr case_expr with pure branches returns false" {
    const branch_body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(branch_body);
    branch_body.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const subj = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(subj);
    subj.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const branches = [_]ast.Branch{
        .{ .pattern = .{ .wildcard = undefined }, .guard = null, .body = branch_body, .is_unbound = false, .span = undefined },
    };
    const expr = ast.Expr{ .case_expr = .{ .subject = subj, .branches = &branches, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr case_expr with effect in subject" {
    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const subj = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(subj);
    subj.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    const branch_body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(branch_body);
    branch_body.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const branches = [_]ast.Branch{
        .{ .pattern = .{ .wildcard = undefined }, .guard = null, .body = branch_body, .is_unbound = false, .span = undefined },
    };
    const expr = ast.Expr{ .case_expr = .{ .subject = subj, .branches = &branches, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&expr));
}

// --- if_expr pure both ---

test "Phase4 hasEffectInExpr if_expr pure both sides returns false" {
    const cond = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(cond);
    cond.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const then_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(then_expr);
    then_expr.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const else_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(else_expr);
    else_expr.* = .{ .int_literal = .{ .value = 0, .span = undefined } };
    const expr = ast.Expr{ .if_expr = .{ .cond = cond, .then = then_expr, .else_ = else_expr, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

// --- checkEmptyBody misc ---

test "Phase4 checkEmptyBody non-do non-let no error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const body = ast.Expr{ .int_literal = .{ .value = 42, .span = undefined } };
    try effect_mod.checkEmptyBody(std.testing.allocator, &body, "expr", &errors);
    try std.testing.expect(!errors.hasErrors());
}

// --- checkLetInPurity pure case ---

test "Phase4 checkLetInPurity pure bindings and body no error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const val = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val);
    val.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const bindings = [_]ast.Binding{
        .{ .name = "x", .value = val, .span = undefined },
    };
    const body = ast.Expr{ .int_literal = .{ .value = 1, .span = undefined } };
    try effect_mod.checkLetInPurity(std.testing.allocator, &bindings, &body, &errors);
    try std.testing.expect(!errors.hasErrors());
}

// --- checkEmptyBody boundary cases ---

test "Phase4 checkEmptyBody do_block with result empty body no error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const result = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(result);
    result.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const body = ast.Expr{ .do_block = .{ .body = &.{}, .result = result, .span = undefined } };
    try effect_mod.checkEmptyBody(std.testing.allocator, &body, "do", &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkEmptyBody do_block with body and result no error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const stmt_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(stmt_expr);
    stmt_expr.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const stmts = [_]ast.Stmt{
        .{ .kind = .{ .expr = stmt_expr }, .span = undefined },
    };
    const result = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(result);
    result.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const body = ast.Expr{ .do_block = .{ .body = &stmts, .result = result, .span = undefined } };
    try effect_mod.checkEmptyBody(std.testing.allocator, &body, "do", &errors);
    try std.testing.expect(!errors.hasErrors());
}

// --- hasEffectInExpr for empty collection literals ---

test "Phase4 hasEffectInExpr empty list returns false" {
    const items = [_]ast.ExprItem{};
    const expr = ast.Expr{ .list_literal = .{ .items = &items, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr empty tuple returns false" {
    const items = [_]*const ast.Expr{};
    const expr = ast.Expr{ .tuple_literal = .{ .items = &items, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr empty record returns false" {
    const fields = [_]ast.RecordField{};
    const expr = ast.Expr{ .record_literal = .{ .fields = &fields, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr empty map returns false" {
    const entries = [_]ast.MapEntry{};
    const expr = ast.Expr{ .map_literal = .{ .entries = &entries, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr empty set returns false" {
    const items = [_]*const ast.Expr{};
    const expr = ast.Expr{ .set_literal = .{ .items = &items, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr ident returns false" {
    const expr = ast.Expr{ .ident = .{ .name = "x", .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr bool_literal returns false" {
    const expr = ast.Expr{ .bool_literal = .{ .value = true, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

test "Phase4 hasEffectInExpr nil_literal returns false" {
    const expr = ast.Expr{ .nil_literal = undefined };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&expr));
}

// --- checkDoLetExclusion recursive paths ---

test "Phase4 checkDoLetExclusion do inside pipe in let emits error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const int_lit = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(int_lit);
    int_lit.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const stmts = [_]ast.Stmt{
        .{ .kind = .{ .expr = int_lit }, .span = undefined },
    };
    const do_inner = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(do_inner);
    do_inner.* = .{ .do_block = .{ .body = &stmts, .result = null, .span = undefined } };
    const pure_r = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(pure_r);
    pure_r.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const pipe_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(pipe_expr);
    pipe_expr.* = .{ .pipe = .{ .left = pure_r, .right = do_inner, .span = undefined } };
    const bindings = [_]ast.Binding{
        .{ .name = "x", .value = pipe_expr, .span = undefined },
    };
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .span = undefined } };
    const expr = ast.Expr{ .let_in = .{ .bindings = &bindings, .body = body, .span = undefined } };
    try effect_mod.checkDoLetExclusion(std.testing.allocator, &expr, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "Phase4 checkDoLetExclusion do inside compose in let emits error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const int_lit = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(int_lit);
    int_lit.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const stmts = [_]ast.Stmt{
        .{ .kind = .{ .expr = int_lit }, .span = undefined },
    };
    const do_inner = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(do_inner);
    do_inner.* = .{ .do_block = .{ .body = &stmts, .result = null, .span = undefined } };
    const pure_r = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(pure_r);
    pure_r.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const compose_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(compose_expr);
    compose_expr.* = .{ .compose = .{ .left = pure_r, .right = do_inner, .span = undefined } };
    const bindings = [_]ast.Binding{
        .{ .name = "x", .value = compose_expr, .span = undefined },
    };
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .span = undefined } };
    const expr = ast.Expr{ .let_in = .{ .bindings = &bindings, .body = body, .span = undefined } };
    try effect_mod.checkDoLetExclusion(std.testing.allocator, &expr, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "Phase4 checkCmdInDo all effect namespaces detected outside do" {
    const names = [_][]const u8{
        "IO", "IO.println", "IO.readln", "IO.write", "IO.flush",
        "File", "File.readString", "File.list", "File.stat",
        "Env", "Env.getenv", "Env.contains",
        "Process", "Process.exit", "Process.pid", "Process.uid", "Process.gid",
        "Task", "Task.wait", "Task.spawn",
        "Random", "Random.int", "Random.float",
        "Signal.on", "Stream.iter",
        "Cmd.exec", "Cmd.timeout", "Cmd.retry", "Cmd.execSafe", "Cmd.which",
        "Cmd.pipe?", "Cmd.pipe!", "Cmd.foo?", "Cmd.foo!",
    };
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    for (names) |name| {
        try effect_mod.checkCmdInDo(std.testing.allocator, name, false, undefined, &errors);
    }
    try std.testing.expect(errors.hasErrors());
    try std.testing.expectEqual(@as(usize, names.len), errors.items.items.len);
}

test "Phase4 checkCmdInDo all effect namespaces allowed inside do" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const names = [_][]const u8{
        "IO.println", "File.readString", "Env.getenv", "Process.exit",
        "Task.spawn", "Random.int", "Signal.on", "Stream.iter",
        "Cmd.exec", "Cmd.timeout", "Cmd.retry", "Cmd.pipe?", "Cmd.foo!",
    };
    for (names) |name| {
        try effect_mod.checkCmdInDo(std.testing.allocator, name, true, undefined, &errors);
    }
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkPureFunctionBody with multiple effect patterns" {
    const patterns = [_]struct { name: []const u8, args: []const u8 }{
        .{ .name = "IO.println", .args = "a" },
        .{ .name = "Cmd.exec", .args = "c" },
        .{ .name = "Process.exit", .args = "0" },
        .{ .name = "File.readString", .args = "p" },
        .{ .name = "Stream.iter", .args = "f" },
        .{ .name = "Random.int", .args = "n" },
        .{ .name = "Signal.on", .args = "s" },
    };
    for (patterns) |p| {
        var errors = try error_mod.ErrorList.init(std.testing.allocator);
        defer errors.deinit(std.testing.allocator);
        const func = try std.testing.allocator.create(ast.Expr);
        defer std.testing.allocator.destroy(func);
        func.* = .{ .ident = .{ .name = p.name, .span = undefined } };
        const arg = try std.testing.allocator.create(ast.Expr);
        defer std.testing.allocator.destroy(arg);
        arg.* = .{ .ident = .{ .name = p.args, .span = undefined } };
        const body = ast.Expr{ .call = .{ .func = func, .arg = arg, .span = undefined } };
        try effect_mod.checkPureFunctionBody(std.testing.allocator, &body, &errors);
        try std.testing.expect(errors.hasErrors());
    }
}

test "Phase4 checkPureFunctionBody pure ident no error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const body = ast.Expr{ .ident = .{ .name = "x", .span = undefined } };
    try effect_mod.checkPureFunctionBody(std.testing.allocator, &body, &errors);
    try std.testing.expect(!errors.hasErrors());
}

test "Phase4 checkDoLetExclusion do in record field in let emits error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const int_lit = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(int_lit);
    int_lit.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const stmts = [_]ast.Stmt{
        .{ .kind = .{ .expr = int_lit }, .span = undefined },
    };
    const do_inner = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(do_inner);
    do_inner.* = .{ .do_block = .{ .body = &stmts, .result = null, .span = undefined } };
    const fields = [_]ast.RecordField{
        .{ .name = "f", .value = do_inner },
    };
    const record_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(record_expr);
    record_expr.* = .{ .record_literal = .{ .fields = &fields, .span = undefined } };
    const bindings = [_]ast.Binding{
        .{ .name = "x", .value = record_expr, .span = undefined },
    };
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .span = undefined } };
    const expr = ast.Expr{ .let_in = .{ .bindings = &bindings, .body = body, .span = undefined } };
    try effect_mod.checkDoLetExclusion(std.testing.allocator, &expr, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "Phase4 checkDoLetExclusion do in case branch in let emits error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const int_lit = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(int_lit);
    int_lit.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const stmts = [_]ast.Stmt{
        .{ .kind = .{ .expr = int_lit }, .span = undefined },
    };
    const do_inner = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(do_inner);
    do_inner.* = .{ .do_block = .{ .body = &stmts, .result = null, .span = undefined } };
    const subj = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(subj);
    subj.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const branches = [_]ast.Branch{
        .{ .pattern = .{ .wildcard = undefined }, .guard = null, .body = do_inner, .is_unbound = false, .span = undefined },
    };
    const case_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(case_expr);
    case_expr.* = .{ .case_expr = .{ .subject = subj, .branches = &branches, .span = undefined } };
    const bindings = [_]ast.Binding{
        .{ .name = "x", .value = case_expr, .span = undefined },
    };
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 0, .span = undefined } };
    const expr = ast.Expr{ .let_in = .{ .bindings = &bindings, .body = body, .span = undefined } };
    try effect_mod.checkDoLetExclusion(std.testing.allocator, &expr, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "Phase4 checkDoLetExclusion let inside case branch in do emits error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const val = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val);
    val.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const bindings = [_]ast.Binding{
        .{ .name = "x", .value = val, .span = undefined },
    };
    const let_body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(let_body);
    let_body.* = .{ .int_literal = .{ .value = 0, .span = undefined } };
    const let_inner = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(let_inner);
    let_inner.* = .{ .let_in = .{ .bindings = &bindings, .body = let_body, .span = undefined } };
    const subj = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(subj);
    subj.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const branches = [_]ast.Branch{
        .{ .pattern = .{ .wildcard = undefined }, .guard = null, .body = let_inner, .is_unbound = false, .span = undefined },
    };
    const case_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(case_expr);
    case_expr.* = .{ .case_expr = .{ .subject = subj, .branches = &branches, .span = undefined } };
    const stmts = [_]ast.Stmt{
        .{ .kind = .{ .expr = case_expr }, .span = undefined },
    };
    const body = ast.Expr{ .do_block = .{ .body = &stmts, .result = null, .span = undefined } };
    try effect_mod.checkDoLetExclusion(std.testing.allocator, &body, &errors);
    try std.testing.expect(errors.hasErrors());
}

test "Phase4 checkDoLetExclusion let inside binary_op in do emits error" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const val = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(val);
    val.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const bindings = [_]ast.Binding{
        .{ .name = "x", .value = val, .span = undefined },
    };
    const let_body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(let_body);
    let_body.* = .{ .int_literal = .{ .value = 0, .span = undefined } };
    const let_inner = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(let_inner);
    let_inner.* = .{ .let_in = .{ .bindings = &bindings, .body = let_body, .span = undefined } };
    const pure_r = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(pure_r);
    pure_r.* = .{ .int_literal = .{ .value = 2, .span = undefined } };
    const binop_expr = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(binop_expr);
    binop_expr.* = .{ .binary_op = .{ .op = .add, .left = let_inner, .right = pure_r, .span = undefined } };
    const stmts = [_]ast.Stmt{
        .{ .kind = .{ .expr = binop_expr }, .span = undefined },
    };
    const body = ast.Expr{ .do_block = .{ .body = &stmts, .result = null, .span = undefined } };
    try effect_mod.checkDoLetExclusion(std.testing.allocator, &body, &errors);
    try std.testing.expect(errors.hasErrors());
}

// --- Phase4 error type verification tests ---

test "Phase4 checkEffectCallback emits effect_callback_mismatch" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkEffectCallback(std.testing.allocator, false, true, undefined, &errors);
    try std.testing.expect(errors.hasErrors());
    try std.testing.expect(errors.items.items[0] == .effect_callback_mismatch);
}

test "Phase4 checkCmdInDo emits effect_in_pure" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkCmdInDo(std.testing.allocator, "IO.println", false, undefined, &errors);
    try std.testing.expect(errors.hasErrors());
    try std.testing.expect(errors.items.items[0] == .effect_in_pure);
}

test "Phase4 checkPipeCommand emits command_not_consumed" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    try effect_mod.checkPipeCommand(std.testing.allocator, true, false, undefined, &errors);
    try std.testing.expect(errors.hasErrors());
    try std.testing.expect(errors.items.items[0] == .command_not_consumed);
}

test "Phase4 checkDoInResult emits pure_unit_return" {
    var errors = try error_mod.ErrorList.init(std.testing.allocator);
    var env = try env_mod.TypeEnv.init(std.testing.allocator); defer env.deinit(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const typed_result = try std.testing.allocator.create(typed.TypedExpr);
    defer std.testing.allocator.destroy(typed_result);
    typed_result.* = .{ .int_literal = .{ .value = 0, .type_ = env_mod.unit_type, .span = undefined } };
    try effect_mod.checkDoInResult(std.testing.allocator, body, typed_result, &env, &errors);
    try std.testing.expect(errors.hasErrors());
    try std.testing.expect(errors.items.items[0] == .pure_unit_return);
}

test "Phase4 checkPureFunctionBody emits effect_in_pure" {
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
    try std.testing.expect(errors.items.items[0] == .effect_in_pure);
}

test "Phase4 checkLetInPurity emits effect_in_let" {
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
    try std.testing.expect(errors.items.items[0] == .effect_in_let);
}

test "Phase4 checkLetInPurity effect in body emits effect_in_let" {
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
    try std.testing.expect(errors.items.items[0] == .effect_in_let);
}
