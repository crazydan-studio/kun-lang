const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const RuntimeEnv = @import("../runtime/primitive.zig").RuntimeEnv;

pub fn absImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .int = 0 };
    if (args[0] != .int) return Value{ .int = 0 };
    const n = args[0].int;
    return Value{ .int = if (n < 0) -n else n };
}

pub fn minImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 2) return if (args.len > 0) args[0] else Value{ .int = 0 };
    if (args[0] != .int or args[1] != .int) return Value{ .int = 0 };
    return Value{ .int = @min(args[0].int, args[1].int) };
}

pub fn maxImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 2) return if (args.len > 0) args[0] else Value{ .int = 0 };
    if (args[0] != .int or args[1] != .int) return Value{ .int = 0 };
    return Value{ .int = @max(args[0].int, args[1].int) };
}

pub fn powImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 2) return Value{ .int = 1 };
    if (args[0] != .int or args[1] != .int) return Value{ .int = 0 };
    const base = args[0].int;
    const exp = args[1].int;
    if (exp < 0) return Value{ .int = 0 };
    var result: i64 = 1;
    var i: i64 = 0;
    while (i < exp) {
        result *%= base;
        i += 1;
    }
    return Value{ .int = result };
}

pub fn clampImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 3) return if (args.len > 0) args[0] else Value{ .int = 0 };
    if (args[0] != .int or args[1] != .int or args[2] != .int) return Value{ .int = 0 };
    const x = args[0].int;
    const lo = args[1].int;
    const hi = args[2].int;
    return Value{ .int = @min(@max(x, lo), hi) };
}

pub fn fromStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

pub fn toFloatImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .float = 0 };
    if (args[0] != .int) return Value{ .float = 0 };
    return Value{ .float = @floatFromInt(args[0].int) };
}

pub fn toStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .string = .{ .ptr = "", .len = 0 } };
    return Value{ .string = .{ .ptr = "", .len = 0 } };
}
