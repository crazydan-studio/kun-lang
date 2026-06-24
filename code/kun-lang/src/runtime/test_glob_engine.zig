const std = @import("std");
const glob_mod = @import("glob_engine.zig");

test "glob match patterns" {
    const cases = [_]struct { pattern: []const u8, input: []const u8, expected: bool }{
        .{ .pattern = "hello", .input = "hello", .expected = true },
        .{ .pattern = "hello", .input = "world", .expected = false },
        .{ .pattern = "*.txt", .input = "file.txt", .expected = true },
        .{ .pattern = "*.txt", .input = "file.log", .expected = false },
        .{ .pattern = "a*c", .input = "abc", .expected = true },
        .{ .pattern = "a*c", .input = "aXYZc", .expected = true },
        .{ .pattern = "a?c", .input = "abc", .expected = true },
        .{ .pattern = "a?c", .input = "axc", .expected = true },
        .{ .pattern = "a?c", .input = "ac", .expected = false },
        .{ .pattern = "[abc]", .input = "a", .expected = true },
        .{ .pattern = "[abc]", .input = "d", .expected = false },
        .{ .pattern = "[!abc]", .input = "a", .expected = false },
        .{ .pattern = "[!abc]", .input = "d", .expected = true },
        .{ .pattern = "[a-z]", .input = "m", .expected = true },
        .{ .pattern = "[a-z]", .input = "9", .expected = false },
        .{ .pattern = "[0-9]", .input = "5", .expected = true },
        .{ .pattern = "*.txt", .input = "readme.TXT", .expected = false },
        .{ .pattern = "*.*", .input = "file.tar.gz", .expected = true },
    };
    for (cases) |c| {
        try std.testing.expectEqual(c.expected, glob_mod.match(c.pattern, c.input));
    }
}
