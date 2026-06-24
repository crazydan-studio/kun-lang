const std = @import("std");
const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");
const primitive = @import("../runtime/primitive.zig");
const error_mod = @import("error.zig");
const env_mod = @import("env.zig");

const TypeError = error_mod.TypeError;
const ErrorList = error_mod.ErrorList;

pub fn isEffectNamespaceCall(name: []const u8) bool {
    return primitive.isEffectBinding(name);
}

pub fn hasEffectInExpr(expr: *const ast.Expr) bool {
    return switch (expr.*) {
        .do_block => true,
        .lambda => |l| hasEffectInExpr(l.body),
        .call => |c| isEffectCall(c.func) or hasEffectInExpr(c.arg),
        .let_in => |l| {
            for (l.bindings) |b| {
                if (hasEffectInExpr(b.value)) return true;
            }
            return hasEffectInExpr(l.body);
        },
        .if_expr => |i| hasEffectInExpr(i.then) or hasEffectInExpr(i.else_),
        .case_expr => |c| {
            if (hasEffectInExpr(c.subject)) return true;
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
        .record_access => |ra| {
            if (ra.record.* == .ident) {
                const rec_name = ra.record.ident.name;
                var buf: [256]u8 = undefined;
                const combined = std.fmt.bufPrint(&buf, "{s}.{s}", .{ rec_name, ra.field }) catch return false;
                return isEffectNamespaceCall(combined);
            }
            return false;
        },
        .call => |c| isEffectCall(c.func),
        .pipe => |p| isEffectCall(p.right),
        .pipe_reverse => |p| isEffectCall(p.left),
        .compose => |c| isEffectCall(c.right),
        .compose_reverse => |c| isEffectCall(c.left),
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
    if (hasEffectInExpr(body)) {
        try errors.add(allocator, .{ .effect_in_pure = .{ .called_func = "effect call in pure function", .span = exprSpan(body) } });
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
        .compose => |c| {
            try checkDoLetExclusionRecurse(allocator, c.left, in_context, errors);
            try checkDoLetExclusionRecurse(allocator, c.right, in_context, errors);
        },
        .compose_reverse => |c| {
            try checkDoLetExclusionRecurse(allocator, c.left, in_context, errors);
            try checkDoLetExclusionRecurse(allocator, c.right, in_context, errors);
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
        const result_type = switch (tr.*) {
            inline else => |v| v.type_,
        };
        if (result_type == env_mod.unit_type) {
            try errors.add(allocator, .{ .pure_unit_return = .{ .func_name = "do in result", .span = exprSpan(body) } });
        }
    }
}

pub fn checkPureUnitReturn(allocator: std.mem.Allocator, func_name: []const u8, body_type: typed.TypeId, env: *env_mod.TypeEnv, span: ast.Span, errors: *ErrorList) !void {
    const resolved = env.applySubst(body_type);
    if (resolved < env.types.items.len and env.types.items[resolved] == .unit) {
        try errors.add(allocator, .{ .pure_unit_return = .{ .func_name = func_name, .span = span } });
    }
}

pub fn checkEffectCallback(allocator: std.mem.Allocator, has_effect: bool, has_bang: bool, span: ast.Span, errors: *ErrorList) !void {
    if (has_bang and !has_effect) {
        try errors.add(allocator, .{ .effect_callback_mismatch = .{ .func_name = "bang callback", .param = 0, .result = 0, .span = span } });
    }
}

pub fn checkCmdInDo(allocator: std.mem.Allocator, name: []const u8, in_do: bool, span: ast.Span, errors: *ErrorList) !void {
    if (!in_do and isEffectNamespaceCall(name)) {
        try errors.add(allocator, .{ .effect_in_pure = .{ .called_func = name, .span = span } });
    }
}

pub fn checkPipeCommand(allocator: std.mem.Allocator, is_command: bool, in_do: bool, span: ast.Span, errors: *ErrorList) !void {
    if (is_command and !in_do) {
        try errors.add(allocator, .{ .command_not_consumed = .{ .cmd_name = "pipe command", .span = span } });
    }
}

pub fn checkImplicitDo(allocator: std.mem.Allocator, body: *const ast.Expr, errors: *ErrorList) !void {
    if (body.* != .do_block) return;
    for (body.do_block.body) |stmt| {
        if (stmt.kind != .expr) continue;
        switch (stmt.kind.expr.*) {
            .case_expr => |c| {
                for (c.branches) |b| {
                    if (!hasEffectInExpr(b.body)) {
                        try errors.add(allocator, .{ .unused_result = stmt.span });
                    }
                }
            },
            .if_expr => |i| {
                if (!hasEffectInExpr(i.then) and !hasEffectInExpr(i.else_)) {
                    try errors.add(allocator, .{ .unused_result = stmt.span });
                }
            },
            else => {},
        }
    }
}

pub fn checkStreamConsumption(allocator: std.mem.Allocator, body: *const ast.Expr, errors: *ErrorList) !void {
    if (body.* != .do_block) return;
    const stmts = body.do_block.body;
    var stream_vars: std.StringHashMapUnmanaged(void) = .empty;
    defer stream_vars.deinit(allocator);

    for (stmts) |stmt| {
        switch (stmt.kind) {
            .binding => |b| {
                if (isStreamSource(b.value)) {
                    try stream_vars.put(allocator, b.name, {});
                }
            },
            .defer_ => {}, // defer doesn't count for consumption
            .expr => |e| {
                markStreamConsumed(e, &stream_vars);
            },
        }
    }

    var it = stream_vars.iterator();
    while (it.next()) |entry| {
        _ = entry;
        try errors.add(allocator, .{ .stream_not_consumed = body.do_block.span });
    }
}

fn isStreamSource(expr: *const ast.Expr) bool {
    return switch (expr.*) {
        .pipe => |p| isCommandIdent(p.left),
        .call => |c| isStreamConstructor(c.func),
        else => false,
    };
}

fn isCommandIdent(expr: *const ast.Expr) bool {
    return switch (expr.*) {
        .ident => |id| std.mem.startsWith(u8, id.name, "Cmd.") and !isKnownCmdApi(id.name) and !isCmdExecSuffix(id.name),
        else => false,
    };
}

fn isCmdExecSuffix(name: []const u8) bool {
    return name.len > 1 and (name[name.len - 1] == '?' or name[name.len - 1] == '!');
}

fn isStreamConstructor(func: *const ast.Expr) bool {
    return switch (func.*) {
        .ident => |id| std.mem.startsWith(u8, id.name, "Stream.") and
            (std.mem.eql(u8, id.name, "Stream.lines") or
            std.mem.eql(u8, id.name, "Stream.fromList") or
            std.mem.eql(u8, id.name, "Stream.range") or
            std.mem.eql(u8, id.name, "Stream.iterate") or
            std.mem.eql(u8, id.name, "Stream.linesMax")),
        else => false,
    };
}

fn isStreamConsumer(func: *const ast.Expr) bool {
    return switch (func.*) {
        .ident => |id| std.mem.startsWith(u8, id.name, "Stream.") and
            (std.mem.eql(u8, id.name, "Stream.toList") or
            std.mem.eql(u8, id.name, "Stream.iter") or
            std.mem.eql(u8, id.name, "Stream.fold") or
            std.mem.eql(u8, id.name, "Stream.string") or
            std.mem.eql(u8, id.name, "Stream.bytes")),
        else => false,
    };
}

fn markStreamConsumed(expr: *const ast.Expr, vars: *std.StringHashMapUnmanaged(void)) void {
    switch (expr.*) {
        .pipe => |p| {
            if (isStreamConsumer(p.right)) {
                if (p.left.* == .ident) {
                    _ = vars.remove(p.left.ident.name);
                }
            }
            markStreamConsumed(p.left, vars);
            markStreamConsumed(p.right, vars);
        },
        .call => |c| {
            if (isStreamConsumer(c.func)) {
                if (c.arg.* == .ident) {
                    _ = vars.remove(c.arg.ident.name);
                }
            }
        },
        .let_in => |l| {
            for (l.bindings) |b| {
                markStreamConsumed(b.value, vars);
            }
            markStreamConsumed(l.body, vars);
        },
        .if_expr => |i| {
            markStreamConsumed(i.then, vars);
            markStreamConsumed(i.else_, vars);
        },
        .case_expr => |c| {
            for (c.branches) |b| {
                markStreamConsumed(b.body, vars);
            }
        },
        .do_block => |d| {
            for (d.body) |s| {
                if (s.kind == .expr) {
                    markStreamConsumed(s.kind.expr, vars);
                }
            }
        },
        .binary_op => |b| {
            markStreamConsumed(b.left, vars);
            markStreamConsumed(b.right, vars);
        },
        else => {},
    }
}

pub fn checkCommandConsumption(allocator: std.mem.Allocator, body: *const ast.Expr, errors: *ErrorList) !void {
    if (body.* != .do_block) return;
    const stmts = body.do_block.body;
    var cmd_vars: std.StringHashMapUnmanaged(void) = .empty;
    defer cmd_vars.deinit(allocator);

    for (stmts) |stmt| {
        switch (stmt.kind) {
            .binding => |b| {
                if (isCmdSource(b.value)) {
                    try cmd_vars.put(allocator, b.name, {});
                }
            },
            .defer_ => {},
            .expr => |e| {
                markCmdConsumed(e, &cmd_vars);
            },
        }
    }

    var it = cmd_vars.iterator();
    while (it.next()) |entry| {
        _ = entry;
        try errors.add(allocator, .{ .command_not_consumed = .{ .cmd_name = "command", .span = body.do_block.span } });
    }
}

fn isCmdSource(expr: *const ast.Expr) bool {
    return switch (expr.*) {
        .ident => isCommandIdent(expr),
        .call => |c| switch (c.func.*) {
            .ident => |id| std.mem.startsWith(u8, id.name, "Cmd.") and !isKnownCmdApi(id.name) and !isCmdExecSuffix(id.name),
            else => false,
        },
        else => false,
    };
}

fn markCmdConsumed(expr: *const ast.Expr, vars: *std.StringHashMapUnmanaged(void)) void {
    switch (expr.*) {
        .pipe => |p| {
            if (p.left.* == .ident) {
                _ = vars.remove(p.left.ident.name);
            }
            markCmdConsumed(p.left, vars);
            markCmdConsumed(p.right, vars);
        },
        .call => |c| {
            if (isCmdExecCall(c.func)) {
                if (c.arg.* == .ident) {
                    _ = vars.remove(c.arg.ident.name);
                }
            }
            if (isCmdSource(c.arg)) {
                // Direct consumption: Cmd.exec (Cmd.echo "hi")
            }
        },
        .let_in => |l| {
            for (l.bindings) |b| {
                markCmdConsumed(b.value, vars);
            }
            markCmdConsumed(l.body, vars);
        },
        .if_expr => |i| {
            markCmdConsumed(i.then, vars);
            markCmdConsumed(i.else_, vars);
        },
        .case_expr => |c| {
            for (c.branches) |b| {
                markCmdConsumed(b.body, vars);
            }
        },
        else => {},
    }
}

fn isCmdExecCall(func: *const ast.Expr) bool {
    return switch (func.*) {
        .ident => |id| std.mem.eql(u8, id.name, "Cmd.exec") or std.mem.eql(u8, id.name, "Cmd.execSafe"),
        else => false,
    };
}

fn isKnownCmdApi(name: []const u8) bool {
    const rest = if (std.mem.startsWith(u8, name, "Cmd.")) name["Cmd.".len..] else return false;
    const apis = [_][]const u8{ "pipe", "withEnv", "withWorkDir", "withStdin", "withStdinFile", "withRawOpt", "mergeStderr", "withRunAs", "andThen", "orElse", "exec", "timeout", "retry", "execSafe", "which" };
    for (apis) |api| {
        if (std.mem.eql(u8, rest, api)) return true;
    }
    return false;
}

pub fn checkUnusedBindings(allocator: std.mem.Allocator, names: []const []const u8, used: []const bool, errors: *ErrorList) !void {
    for (names, used, 0..) |name, is_used, i| {
        _ = i;
        if (!is_used) {
            try errors.add(allocator, .{ .effect_in_let = .{ .called_func = name, .span = .{ .start = .{ .line = 0, .col = 0, .offset = 0 }, .end = .{ .line = 0, .col = 0, .offset = 0 } } } });
        }
    }
}

pub fn checkUnusedResult(allocator: std.mem.Allocator, is_pure: bool, span: ast.Span, errors: *ErrorList) !void {
    if (is_pure) {
        try errors.add(allocator, .{ .effect_in_let = .{ .called_func = "unused result", .span = span } });
    }
}

pub fn checkPureExprLast(allocator: std.mem.Allocator, is_pure: bool, span: ast.Span, errors: *ErrorList) !void {
    if (is_pure) {
        try errors.add(allocator, .{ .effect_in_let = .{ .called_func = "pure expr last", .span = span } });
    }
}
