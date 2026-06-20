const std = @import("std");
const lexer = @import("lexer/lexer.zig");
const parser = @import("parser/parser.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);

    if (args.len < 3 or !std.mem.eql(u8, args[1], "--dump-ast")) {
        try usage();
        return;
    }

    const file_path = args[2];
    const cwd = std.Io.Dir.cwd();
    const limit: std.Io.Limit = @enumFromInt(1024 * 1024);
    const source = try std.Io.Dir.readFileAlloc(cwd, init.io, file_path, allocator, limit);

    const tokens = try lexer.tokenize(allocator, source);
    const decls = try parser.parseModule(allocator, tokens);

    dumpAST(decls, source);
}

fn usage() !void {
    std.log.err("Usage: kun --dump-ast <file.kun>", .{});
}

fn dumpAST(decls: []const parser.Decl, source: []const u8) void {
    _ = source;
    std.log.info("=== AST dump: {} declarations ===", .{decls.len});
    for (decls, 0..) |decl, i| {
        std.log.info("  [{}] {s}", .{ i, @tagName(decl) });
    }
    std.log.info("=== end ===", .{});
}
