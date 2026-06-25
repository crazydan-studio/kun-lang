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

test "glob match empty patterns" {
    try std.testing.expectEqual(true, glob_mod.match("", ""));
    try std.testing.expectEqual(false, glob_mod.match("", "a"));
}

test "glob match star only" {
    try std.testing.expectEqual(true, glob_mod.match("*", ""));
    try std.testing.expectEqual(true, glob_mod.match("*", "anything"));
    try std.testing.expectEqual(true, glob_mod.match("*", "with spaces and symbols!@#"));
}

test "glob match question mark" {
    try std.testing.expectEqual(true, glob_mod.match("?", "a"));
    try std.testing.expectEqual(true, glob_mod.match("?", "Z"));
    try std.testing.expectEqual(false, glob_mod.match("?", ""));
    try std.testing.expectEqual(false, glob_mod.match("?", "ab"));
    try std.testing.expectEqual(true, glob_mod.match("???", "abc"));
    try std.testing.expectEqual(false, glob_mod.match("???", "ab"));
}

test "glob match double star" {
    try std.testing.expectEqual(true, glob_mod.match("**", ""));
    try std.testing.expectEqual(true, glob_mod.match("**", "anything"));
    try std.testing.expectEqual(true, glob_mod.match("**", "a/b/c"));
    try std.testing.expectEqual(true, glob_mod.match("a**b", "ab"));
    try std.testing.expectEqual(true, glob_mod.match("a**b", "aXYZb"));
}

test "glob match character class edge cases" {
    try std.testing.expectEqual(true, glob_mod.match("[a-zA-Z]", "A"));
    try std.testing.expectEqual(true, glob_mod.match("[a-zA-Z]", "z"));
    try std.testing.expectEqual(false, glob_mod.match("[a-zA-Z]", "0"));
    try std.testing.expectEqual(true, glob_mod.match("[0-9a-fA-F]", "f"));
    try std.testing.expectEqual(true, glob_mod.match("[0-9a-fA-F]", "9"));
    try std.testing.expectEqual(false, glob_mod.match("[0-9a-fA-F]", "g"));
    try std.testing.expectEqual(true, glob_mod.match("[!0-9]", "a"));
    try std.testing.expectEqual(false, glob_mod.match("[!0-9]", "5"));
    try std.testing.expectEqual(true, glob_mod.match("[a-ce-g]", "b"));
    try std.testing.expectEqual(true, glob_mod.match("[a-ce-g]", "f"));
    try std.testing.expectEqual(false, glob_mod.match("[a-ce-g]", "d"));
}

test "glob match unclosed bracket" {
    try std.testing.expectEqual(false, glob_mod.match("[abc", "a"));
    try std.testing.expectEqual(false, glob_mod.match("[abc", "b"));
    try std.testing.expectEqual(false, glob_mod.match("[", "a"));
}

test "glob match star at boundaries" {
    try std.testing.expectEqual(true, glob_mod.match("*.txt", ".txt"));
    try std.testing.expectEqual(true, glob_mod.match("a*", "a"));
    try std.testing.expectEqual(true, glob_mod.match("a*", "abc"));
    try std.testing.expectEqual(false, glob_mod.match("a*", "b"));
    try std.testing.expectEqual(true, glob_mod.match("*c", "c"));
    try std.testing.expectEqual(true, glob_mod.match("*c", "abc"));
    try std.testing.expectEqual(false, glob_mod.match("*c", "ab"));
}

test "glob match single character" {
    try std.testing.expectEqual(true, glob_mod.match("a", "a"));
    try std.testing.expectEqual(false, glob_mod.match("a", "b"));
    try std.testing.expectEqual(true, glob_mod.match("\\", "\\"));
    try std.testing.expectEqual(true, glob_mod.match(".", "."));
}

test "glob match complex patterns" {
    try std.testing.expectEqual(true, glob_mod.match("f*.[ch]", "file.c"));
    try std.testing.expectEqual(true, glob_mod.match("f*.[ch]", "foo.h"));
    try std.testing.expectEqual(false, glob_mod.match("f*.[ch]", "file.cpp"));
    try std.testing.expectEqual(true, glob_mod.match("test_*.zig", "test_parser.zig"));
    try std.testing.expectEqual(true, glob_mod.match("test_*.zig", "test_file.zig"));
    try std.testing.expectEqual(false, glob_mod.match("test_*.zig", "parser.zig"));
}

test "glob match negative char class edge" {
    try std.testing.expectEqual(false, glob_mod.match("[!a]", "a"));
    try std.testing.expectEqual(true, glob_mod.match("[!a]", "b"));
    try std.testing.expectEqual(false, glob_mod.match("[!0-9]", "0"));
    try std.testing.expectEqual(false, glob_mod.match("[!0-9]", "5"));
    try std.testing.expectEqual(true, glob_mod.match("[!0-9]", "x"));
}
