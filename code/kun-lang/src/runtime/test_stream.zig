const std = @import("std");
const stream_mod = @import("primitive/stream.zig");
const value_mod = @import("value.zig");
const RuntimeEnv = @import("primitive.zig").RuntimeEnv;

const Value = value_mod.Value;

fn makeEnv(allocator: std.mem.Allocator) RuntimeEnv {
    return .{ .frame = undefined, .primitives = .{ .bindings = &.{} }, .allocator = allocator };
}

test "stream range produces sequence" {
    const cases = [_]struct { start: i64, end: i64, step: i64, expected_len: usize }{
        .{ .start = 1, .end = 5, .step = 1, .expected_len = 4 },
        .{ .start = 0, .end = 10, .step = 2, .expected_len = 5 },
        .{ .start = 5, .end = 5, .step = 1, .expected_len = 0 },
        .{ .start = 10, .end = 1, .step = 1, .expected_len = 0 },
    };
    for (cases) |c| {
        var env = makeEnv(std.testing.allocator);
        const args = [_]Value{ Value{ .int = c.start }, Value{ .int = c.end }, Value{ .int = c.step } };
        const result = stream_mod.streamRangeImpl(&env, &args);
        if (c.expected_len == 0) {
            try std.testing.expect(result == .nil);
        } else {
            try std.testing.expect(result == .stream);
            const list_val = stream_mod.streamToListImpl(&env, &.{result});
            try std.testing.expectEqual(c.expected_len, list_val.list.items.len);
        }
    }
}

test "stream fromList toList round trip" {
    const cases = [_]struct { values: []const i64 }{
        .{ .values = &.{} },
        .{ .values = &.{42} },
        .{ .values = &.{ 1, 2, 3, 4, 5 } },
    };
    for (cases) |c| {
        const allocator = std.testing.allocator;
        var env = makeEnv(allocator);
        const items = try allocator.alloc(Value, c.values.len);
        for (c.values, 0..) |v, i| items[i] = Value{ .int = v };
        const list = Value{ .list = .{ .items = items, .cap = c.values.len } };
        const stream_val = stream_mod.streamFromListImpl(&env, &.{list});
        try std.testing.expect(stream_val == .stream);
        const result = stream_mod.streamToListImpl(&env, &.{stream_val});
        try std.testing.expectEqual(c.values.len, result.list.items.len);
        for (c.values, 0..) |v, i| {
            try std.testing.expectEqual(v, result.list.items[i].int);
        }
    }
}

test "stream lines and stringify" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const items = try allocator.alloc(Value, 2);
    items[0] = Value{ .string = "hello\n" };
    items[1] = Value{ .string = "world" };
    const list = Value{ .list = .{ .items = items, .cap = 2 } };
    const stream_val = stream_mod.streamFromListImpl(&env, &.{list});
    const result = stream_mod.streamStringImpl(&env, &.{stream_val});
    try std.testing.expect(result == .string);
    try std.testing.expect(std.mem.eql(u8, "hello\nworld", result.string));
}
