const std = @import("std");
const regex_engine = @import("regex_engine.zig");

test "regex isMatch basic" {
    const allocator = std.testing.allocator;
    try std.testing.expect(try regex_engine.isMatch(allocator, "hello", "hello world"));
    try std.testing.expect(!try regex_engine.isMatch(allocator, "hello", "world"));
}

test "regex isMatch with digit" {
    const allocator = std.testing.allocator;
    try std.testing.expect(try regex_engine.isMatch(allocator, "\\d+", "123"));
    try std.testing.expect(!try regex_engine.isMatch(allocator, "\\d+", "abc"));
}

test "regex firstMatch" {
    const allocator = std.testing.allocator;
    const result = try regex_engine.firstMatch(allocator, "\\d+", "abc 123 def");
    try std.testing.expect(result != null);
    if (result) |m| try std.testing.expectEqualStrings("123", m);
}

test "regex replace" {
    const allocator = std.testing.allocator;
    const result = try regex_engine.replace(allocator, "world", "hello world", "Zig");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello Zig", result);
}
