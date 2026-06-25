const std = @import("std");
const crypto_mod = @import("primitive/crypto.zig");
const stream_mod = @import("primitive/stream.zig");
const RuntimeEnv = @import("primitive.zig").RuntimeEnv;
const value_mod = @import("value.zig");

const Value = value_mod.Value;

fn makeEnv(allocator: std.mem.Allocator) RuntimeEnv {
    return .{ .frame = undefined, .primitives = .{ .bindings = &.{} }, .allocator = allocator };
}

test "json parse valid inputs" {
    const cases = [_]struct { input: []const u8, check: *const fn (Value) bool }{
        .{ .input = "42", .check = struct {
            fn f(v: Value) bool { return v.adt.tag == 0 and v.adt.payload.* == .int and v.adt.payload.*.int == 42; }
        }.f },
        .{ .input = "null", .check = struct {
            fn f(v: Value) bool { return v.adt.tag == 0 and v.adt.payload.* == .nil; }
        }.f },
        .{ .input = "true", .check = struct {
            fn f(v: Value) bool { return v.adt.tag == 0 and v.adt.payload.* == .bool and v.adt.payload.*.bool; }
        }.f },
        .{ .input = "false", .check = struct {
            fn f(v: Value) bool { return v.adt.tag == 0 and v.adt.payload.* == .bool and !v.adt.payload.*.bool; }
        }.f },
        .{ .input = "\"hello\"", .check = struct {
            fn f(v: Value) bool { return v.adt.tag == 0 and v.adt.payload.* == .string and std.mem.eql(u8, "hello", v.adt.payload.*.string); }
        }.f },
        .{ .input = "[]", .check = struct {
            fn f(v: Value) bool { return v.adt.tag == 0 and v.adt.payload.* == .list and v.adt.payload.*.list.items.len == 0; }
        }.f },
        .{ .input = "[1,2,3]", .check = struct {
            fn f(v: Value) bool { return v.adt.tag == 0 and v.adt.payload.* == .list and v.adt.payload.*.list.items.len == 3; }
        }.f },
        .{ .input = "{\"a\":1}", .check = struct {
            fn f(v: Value) bool { return v.adt.tag == 0 and v.adt.payload.* == .map and v.adt.payload.*.map.len == 1; }
        }.f },
    };
    for (cases) |c| {
        var env = makeEnv(std.testing.allocator);
        const args = [_]Value{Value{ .string = c.input }};
        const result = crypto_mod.jsonFromStringImpl(&env, &args);
        try std.testing.expect(c.check(result));
    }
}

test "json parse nested object" {
    var env = makeEnv(std.testing.allocator);
    const args = [_]Value{Value{ .string = "{\"x\":{\"y\":[1,2,{\"z\":3}]}}" }};
    const result = crypto_mod.jsonFromStringImpl(&env, &args);
    try std.testing.expect(result.adt.tag == 0);
    try std.testing.expect(result.adt.payload.* == .map);
    try std.testing.expectEqual(@as(u64, 1), result.adt.payload.*.map.len);
}

test "json parse escaped string" {
    var env = makeEnv(std.testing.allocator);
    const args = [_]Value{Value{ .string = "\"hello\\\"world\"" }};
    const result = crypto_mod.jsonFromStringImpl(&env, &args);
    try std.testing.expect(result.adt.tag == 0);
    try std.testing.expect(result.adt.payload.* == .string);
}

test "json parse negative number" {
    var env = makeEnv(std.testing.allocator);
    const args = [_]Value{Value{ .string = "-42" }};
    const result = crypto_mod.jsonFromStringImpl(&env, &args);
    try std.testing.expect(result.adt.tag == 0);
    try std.testing.expect(result.adt.payload.* == .int);
    try std.testing.expectEqual(@as(i64, -42), result.adt.payload.*.int);
}

test "json parse zero" {
    var env = makeEnv(std.testing.allocator);
    const args = [_]Value{Value{ .string = "0" }};
    const result = crypto_mod.jsonFromStringImpl(&env, &args);
    try std.testing.expect(result.adt.tag == 0);
    try std.testing.expectEqual(@as(i64, 0), result.adt.payload.*.int);
}

test "json parse float" {
    var env = makeEnv(std.testing.allocator);
    const args = [_]Value{Value{ .string = "3.14" }};
    const result = crypto_mod.jsonFromStringImpl(&env, &args);
    try std.testing.expect(result.adt.tag == 0);
    try std.testing.expect(result.adt.payload.* == .float);
}

test "json parse empty object" {
    var env = makeEnv(std.testing.allocator);
    const args = [_]Value{Value{ .string = "{}" }};
    const result = crypto_mod.jsonFromStringImpl(&env, &args);
    try std.testing.expect(result.adt.tag == 0);
    try std.testing.expect(result.adt.payload.* == .map);
    try std.testing.expectEqual(@as(u64, 0), result.adt.payload.*.map.len);
}

test "json parse invalid inputs" {
    const cases = [_][]const u8{
        "not json",
        "{bad",
        "[1,",
    };
    for (cases) |input| {
        var env = makeEnv(std.testing.allocator);
        const args = [_]Value{Value{ .string = input }};
        const result = crypto_mod.jsonFromStringImpl(&env, &args);
        try std.testing.expect(result == .adt);
        try std.testing.expectEqual(@as(u8, 1), result.adt.tag);
    }
}

test "json parse trailing comma" {
    var env = makeEnv(std.testing.allocator);
    const args = [_]Value{Value{ .string = "[1,]" }};
    const result = crypto_mod.jsonFromStringImpl(&env, &args);
    try std.testing.expect(result == .adt);
    try std.testing.expectEqual(@as(u8, 1), result.adt.tag);
}

test "json toString basic types" {
    const cases = [_]struct { val: Value, contains: []const u8 }{
        .{ .val = Value{ .int = 42 }, .contains = "42" },
        .{ .val = Value{ .nil = {} }, .contains = "null" },
        .{ .val = Value{ .bool = true }, .contains = "true" },
        .{ .val = Value{ .string = "hi" }, .contains = "hi" },
    };
    for (cases) |c| {
        var env = makeEnv(std.testing.allocator);
        const args = [_]Value{c.val};
        const result = crypto_mod.jsonToStringImpl(&env, &args);
        try std.testing.expect(result == .adt);
        try std.testing.expectEqual(@as(u8, 0), result.adt.tag);
        try std.testing.expect(std.mem.indexOf(u8, result.adt.payload.*.string, c.contains) != null);
    }
}

test "json toString array" {
    var env = makeEnv(std.testing.allocator);
    const items = [_]Value{ Value{ .int = 1 }, Value{ .int = 2 }, Value{ .int = 3 } };
    const val = Value{ .list = .{ .items = &items, .cap = 3 } };
    const args = [_]Value{val};
    const result = crypto_mod.jsonToStringImpl(&env, &args);
    try std.testing.expect(result == .adt);
    try std.testing.expectEqual(@as(u8, 0), result.adt.tag);
    try std.testing.expect(std.mem.indexOf(u8, result.adt.payload.*.string, "[1,2,3]") != null);
}

test "json toString empty array" {
    var env = makeEnv(std.testing.allocator);
    const val = Value{ .list = .{ .items = &.{}, .cap = 0 } };
    const args = [_]Value{val};
    const result = crypto_mod.jsonToStringImpl(&env, &args);
    try std.testing.expect(result == .adt);
    try std.testing.expectEqual(@as(u8, 0), result.adt.tag);
    try std.testing.expect(std.mem.indexOf(u8, result.adt.payload.*.string, "[]") != null);
}

test "sha256 of bytes" {
    var env = makeEnv(std.testing.allocator);
    const args = [_]Value{Value{ .bytes = "hello" }};
    const result = crypto_mod.sha256Impl(&env, &args);
    try std.testing.expect(result == .bytes);
    try std.testing.expectEqual(@as(usize, 32), result.bytes.len);
}

test "sha256 hex of bytes" {
    var env = makeEnv(std.testing.allocator);
    const args = [_]Value{Value{ .bytes = "hello" }};
    const result = crypto_mod.sha256HexImpl(&env, &args);
    try std.testing.expect(result == .string);
    try std.testing.expectEqual(@as(usize, 64), result.string.len);
}

test "sha256Stream with bytes stream" {
    var env = makeEnv(std.testing.allocator);
    const items = try std.testing.allocator.alloc(Value, 1);
    items[0] = Value{ .bytes = "test data" };
    const list = Value{ .list = .{ .items = items, .cap = 1 } };
    const stream_val = stream_mod.streamFromListImpl(&env, &.{list});
    const args = [_]Value{stream_val};
    const result = crypto_mod.sha256StreamImpl(&env, &args);
    try std.testing.expect(result == .bytes);
    try std.testing.expectEqual(@as(usize, 32), result.bytes.len);
}

test "sha256Stream with non-stream returns empty" {
    var env = makeEnv(std.testing.allocator);
    const args = [_]Value{Value{ .int = 0 }};
    const result = crypto_mod.sha256StreamImpl(&env, &args);
    try std.testing.expect(result == .bytes);
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
}

test "sha256 empty bytes" {
    var env = makeEnv(std.testing.allocator);
    const args = [_]Value{Value{ .bytes = "" }};
    const result = crypto_mod.sha256Impl(&env, &args);
    try std.testing.expect(result == .bytes);
    try std.testing.expectEqual(@as(usize, 32), result.bytes.len);
}

test "sha256 invalid arg type" {
    var env = makeEnv(std.testing.allocator);
    const args = [_]Value{Value{ .int = 42 }};
    const result = crypto_mod.sha256Impl(&env, &args);
    try std.testing.expect(result == .bytes);
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
}

test "base64 encode decode round trip" {
    var env = makeEnv(std.testing.allocator);
    const args_enc = [_]Value{Value{ .bytes = "hello world" }};
    const encoded = crypto_mod.base64EncodeImpl(&env, &args_enc);
    try std.testing.expect(encoded == .string);

    const args_dec = [_]Value{encoded};
    const decoded = crypto_mod.base64DecodeImpl(&env, &args_dec);
    try std.testing.expect(decoded == .bytes);
    try std.testing.expect(std.mem.eql(u8, "hello world", decoded.bytes));
}

test "base64 decode invalid string" {
    var env = makeEnv(std.testing.allocator);
    const args = [_]Value{Value{ .string = "!!!not base64!!!" }};
    const result = crypto_mod.base64DecodeImpl(&env, &args);
    try std.testing.expect(result == .adt);
    try std.testing.expectEqual(@as(u8, 1), result.adt.tag);
}
