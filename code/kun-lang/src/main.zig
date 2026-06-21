const std = @import("std");
const lexer = @import("lexer/lexer.zig");
const parser = @import("parser/parser.zig");
const typecheck = @import("typecheck/infer.zig");
const typecheck_env = @import("typecheck/env.zig");
const runtime = @import("runtime/eval.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);

    if (args.len < 3) {
        try usage();
        return;
    }

    const cmd = args[1];
    const file_path = args[2];

    if (!std.mem.eql(u8, cmd, "--dump-ast") and !std.mem.eql(u8, cmd, "--run")) {
        try usage();
        return;
    }

    const cwd = std.Io.Dir.cwd();
    const limit: std.Io.Limit = @enumFromInt(1024 * 1024);
    const source = try std.Io.Dir.readFileAlloc(cwd, init.io, file_path, allocator, limit);

    const tokens = try lexer.tokenize(allocator, source);
    const decls = try parser.parseModule(allocator, tokens);

    if (std.mem.eql(u8, cmd, "--dump-ast")) {
        dumpAST(decls, source);
        return;
    }

    var type_env = try typecheck_env.TypeEnv.init(allocator);
    defer type_env.deinit(allocator);

    const typed_decls = typecheck.infer(allocator, decls, &type_env) catch |err| {
        if (err == error.TypeCheckFailed) {
            std.log.err("type check failed", .{});
            return err;
        }
        return err;
    };

    try runtime.evalModule(typed_decls, allocator);
}

fn usage() !void {
    std.log.err("Usage: kun --dump-ast <file.kun>", .{});
    std.log.err("       kun --run <file.kun>", .{});
}

fn dumpAST(decls: []const parser.Decl, source: []const u8) void {
    _ = source;
    std.log.info("=== AST dump: {} declarations ===", .{decls.len});
    for (decls, 0..) |decl, i| {
        std.log.info("  [{}] {s}", .{ i, @tagName(decl) });
    }
    std.log.info("=== end ===", .{});
}
