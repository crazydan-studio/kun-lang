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
    std.debug.print("{s}\n", .{args.string});
    return Value{ .unit = {} };
}

fn readlnImpl(env: *RuntimeEnv, args: *const Value) Value {
    _ = env;
    _ = args;
    @panic("unimplemented: IO.readln");
}

pub fn buildPrimitiveTable(comptime int_t: TypeId, comptime string_t: TypeId, comptime unit_t: TypeId, comptime stream_string_t: TypeId) PrimitiveTable {
    const bindings = [_]PrimitiveBinding{
        .{ .module = "IO", .name = "println", .fn_ptr = printlnImpl, .signature = unit_t, .is_effect = true },
        .{ .module = "IO", .name = "readln", .fn_ptr = readlnImpl, .signature = string_t, .is_effect = true },
    };
    _ = int_t;
    _ = stream_string_t;
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
