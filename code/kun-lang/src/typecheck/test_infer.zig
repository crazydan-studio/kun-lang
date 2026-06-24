const std = @import("std");
const ast = @import("../ast/ast.zig");
const parser = @import("../parser/parser.zig");
const env_mod = @import("env.zig");
const infer_mod = @import("infer.zig");
const primitive_mod = @import("../runtime/primitive.zig");

const TypeEnv = env_mod.TypeEnv;

test "infer: function effect detection" {
    const cases = [_]struct {
        name: []const u8,
        buildBody: *const fn (alloc: std.mem.Allocator) error{OutOfMemory}!*ast.Expr,
        expect_effect: bool,
        expect_type: u32,
    }{
        .{
            .name = "int literal",
            .buildBody = struct {
                fn f(alloc: std.mem.Allocator) error{OutOfMemory}!*ast.Expr {
                    const b = try alloc.create(ast.Expr);
                    b.* = .{ .int_literal = .{ .value = 42, .span = undefined } };
                    return b;
                }
            }.f,
            .expect_effect = false,
            .expect_type = env_mod.int_type,
        },
        .{
            .name = "do block",
            .buildBody = struct {
                fn f(alloc: std.mem.Allocator) error{OutOfMemory}!*ast.Expr {
                    const lit = try alloc.create(ast.Expr);
                    lit.* = .{ .int_literal = .{ .value = 1, .span = undefined } };
                    const stmts = try alloc.alloc(ast.Stmt, 1);
                    stmts[0] = .{ .kind = .{ .expr = lit }, .span = undefined };
                    const b = try alloc.create(ast.Expr);
                    b.* = .{ .do_block = .{ .body = stmts, .result = null, .span = undefined } };
                    return b;
                }
            }.f,
            .expect_effect = true,
            .expect_type = env_mod.unit_type,
        },
        .{
            .name = "IO.println call in do",
            .buildBody = struct {
                fn f(alloc: std.mem.Allocator) error{OutOfMemory}!*ast.Expr {
                    const ident = try alloc.create(ast.Expr);
                    ident.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
                    const arg = try alloc.create(ast.Expr);
                    arg.* = .{ .string_literal = .{ .value = "hi", .span = undefined } };
                    const call = try alloc.create(ast.Expr);
                    call.* = .{ .call = .{ .func = ident, .arg = arg, .span = undefined } };
                    const stmts = try alloc.alloc(ast.Stmt, 1);
                    stmts[0] = .{ .kind = .{ .expr = call }, .span = undefined };
                    const b = try alloc.create(ast.Expr);
                    b.* = .{ .do_block = .{ .body = stmts, .result = null, .span = undefined } };
                    return b;
                }
            }.f,
            .expect_effect = true,
            .expect_type = env_mod.unit_type,
        },
        .{
            .name = "IO.println in do_block",
            .buildBody = struct {
                fn f(alloc: std.mem.Allocator) error{OutOfMemory}!*ast.Expr {
                    const ident = try alloc.create(ast.Expr);
                    ident.* = .{ .ident = .{ .name = "IO.println", .span = undefined } };
                    const arg = try alloc.create(ast.Expr);
                    arg.* = .{ .string_literal = .{ .value = "x", .span = undefined } };
                    const call = try alloc.create(ast.Expr);
                    call.* = .{ .call = .{ .func = ident, .arg = arg, .span = undefined } };
                    const stmts = try alloc.alloc(ast.Stmt, 1);
                    stmts[0] = .{ .kind = .{ .expr = call }, .span = undefined };
                    const b = try alloc.create(ast.Expr);
                    b.* = .{ .do_block = .{ .body = stmts, .result = null, .span = undefined } };
                    return b;
                }
            }.f,
            .expect_effect = true,
            .expect_type = env_mod.unit_type,
        },
    };

    for (cases) |c| {
        var env = try TypeEnv.init(std.testing.allocator);
        defer env.deinit(std.testing.allocator);

        const body = try c.buildBody(std.testing.allocator);
        defer std.testing.allocator.destroy(body);

        const decls = [_]parser.Decl{
            .{ .function_def = .{ .name = "f", .params = &.{}, .return_type = null, .body = body, .span = undefined } },
        };

        const pt = primitive_mod.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
        const result = try infer_mod.infer(std.testing.allocator, &decls, &env, pt);
        try std.testing.expect(result.len == 1);
        try std.testing.expectEqual(c.expect_effect, result[0].kind.function_def.is_effect);
        try std.testing.expectEqual(c.expect_type, env.applySubst(result[0].kind.function_def.type_));
    }
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

    const pt = primitive_mod.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    const result = try infer_mod.infer(std.testing.allocator, &decls, &env, pt);
    try std.testing.expectEqual(@as(usize, 2), result.len);
}
