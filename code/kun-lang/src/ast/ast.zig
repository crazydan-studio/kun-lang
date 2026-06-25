const std = @import("std");

pub const SourceLoc = struct {
    line: u32,
    col: u32,
    offset: usize,

    pub fn format(self: SourceLoc, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{d}:{d}", .{ self.line, self.col });
    }
};

pub const Span = struct {
    start: SourceLoc = SourceLoc{ .line = 0, .col = 0, .offset = 0 },
    end: SourceLoc = SourceLoc{ .line = 0, .col = 0, .offset = 0 },
    file: []const u8 = "",
    source: []const u8 = "",
    line_start: u32 = 0,
    col_start: u32 = 0,
    line_end: u32 = 0,
    col_end: u32 = 0,

    pub fn format(self: Span, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{d}:{d}", .{ self.start.line, self.start.col });
    }
};

pub const DurationUnit = enum(u3) { s, ms, min, h, d, us, ns };

pub const Stmt = struct {
    kind: union(enum) {
        binding: ExprBinding,
        defer_: struct { expr: *const Expr },
        expr: *const Expr,
    },
    span: Span,
};

pub const ExprBinding = struct {
    name: []const u8,
    value: *const Expr,
};

pub const Param = struct {
    name: []const u8,
    span: Span,
};

pub const Binding = struct {
    name: []const u8,
    value: *const Expr,
    span: Span,
};

pub const Branch = struct {
    pattern: Pattern,
    guard: ?*const Expr,
    body: *const Expr,
    is_unbound: bool,
    span: Span,
};

pub const Pattern = union(enum) {
    wildcard: Span,
    literal: *const Expr,
    ident: struct { name: []const u8, span: Span },
    variant: struct { name: []const u8, inner: ?*const Pattern, span: Span },
    list: struct { items: []const Pattern, rest: ?*const Pattern, span: Span },
    tuple: struct { items: []const Pattern, span: Span },
    record: []const RecordPatternField,
    guard: struct { inner: *const Pattern, cond: *const Expr, span: Span },
    or_: struct { left: *const Pattern, right: *const Pattern, span: Span },
};

pub const RecordPatternField = struct {
    name: []const u8,
    pattern: Pattern,
    span: Span = undefined,
};

pub const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
    mod,
    eq,
    neq,
    lt,
    le,
    gt,
    ge,
    and_,
    or_,
    concat,
    nil_coal,
    range,
};

pub const UnaryOp = enum { neg, not };

pub const Expr = union(enum) {
    int_literal: struct { value: i64, span: Span },
    float_literal: struct { value: f64, span: Span },
    string_literal: struct { value: []const u8, span: Span },
    bool_literal: struct { value: bool, span: Span },
    char_literal: struct { value: u21, span: Span },
    nil_literal: Span,
    duration_literal: struct { value: i64, unit: DurationUnit, span: Span },
    path_literal: struct { value: []const u8, span: Span },
    regex_literal: struct { value: []const u8, span: Span },
    bytes_literal: struct { value: []const u8, span: Span },
    ident: struct { name: []const u8, span: Span },
    lambda: struct { params: []const Param, body: *const Expr, span: Span },
    call: struct { func: *const Expr, arg: *const Expr, span: Span },
    let_in: struct { bindings: []const Binding, body: *const Expr, span: Span },
    do_block: struct { body: []const Stmt, result: ?*const Expr, span: Span },
    if_expr: struct { cond: *const Expr, then: *const Expr, else_: *const Expr, span: Span },
    case_expr: struct { subject: *const Expr, branches: []const Branch, span: Span },
    pipe: struct { left: *const Expr, right: *const Expr, span: Span },
    pipe_reverse: struct { left: *const Expr, right: *const Expr, span: Span },
    compose: struct { left: *const Expr, right: *const Expr, span: Span },
    compose_reverse: struct { left: *const Expr, right: *const Expr, span: Span },
    binary_op: struct { op: BinaryOp, left: *const Expr, right: *const Expr, span: Span },
    unary_op: struct { op: UnaryOp, operand: *const Expr, span: Span },
    list_literal: struct { items: []const ExprItem, span: Span },
    tuple_literal: struct { items: []const *const Expr, span: Span },
    record_literal: struct { fields: []const RecordField, span: Span },
    record_access: struct { record: *const Expr, field: []const u8, span: Span },
    record_update: struct { record: *const Expr, fields: []const RecordField, span: Span },
    map_literal: struct { entries: []const MapEntry, span: Span },
    set_literal: struct { items: []const *const Expr, span: Span },
    range_literal: struct { from: *const Expr, to: *const Expr, step: ?*const Expr, span: Span },
    ternary: struct { cond: *const Expr, then: *const Expr, else_: *const Expr, span: Span },
    optional_chaining: struct { object: *const Expr, field: []const u8, span: Span },
};

pub const ExprItem = union(enum) {
    expr: *const Expr,
    spread: *const Expr,
};

pub const RecordField = struct {
    name: []const u8,
    value: *const Expr,
};

pub const MapEntry = struct {
    key: *const Expr,
    value: *const Expr,
};
