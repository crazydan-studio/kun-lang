const std = @import("std");
const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");
const primitive = @import("../runtime/primitive.zig");
const error_mod = @import("error.zig");

const TypeError = error_mod.TypeError;
const ErrorList = error_mod.ErrorList;

pub fn isEffectNamespaceCall(name: []const u8) bool {
    return primitive.isEffectBinding(name);
}

pub fn hasEffectInExpr(expr: *const ast.Expr) bool {
    return switch (expr.*) {
        .do_block => true,
        .call => |c| isEffectCall(c.func) or hasEffectInExpr(c.arg),
        .let_in => |l| {
            for (l.bindings) |b| {
                if (hasEffectInExpr(b.value)) return true;
            }
            return hasEffectInExpr(l.body);
        },
        .if_expr => |i| hasEffectInExpr(i.then) or hasEffectInExpr(i.else_),
        .case_expr => |c| {
            for (c.branches) |b| {
                if (hasEffectInExpr(b.body)) return true;
            }
            return false;
        },
        .binary_op => |b| hasEffectInExpr(b.left) or hasEffectInExpr(b.right),
        .unary_op => |u| hasEffectInExpr(u.operand),
        .pipe => |p| hasEffectInExpr(p.left) or hasEffectInExpr(p.right),
        .pipe_reverse => |p| hasEffectInExpr(p.left) or hasEffectInExpr(p.right),
        .compose => |c| hasEffectInExpr(c.left) or hasEffectInExpr(c.right),
        .compose_reverse => |c| hasEffectInExpr(c.left) or hasEffectInExpr(c.right),
        .list_literal => |l| {
            for (l.items) |item| {
                switch (item) {
                    .expr => |e| { if (hasEffectInExpr(e)) return true; },
                    .spread => |s| { if (hasEffectInExpr(s)) return true; },
                }
            }
            return false;
        },
        .tuple_literal => |t| {
            for (t.items) |item| {
                if (hasEffectInExpr(item)) return true;
            }
            return false;
        },
        .record_literal => |r| {
            for (r.fields) |f| {
                if (hasEffectInExpr(f.value)) return true;
            }
            return false;
        },
        .record_access => |r| hasEffectInExpr(r.record),
        .record_update => |r| {
            for (r.fields) |f| {
                if (hasEffectInExpr(f.value)) return true;
            }
            return false;
        },
        .map_literal => |m| {
            for (m.entries) |e| {
                if (hasEffectInExpr(e.key)) return true;
                if (hasEffectInExpr(e.value)) return true;
            }
            return false;
        },
        .set_literal => |s| {
            for (s.items) |item| {
                if (hasEffectInExpr(item)) return true;
            }
            return false;
        },
        else => false,
    };
}

fn isEffectCall(func: *const ast.Expr) bool {
    return switch (func.*) {
        .ident => |id| isEffectNamespaceCall(id.name),
        .call => |c| isEffectCall(c.func),
        .pipe => |p| isEffectCall(p.right),
        .pipe_reverse => |p| isEffectCall(p.left),
        else => false,
    };
}

pub fn checkDuplicateBindings(allocator: std.mem.Allocator, bindings: []const ast.Binding) !bool {
    for (bindings, 0..) |b1, i| {
        for (bindings[i + 1 ..]) |b2| {
            if (std.mem.eql(u8, b1.name, b2.name)) {
                _ = allocator;
                return true;
            }
        }
    }
    return false;
}

pub fn checkPureFunctionBody(allocator: std.mem.Allocator, body: *const ast.Expr, errors: *ErrorList) !void {
    _ = allocator;
    _ = errors;
    if (hasEffectInExpr(body)) {
        return error.EffectInPure;
    }
}

pub fn checkLetInPurity(allocator: std.mem.Allocator, bindings: []const ast.Binding, body: *const ast.Expr, errors: *ErrorList) !void {
    for (bindings) |b| {
        if (hasEffectInExpr(b.value)) {
            try errors.add(allocator, .{ .effect_in_let = .{ .called_func = b.name, .span = b.span } });
        }
    }
    if (hasEffectInExpr(body)) {
        try errors.add(allocator, .{ .effect_in_let = .{ .called_func = "let body", .span = exprSpan(body) } });
    }
}

fn exprSpan(expr: *const ast.Expr) ast.Span {
    return switch (expr.*) {
        .int_literal => |v| v.span,
        .float_literal => |v| v.span,
        .string_literal => |v| v.span,
        .bool_literal => |v| v.span,
        .char_literal => |v| v.span,
        .nil_literal => |s| s,
        .duration_literal => |v| v.span,
        .path_literal => |v| v.span,
        .regex_literal => |v| v.span,
        .bytes_literal => |v| v.span,
        .ident => |v| v.span,
        .lambda => |v| v.span,
        .call => |v| v.span,
        .let_in => |v| v.span,
        .do_block => |v| v.span,
        .if_expr => |v| v.span,
        .case_expr => |v| v.span,
        .pipe => |v| v.span,
        .pipe_reverse => |v| v.span,
        .compose => |v| v.span,
        .compose_reverse => |v| v.span,
        .binary_op => |v| v.span,
        .unary_op => |v| v.span,
        .list_literal => |v| v.span,
        .tuple_literal => |v| v.span,
        .record_literal => |v| v.span,
        .record_access => |v| v.span,
        .record_update => |v| v.span,
        .map_literal => |v| v.span,
        .set_literal => |v| v.span,
        .range_literal => |v| v.span,
        .ternary => |v| v.span,
    };
}

pub fn checkDoLetExclusion(allocator: std.mem.Allocator, body: *const ast.Expr, errors: *ErrorList) !void {
    try checkDoLetExclusionRecurse(allocator, body, null, errors);
}

fn checkDoLetExclusionRecurse(allocator: std.mem.Allocator, expr: *const ast.Expr, in_context: ?enum { do_block, let_in }, errors: *ErrorList) !void {
    switch (expr.*) {
        .do_block => |d| {
            if (in_context == .let_in) {
                try errors.add(allocator, .{ .effect_in_let = .{ .called_func = "do block in let bindings", .span = d.span } });
            }
            for (d.body) |stmt| {
                switch (stmt.kind) {
                    .binding => |b| try checkDoLetExclusionRecurse(allocator, b.value, .do_block, errors),
                    .defer_ => |de| try checkDoLetExclusionRecurse(allocator, de.expr, .do_block, errors),
                    .expr => |e| try checkDoLetExclusionRecurse(allocator, e, .do_block, errors),
                }
            }
            if (d.result) |r| try checkDoLetExclusionRecurse(allocator, r, .do_block, errors);
        },
        .let_in => |l| {
            if (in_context == .do_block) {
                try errors.add(allocator, .{ .effect_in_let = .{ .called_func = "let bindings in do block", .span = l.span } });
            }
            for (l.bindings) |b| try checkDoLetExclusionRecurse(allocator, b.value, .let_in, errors);
            try checkDoLetExclusionRecurse(allocator, l.body, .let_in, errors);
        },
        .call => |c| {
            try checkDoLetExclusionRecurse(allocator, c.func, in_context, errors);
            try checkDoLetExclusionRecurse(allocator, c.arg, in_context, errors);
        },
        .if_expr => |i| {
            try checkDoLetExclusionRecurse(allocator, i.then, in_context, errors);
            try checkDoLetExclusionRecurse(allocator, i.else_, in_context, errors);
        },
        .case_expr => |c| {
            for (c.branches) |b| try checkDoLetExclusionRecurse(allocator, b.body, in_context, errors);
        },
        .lambda => |l| try checkDoLetExclusionRecurse(allocator, l.body, in_context, errors),
        .binary_op => |b| {
            try checkDoLetExclusionRecurse(allocator, b.left, in_context, errors);
            try checkDoLetExclusionRecurse(allocator, b.right, in_context, errors);
        },
        .unary_op => |u| try checkDoLetExclusionRecurse(allocator, u.operand, in_context, errors),
        .pipe => |p| {
            try checkDoLetExclusionRecurse(allocator, p.left, in_context, errors);
            try checkDoLetExclusionRecurse(allocator, p.right, in_context, errors);
        },
        .list_literal => |l| {
            for (l.items) |item| {
                switch (item) {
                    .expr => |e| try checkDoLetExclusionRecurse(allocator, e, in_context, errors),
                    .spread => |s| try checkDoLetExclusionRecurse(allocator, s, in_context, errors),
                }
            }
        },
        .tuple_literal => |t| {
            for (t.items) |item| try checkDoLetExclusionRecurse(allocator, item, in_context, errors);
        },
        .record_literal => |r| {
            for (r.fields) |f| try checkDoLetExclusionRecurse(allocator, f.value, in_context, errors);
        },
        .record_access => |r| try checkDoLetExclusionRecurse(allocator, r.record, in_context, errors),
        .record_update => |r| {
            for (r.fields) |f| try checkDoLetExclusionRecurse(allocator, f.value, in_context, errors);
        },
        .map_literal => |m| {
            for (m.entries) |e| {
                try checkDoLetExclusionRecurse(allocator, e.key, in_context, errors);
                try checkDoLetExclusionRecurse(allocator, e.value, in_context, errors);
            }
        },
        .set_literal => |s| {
            for (s.items) |item| try checkDoLetExclusionRecurse(allocator, item, in_context, errors);
        },
        else => {},
    }
}

pub fn checkEmptyBody(allocator: std.mem.Allocator, body: *const ast.Expr, context: []const u8, errors: *ErrorList) !void {
    switch (body.*) {
        .do_block => |d| {
            if (d.body.len == 0 and d.result == null) {
                try errors.add(allocator, .{ .empty_body = .{ .context = context, .span = d.span } });
            }
        },
        .let_in => |l| {
            if (l.bindings.len == 0) {
                try errors.add(allocator, .{ .empty_body = .{ .context = context, .span = l.span } });
            }
        },
        else => {},
    }
}

pub fn checkDoInResult(allocator: std.mem.Allocator, body: *const ast.Expr, typed_result: ?*const typed.TypedExpr, errors: *ErrorList) !void {
    if (typed_result) |tr| {
        if (tr.type_ == typed.unit_t) {
            try errors.add(allocator, .{ .pure_unit_return = .{ .func_name = "do in result", .span = exprSpan(body) } });
        }
    }
}

pub fn checkEffectCallback(allocator: std.mem.Allocator, errors: *ErrorList) !void {
    _ = errors;
    _ = allocator;
}

pub fn checkCmdInDo(allocator: std.mem.Allocator, errors: *ErrorList) !void {
    _ = errors;
    _ = allocator;
}

pub fn checkPipeCommand(allocator: std.mem.Allocator, errors: *ErrorList) !void {
    _ = errors;
    _ = allocator;
}

pub fn checkImplicitDo(allocator: std.mem.Allocator, body: *const ast.Expr, errors: *ErrorList) !void {
    _ = errors;
    _ = allocator;
    _ = body;
}

pub fn checkStreamConsumption(allocator: std.mem.Allocator, errors: *ErrorList) !void {
    _ = errors;
    _ = allocator;
}

pub fn checkCommandConsumption(allocator: std.mem.Allocator, errors: *ErrorList) !void {
    _ = errors;
    _ = allocator;
}

pub fn checkUnusedBindings(allocator: std.mem.Allocator, errors: *ErrorList) !void {
    _ = errors;
    _ = allocator;
}

pub fn checkUnusedResult(allocator: std.mem.Allocator, errors: *ErrorList) !void {
    _ = errors;
    _ = allocator;
}

pub fn checkPureExprLast(allocator: std.mem.Allocator, errors: *ErrorList) !void {
    _ = errors;
    _ = allocator;
}
