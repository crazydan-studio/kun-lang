const std = @import("std");
const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");
const env_mod = @import("env.zig");
const constraint_mod = @import("constraint.zig");
const error_mod = @import("error.zig");
const effect_mod = @import("effect.zig");

const TypeEnv = env_mod.TypeEnv;
const ErrorList = error_mod.ErrorList;

fn setup() !struct { env: TypeEnv, arena: std.heap.ArenaAllocator } {
    return .{
        .env = try TypeEnv.init(std.testing.allocator),
        .arena = std.heap.ArenaAllocator.init(std.testing.allocator),
    };
}

test "constraint infers int literal" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();

    const int_expr = ast.Expr{ .int_literal = .{ .value = 42, .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(s.arena.allocator(), &int_expr, &s.env, &errors);
    try std.testing.expect(result.* == .int_literal);
    try std.testing.expect(result.int_literal.type_ == env_mod.int_type);
    try std.testing.expectEqual(@as(i64, 42), result.int_literal.value);
}

test "constraint infers bool literal" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();

    const expr = ast.Expr{ .bool_literal = .{ .value = true, .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(s.arena.allocator(), &expr, &s.env, &errors);
    try std.testing.expect(result.bool_literal.type_ == env_mod.bool_type);
}

test "constraint infers string literal" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();

    const expr = ast.Expr{ .string_literal = .{ .value = "hello", .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(s.arena.allocator(), &expr, &s.env, &errors);
    try std.testing.expect(result.string_literal.type_ == env_mod.string_type);
}

test "constraint nil literal is nilable" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();

    const expr = ast.Expr{ .nil_literal = undefined };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(s.arena.allocator(), &expr, &s.env, &errors);
    try std.testing.expect(result.* == .nil_literal);
    const nil_ty = s.env.resolveType(result.nil_literal.type_);
    try std.testing.expect(nil_ty == .nilable);
}

test "constraint infers float literal" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();

    const expr = ast.Expr{ .float_literal = .{ .value = 3.14, .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(s.arena.allocator(), &expr, &s.env, &errors);
    try std.testing.expect(result.float_literal.type_ == env_mod.float_type);
}

test "constraint infers char literal" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();

    const expr = ast.Expr{ .char_literal = .{ .value = 'A', .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(s.arena.allocator(), &expr, &s.env, &errors);
    try std.testing.expect(result.char_literal.type_ == env_mod.char_type);
}

test "constraint infers duration literal" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();

    const expr = ast.Expr{ .duration_literal = .{ .value = 5, .unit = .s, .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(s.arena.allocator(), &expr, &s.env, &errors);
    try std.testing.expect(result.duration_literal.type_ == env_mod.duration_type);
}

test "constraint infers path literal" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();

    const expr = ast.Expr{ .path_literal = .{ .value = "/tmp", .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(s.arena.allocator(), &expr, &s.env, &errors);
    try std.testing.expect(result.path_literal.type_ == env_mod.path_type);
}

test "constraint infers regex literal" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();

    const expr = ast.Expr{ .regex_literal = .{ .value = "[0-9]+", .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(s.arena.allocator(), &expr, &s.env, &errors);
    try std.testing.expect(result.regex_literal.type_ == env_mod.regex_type);
}

test "constraint infers bytes literal" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();

    const expr = ast.Expr{ .bytes_literal = .{ .value = "deadbeef", .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(s.arena.allocator(), &expr, &s.env, &errors);
    try std.testing.expect(result.bytes_literal.type_ == env_mod.bytes_type);
}

test "constraint infers binary op types" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();
    const allocator = s.arena.allocator();

    const left = try allocator.create(ast.Expr);
    left.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const right = try allocator.create(ast.Expr);
    right.* = .{ .int_literal = .{ .value = 2, .span = undefined } };

    const expr = ast.Expr{ .binary_op = .{ .op = .add, .left = left, .right = right, .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(allocator, &expr, &s.env, &errors);
    try std.testing.expect(result.binary_op.type_ == env_mod.int_type);
}

test "constraint hasEffect detects do_block" {
    const body = ast.Expr{ .do_block = .{ .body = &.{}, .result = null, .span = undefined } };
    try std.testing.expect(effect_mod.hasEffectInExpr(&body));
}

test "constraint hasEffect false for pure expr" {
    const body = ast.Expr{ .int_literal = .{ .value = 42, .span = undefined } };
    try std.testing.expect(!effect_mod.hasEffectInExpr(&body));
}

test "effect namespace detection" {
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("IO.println"));
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("File.readString"));
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("Env.get"));
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("Process.exit"));
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("Signal.on"));
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("Cmd.exec"));
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("Cmd.which"));
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("Cmd.timeout"));
}

test "effect namespace non-effect functions" {
    try std.testing.expect(!constraint_mod.isEffectNamespaceCall("Cmd.withEnv"));
    try std.testing.expect(!constraint_mod.isEffectNamespaceCall("Cmd.pipe"));
    try std.testing.expect(!constraint_mod.isEffectNamespaceCall("Cmd.mergeStderr"));
    try std.testing.expect(!constraint_mod.isEffectNamespaceCall("List.map"));
    try std.testing.expect(!constraint_mod.isEffectNamespaceCall("String.length"));
}

test "constraint infers if_expr subtypes" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();
    const allocator = s.arena.allocator();

    const cond = try allocator.create(ast.Expr);
    cond.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const then_expr = try allocator.create(ast.Expr);
    then_expr.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const else_expr = try allocator.create(ast.Expr);
    else_expr.* = .{ .int_literal = .{ .value = 0, .span = undefined } };

    const expr = ast.Expr{ .if_expr = .{ .cond = cond, .then = then_expr, .else_ = else_expr, .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(allocator, &expr, &s.env, &errors);
    try std.testing.expect(result.if_expr.type_ == env_mod.int_type);
}

test "constraint hasEffect detects effect in nested call" {
    const inner_func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(inner_func);
    inner_func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const inner_arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(inner_arg);
    inner_arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };

    const effect_call = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(effect_call);
    effect_call.* = .{ .call = .{ .func = inner_func, .arg = inner_arg, .span = undefined } };

    const outer_func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(outer_func);
    outer_func.* = .{ .ident = .{ .name = "List.map", .span = undefined } };
    const outer_call = ast.Expr{ .call = .{ .func = outer_func, .arg = effect_call, .span = undefined } };

    try std.testing.expect(effect_mod.hasEffectInExpr(&outer_call));
}

test "constraint infers call expression" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();
    const allocator = s.arena.allocator();

    const func = try allocator.create(ast.Expr);
    func.* = .{ .ident = .{ .name = "f", .span = undefined } };
    const arg = try allocator.create(ast.Expr);
    arg.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const expr = ast.Expr{ .call = .{ .func = func, .arg = arg, .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(allocator, &expr, &s.env, &errors);
    try std.testing.expect(result.* == .call);
    try std.testing.expect(result.call.func.* == .ident);
    try std.testing.expectEqualStrings("f", result.call.func.ident.name);
}

test "constraint infers lambda expression" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();
    const allocator = s.arena.allocator();

    const body = try allocator.create(ast.Expr);
    body.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const params = try allocator.alloc(ast.Param, 1);
    params[0] = .{ .name = "x", .span = undefined };
    const expr = ast.Expr{ .lambda = .{ .params = params, .body = body, .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(allocator, &expr, &s.env, &errors);
    try std.testing.expect(result.* == .lambda);
    try std.testing.expect(result.lambda.type_ != 0);
    try std.testing.expectEqual(@as(usize, 1), result.lambda.params.len);
    try std.testing.expectEqualStrings("x", result.lambda.params[0].name);
}

test "constraint infers let_in expression" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();
    const allocator = s.arena.allocator();

    const val = try allocator.create(ast.Expr);
    val.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const bindings = try allocator.alloc(ast.Binding, 1);
    bindings[0] = .{ .name = "x", .value = val, .span = undefined };
    const body = try allocator.create(ast.Expr);
    body.* = .{ .ident = .{ .name = "x", .span = undefined } };
    const expr = ast.Expr{ .let_in = .{ .bindings = bindings, .body = body, .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(allocator, &expr, &s.env, &errors);
    try std.testing.expect(result.* == .let_in);
    try std.testing.expectEqual(@as(usize, 1), result.let_in.bindings.len);
    try std.testing.expectEqualStrings("x", result.let_in.bindings[0].name);
}

test "constraint infers record literal" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();
    const allocator = s.arena.allocator();

    const val = try allocator.create(ast.Expr);
    val.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const fields = try allocator.alloc(ast.RecordField, 1);
    fields[0] = .{ .name = "x", .value = val };
    const expr = ast.Expr{ .record_literal = .{ .fields = fields, .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(allocator, &expr, &s.env, &errors);
    try std.testing.expect(result.* == .record_literal);
    try std.testing.expectEqual(@as(usize, 1), result.record_literal.fields.len);
    try std.testing.expectEqualStrings("x", result.record_literal.fields[0].name);
}

test "constraint int + bool accumulates type mismatch" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();
    const allocator = s.arena.allocator();

    const left = try allocator.create(ast.Expr);
    left.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const right = try allocator.create(ast.Expr);
    right.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const expr = ast.Expr{ .binary_op = .{ .op = .add, .left = left, .right = right, .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    _ = constraint_mod.inferExpr(allocator, &expr, &s.env, &errors) catch {};
    try std.testing.expect(errors.hasErrors());
}

test "constraint infers case_expr" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();
    const allocator = s.arena.allocator();

    const subject = try allocator.create(ast.Expr);
    subject.* = .{ .bool_literal = .{ .value = true, .span = undefined } };
    const body = try allocator.create(ast.Expr);
    body.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const branches = try allocator.alloc(ast.Branch, 1);
    branches[0] = .{ .pattern = .{ .wildcard = undefined }, .guard = null, .body = body, .is_unbound = false, .span = undefined };
    const expr = ast.Expr{ .case_expr = .{ .subject = subject, .branches = branches, .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(allocator, &expr, &s.env, &errors);
    try std.testing.expect(result.* == .case_expr);
    try std.testing.expectEqual(@as(usize, 1), result.case_expr.branches.len);
}

test "constraint infers do_block" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();
    const allocator = s.arena.allocator();

    const expr = ast.Expr{ .do_block = .{ .body = &.{}, .result = null, .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(allocator, &expr, &s.env, &errors);
    try std.testing.expect(result.* == .do_block);
    try std.testing.expectEqual(env_mod.unit_type, result.do_block.type_);
}

test "constraint infers do_block with in result" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();
    const allocator = s.arena.allocator();

    const result_expr = try allocator.create(ast.Expr);
    result_expr.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
    const expr = ast.Expr{ .do_block = .{ .body = &.{}, .result = result_expr, .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(allocator, &expr, &s.env, &errors);
    try std.testing.expect(result.* == .do_block);
    try std.testing.expectEqual(env_mod.int_type, result.do_block.type_);
}

test "constraint Cmd.echo ident is command_t" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();
    const allocator = s.arena.allocator();

    const expr = ast.Expr{ .ident = .{ .name = "Cmd.echo", .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(allocator, &expr, &s.env, &errors);
    try std.testing.expect(result.* == .ident);
    try std.testing.expectEqual(env_mod.command_type, result.ident.type_);
}

test "constraint Cmd.withEnv ident is not command_t" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();
    const allocator = s.arena.allocator();

    const expr = ast.Expr{ .ident = .{ .name = "Cmd.withEnv", .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(allocator, &expr, &s.env, &errors);
    try std.testing.expect(result.ident.type_ != env_mod.command_type);
}

test "constraint Cmd.exec ident is not command_t" {
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();
    const allocator = s.arena.allocator();

    const expr = ast.Expr{ .ident = .{ .name = "Cmd.exec", .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(allocator, &expr, &s.env, &errors);
    try std.testing.expect(result.ident.type_ != env_mod.command_type);
}

test "constraint Cmd.ls? ident is not command_t" {
    // ? suffix — known effect, not bare command
    var s = try setup();
    defer s.env.deinit(std.testing.allocator);
    defer s.arena.deinit();
    const allocator = s.arena.allocator();

    const expr = ast.Expr{ .ident = .{ .name = "Cmd.ls?", .span = undefined } };
    var errors = try ErrorList.init(std.testing.allocator);
    defer errors.deinit(std.testing.allocator);

    const result = try constraint_mod.inferExpr(allocator, &expr, &s.env, &errors);
    try std.testing.expect(result.ident.type_ != env_mod.command_type);
}
