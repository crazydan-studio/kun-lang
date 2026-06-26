const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const RuntimeEnv = @import("../runtime/primitive.zig").RuntimeEnv;

/// oneOf : List String -> String -> Result String String
pub fn oneOfImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2) return Value{ .nil = {} };
    const list = args[0];
    const input = args[1];
    if (list != .list) return Value{ .nil = {} };
    if (input != .string) return Value{ .nil = {} };

    for (list.list.items) |item| {
        if (item == .string and std.mem.eql(u8, item.string, input.string)) {
            return value_mod.makeOk(input, env.allocator) catch Value{ .nil = {} };
        }
    }

    const err_msg = value_mod.makeErr(1, Value{ .string = "not in allowed values" }, env.allocator) catch Value{ .nil = {} };
    return err_msg;
}

/// range : Int -> Int -> Int -> Result Int String
pub fn rangeImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 3) return Value{ .nil = {} };
    const lo = args[0];
    const hi = args[1];
    const val = args[2];
    if (lo != .int or hi != .int or val != .int) return Value{ .nil = {} };

    if (val.int >= lo.int and val.int <= hi.int) {
        return value_mod.makeOk(val, env.allocator) catch Value{ .nil = {} };
    }

    return value_mod.makeErr(1, Value{ .string = "value out of range" }, env.allocator) catch Value{ .nil = {} };
}

/// nonEmpty : String -> Result String String
pub fn nonEmptyImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1) return Value{ .nil = {} };
    const input = args[0];
    if (input != .string) return Value{ .nil = {} };

    if (input.string.len > 0) {
        return value_mod.makeOk(input, env.allocator) catch Value{ .nil = {} };
    }

    return value_mod.makeErr(1, Value{ .string = "value must not be empty" }, env.allocator) catch Value{ .nil = {} };
}

/// regex : String -> String -> Result String String
pub fn regexImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    // TODO: delegate to Regex.fromString when zig-regex is available
    return Value{ .nil = {} };
}
