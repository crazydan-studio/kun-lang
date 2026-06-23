const std = @import("std");
const value_mod = @import("value.zig");
const typed = @import("../ast/typed.zig");

const Value = value_mod.Value;
const TypeId = typed.TypeId;
const Frame = @import("env.zig").Frame;

pub const RuntimeEnv = struct {
    frame: *Frame,
    primitives: PrimitiveTable,
    allocator: std.mem.Allocator,

    pub fn init(frame: *Frame, primitives: PrimitiveTable, allocator: std.mem.Allocator) RuntimeEnv {
        return .{ .frame = frame, .primitives = primitives, .allocator = allocator };
    }
};

pub const PrimitiveFn = *const fn (env: *RuntimeEnv, args: *const Value) Value;

pub const PrimitiveBinding = struct {
    module: []const u8,
    name: []const u8,
    fn_ptr: PrimitiveFn,
    signature: TypeId,
    is_effect: bool,
};

pub const PrimitiveTable = struct {
    bindings: []const PrimitiveBinding,
};

fn printlnImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    if (args.* != .string) return Value{ .unit = {} };
    return Value{ .unit = {} };
}

fn readlnImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = args;
    _ = env;
    return Value{ .string = "" };
}

fn readStringImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn listDirImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn statImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn getenvImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn containsEnvImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .bool = false };
}

fn exitImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    const code: u8 = if (args.* == .int) @intCast(@min(args.int, 255)) else 0;
    std.process.exit(code);
}

fn pidImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .int = 1 };
}

fn uidImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .int = 0 };
}

fn gidImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .int = 0 };
}

fn whichImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn streamLinesImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn streamIterImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .unit = {} };
}

fn streamFoldImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .unit = {} };
}

fn streamToListImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn streamStringImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .string = "" };
}

fn streamBytesImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    return Value{ .bytes = &.{} };
}

pub fn buildPrimitiveTable(comptime int_t: TypeId, comptime string_t: TypeId, comptime unit_t: TypeId, comptime stream_string_t: TypeId) PrimitiveTable {
    const bindings = [_]PrimitiveBinding{
        .{ .module = "IO", .name = "println", .fn_ptr = printlnImpl, .signature = unit_t, .is_effect = true },
        .{ .module = "IO", .name = "readln", .fn_ptr = readlnImpl, .signature = string_t, .is_effect = true },
        .{ .module = "File", .name = "readString", .fn_ptr = readStringImpl, .signature = string_t, .is_effect = true },
        .{ .module = "File", .name = "list", .fn_ptr = listDirImpl, .signature = unit_t, .is_effect = true },
        .{ .module = "File", .name = "stat", .fn_ptr = statImpl, .signature = unit_t, .is_effect = true },
        .{ .module = "Env", .name = "getenv", .fn_ptr = getenvImpl, .signature = string_t, .is_effect = true },
        .{ .module = "Env", .name = "contains", .fn_ptr = containsEnvImpl, .signature = int_t, .is_effect = true },
        .{ .module = "Process", .name = "exit", .fn_ptr = exitImpl, .signature = unit_t, .is_effect = true },
        .{ .module = "Process", .name = "pid", .fn_ptr = pidImpl, .signature = int_t, .is_effect = true },
        .{ .module = "Process", .name = "uid", .fn_ptr = uidImpl, .signature = int_t, .is_effect = true },
        .{ .module = "Process", .name = "gid", .fn_ptr = gidImpl, .signature = int_t, .is_effect = true },
        .{ .module = "Cmd", .name = "which", .fn_ptr = whichImpl, .signature = string_t, .is_effect = true },
        .{ .module = "Stream", .name = "lines", .fn_ptr = streamLinesImpl, .signature = stream_string_t, .is_effect = false },
        .{ .module = "Stream", .name = "iter", .fn_ptr = streamIterImpl, .signature = unit_t, .is_effect = true },
        .{ .module = "Stream", .name = "fold", .fn_ptr = streamFoldImpl, .signature = unit_t, .is_effect = false },
        .{ .module = "Stream", .name = "toList", .fn_ptr = streamToListImpl, .signature = unit_t, .is_effect = false },
        .{ .module = "Stream", .name = "string", .fn_ptr = streamStringImpl, .signature = string_t, .is_effect = false },
        .{ .module = "Stream", .name = "bytes", .fn_ptr = streamBytesImpl, .signature = int_t, .is_effect = false },
    };
    if (int_t > 0) {} else {}
    return .{ .bindings = &bindings };
}

const EffectNamespacePattern = struct {
    module: []const u8,
    is_effect: bool,
};

const effect_namespaces = [_]EffectNamespacePattern{
    .{ .module = "IO", .is_effect = true },
    .{ .module = "File", .is_effect = true },
    .{ .module = "Env", .is_effect = true },
    .{ .module = "Process", .is_effect = true },
    .{ .module = "Task", .is_effect = true },
    .{ .module = "Random", .is_effect = true },
    .{ .module = "Stream.iter", .is_effect = true },
};

pub fn isEffectBinding(name: []const u8) bool {
    if (std.mem.eql(u8, name, "Signal.on")) return true;
    if (std.mem.startsWith(u8, name, "Cmd.")) {
        const rest = name["Cmd.".len..];
        if (std.mem.containsAtLeast(u8, rest, 1, "?")) return true;
        if (std.mem.containsAtLeast(u8, rest, 1, "!")) return true;
        if (std.mem.eql(u8, rest, "exec")) return true;
        if (std.mem.eql(u8, rest, "pipe?")) return true;
        if (std.mem.eql(u8, rest, "pipe!")) return true;
        if (std.mem.eql(u8, rest, "timeout")) return true;
        if (std.mem.eql(u8, rest, "retry")) return true;
        if (std.mem.eql(u8, rest, "execSafe")) return true;
        if (std.mem.eql(u8, rest, "which")) return true;
        return false;
    }
    for (effect_namespaces) |ns| {
        if (std.mem.startsWith(u8, name, ns.module) and ns.is_effect) {
            if (name.len == ns.module.len) return true;
            if (name.len > ns.module.len and name[ns.module.len] == '.') return true;
        }
    }
    return false;
}
