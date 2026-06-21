const std = @import("std");
const ast = @import("../ast/ast.zig");
const parser = @import("../parser/parser.zig");
const env_mod = @import("env.zig");
const infer_mod = @import("infer.zig");

const TypeEnv = env_mod.TypeEnv;

test "infer function with int body detects non-effect" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 42, .span = undefined } };

    const decls = [_]parser.Decl{
        .{ .function_def = .{ .name = "f", .params = &.{}, .return_type = null, .body = body, .span = undefined } },
    };

    const result = try infer_mod.infer(std.testing.allocator, &decls, &env);
    try std.testing.expect(result.len == 1);
    try std.testing.expect(!result[0].kind.function_def.is_effect);
    try std.testing.expectEqual(env_mod.int_type, result[0].kind.function_def.type_);
}

test "infer function with do_block detects effect" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .do_block = .{ .body = &.{}, .result = null, .span = undefined } };

    const decls = [_]parser.Decl{
        .{ .function_def = .{ .name = "f", .params = &.{}, .return_type = null, .body = body, .span = undefined } },
    };

    const result = try infer_mod.infer(std.testing.allocator, &decls, &env);
    try std.testing.expect(result.len == 1);
    try std.testing.expect(result[0].kind.function_def.is_effect);
}

test "infer function with IO.println detects effect" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "hi", .span = undefined } };
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };

    const decls = [_]parser.Decl{
        .{ .function_def = .{ .name = "f", .params = &.{}, .return_type = null, .body = body, .span = undefined } },
    };

    const result = try infer_mod.infer(std.testing.allocator, &decls, &env);
    try std.testing.expect(result.len == 1);
    try std.testing.expect(result[0].kind.function_def.is_effect);
}

test "infer verifies non-effect function has correct flag" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .int_literal = .{ .value = 42, .span = undefined } };

    const decls = [_]parser.Decl{
        .{ .function_def = .{ .name = "answer", .params = &.{}, .return_type = null, .body = body, .span = undefined } },
    };

    const result = try infer_mod.infer(std.testing.allocator, &decls, &env);
    try std.testing.expect(result.len == 1);
    try std.testing.expect(!result[0].kind.function_def.is_effect);
}

test "infer multiple decls" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const b1 = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(b1);
    b1.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
    const b2 = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(b2);
    b2.* = .{ .int_literal = .{ .value = 2, .span = undefined } };

    const decls = [_]parser.Decl{
        .{ .function_def = .{ .name = "f", .params = &.{}, .return_type = null, .body = b1, .span = undefined } },
        .{ .function_def = .{ .name = "g", .params = &.{}, .return_type = null, .body = b2, .span = undefined } },
    };

    const result = try infer_mod.infer(std.testing.allocator, &decls, &env);
    try std.testing.expectEqual(@as(usize, 2), result.len);
}

test "infer function with effect call in do_block marked effect" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const func = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(func);
    func.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
    const arg = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(arg);
    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
    const call = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(call);
    call.* = .{ .call = .{ .func = func, .arg = arg, .span = undefined } };

    const stmts = try std.testing.allocator.alloc(ast.Stmt, 1);
    defer std.testing.allocator.free(stmts);
    stmts[0] = .{ .kind = .{ .expr = call }, .span = undefined };
    const body = try std.testing.allocator.create(ast.Expr);
    defer std.testing.allocator.destroy(body);
    body.* = .{ .do_block = .{ .body = stmts, .result = null, .span = undefined } };

    const decls = [_]parser.Decl{
        .{ .function_def = .{ .name = "f", .params = &.{}, .return_type = null, .body = body, .span = undefined } },
    };

    const result = try infer_mod.infer(std.testing.allocator, &decls, &env);
    try std.testing.expect(result.len == 1);
    try std.testing.expect(result[0].kind.function_def.is_effect);
}
