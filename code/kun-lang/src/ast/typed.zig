const ast = @import("ast.zig");

pub const TypeId = u32;

pub const RecordFieldType = struct { name: []const u8, type_: TypeId };

pub const AdtVariant = struct { name: []const u8, payload: []const TypeId };

pub const Type = union(enum) {
    int: void,
    float: void,
    bool: void,
    string: void,
    char: void,
    bytes: void,
    unit: void,
    path: void,
    duration: void,
    regex: void,
    decimal_t: void,
    command_t: void,
    datetime_t: void,
    nilable: TypeId,
    list: TypeId,
    map: struct { key: TypeId, value: TypeId },
    set: TypeId,
    stream: TypeId,
    tuple: []const TypeId,
    record: []const RecordFieldType,
    function: struct { param: TypeId, result: TypeId },
    effect_fn: struct { param: TypeId, result: TypeId },
    adt: struct { name: []const u8, variants: []const AdtVariant },
    variable: struct { id: u32, level: u32 },
    error_: void,
};

pub const Param = struct { name: []const u8, type_: TypeId };

pub const Binding = struct { name: []const u8, value: *const TypedExpr };

pub const RecordField = struct { name: []const u8, value: *const TypedExpr };

pub const ExprItem = union(enum) { expr: *const TypedExpr, spread: *const TypedExpr };

pub const Stmt = struct {
    kind: union(enum) {
        binding: Binding,
        defer_: struct { expr: *const TypedExpr },
        expr: *const TypedExpr,
    },
    type_: TypeId,
};

pub const Branch = struct { pattern: ast.Pattern, body: *const TypedExpr, type_: TypeId, guard_cond: ?*const TypedExpr = null };

pub const TypedExpr = union(enum) {
    int_literal: struct { value: i64, type_: TypeId, span: ast.Span },
    float_literal: struct { value: f64, type_: TypeId, span: ast.Span },
    string_literal: struct { value: []const u8, type_: TypeId, span: ast.Span },
    bool_literal: struct { value: bool, type_: TypeId, span: ast.Span },
    char_literal: struct { value: u32, type_: TypeId, span: ast.Span },
    nil_literal: struct { type_: TypeId, span: ast.Span },
    duration_literal: struct { value: i64, unit: ast.DurationUnit, type_: TypeId, span: ast.Span },
    path_literal: struct { value: []const u8, type_: TypeId, span: ast.Span },
    regex_literal: struct { value: []const u8, type_: TypeId, span: ast.Span },
    bytes_literal: struct { value: []const u8, type_: TypeId, span: ast.Span },
    ident: struct { name: []const u8, type_: TypeId, span: ast.Span },
    lambda: struct { params: []const Param, body: *const TypedExpr, type_: TypeId, span: ast.Span },
    call: struct { func: *const TypedExpr, arg: *const TypedExpr, type_: TypeId, span: ast.Span },
    let_in: struct { bindings: []const Binding, body: *const TypedExpr, type_: TypeId, span: ast.Span },
    do_block: struct { body: []const Stmt, result: ?*const TypedExpr, type_: TypeId, span: ast.Span },
    if_expr: struct { cond: *const TypedExpr, then: *const TypedExpr, else_: *const TypedExpr, type_: TypeId, span: ast.Span },
    case_expr: struct { subject: *const TypedExpr, branches: []const Branch, type_: TypeId, span: ast.Span },
    binary_op: struct { op: ast.BinaryOp, left: *const TypedExpr, right: *const TypedExpr, type_: TypeId, span: ast.Span },
    unary_op: struct { op: ast.UnaryOp, operand: *const TypedExpr, type_: TypeId, span: ast.Span },
    list_literal: struct { items: []const ExprItem, type_: TypeId, span: ast.Span },
    tuple_literal: struct { items: []const TypedExpr, type_: TypeId, span: ast.Span },
    record_literal: struct { fields: []const RecordField, type_: TypeId, span: ast.Span },
    record_access: struct { record: *const TypedExpr, field: []const u8, type_: TypeId, span: ast.Span },
    pipe: struct { left: *const TypedExpr, right: *const TypedExpr, type_: TypeId, span: ast.Span },
    pipe_reverse: struct { left: *const TypedExpr, right: *const TypedExpr, type_: TypeId, span: ast.Span },
    compose: struct { left: *const TypedExpr, right: *const TypedExpr, type_: TypeId, span: ast.Span },
    compose_reverse: struct { left: *const TypedExpr, right: *const TypedExpr, type_: TypeId, span: ast.Span },
    map_literal: struct { entries: []const MapEntry, type_: TypeId, span: ast.Span },
    set_literal: struct { items: []const TypedExpr, type_: TypeId, span: ast.Span },
    record_update: struct { record: *const TypedExpr, fields: []const RecordField, type_: TypeId, span: ast.Span },
    range_literal: struct { from: *const TypedExpr, to: *const TypedExpr, step: ?*const TypedExpr, type_: TypeId, span: ast.Span },
    ternary: struct { cond: *const TypedExpr, then: *const TypedExpr, else_: *const TypedExpr, type_: TypeId, span: ast.Span },
    opt_chain: struct { object: *const TypedExpr, field: []const u8, type_: TypeId, span: ast.Span },
};

pub const MapEntry = struct { key: *const TypedExpr, value: *const TypedExpr };

pub const TypedDecl = struct {
    kind: union(enum) {
        import: struct { module: []const u8, alias: ?[]const u8 },
        export_: struct { names: []const []const u8 },
        type_def: struct { name: []const u8, type_: TypeId },
        function_def: struct {
            name: []const u8,
            params: []const Param,
            body: *const TypedExpr,
            type_: TypeId,
            is_effect: bool,
        },
    },
    span: ast.Span,
};
