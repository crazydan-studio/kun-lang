const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const RuntimeEnv = @import("../runtime/primitive.zig").RuntimeEnv;

pub fn toNanosImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .int = 0 };
    if (args[0] != .duration) return Value{ .int = 0 };
    return Value{ .int = args[0].duration };
}

pub fn toMicrosImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .int = 0 };
    if (args[0] != .duration) return Value{ .int = 0 };
    return Value{ .int = args[0].duration / 1000 };
}

pub fn toMillisImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .int = 0 };
    if (args[0] != .duration) return Value{ .int = 0 };
    return Value{ .int = args[0].duration / (1000 * 1000) };
}

pub fn toSecondsImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .int = 0 };
    if (args[0] != .duration) return Value{ .int = 0 };
    return Value{ .int = args[0].duration / (1000 * 1000 * 1000) };
}

pub fn toMinutesImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .int = 0 };
    if (args[0] != .duration) return Value{ .int = 0 };
    return Value{ .int = args[0].duration / (60 * 1000 * 1000 * 1000) };
}

pub fn toHoursImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .int = 0 };
    if (args[0] != .duration) return Value{ .int = 0 };
    return Value{ .int = args[0].duration / (3600 * 1000 * 1000 * 1000) };
}

pub fn toDaysImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .int = 0 };
    if (args[0] != .duration) return Value{ .int = 0 };
    return Value{ .int = args[0].duration / (24 * 3600 * 1000 * 1000 * 1000) };
}

pub fn fromStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

pub fn fromMillisImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .duration = 0 };
    if (args[0] != .int) return Value{ .duration = 0 };
    return Value{ .duration = args[0].int * (1000 * 1000) };
}

pub fn toStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .string = .{ .ptr = "", .len = 0 } };
    return Value{ .string = .{ .ptr = "", .len = 0 } };
}

pub fn formatImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

pub fn negateImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .duration = 0 };
    if (args[0] != .duration) return Value{ .duration = 0 };
    return Value{ .duration = -args[0].duration };
}

pub fn isNegativeImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .bool = false };
    if (args[0] != .duration) return Value{ .bool = false };
    return Value{ .bool = args[0].duration < 0 };
}

pub fn absImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .duration = 0 };
    if (args[0] != .duration) return Value{ .duration = 0 };
    const d = args[0].duration;
    return Value{ .duration = if (d < 0) -d else d };
}
