const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");

pub const Closure = struct {
    param_names: []const []const u8,
    body: *const typed.TypedExpr,
    env: *Frame,
};

pub const RecordFieldValue = struct { name: []const u8, value: Value };

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
};

const Frame = @import("env.zig").Frame;
