const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");

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

pub const CommandPayload = struct {
    tag: u8,
    _payload: [32]u8,
};

pub const RegexHandle = opaque {};

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
    adt: struct { tag: u8, payload: [*]u8 },
};
