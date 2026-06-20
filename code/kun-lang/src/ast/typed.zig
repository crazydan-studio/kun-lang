const ast = @import("ast.zig");

pub const TypeId = usize;

pub const Type = union(enum) {
    int: void,
    float: void,
    bool: void,
    string: void,
    char: void,
    bytes: void,
    unit: void,
    nilable: *const Type,
    list: *const Type,
    map: struct { key: *const Type, value: *const Type },
    set: *const Type,
    tuple: []const Type,
    record: []const RecordTypeField,
    function: struct { params: []const Type, ret: *const Type },
    effect_fn: struct { params: []const Type, ret: *const Type },
    custom: struct { name: []const u8, type_args: []const Type },
    var_: TypeId,
};

pub const RecordTypeField = struct {
    name: []const u8,
    type_: Type,
};

pub const TypedExpr = union(enum) {
    int_literal: struct { value: i64, type_: Type },
    float_literal: struct { value: f64, type_: Type },
    string_literal: struct { value: []const u8, type_: Type },
    bool_literal: struct { value: bool, type_: Type },
    char_literal: struct { value: u21, type_: Type },
    nil_literal: Type,
    ident: struct { name: []const u8, type_: Type },
    lambda: struct { params: []const Param, body: *const TypedExpr, type_: Type },
    call: struct { func: *const TypedExpr, arg: *const TypedExpr, type_: Type },
    let_in: struct { bindings: []const Binding, body: *const TypedExpr, type_: Type },
    do_block: struct { body: []const Stmt, result: ?*const TypedExpr, type_: Type },
    if_expr: struct { cond: *const TypedExpr, then: *const TypedExpr, else_: *const TypedExpr, type_: Type },
    case_expr: struct { subject: *const TypedExpr, branches: []const Branch, type_: Type },
    binary_op: struct { op: ast.BinaryOp, left: *const TypedExpr, right: *const TypedExpr, type_: Type },
    unary_op: struct { op: ast.UnaryOp, operand: *const TypedExpr, type_: Type },
    list_literal: struct { items: []const ExprItem, type_: Type },
    tuple_literal: struct { items: []const TypedExpr, type_: Type },
    record_literal: struct { fields: []const RecordField, type_: Type },
    record_access: struct { record: *const TypedExpr, field: []const u8, type_: Type },
    pipe: struct { left: *const TypedExpr, right: *const TypedExpr, type_: Type },
};

pub const Param = struct { name: []const u8, type_: Type };
pub const Binding = struct { name: []const u8, value: *const TypedExpr };
pub const Stmt = struct { kind: union(enum) { binding: Binding, expr: *const TypedExpr }, type_: Type };
pub const Branch = struct { pattern: ast.Pattern, body: *const TypedExpr, type_: Type };
pub const ExprItem = union(enum) { expr: *const TypedExpr, spread: *const TypedExpr };
pub const RecordField = struct { name: []const u8, value: *const TypedExpr };
