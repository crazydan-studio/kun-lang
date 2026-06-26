const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const RuntimeEnv = @import("../runtime/primitive.zig").RuntimeEnv;

pub fn ofImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .char = 0 };
    return Value{ .char = @intCast(args[0].int) };
}

pub fn fromIntImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

pub fn isDigitImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .bool = false };
    return Value{ .bool = std.ascii.isDigit(@intCast(args[0].char)) };
}

pub fn isAlphaImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .bool = false };
    return Value{ .bool = std.ascii.isAlphabetic(@intCast(args[0].char)) };
}

pub fn isUpperImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .bool = false };
    return Value{ .bool = std.ascii.isUpper(@intCast(args[0].char)) };
}

pub fn isLowerImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .bool = false };
    return Value{ .bool = std.ascii.isLower(@intCast(args[0].char)) };
}

pub fn isWhitespaceImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .bool = false };
    return Value{ .bool = std.ascii.isWhitespace(@intCast(args[0].char)) };
}

pub fn isControlImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .bool = false };
    return Value{ .bool = std.ascii.isControl(@intCast(args[0].char)) };
}

pub fn toUpperImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .char = 0 };
    return Value{ .char = std.ascii.toUpper(@intCast(args[0].char)) };
}

pub fn toLowerImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .char = 0 };
    return Value{ .char = std.ascii.toLower(@intCast(args[0].char)) };
}

pub fn toIntImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .int = 0 };
    return Value{ .int = args[0].char };
}
