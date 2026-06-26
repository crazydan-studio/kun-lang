const std = @import("std");
const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");
const regex = @import("regex");

pub const Closure = struct {
    param_names: []const []const u8,
    body: *const typed.TypedExpr,
    env: *Frame,
};

pub const RecordFieldValue = struct { name: []const u8, value: Value };

pub const MapEntryValue = struct { key: Value, value: Value };

pub const MapRepr = struct {
    entries: [*]u8,
    len: u64,
    cap: u64,
};

pub const SetRepr = struct {
    entries: [*]u8,
    len: u64,
    cap: u64,
};

pub const CmdOption = struct { name: []const u8, value: Value };

pub const CommandPayload = struct {
    bin: []const u8,
    options: []const CmdOption,
    positional: []const Value,
};

pub const RegexHandle = regex.Regex;

pub const Frame = @import("env.zig").Frame;
const PrimitiveFn = @import("primitive.zig").PrimitiveFn;

pub const StreamFn = union(enum) {
    primitive: PrimitiveFn,
    closure: *const Closure,
};

pub const StreamNode = union(enum) {
    cmd: struct { fd: i32, pid: i32, buf: []u8 },
    mapped: struct { upstream: *StreamNode, f: StreamFn },
    filtered: struct { upstream: *StreamNode, pred: StreamFn },
    taken: struct { upstream: *StreamNode, remaining: usize },
    dropped: struct { upstream: *StreamNode, remaining: usize },
    lines: struct { upstream: *StreamNode, buf: []u8, pos: usize, max_len: usize },
    parse_mapped: struct { upstream: *StreamNode, f: StreamFn },
    parse_mapped_keep: struct { upstream: *StreamNode, f: StreamFn },
    list_items: struct { items: []const Value, index: usize },
    generate: struct { seed: Value, f: StreamFn, count: usize },
};

pub const Value = union(enum) {
    int: i64,
    float: f64,
    bool: bool,
    char: u32,
    unit,
    nil,
    string: []const u8,
    bytes: []const u8,
    path: []const u8,
    duration: i64,
    list: struct { items: []const Value, cap: usize },
    tuple: struct { items: []const Value },
    record: struct { fields: []const RecordFieldValue },
    closure: Closure,
    primitive: PrimitiveFn,
    map: MapRepr,
    set: SetRepr,
    stream: *StreamNode,
    command: CommandPayload,
    regex: *const RegexHandle,
    decimal: struct { mantissa: i64, exponent: i32 },
    datetime: i64,
    adt: struct { tag: u8, payload: *Value },
    partial: struct { fn_ptr: PrimitiveFn, args: []const Value, remaining: u8 },
};

pub fn makeOk(val: Value, allocator: std.mem.Allocator) !Value {
    const payload = try allocator.create(Value);
    payload.* = val;
    return Value{ .adt = .{ .tag = 0, .payload = payload } };
}

pub fn makeErr(tag: u8, val: Value, allocator: std.mem.Allocator) !Value {
    const payload = try allocator.create(Value);
    payload.* = val;
    return Value{ .adt = .{ .tag = tag, .payload = payload } };
}

pub fn streamMap(allocator: std.mem.Allocator, upstream: *StreamNode, f: StreamFn) !*StreamNode {
    const node = try allocator.create(StreamNode);
    node.* = .{ .mapped = .{ .upstream = upstream, .f = f } };
    return node;
}

pub fn streamFilter(allocator: std.mem.Allocator, upstream: *StreamNode, pred: StreamFn) !*StreamNode {
    const node = try allocator.create(StreamNode);
    node.* = .{ .filtered = .{ .upstream = upstream, .pred = pred } };
    return node;
}

pub fn streamTake(allocator: std.mem.Allocator, upstream: *StreamNode, n: usize) !*StreamNode {
    const node = try allocator.create(StreamNode);
    node.* = .{ .taken = .{ .upstream = upstream, .remaining = n } };
    return node;
}

pub fn streamDrop(allocator: std.mem.Allocator, upstream: *StreamNode, n: usize) !*StreamNode {
    const node = try allocator.create(StreamNode);
    node.* = .{ .dropped = .{ .upstream = upstream, .remaining = n } };
    return node;
}

pub fn streamLines(allocator: std.mem.Allocator, upstream: *StreamNode, max_len: usize) !*StreamNode {
    const buf = try allocator.alloc(u8, 4096);
    const node = try allocator.create(StreamNode);
    node.* = .{ .lines = .{ .upstream = upstream, .buf = buf, .pos = 0, .max_len = max_len } };
    return node;
}

pub fn streamParseMap(allocator: std.mem.Allocator, upstream: *StreamNode, f: StreamFn) !*StreamNode {
    const node = try allocator.create(StreamNode);
    node.* = .{ .parse_mapped = .{ .upstream = upstream, .f = f } };
    return node;
}

pub fn streamParseMapKeep(allocator: std.mem.Allocator, upstream: *StreamNode, f: StreamFn) !*StreamNode {
    const node = try allocator.create(StreamNode);
    node.* = .{ .parse_mapped_keep = .{ .upstream = upstream, .f = f } };
    return node;
}

pub fn streamFromList(allocator: std.mem.Allocator, items: []const Value) !*StreamNode {
    const node = try allocator.create(StreamNode);
    node.* = .{ .list_items = .{ .items = items, .index = 0 } };
    return node;
}

pub fn streamGenerate(allocator: std.mem.Allocator, seed: Value, f: StreamFn) !*StreamNode {
    const node = try allocator.create(StreamNode);
    node.* = .{ .generate = .{ .seed = seed, .f = f, .count = 0 } };
    return node;
}
