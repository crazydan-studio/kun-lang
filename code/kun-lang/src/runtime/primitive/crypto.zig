const std = @import("std");
const value_mod = @import("../value.zig");
const RuntimeEnv = @import("../primitive.zig").RuntimeEnv;

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

pub fn sha256StreamImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .bytes = &.{} }; }

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
    decoder.decode(buf, args[0].string) catch return value_mod.makeErr(1, Value{ .string = "decode error" }, env.allocator) catch return Value{ .nil = {} };
    return Value{ .bytes = buf };
}

pub fn dateTimeNowImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .int = 0 }; }
pub fn dateTimeFormatImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn dateTimeParseImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }

pub fn jsonFromStringImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn jsonToStringImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }

pub fn regexIsMatchImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .bool = false }; }
pub fn regexFromStringImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn regexFirstMatchImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn regexAllMatchesImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .list = .{ .items = &.{}, .cap = 0 } }; }
pub fn regexReplaceImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .string = "" }; }
pub fn regexReplaceAllImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .string = "" }; }
pub fn regexSplitImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .list = .{ .items = &.{}, .cap = 0 } }; }
pub fn validatorRegexImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
