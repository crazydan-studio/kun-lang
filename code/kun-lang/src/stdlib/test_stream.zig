const std = @import("std");
const stream_mod = @import("stream.zig");
const value_mod = @import("../runtime/value.zig");
const typed = @import("../ast/typed.zig");
const RuntimeEnv = @import("../runtime/primitive.zig").RuntimeEnv;

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
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
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
        const items = try std.testing.allocator.alloc(Value, c.values.len);
        defer std.testing.allocator.free(items);
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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const items = try std.testing.allocator.alloc(Value, 2);
    defer std.testing.allocator.free(items);
    items[0] = Value{ .string = "hello\n" };
    items[1] = Value{ .string = "world" };
    const list = Value{ .list = .{ .items = items, .cap = 2 } };
    const stream_val = stream_mod.streamFromListImpl(&env, &.{list});
    const result = stream_mod.streamStringImpl(&env, &.{stream_val});
    try std.testing.expect(result == .string);
    try std.testing.expect(std.mem.eql(u8, "hello\nworld", result.string));
}

test "stream range descending" {
    const cases = [_]struct { start: i64, end: i64, step: i64, expected_nil: bool }{
        .{ .start = 10, .end = 1, .step = -1, .expected_nil = true },
        .{ .start = 5, .end = 10, .step = 0, .expected_nil = true },
        .{ .start = 0, .end = 5, .step = -2, .expected_nil = true },
    };
    for (cases) |c| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
        const args = [_]Value{ Value{ .int = c.start }, Value{ .int = c.end }, Value{ .int = c.step } };
        const result = stream_mod.streamRangeImpl(&env, &args);
        try std.testing.expectEqual(c.expected_nil, result == .nil);
    }
}

test "stream range non-int args returns nil" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const args = [_]Value{ Value{ .string = "a" }, Value{ .int = 5 }, Value{ .int = 1 } };
    const result = stream_mod.streamRangeImpl(&env, &args);
    try std.testing.expect(result == .nil);
}

test "stream iterate generates values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const seed = Value{ .int = 0 };
    const closure = value_mod.Closure{
        .param_names = &.{"x"},
        .body = &typed.TypedExpr{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } },
        .env = undefined,
    };
    const args = [_]Value{ seed, Value{ .closure = closure } };
    const result = stream_mod.streamIterateImpl(&env, &args);
    try std.testing.expect(result == .stream);
}

test "stream iterate invalid args returns nil" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const args = [_]Value{ Value{ .int = 0 }, Value{ .int = 1 } };
    const result = stream_mod.streamIterateImpl(&env, &args);
    try std.testing.expect(result == .nil);
}

test "stream iter calls callback" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const items = try std.testing.allocator.alloc(Value, 1);
    defer std.testing.allocator.free(items);
    items[0] = Value{ .int = 42 };
    const list = Value{ .list = .{ .items = items, .cap = 1 } };
    const stream_val = stream_mod.streamFromListImpl(&env, &.{list});
    const closure = value_mod.Closure{
        .param_names = &.{"x"},
        .body = &typed.TypedExpr{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } },
        .env = undefined,
    };
    const args = [_]Value{ Value{ .closure = closure }, stream_val };
    const result = stream_mod.streamIterImpl(&env, &args);
    try std.testing.expect(result == .unit);
}

test "stream iter invalid args returns unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const args = [_]Value{ Value{ .int = 0 }, Value{ .int = 0 } };
    const result = stream_mod.streamIterImpl(&env, &args);
    try std.testing.expect(result == .unit);
}

test "stream fold with closure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const items = try std.testing.allocator.alloc(Value, 3);
    defer std.testing.allocator.free(items);
    items[0] = Value{ .int = 1 };
    items[1] = Value{ .int = 2 };
    items[2] = Value{ .int = 3 };
    const list = Value{ .list = .{ .items = items, .cap = 3 } };
    const stream_val = stream_mod.streamFromListImpl(&env, &.{list});
    const closure = value_mod.Closure{
        .param_names = &.{ "acc", "x" },
        .body = &typed.TypedExpr{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } },
        .env = undefined,
    };
    const args = [_]Value{ Value{ .closure = closure }, Value{ .int = 0 }, stream_val };
    const result = stream_mod.streamFoldImpl(&env, &args);
    try std.testing.expectEqual(@as(i64, 0), result.int);
}

test "stream fold invalid args returns unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const args = [_]Value{ Value{ .int = 1 }, Value{ .int = 0 }, Value{ .int = 0 } };
    const result = stream_mod.streamFoldImpl(&env, &args);
    try std.testing.expect(result == .unit);
}

test "stream fromList non-list returns stream" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const args = [_]Value{Value{ .int = 42 }};
    const result = stream_mod.streamFromListImpl(&env, &args);
    try std.testing.expect(result == .stream);
}

test "stream fromList empty list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const list = Value{ .list = .{ .items = &.{}, .cap = 0 } };
    const args = [_]Value{list};
    const result = stream_mod.streamFromListImpl(&env, &args);
    try std.testing.expect(result == .stream);
    const drained = stream_mod.streamToListImpl(&env, &.{result});
    try std.testing.expectEqual(@as(usize, 0), drained.list.items.len);
}

test "stream bytes from stream" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const items = try std.testing.allocator.alloc(Value, 2);
    defer std.testing.allocator.free(items);
    items[0] = Value{ .bytes = "abc" };
    items[1] = Value{ .bytes = "def" };
    const list = Value{ .list = .{ .items = items, .cap = 2 } };
    const stream_val = stream_mod.streamFromListImpl(&env, &.{list});
    const result = stream_mod.streamBytesImpl(&env, &.{stream_val});
    try std.testing.expect(result == .bytes);
    try std.testing.expect(std.mem.eql(u8, "abcdef", result.bytes));
}

test "stream bytes from non-stream returns empty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const args = [_]Value{Value{ .int = 0 }};
    const result = stream_mod.streamBytesImpl(&env, &args);
    try std.testing.expect(result == .bytes);
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
}

test "stream linesMax" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const args = [_]Value{ Value{ .int = 10 }, Value{ .int = 0 } };
    const result = stream_mod.streamLinesMaxImpl(&env, &args);
    try std.testing.expect(result == .nil);
}

test "stream toList invalid args returns nil" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const args = [_]Value{Value{ .int = 0 }};
    const result = stream_mod.streamToListImpl(&env, &args);
    try std.testing.expect(result == .nil);
}

test "stream stringify invalid args returns empty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const args = [_]Value{Value{ .int = 0 }};
    const result = stream_mod.streamStringImpl(&env, &args);
    try std.testing.expect(result == .string);
    try std.testing.expect(std.mem.eql(u8, "", result.string));
}

test "stream lines invalid args returns nil" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = makeEnv(arena.allocator());
    const args = [_]Value{Value{ .int = 0 }};
    const result = stream_mod.streamLinesImpl(&env, &args);
    try std.testing.expect(result == .nil);
}
