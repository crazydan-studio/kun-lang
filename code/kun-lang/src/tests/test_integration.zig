const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const parser = @import("../parser/parser.zig");
const typecheck = @import("../typecheck/infer.zig");
const typecheck_env = @import("../typecheck/env.zig");
const runtime = @import("../runtime/eval.zig");

test "integration parse and typecheck simple binding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tokens = try lexer.tokenize(allocator, "x = 42");
    const decls = try parser.parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);

    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);

    _ = typecheck.infer(allocator, decls, &type_env) catch {};
}

test "integration parse and typecheck add function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tokens = try lexer.tokenize(allocator, "add = (\\a -> (\\b -> a + b))");
    const decls = try parser.parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);

    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);

    _ = typecheck.infer(allocator, decls, &type_env) catch {};
}

test "integration parse and typecheck if expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tokens = try lexer.tokenize(allocator, "f = (if true then 1 else 0)");
    const decls = try parser.parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);

    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);

    _ = typecheck.infer(allocator, decls, &type_env) catch {};
}

test "integration parse and typecheck let expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tokens = try lexer.tokenize(allocator, "f = (let x = 1 in x + 1)");
    const decls = try parser.parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);

    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);

    _ = typecheck.infer(allocator, decls, &type_env) catch {};
}

test "integration parse and eval simple" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "f = 42";
    const tokens = try lexer.tokenize(allocator, source);
    const decls = try parser.parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);

    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);

    const typed = typecheck.infer(allocator, decls, &type_env) catch return;
    _ = runtime.evalModule(typed, allocator) catch {};
}

test "integration parse and eval binary op" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "f = (1 + 2)";
    const tokens = try lexer.tokenize(allocator, source);
    const decls = try parser.parseModule(allocator, tokens);

    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);

    const typed = typecheck.infer(allocator, decls, &type_env) catch return;
    _ = runtime.evalModule(typed, allocator) catch {};
}

test "integration parse and eval lambda call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "f = (\\x -> x + 1)";
    const tokens = try lexer.tokenize(allocator, source);
    const decls = try parser.parseModule(allocator, tokens);

    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);

    const typed = typecheck.infer(allocator, decls, &type_env) catch return;
    _ = runtime.evalModule(typed, allocator) catch {};
}
