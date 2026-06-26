const std = @import("std");
const regex = @import("regex");

const RegexHandle = regex.Regex;
const RuntimeEnv = @import("../runtime/primitive.zig").RuntimeEnv;
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;

pub fn compile(allocator: std.mem.Allocator, pattern: []const u8) !RegexHandle {
    return try RegexHandle.compile(allocator, pattern);
}

pub fn isMatch(allocator: std.mem.Allocator, pattern: []const u8, input: []const u8) !bool {
    var re = try RegexHandle.compile(allocator, pattern);
    defer re.deinit();
    return (try re.find(input)) != null;
}

pub fn firstMatch(allocator: std.mem.Allocator, pattern: []const u8, input: []const u8) !?[]const u8 {
    var re = try RegexHandle.compile(allocator, pattern);
    defer re.deinit();
    if (try re.find(input)) |match| {
        var m = match;
        defer m.deinit(allocator);
        return m.slice;
    }
    return null;
}

pub fn replace(allocator: std.mem.Allocator, pattern: []const u8, input: []const u8, replacement: []const u8) ![]const u8 {
    var re = try RegexHandle.compile(allocator, pattern);
    defer re.deinit();
    return try re.replace(allocator, input, replacement);
}

pub fn replaceAll(allocator: std.mem.Allocator, pattern: []const u8, input: []const u8, replacement: []const u8) ![]const u8 {
    var re = try RegexHandle.compile(allocator, pattern);
    defer re.deinit();
    return try re.replaceAll(allocator, input, replacement);
}

pub fn split(allocator: std.mem.Allocator, pattern: []const u8, input: []const u8) ![][]const u8 {
    var re = try RegexHandle.compile(allocator, pattern);
    defer re.deinit();
    return try re.split(allocator, input);
}
