const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const RuntimeEnv = @import("../runtime/primitive.zig").RuntimeEnv;

/// Nilable.withDefault : a -> ?a -> a
pub fn withDefaultImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 2) return args[0];
    if (args[1] == .nil) return args[0];
    return args[1];
}

/// Nilable.map : (a -> b) -> ?a -> ?b
pub fn mapImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

/// Nilable.orElse : ?a -> ?a -> ?a
pub fn orElseImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 2) return args[0];
    if (args[0] != .nil) return args[0];
    return args[1];
}

/// Nilable.toResult : e -> ?a -> Result a e
pub fn toResultImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 2) return args[0];
    return args[1];
}

/// Nilable.andThen : (a -> ?b) -> ?a -> ?b
pub fn andThenImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

/// Nilable.isNil : ?a -> Bool
pub fn isNilImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .bool = true };
    return Value{ .bool = args[0] == .nil };
}

/// Nilable.isSome : ?a -> Bool
pub fn isSomeImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1) return Value{ .bool = false };
    return Value{ .bool = args[0] != .nil };
}

/// Nilable.filter : (a -> Bool) -> ?a -> ?a
pub fn filterImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}
