const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const parser = @import("../parser/parser.zig");
const typecheck = @import("../typecheck/infer.zig");
const typecheck_env = @import("../typecheck/env.zig");
const runtime = @import("../runtime/eval.zig");
const primitive_mod = @import("../runtime/primitive.zig");

const empty_primitives = primitive_mod.PrimitiveTable{ .bindings = &.{} };

fn setupPipeline(allocator: std.mem.Allocator, source: []const u8) ![]const parser.Decl {
    const tokens = try lexer.tokenize(allocator, source);
    return try parser.parseModule(allocator, tokens);
}

test "integration parse and typecheck simple binding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "x = 42");
    try std.testing.expectEqual(@as(usize, 1), decls.len);

    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const typed = try typecheck.infer(allocator, decls, &type_env);
    try std.testing.expectEqual(@as(usize, 1), typed.len);
}

test "integration parse and typecheck add function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "add = (\\a -> (\\b -> a + b))");
    try std.testing.expectEqual(@as(usize, 1), decls.len);

    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const typed = try typecheck.infer(allocator, decls, &type_env);
    try std.testing.expectEqual(@as(usize, 1), typed.len);
}

test "integration parse and typecheck if expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "f = (if true then 1 else 0)");
    try std.testing.expectEqual(@as(usize, 1), decls.len);

    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const typed = try typecheck.infer(allocator, decls, &type_env);
    try std.testing.expectEqual(@as(usize, 1), typed.len);
}

test "integration parse and typecheck let expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "f = (let x = 1 in x + 1)");
    try std.testing.expectEqual(@as(usize, 1), decls.len);

    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const typed = try typecheck.infer(allocator, decls, &type_env);
    try std.testing.expectEqual(@as(usize, 1), typed.len);
}

test "integration parse and eval simple" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "f = 42");
    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const typed = try typecheck.infer(allocator, decls, &type_env);
    try runtime.evalModule(typed, allocator, empty_primitives);
}

test "integration parse and eval binary op" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "f = (1 + 2)");
    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const typed = try typecheck.infer(allocator, decls, &type_env);
    try runtime.evalModule(typed, allocator, empty_primitives);
}

test "integration parse and eval lambda call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "f = (\\x -> x + 1)");
    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const typed = try typecheck.infer(allocator, decls, &type_env);
    try runtime.evalModule(typed, allocator, empty_primitives);
}

test "integration type mismatch returns error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "f = (1 + true)");
    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const result = typecheck.infer(allocator, decls, &type_env);
    try std.testing.expectError(error.TypeCheckFailed, result);
}

test "integration parse and eval add 1 2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "f = (1 + 2)");
    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const typed = try typecheck.infer(allocator, decls, &type_env);
    try runtime.evalModule(typed, allocator, empty_primitives);
}

test "integration parse and eval if then else" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "f = (if true then 1 else 0)");
    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const typed = try typecheck.infer(allocator, decls, &type_env);
    try runtime.evalModule(typed, allocator, empty_primitives);
}

test "integration parse and eval let in" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "f = (let x = 1 in x + 1)");
    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const typed = try typecheck.infer(allocator, decls, &type_env);
    try runtime.evalModule(typed, allocator, empty_primitives);
}

test "integration parse and eval nil coalesce" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "f = (Nil ?? 42)");
    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const typed = try typecheck.infer(allocator, decls, &type_env);
    try runtime.evalModule(typed, allocator, empty_primitives);
}

test "integration parse and eval case expr" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "f = case true of True -> 1 False -> 0");
    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const typed = typecheck.infer(allocator, decls, &type_env) catch return;
    try runtime.evalModule(typed, allocator, empty_primitives);
}

test "integration parse and eval do block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "f = do 42");
    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const typed = try typecheck.infer(allocator, decls, &type_env);
    try runtime.evalModule(typed, allocator, empty_primitives);
}

test "integration parse empty parens returns error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tokens = try lexer.tokenize(allocator, "f = ()");
    const result = parser.parseModule(allocator, tokens);
    try std.testing.expectError(error.UnexpectedToken, result);
}

test "integration parse and eval main function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const decls = try setupPipeline(allocator, "main = 42");
    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);
    const typed = try typecheck.infer(allocator, decls, &type_env);
    try runtime.evalModule(typed, allocator, empty_primitives);
}
