const std = @import("std");
const value_mod = @import("value.zig");
const RuntimeEnv = @import("primitive.zig").RuntimeEnv;

const Value = value_mod.Value;

pub fn listLengthImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .list) return Value{ .int = 0 };
    return Value{ .int = @intCast(args[0].list.items.len) };
}

pub fn listIsEmptyImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .list) return Value{ .bool = true };
    return Value{ .bool = args[0].list.items.len == 0 };
}

pub fn listHeadImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .list or args[0].list.items.len == 0) return Value{ .nil = {} };
    return args[0].list.items[0];
}

pub fn listLastImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .list or args[0].list.items.len == 0) return Value{ .nil = {} };
    return args[0].list.items[args[0].list.items.len - 1];
}

pub fn listGetImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 2 or args[0] != .int or args[1] != .list) return Value{ .nil = {} };
    const idx: usize = @intCast(@max(args[0].int, 0));
    if (idx >= args[1].list.items.len) return Value{ .nil = {} };
    return args[1].list.items[idx];
}

pub fn listAppendImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .list or args[1] != .list) return Value{ .nil = {} };
    const a = args[0].list;
    const b = args[1].list;
    const items = env.allocator.alloc(Value, a.items.len + b.items.len) catch return Value{ .nil = {} };
    @memcpy(items[0..a.items.len], a.items);
    @memcpy(items[a.items.len..], b.items);
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

pub fn listReverseImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .list) return Value{ .nil = {} };
    const src = args[0].list.items;
    const items = env.allocator.alloc(Value, src.len) catch return Value{ .nil = {} };
    for (src, 0..) |v, i| {
        items[src.len - 1 - i] = v;
    }
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

pub fn listSortImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[1] != .list) return Value{ .nil = {} };
    const src = args[1].list.items;
    if (src.len == 0) return args[1];
    const items = env.allocator.alloc(Value, src.len) catch return Value{ .nil = {} };
    @memcpy(items, src);
    std.mem.sort(Value, items, {}, cmpValue);
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

fn cmpValue(_: void, a: Value, b: Value) bool {
    if (a == .int and b == .int) return a.int < b.int;
    if (a == .string and b == .string) return std.mem.lessThan(u8, a.string, b.string);
    return @intFromEnum(a) < @intFromEnum(b);
}

pub fn listSliceImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 3 or args[0] != .int or args[1] != .int or args[2] != .list) return Value{ .nil = {} };
    const start: usize = @intCast(@max(args[0].int, 0));
    const len: usize = @intCast(@max(args[1].int, 0));
    const src = args[2].list.items;
    const actual_start = @min(start, src.len);
    const actual_end = @min(actual_start + len, src.len);
    const items = env.allocator.alloc(Value, actual_end - actual_start) catch return Value{ .nil = {} };
    @memcpy(items, src[actual_start..actual_end]);
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

pub fn listTakeImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .int or args[1] != .list) return Value{ .nil = {} };
    const n: usize = @intCast(@max(args[0].int, 0));
    const src = args[1].list.items;
    const count = @min(n, src.len);
    const items = env.allocator.alloc(Value, count) catch return Value{ .nil = {} };
    @memcpy(items, src[0..count]);
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

pub fn listDropImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .int or args[1] != .list) return Value{ .nil = {} };
    const n: usize = @intCast(@max(args[0].int, 0));
    const src = args[1].list.items;
    if (n >= src.len) return Value{ .list = .{ .items = &.{}, .cap = 0 } };
    const items = env.allocator.alloc(Value, src.len - n) catch return Value{ .nil = {} };
    @memcpy(items, src[n..]);
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

pub fn mapSizeImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .map) return Value{ .int = 0 };
    return Value{ .int = @intCast(args[0].map.len) };
}

pub fn mapIsEmptyImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .map) return Value{ .bool = true };
    return Value{ .bool = args[0].map.len == 0 };
}

pub fn mapInsertImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn mapGetImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn mapRemoveImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn mapKeysImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .list = .{ .items = &.{}, .cap = 0 } }; }
pub fn mapValuesImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .list = .{ .items = &.{}, .cap = 0 } }; }

pub fn setSizeImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .set) return Value{ .int = 0 };
    return Value{ .int = @intCast(args[0].set.len) };
}
pub fn setIsEmptyImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .set) return Value{ .bool = true };
    return Value{ .bool = args[0].set.len == 0 };
}
pub fn setContainsImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .bool = false }; }
pub fn setInsertImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn setRemoveImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }

pub fn bytesLengthImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .bytes) return Value{ .int = 0 };
    return Value{ .int = @intCast(args[0].bytes.len) };
}
pub fn bytesSliceImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 3 or args[0] != .int or args[1] != .int or args[2] != .bytes) return Value{ .bytes = &.{} };
    const start: usize = @intCast(@max(args[0].int, 0));
    const len: usize = @intCast(@max(args[1].int, 0));
    const src = args[2].bytes;
    if (start >= src.len) return Value{ .bytes = &.{} };
    const end = @min(start + len, src.len);
    return Value{ .bytes = src[start..end] };
}

pub fn stringLengthImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .string) return Value{ .int = 0 };
    return Value{ .int = @intCast(args[0].string.len) };
}
pub fn stringSliceImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 3 or args[0] != .int or args[1] != .int or args[2] != .string) return Value{ .string = "" };
    const start: usize = @intCast(@max(args[0].int, 0));
    const len: usize = @intCast(@max(args[1].int, 0));
    const src = args[2].string;
    if (start >= src.len) return Value{ .string = "" };
    const end = @min(start + len, src.len);
    const result = env.allocator.dupe(u8, src[start..end]) catch return Value{ .string = "" };
    return Value{ .string = result };
}
pub fn stringToStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1) return Value{ .string = "" };
    return switch (args[0]) {
        .int => |i| {
            const s = std.fmt.allocPrint(env.allocator, "{d}", .{i}) catch return Value{ .string = "" };
            return Value{ .string = s };
        },
        .float => |f| {
            const s = std.fmt.allocPrint(env.allocator, "{d}", .{f}) catch return Value{ .string = "" };
            return Value{ .string = s };
        },
        .bool => |b| Value{ .string = if (b) "true" else "false" },
        .string => |s| Value{ .string = s },
        else => Value{ .string = "" },
    };
}
