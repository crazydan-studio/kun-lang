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
    _ = errors;
    _ = allocator;
    _ = body;
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

pub fn checkDoInResult(allocator: std.mem.Allocator, body: *const ast.Expr, errors: *ErrorList) !void {
    _ = errors;
    _ = allocator;
    _ = body;
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
