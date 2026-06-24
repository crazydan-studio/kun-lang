const std = @import("std");
const crypto_mod = @import("primitive/crypto.zig");
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
