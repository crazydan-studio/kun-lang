const std = @import("std");
const value_mod = @import("value.zig");
const typed = @import("../ast/typed.zig");
const stream_consumer = @import("stream_consumer.zig");

const Value = value_mod.Value;
const TypeId = typed.TypeId;
const Frame = @import("env.zig").Frame;
const StreamNode = value_mod.StreamNode;
const StreamFn = value_mod.StreamFn;

pub const RuntimeEnv = struct {
    frame: *Frame,
    primitives: PrimitiveTable,
    allocator: std.mem.Allocator,

    pub fn init(frame: *Frame, primitives: PrimitiveTable, allocator: std.mem.Allocator) RuntimeEnv {
        return .{ .frame = frame, .primitives = primitives, .allocator = allocator };
    }
};

pub const PrimitiveFn = *const fn (env: *RuntimeEnv, args: []const Value) Value;

pub const PrimitiveBinding = struct {
    module: []const u8,
    name: []const u8,
    fn_ptr: PrimitiveFn,
    arg_count: u8,
    return_type: TypeId,
    is_polymorphic: bool,
    is_effect: bool,
};

pub const PrimitiveTable = struct {
    bindings: []const PrimitiveBinding,
};

fn printlnImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len > 0 and args[0] == .string) return Value{ .unit = {} };
    return Value{ .unit = {} };
}

fn readlnImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    _ = env;
    return Value{ .string = "" };
}

fn readStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn listDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn statImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn getenvImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn containsEnvImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .bool = false };
}

fn exitImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    const code: u8 = if (args.len > 0 and args[0] == .int) @intCast(@min(args[0].int, 255)) else 0;
    std.process.exit(code);
}

fn pidImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .int = 1 };
}

fn uidImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .int = 0 };
}

fn gidImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .int = 0 };
}

fn whichImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn streamLinesImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .stream) return Value{ .nil = {} };
    const node = value_mod.streamLines(env.allocator, args[0].stream, 65536) catch return Value{ .nil = {} };
    return Value{ .stream = node };
}

fn streamIterImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .unit = {} };
}

fn streamFoldImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .unit = {} };
}

fn streamToListImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .stream) return Value{ .nil = {} };
    var list: std.ArrayListUnmanaged(Value) = .empty;
    while (stream_consumer.consumeNext(args[0].stream, env.allocator, null) catch null) |val| {
        list.append(env.allocator, val) catch return Value{ .nil = {} };
    }
    const items = list.toOwnedSlice(env.allocator) catch return Value{ .nil = {} };
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

fn streamStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .stream) return Value{ .string = "" };
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    while (stream_consumer.consumeNext(args[0].stream, env.allocator, null) catch null) |val| {
        if (val != .string) continue;
        buf.appendSlice(env.allocator, val.string) catch break;
    }
    const s = buf.toOwnedSlice(env.allocator) catch return Value{ .string = "" };
    return Value{ .string = s };
}

fn streamBytesImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .stream) return Value{ .bytes = &.{} };
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    while (stream_consumer.consumeNext(args[0].stream, env.allocator, null) catch null) |val| {
        if (val != .bytes) {
            const s = switch (val) {
                .string => |s| s,
                .int => |i| blk: {
                    var b: [32]u8 = undefined;
                    break :blk std.fmt.bufPrint(&b, "{d}", .{i}) catch continue;
                },
                else => continue,
            };
            buf.appendSlice(env.allocator, s) catch break;
        } else {
            buf.appendSlice(env.allocator, val.bytes) catch break;
        }
    }
    const b = buf.toOwnedSlice(env.allocator) catch return Value{ .bytes = &.{} };
    return Value{ .bytes = b };
}

pub fn buildPrimitiveTable(comptime int_t: TypeId, comptime string_t: TypeId, comptime unit_t: TypeId, comptime stream_string_t: TypeId, comptime bool_t: TypeId, comptime bytes_t: TypeId) PrimitiveTable {
    const P = true;
    const bindings = [_]PrimitiveBinding{
        .{ .module = "IO", .name = "println", .fn_ptr = printlnImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "readln", .fn_ptr = readlnImpl, .arg_count = 0, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "readString", .fn_ptr = readStringImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "list", .fn_ptr = listDirImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "stat", .fn_ptr = statImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Env", .name = "getenv", .fn_ptr = getenvImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Env", .name = "contains", .fn_ptr = containsEnvImpl, .arg_count = 1, .return_type = bool_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "exit", .fn_ptr = exitImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "pid", .fn_ptr = pidImpl, .arg_count = 0, .return_type = int_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "uid", .fn_ptr = uidImpl, .arg_count = 0, .return_type = int_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "gid", .fn_ptr = gidImpl, .arg_count = 0, .return_type = int_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Cmd", .name = "which", .fn_ptr = whichImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Stream", .name = "lines", .fn_ptr = streamLinesImpl, .arg_count = 1, .return_type = stream_string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Stream", .name = "iter", .fn_ptr = streamIterImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = true },
        .{ .module = "Stream", .name = "fold", .fn_ptr = streamFoldImpl, .arg_count = 3, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Stream", .name = "toList", .fn_ptr = streamToListImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Stream", .name = "string", .fn_ptr = streamStringImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Stream", .name = "bytes", .fn_ptr = streamBytesImpl, .arg_count = 1, .return_type = bytes_t, .is_polymorphic = P, .is_effect = false },
    };
    _ = .{ int_t, string_t, unit_t, stream_string_t, bool_t, bytes_t };
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
