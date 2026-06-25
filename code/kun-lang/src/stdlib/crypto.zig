const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const RuntimeEnv = @import("../runtime/primitive.zig").RuntimeEnv;
const stream_consumer = @import("../runtime/stream_consumer.zig");
const hash_map = @import("../runtime/hash_map.zig");

const Value = value_mod.Value;

pub fn sha256Impl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .bytes) return Value{ .bytes = &.{} };
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(args[0].bytes, &out, .{});
    const result = env.allocator.dupe(u8, &out) catch return Value{ .nil = {} };
    return Value{ .bytes = result };
}

pub fn sha256HexImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .bytes) return Value{ .string = "" };
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(args[0].bytes, &out, .{});
    const hex_chars = "0123456789abcdef";
    const result = env.allocator.alloc(u8, 64) catch return Value{ .string = "" };
    for (&out, 0..) |byte, i| {
        result[i * 2] = hex_chars[byte >> 4];
        result[i * 2 + 1] = hex_chars[byte & 0xF];
    }
    return Value{ .string = result };
}

pub fn sha256StreamImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .stream) return Value{ .bytes = &.{} };
    var data_list: std.ArrayListUnmanaged(u8) = .empty;
    const stream_node = args[0].stream;
    while (stream_consumer.consumeNext(stream_node, env.allocator, null) catch null) |val| {
        const chunk = switch (val) {
            .bytes => |b| b,
            .string => |s| s,
            else => continue,
        };
        data_list.appendSlice(env.allocator, chunk) catch break;
    }
    defer data_list.deinit(env.allocator);
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data_list.items, &out, .{});
    const result = env.allocator.dupe(u8, &out) catch return Value{ .nil = {} };
    return Value{ .bytes = result };
}

pub fn base64EncodeImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .bytes) return Value{ .string = "" };
    const encoder = std.base64.standard.Encoder;
    const out_len = encoder.calcSize(args[0].bytes.len);
    const buf = env.allocator.alloc(u8, out_len) catch return Value{ .string = "" };
    const encoded = encoder.encode(buf, args[0].bytes);
    return Value{ .string = encoded };
}

pub fn base64DecodeImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .string) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const decoder = std.base64.standard.Decoder;
    const out_len = decoder.calcSizeForSlice(args[0].string) catch return value_mod.makeErr(1, Value{ .string = "invalid" }, env.allocator) catch return Value{ .nil = {} };
    const buf = env.allocator.alloc(u8, out_len) catch return Value{ .nil = {} };
    decoder.decode(buf, args[0].string) catch {
        env.allocator.free(buf);
        return value_mod.makeErr(1, Value{ .string = "decode error" }, env.allocator) catch return Value{ .nil = {} };
    };
    return Value{ .bytes = buf };
}

pub fn dateTimeNowImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .int = 0 }; }
pub fn dateTimeFormatImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn dateTimeParseImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }

pub fn jsonFromStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .string) return Value{ .nil = {} };
    const parsed = std.json.parseFromSlice(std.json.Value, env.allocator, args[0].string, .{}) catch {
        return value_mod.makeErr(1, Value{ .string = "parse error" }, env.allocator) catch return Value{ .nil = {} };
    };
    defer parsed.deinit();
    const result = jsonToKunValue(env.allocator, parsed.value) catch return Value{ .nil = {} };
    return value_mod.makeOk(result, env.allocator) catch return Value{ .nil = {} };
}

pub fn jsonToStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1) return Value{ .nil = {} };
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    kunToJsonValue(env.allocator, args[0], &buf) catch return Value{ .nil = {} };
    const s = buf.toOwnedSlice(env.allocator) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .string = s }, env.allocator) catch return Value{ .nil = {} };
}

fn jsonToKunValue(allocator: std.mem.Allocator, jv: std.json.Value) !Value {
    return switch (jv) {
        .null => Value{ .nil = {} },
        .bool => |b| Value{ .bool = b },
        .integer => |i| Value{ .int = i },
        .float => |f| Value{ .float = f },
        .string => |s| Value{ .string = try allocator.dupe(u8, s) },
        .array => |arr| {
            var items: std.ArrayListUnmanaged(Value) = .empty;
            for (arr.items) |item| {
                try items.append(allocator, try jsonToKunValue(allocator, item));
            }
            return Value{ .list = .{ .items = items.items, .cap = items.items.len } };
        },
        .object => |obj| {
            var map = value_mod.MapRepr{ .entries = @constCast(&[0]u8{}), .len = 0, .cap = 0 };
            var it = obj.iterator();
            while (it.next()) |entry| {
                const k = Value{ .string = try allocator.dupe(u8, entry.key_ptr.*) };
                const v = try jsonToKunValue(allocator, entry.value_ptr.*);
                map = try @import("../runtime/hash_map.zig").mapInsert(allocator, map.entries, map.len, map.cap, k, v);
            }
            return Value{ .map = map };
        },
        else => Value{ .nil = {} },
    };
}

fn kunToJsonValue(allocator: std.mem.Allocator, val: Value, buf: *std.ArrayListUnmanaged(u8)) !void {
    try buf.ensureUnusedCapacity(allocator, 256);
    switch (val) {
        .nil => buf.appendSliceAssumeCapacity("null"),
        .bool => |b| {
            const s = if (b) "true" else "false";
            buf.appendSliceAssumeCapacity(s);
        },
        .int => |i| {
            var tmp: [32]u8 = undefined;
            const s = try std.fmt.bufPrint(&tmp, "{d}", .{i});
            buf.appendSliceAssumeCapacity(s);
        },
        .float => |f| {
            var tmp: [64]u8 = undefined;
            const s = try std.fmt.bufPrint(&tmp, "{d}", .{f});
            buf.appendSliceAssumeCapacity(s);
        },
        .string => |s| {
            buf.appendSliceAssumeCapacity("\"");
            buf.appendSliceAssumeCapacity(s);
            buf.appendSliceAssumeCapacity("\"");
        },
        .list => |l| {
            buf.appendSliceAssumeCapacity("[");
            for (l.items, 0..) |item, idx| {
                if (idx > 0) buf.appendSliceAssumeCapacity(",");
                try kunToJsonValue(allocator, item, buf);
            }
            buf.appendSliceAssumeCapacity("]");
        },
        .map => |m| {
            buf.appendSliceAssumeCapacity("{");
            const keys = hash_map.mapKeys(allocator, m.entries, m.len, m.cap) catch {
                buf.appendSliceAssumeCapacity("null");
                return;
            };
            defer allocator.free(keys);
            for (keys, 0..) |key, idx| {
                if (idx > 0) buf.appendSliceAssumeCapacity(",");
                try kunToJsonValue(allocator, key, buf);
                buf.appendSliceAssumeCapacity(":");
                const found_val = hash_map.mapGet(m.entries, m.len, m.cap, key) orelse {
                    buf.appendSliceAssumeCapacity("null");
                    continue;
                };
                try kunToJsonValue(allocator, found_val, buf);
            }
            buf.appendSliceAssumeCapacity("}");
        },
        else => buf.appendSliceAssumeCapacity("null"),
    }
}

pub fn regexIsMatchImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .bool = false }; }
pub fn regexFromStringImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn regexFirstMatchImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn regexAllMatchesImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .list = .{ .items = &.{}, .cap = 0 } }; }
pub fn regexReplaceImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .string = "" }; }
pub fn regexReplaceAllImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .string = "" }; }
pub fn regexSplitImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .list = .{ .items = &.{}, .cap = 0 } }; }
pub fn validatorRegexImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
