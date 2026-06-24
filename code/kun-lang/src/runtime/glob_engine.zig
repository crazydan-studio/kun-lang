const std = @import("std");

pub fn match(pattern: []const u8, filename: []const u8) bool {
    return matchRecursive(pattern, filename, 0, 0);
}

fn matchRecursive(pattern: []const u8, name: []const u8, pi: usize, ni: usize) bool {
    var p = pi;
    var n = ni;
    while (p < pattern.len) {
        switch (pattern[p]) {
            '*' => {
                if (p + 1 >= pattern.len) return true;
                var nn = n;
                while (nn <= name.len) : (nn += 1) {
                    if (matchRecursive(pattern, name, p + 1, nn)) return true;
                }
                return false;
            },
            '?' => {
                if (n >= name.len) return false;
                p += 1;
                n += 1;
            },
            '[' => {
                if (n >= name.len) return false;
                const end = std.mem.indexOfScalarPos(u8, pattern, p + 1, ']') orelse return false;
                const negate = p + 1 < pattern.len and pattern[p + 1] == '!';
                const class_start = if (negate) p + 2 else p + 1;
                const class = pattern[class_start..end];
                const matched = for (class, 0..) |c, i| {
                    if (c == name[n]) break true;
                    if (i + 2 < class.len and class[i + 1] == '-' and class[i + 2] >= c) {
                        if (name[n] >= c and name[n] <= class[i + 2]) break true;
                    }
                } else false;
                if (negate == matched) return false;
                p = end + 1;
                n += 1;
            },
            else => {
                if (n >= name.len or pattern[p] != name[n]) return false;
                p += 1;
                n += 1;
            },
        }
    }
    return n == name.len;
}

test "glob literal match" {
    try std.testing.expect(match("hello", "hello"));
    try std.testing.expect(!match("hello", "world"));
}

test "glob star" {
    try std.testing.expect(match("*.txt", "file.txt"));
    try std.testing.expect(!match("*.txt", "file.log"));
    try std.testing.expect(match("a*c", "abc"));
    try std.testing.expect(match("a*c", "aXYZc"));
}

test "glob question" {
    try std.testing.expect(match("a?c", "abc"));
    try std.testing.expect(match("a?c", "axc"));
    try std.testing.expect(!match("a?c", "ac"));
}

test "glob charclass" {
    try std.testing.expect(match("[abc]", "a"));
    try std.testing.expect(match("[abc]", "b"));
    try std.testing.expect(!match("[abc]", "d"));
    try std.testing.expect(!match("[!abc]", "a"));
    try std.testing.expect(match("[!abc]", "d"));
}

test "glob range" {
    try std.testing.expect(match("[a-z]", "m"));
    try std.testing.expect(!match("[a-z]", "9"));
    try std.testing.expect(match("[0-9]", "5"));
}
