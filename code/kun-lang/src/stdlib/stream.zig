const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const env_mod = @import("../runtime/env.zig");
const primitive_mod = @import("../runtime/primitive.zig");
const RuntimeEnv = primitive_mod.RuntimeEnv;
const stream_consumer = @import("../runtime/stream_consumer.zig");
const cmd_mod = @import("../command/cmd.zig");

const Value = value_mod.Value;
const StreamNode = value_mod.StreamNode;

pub fn streamLinesImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .stream) return Value{ .nil = {} };
    const node = value_mod.streamLines(env.allocator, args[0].stream, 65536) catch return Value{ .nil = {} };
    return Value{ .stream = node };
}

pub fn streamIterImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .closure or args[1] != .stream) return Value{ .unit = {} };
    const callback = args[0].closure;
    const stream_node = args[1].stream;
    const frame = env.allocator.create(env_mod.Frame) catch return Value{ .unit = {} };
    frame.* = env_mod.Frame{ .bindings = .empty, .parent = callback.env, .primitives = null };
    while (stream_consumer.consumeNext(stream_node, env.allocator, null) catch null) |val| {
        frame.bindings.clearRetainingCapacity();
        frame.bindings.put(env.allocator, callback.param_names[0], val) catch return Value{ .unit = {} };
        _ = primitive_mod.callEval(env, callback.body, frame) catch {};
    }
    return Value{ .unit = {} };
}

pub fn streamFoldImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 3 or args[0] != .closure or args[2] != .stream) return Value{ .unit = {} };
    const folder = args[0].closure;
    var acc = args[1];
    const stream_node = args[2].stream;
    const frame = env.allocator.create(env_mod.Frame) catch return Value{ .unit = {} };
    frame.* = env_mod.Frame{ .bindings = .empty, .parent = folder.env, .primitives = null };
    while (stream_consumer.consumeNext(stream_node, env.allocator, null) catch null) |val| {
        frame.bindings.clearRetainingCapacity();
        if (folder.param_names.len >= 2) {
            frame.bindings.put(env.allocator, folder.param_names[0], acc) catch return Value{ .unit = {} };
            frame.bindings.put(env.allocator, folder.param_names[1], val) catch return Value{ .unit = {} };
        } else if (folder.param_names.len == 1) {
            frame.bindings.put(env.allocator, folder.param_names[0], val) catch return Value{ .unit = {} };
        }
        acc = primitive_mod.callEval(env, folder.body, frame) catch return acc;
    }
    return acc;
}

pub fn streamToListImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .stream) return Value{ .nil = {} };
    var list: std.ArrayListUnmanaged(Value) = .empty;
    while (stream_consumer.consumeNext(args[0].stream, env.allocator, null) catch null) |val| {
        list.append(env.allocator, val) catch return Value{ .nil = {} };
    }
    const items = list.toOwnedSlice(env.allocator) catch return Value{ .nil = {} };
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

pub fn streamStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .stream) return Value{ .string = "" };
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    while (stream_consumer.consumeNext(args[0].stream, env.allocator, null) catch null) |val| {
        if (val != .string) continue;
        buf.appendSlice(env.allocator, val.string) catch break;
    }
    const s = buf.toOwnedSlice(env.allocator) catch return Value{ .string = "" };
    return Value{ .string = s };
}

pub fn streamBytesImpl(env: *RuntimeEnv, args: []const Value) Value {
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

pub fn streamFromListImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .list) return Value{ .stream = value_mod.streamFromList(env.allocator, &.{}) catch return Value{ .nil = {} } };
    const node = value_mod.streamFromList(env.allocator, args[0].list.items) catch return Value{ .nil = {} };
    return Value{ .stream = node };
}

pub fn streamRangeImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 3) return Value{ .nil = {} };
    const start = args[0];
    const end = args[1];
    const step = args[2];
    if (start != .int or end != .int or step != .int) return Value{ .nil = {} };
    if (step.int <= 0) return Value{ .nil = {} };
    const count: i64 = @divTrunc(end.int - start.int + step.int - 1, step.int);
    if (count <= 0) return Value{ .nil = {} };
    const items = env.allocator.alloc(Value, @intCast(count)) catch return Value{ .nil = {} };
    var i: i64 = 0;
    while (i < count) : (i += 1) {
        items[@intCast(i)] = Value{ .int = start.int + i * step.int };
    }
    const node = value_mod.streamFromList(env.allocator, items) catch return Value{ .nil = {} };
    return Value{ .stream = node };
}

pub fn streamIterateImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[1] != .closure) return Value{ .nil = {} };
    const seed = args[0];
    const f = args[1].closure;
    const node = value_mod.streamGenerate(env.allocator, seed, .{ .closure = &f }) catch return Value{ .nil = {} };
    return Value{ .stream = node };
}

pub fn streamLinesMaxImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .int or args[1] != .stream) return Value{ .nil = {} };
    const node = value_mod.streamLines(env.allocator, args[1].stream, @intCast(@max(args[0].int, 0))) catch return Value{ .nil = {} };
    return Value{ .stream = node };
}

pub fn cmdExecImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .command) return Value{ .unit = {} };
    const stream_node = cmd_mod.execCommand(&args[0].command, env.allocator) catch return Value{ .unit = {} };
    while (stream_consumer.consumeNext(stream_node, env.allocator, null) catch null) |_| {}
    return Value{ .unit = {} };
}

pub fn cmdExecSafeImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .command) return value_mod.makeErr(2, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .stream = cmd_mod.execCommand(&args[0].command, env.allocator) catch return value_mod.makeErr(2, Value{ .string = "exec error" }, env.allocator) catch return Value{ .nil = {} } }, env.allocator) catch return Value{ .nil = {} };
}

pub fn cmdPipeImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .command or args[1] != .command) return Value{ .nil = {} };
    const node = cmd_mod.execPipeCommand(&args[0].command, &args[1].command, env.allocator) catch return value_mod.makeErr(2, Value{ .string = "pipe error" }, env.allocator) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .stream = node }, env.allocator) catch return Value{ .nil = {} };
}

pub fn cmdPipeBangImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .command or args[1] != .command) return Value{ .unit = {} };
    const node = cmd_mod.execPipeCommand(&args[0].command, &args[1].command, env.allocator) catch return Value{ .unit = {} };
    while (stream_consumer.consumeNext(node, env.allocator, null) catch null) |_| {}
    return Value{ .unit = {} };
}
