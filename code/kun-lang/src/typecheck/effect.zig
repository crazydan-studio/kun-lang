const std = @import("std");
const ast = @import("../ast/ast.zig");

const EffectNamespaces = [_][]const u8{
    "IO", "File", "Env", "Process", "Task", "Random",
};

const CmdEffectFns = [_][]const u8{
    "exec", "which", "timeout", "retry", "execSafe",
};

pub fn isEffectNamespaceCall(name: []const u8) bool {
    if (std.mem.eql(u8, name, "Signal.on")) return true;

    if (std.mem.startsWith(u8, name, "Cmd.")) {
        const rest = name["Cmd.".len..];
        if (std.mem.containsAtLeast(u8, rest, 1, "?")) return true;
        if (std.mem.containsAtLeast(u8, rest, 1, "!")) return true;
        if (std.mem.startsWith(u8, rest, "pipe?")) return true;
        if (std.mem.startsWith(u8, rest, "pipe!")) return true;
        for (CmdEffectFns) |efn| {
            if (std.mem.eql(u8, rest, efn)) return true;
        }
        return false;
    }

    for (EffectNamespaces) |ns| {
        if (std.mem.startsWith(u8, name, ns)) {
            if (name.len == ns.len) return true;
            if (name.len > ns.len and name[ns.len] == '.') return true;
        }
    }
    return false;
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
