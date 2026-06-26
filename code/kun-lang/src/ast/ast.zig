const std = @import("std");

pub const SourceLoc = struct {
    line: u32,
    col: u32,
    offset: usize,

    pub fn format(self: SourceLoc, writer: anytype) !void {
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

    pub fn format(self: Span, writer: anytype) !void {
        if (self.file.len > 0 and self.file.len < 65536) {
            try writer.print("{s}:{d}:{d}", .{ self.file, self.start.line, self.start.col });
        } else {
            try writer.print("{d}:{d}", .{ self.start.line, self.start.col });
        }
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

fn destroyStmtSub(allocator: std.mem.Allocator, stmt: *const Stmt) void {
    switch (stmt.kind) {
        .binding => |b| {
            destroyExprSub(allocator, b.value);
            allocator.destroy(@constCast(b.value));
        },
        .defer_ => |d| {
            destroyExprSub(allocator, d.expr);
            allocator.destroy(@constCast(d.expr));
        },
        .expr => |e| {
            destroyExprSub(allocator, e);
            allocator.destroy(@constCast(e));
        },
    }
}

fn destroyPatternSub(allocator: std.mem.Allocator, pat: *const Pattern) void {
    switch (pat.*) {
        .wildcard => {},
        .literal => |l| {
            destroyExprSub(allocator, l);
            allocator.destroy(@constCast(l));
        },
        .ident => {},
        .variant => |v| {
            if (v.inner) |inner| destroyPatternSub(allocator, inner);
        },
        .list => |l| {
            for (l.items) |item| destroyPatternSub(allocator, &item);
            allocator.free(@constCast(l.items));
            if (l.rest) |rest| destroyPatternSub(allocator, rest);
        },
        .tuple => |t| {
            for (t.items) |item| destroyPatternSub(allocator, &item);
            allocator.free(@constCast(t.items));
        },
        .record => |fields| {
            for (fields) |f| destroyPatternSub(allocator, &f.pattern);
            allocator.free(@constCast(fields));
        },
        .guard => |g| {
            destroyPatternSub(allocator, g.inner);
            destroyExprSub(allocator, g.cond);
            allocator.destroy(@constCast(g.cond));
        },
        .or_ => |o| {
            destroyPatternSub(allocator, o.left);
            destroyPatternSub(allocator, o.right);
        },
    }
}

fn destroyBranchSub(allocator: std.mem.Allocator, branch: *const Branch) void {
    destroyPatternSub(allocator, &branch.pattern);
    if (branch.guard) |g| {
        destroyExprSub(allocator, g);
        allocator.destroy(@constCast(g));
    }
    destroyExprSub(allocator, branch.body);
    allocator.destroy(@constCast(branch.body));
}

pub fn destroyExprSub(allocator: std.mem.Allocator, expr: *const Expr) void {
    switch (expr.*) {
        .int_literal, .float_literal, .string_literal, .bool_literal,
        .char_literal, .duration_literal, .path_literal,
        .regex_literal, .bytes_literal, .ident => {},
        .lambda => |l| {
            destroyExprSub(allocator, l.body);
            allocator.destroy(@constCast(l.body));
            allocator.free(@constCast(l.params));
        },
        .call => |c| {
            destroyExprSub(allocator, c.func);
            allocator.destroy(@constCast(c.func));
            destroyExprSub(allocator, c.arg);
            allocator.destroy(@constCast(c.arg));
        },
        .let_in => |l| {
            for (l.bindings) |b| {
                destroyExprSub(allocator, b.value);
                allocator.destroy(@constCast(b.value));
            }
            allocator.free(@constCast(l.bindings));
            destroyExprSub(allocator, l.body);
            allocator.destroy(@constCast(l.body));
        },
        .do_block => |d| {
            for (d.body) |*s| destroyStmtSub(allocator, s);
            allocator.free(@constCast(d.body));
            if (d.result) |r| {
                destroyExprSub(allocator, r);
                allocator.destroy(@constCast(r));
            }
        },
        .if_expr => |i| {
            destroyExprSub(allocator, i.cond);
            allocator.destroy(@constCast(i.cond));
            destroyExprSub(allocator, i.then);
            allocator.destroy(@constCast(i.then));
            destroyExprSub(allocator, i.else_);
            allocator.destroy(@constCast(i.else_));
        },
        .case_expr => |c| {
            destroyExprSub(allocator, c.subject);
            allocator.destroy(@constCast(c.subject));
            for (c.branches) |*b| destroyBranchSub(allocator, b);
            allocator.free(@constCast(c.branches));
        },
        .pipe => |p| {
            destroyExprSub(allocator, p.left);
            allocator.destroy(@constCast(p.left));
            destroyExprSub(allocator, p.right);
            allocator.destroy(@constCast(p.right));
        },
        .pipe_reverse => |p| {
            destroyExprSub(allocator, p.left);
            allocator.destroy(@constCast(p.left));
            destroyExprSub(allocator, p.right);
            allocator.destroy(@constCast(p.right));
        },
        .compose => |p| {
            destroyExprSub(allocator, p.left);
            allocator.destroy(@constCast(p.left));
            destroyExprSub(allocator, p.right);
            allocator.destroy(@constCast(p.right));
        },
        .compose_reverse => |p| {
            destroyExprSub(allocator, p.left);
            allocator.destroy(@constCast(p.left));
            destroyExprSub(allocator, p.right);
            allocator.destroy(@constCast(p.right));
        },
        .binary_op => |b| {
            destroyExprSub(allocator, b.left);
            allocator.destroy(@constCast(b.left));
            destroyExprSub(allocator, b.right);
            allocator.destroy(@constCast(b.right));
        },
        .unary_op => |u| {
            destroyExprSub(allocator, u.operand);
            allocator.destroy(@constCast(u.operand));
        },
        .list_literal => |l| {
            for (l.items) |item| {
                switch (item) {
                    .expr => |e| {
                        destroyExprSub(allocator, e);
                        allocator.destroy(@constCast(e));
                    },
                    .spread => |s| {
                        destroyExprSub(allocator, s);
                        allocator.destroy(@constCast(s));
                    },
                }
            }
            allocator.free(@constCast(l.items));
        },
        .tuple_literal => |t| {
            for (t.items) |item| {
                destroyExprSub(allocator, item);
                allocator.destroy(@constCast(item));
            }
            allocator.free(@constCast(t.items));
        },
        .record_literal => |r| {
            for (r.fields) |f| {
                destroyExprSub(allocator, f.value);
                allocator.destroy(@constCast(f.value));
            }
            allocator.free(@constCast(r.fields));
        },
        .record_access => |r| {
            destroyExprSub(allocator, r.record);
            allocator.destroy(@constCast(r.record));
        },
        .record_update => |r| {
            destroyExprSub(allocator, r.record);
            allocator.destroy(@constCast(r.record));
            for (r.fields) |f| {
                destroyExprSub(allocator, f.value);
                allocator.destroy(@constCast(f.value));
            }
            allocator.free(@constCast(r.fields));
        },
        .map_literal => |m| {
            for (m.entries) |e| {
                destroyExprSub(allocator, e.key);
                allocator.destroy(@constCast(e.key));
                destroyExprSub(allocator, e.value);
                allocator.destroy(@constCast(e.value));
            }
            allocator.free(@constCast(m.entries));
        },
        .set_literal => |s| {
            for (s.items) |item| {
                destroyExprSub(allocator, item);
                allocator.destroy(@constCast(item));
            }
            allocator.free(@constCast(s.items));
        },
        .range_literal => |r| {
            destroyExprSub(allocator, r.from);
            allocator.destroy(@constCast(r.from));
            destroyExprSub(allocator, r.to);
            allocator.destroy(@constCast(r.to));
            if (r.step) |step| {
                destroyExprSub(allocator, step);
                allocator.destroy(@constCast(step));
            }
        },
        .ternary => |t| {
            destroyExprSub(allocator, t.cond);
            allocator.destroy(@constCast(t.cond));
            destroyExprSub(allocator, t.then);
            allocator.destroy(@constCast(t.then));
            destroyExprSub(allocator, t.else_);
            allocator.destroy(@constCast(t.else_));
        },
        .optional_chaining => |o| {
            destroyExprSub(allocator, o.object);
            allocator.destroy(@constCast(o.object));
        },
    }
}
