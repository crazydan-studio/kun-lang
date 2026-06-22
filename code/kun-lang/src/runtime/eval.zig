const std = @import("std");
const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");
const value_mod = @import("value.zig");
const env_mod = @import("env.zig");
const defer_mod = @import("defer.zig");
const primitive_mod = @import("primitive.zig");

const Value = value_mod.Value;
const Closure = value_mod.Closure;
const RecordFieldValue = value_mod.RecordFieldValue;
const Frame = env_mod.Frame;
const DeferStack = defer_mod.DeferStack;
const PrimitiveFn = primitive_mod.PrimitiveFn;
const RuntimeEnv = primitive_mod.RuntimeEnv;
const TypedExpr = typed.TypedExpr;
const TypedDecl = typed.TypedDecl;
const MapEntry = typed.MapEntry;

pub const EvalError = error{
    UnboundVariable,
    NotAFunction,
    TypeMismatch,
    DivisionByZero,
    UnknownField,
    NoMatch,
    Unimplemented,
    OutOfMemory,
};

pub fn eval(expr: *const TypedExpr, frame: *Frame, allocator: std.mem.Allocator) EvalError!Value {
    return switch (expr.*) {
        .int_literal => |v| Value{ .int = v.value },
        .float_literal => |v| Value{ .float = v.value },
        .string_literal => |v| Value{ .string = v.value },
        .bool_literal => |v| Value{ .bool = v.value },
        .char_literal => |v| Value{ .char = v.value },
        .nil_literal => Value{ .nil = {} },
        .duration_literal => |v| Value{ .duration = v.value },
        .path_literal => |v| Value{ .path = v.value },
        .regex_literal => @panic("unimplemented: regex"),
        .bytes_literal => |v| Value{ .bytes = v.value },
        .ident => |v| {
            if (frame.lookup(v.name)) |val| return val;
            if (std.mem.startsWith(u8, v.name, "Cmd.") and !isKnownCmdApi(v.name)) {
                var payload = std.mem.zeroes([32]u8);
                const bin_name = if (std.mem.indexOf(u8, v.name, ".")) |dot| v.name[dot + 1 ..] else v.name;
                @memcpy(payload[0..@min(bin_name.len, 31)], bin_name);
                return Value{ .command = .{ .tag = 0, ._payload = payload } };
            }
            return error.UnboundVariable;
        },
        .lambda => |v| {
            const names = try allocator.alloc([]const u8, v.params.len);
            for (v.params, 0..) |p, i| names[i] = p.name;
            return Value{ .closure = Closure{ .param_names = names, .body = v.body, .env = frame } };
        },
        .call => |v| {
            const func = try eval(v.func, frame, allocator);
            const arg = try eval(v.arg, frame, allocator);
            return apply(func, arg, allocator);
        },
        .let_in => |v| {
            const local = try allocator.create(Frame);
            local.* = Frame{ .bindings = .empty, .parent = frame };
            for (v.bindings) |b| {
                const val = try eval(b.value, frame, allocator);
                try local.bindings.put(allocator, b.name, val);
            }
            return eval(v.body, local, allocator);
        },
        .do_block => |v| {
            const local = try allocator.create(Frame);
            local.* = Frame{ .bindings = .empty, .parent = frame };
            var defers = DeferStack.init(allocator);
            defer defers.deinit();
            for (v.body) |stmt| {
                switch (stmt.kind) {
                    .binding => |b| {
                        const val = try eval(b.value, local, allocator);
                        try local.bindings.put(allocator, b.name, val);
                    },
                    .defer_ => |d| try defers.push(d.expr),
                    .expr => |e| _ = try eval(e, local, allocator),
                }
            }
            while (defers.pop()) |deferred| _ = try eval(deferred, local, allocator);
            if (v.result) |r| return eval(r, local, allocator);
            return Value{ .unit = {} };
        },
        .if_expr => |v| {
            const cond = try eval(v.cond, frame, allocator);
            if (cond.bool) return eval(v.then, frame, allocator);
            return eval(v.else_, frame, allocator);
        },
        .binary_op => |v| evalBinaryOp(v.op, v.left, v.right, frame, allocator),
        .unary_op => |v| evalUnaryOp(v.op, v.operand, frame, allocator),
        .list_literal => |v| evalList(v.items, frame, allocator),
        .tuple_literal => |v| evalTuple(v.items, frame, allocator),
        .record_literal => |v| evalRecord(v.fields, frame, allocator),
        .record_access => |v| evalRecordAccess(v.record, v.field, frame, allocator),
        .pipe => |v| {
            const left = try eval(v.left, frame, allocator);
            _ = left;
            return eval(v.right, frame, allocator);
        },
        .pipe_reverse => @panic("unimplemented: pipe_reverse (should be desugared to call)"),
        .compose => @panic("unimplemented: compose (should be desugared to lambda+call)"),
        .compose_reverse => @panic("unimplemented: compose_reverse (should be desugared to lambda+call)"),
        .map_literal => |v| evalMapLiteral(v.entries, frame, allocator),
        .set_literal => |v| evalSetLiteral(v.items, frame, allocator),
        .case_expr => |v| evalCase(v.subject, v.branches, frame, allocator),
    };
}

fn apply(func: Value, arg: Value, allocator: std.mem.Allocator) EvalError!Value {
    return switch (func) {
        .closure => |c| {
            const frame = try allocator.create(Frame);
            frame.* = Frame{ .bindings = .empty, .parent = c.env };
            if (c.param_names.len == 1) {
                try frame.bindings.put(allocator, c.param_names[0], arg);
            } else if (c.param_names.len > 1) {
                if (arg == .tuple) {
                    const elems = arg.tuple.items;
                    const n = @min(c.param_names.len, elems.len);
                    for (0..n) |i| {
                        try frame.bindings.put(allocator, c.param_names[i], elems[i]);
                    }
                }
            }
            return eval(c.body, frame, allocator);
        },
        .primitive => |p| {
            var renv = RuntimeEnv{ .frame = undefined, .primitives = undefined, .allocator = allocator };
            return p(&renv, &arg);
        },
        .command => |c| {
            if (arg == .string) {
                var payload = c._payload;
                @memcpy(payload[@min(binNameLen(payload), 31)..@min(binNameLen(payload) + arg.string.len, 31)], arg.string);
                return Value{ .command = .{ .tag = 0, ._payload = payload } };
            }
            return func;
        },
        else => error.NotAFunction,
    };
}

fn binNameLen(payload: [32]u8) usize {
    for (payload, 0..) |b, i| {
        if (b == 0) return i;
    }
    return 32;
}

const known_cmd_apis = [_][]const u8{ "pipe", "withEnv", "withWorkDir", "withStdin", "withStdinFile", "withRawOpt", "mergeStderr", "withRunAs", "andThen", "orElse", "exec", "timeout", "retry", "execSafe", "which" };

fn isKnownCmdApi(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "Cmd.")) return false;
    const rest = name["Cmd.".len..];
    if (std.mem.containsAtLeast(u8, rest, 1, "?")) return true;
    if (std.mem.containsAtLeast(u8, rest, 1, "!")) return true;
    for (known_cmd_apis) |api| {
        if (std.mem.eql(u8, rest, api)) return true;
    }
    return false;
}

fn evalBinaryOp(
    op: ast.BinaryOp,
    left_expr: *const TypedExpr,
    right_expr: *const TypedExpr,
    frame: *Frame,
    allocator: std.mem.Allocator,
) !Value {
    return switch (op) {
        .add => {
            const l = try eval(left_expr, frame, allocator);
            const r = try eval(right_expr, frame, allocator);
            if (l == .int and r == .int) return Value{ .int = l.int + r.int };
            if (l == .float and r == .float) return Value{ .float = l.float + r.float };
            return error.TypeMismatch;
        },
        .sub => {
            const l = try eval(left_expr, frame, allocator);
            const r = try eval(right_expr, frame, allocator);
            if (l == .int and r == .int) return Value{ .int = l.int - r.int };
            if (l == .float and r == .float) return Value{ .float = l.float - r.float };
            return error.TypeMismatch;
        },
        .mul => {
            const l = try eval(left_expr, frame, allocator);
            const r = try eval(right_expr, frame, allocator);
            if (l == .int and r == .int) return Value{ .int = l.int * r.int };
            if (l == .float and r == .float) return Value{ .float = l.float * r.float };
            return error.TypeMismatch;
        },
        .div => {
            const l = try eval(left_expr, frame, allocator);
            const r = try eval(right_expr, frame, allocator);
            if (l == .int and r == .int) {
                if (r.int == 0) return error.DivisionByZero;
                return Value{ .int = @divTrunc(l.int, r.int) };
            }
            if (l == .float and r == .float) return Value{ .float = l.float / r.float };
            return error.TypeMismatch;
        },
        .mod => {
            const l = try eval(left_expr, frame, allocator);
            const r = try eval(right_expr, frame, allocator);
            if (l == .int and r == .int) {
                if (r.int == 0) return error.DivisionByZero;
                return Value{ .int = @mod(l.int, r.int) };
            }
            return error.TypeMismatch;
        },
        .eq => {
            const l = try eval(left_expr, frame, allocator);
            const r = try eval(right_expr, frame, allocator);
            return Value{ .bool = valueEqual(l, r) };
        },
        .neq => {
            const l = try eval(left_expr, frame, allocator);
            const r = try eval(right_expr, frame, allocator);
            return Value{ .bool = !valueEqual(l, r) };
        },
        .lt => {
            const l = try eval(left_expr, frame, allocator);
            const r = try eval(right_expr, frame, allocator);
            if (l == .int and r == .int) return Value{ .bool = l.int < r.int };
            if (l == .float and r == .float) return Value{ .bool = l.float < r.float };
            return error.TypeMismatch;
        },
        .le => {
            const l = try eval(left_expr, frame, allocator);
            const r = try eval(right_expr, frame, allocator);
            if (l == .int and r == .int) return Value{ .bool = l.int <= r.int };
            if (l == .float and r == .float) return Value{ .bool = l.float <= r.float };
            return error.TypeMismatch;
        },
        .gt => {
            const l = try eval(left_expr, frame, allocator);
            const r = try eval(right_expr, frame, allocator);
            if (l == .int and r == .int) return Value{ .bool = l.int > r.int };
            if (l == .float and r == .float) return Value{ .bool = l.float > r.float };
            return error.TypeMismatch;
        },
        .ge => {
            const l = try eval(left_expr, frame, allocator);
            const r = try eval(right_expr, frame, allocator);
            if (l == .int and r == .int) return Value{ .bool = l.int >= r.int };
            if (l == .float and r == .float) return Value{ .bool = l.float >= r.float };
            return error.TypeMismatch;
        },
        .and_ => {
            const l = try eval(left_expr, frame, allocator);
            if (l != .bool) return error.TypeMismatch;
            if (!l.bool) return Value{ .bool = false };
            const r = try eval(right_expr, frame, allocator);
            if (r != .bool) return error.TypeMismatch;
            return Value{ .bool = r.bool };
        },
        .or_ => {
            const l = try eval(left_expr, frame, allocator);
            if (l != .bool) return error.TypeMismatch;
            if (l.bool) return Value{ .bool = true };
            const r = try eval(right_expr, frame, allocator);
            if (r != .bool) return error.TypeMismatch;
            return Value{ .bool = r.bool };
        },
        .concat => {
            const l = try eval(left_expr, frame, allocator);
            const r = try eval(right_expr, frame, allocator);
            if (l == .string and r == .string) {
                const result = try std.fmt.allocPrint(allocator, "{s}{s}", .{ l.string, r.string });
                return Value{ .string = result };
            }
            return error.TypeMismatch;
        },
        .nil_coal => {
            const l = try eval(left_expr, frame, allocator);
            if (l == .nil) return eval(right_expr, frame, allocator);
            return l;
        },
        .range => @panic("unimplemented: range"),
    };
}

fn evalUnaryOp(
    op: ast.UnaryOp,
    operand: *const TypedExpr,
    frame: *Frame,
    allocator: std.mem.Allocator,
) !Value {
    const val = try eval(operand, frame, allocator);
    return switch (op) {
        .neg => switch (val) {
            .int => |i| Value{ .int = -i },
            .float => |f| Value{ .float = -f },
            else => error.TypeMismatch,
        },
        .not => switch (val) {
            .bool => |b| Value{ .bool = !b },
            else => error.TypeMismatch,
        },
    };
}

fn evalList(items: []const typed.ExprItem, frame: *Frame, allocator: std.mem.Allocator) !Value {
    var vals: std.ArrayListUnmanaged(Value) = .empty;
    defer vals.deinit(allocator);
    for (items) |item| {
        switch (item) {
            .expr => |e| {
                const val = try eval(e, frame, allocator);
                try vals.append(allocator, val);
            },
            .spread => |s| {
                const val = try eval(s, frame, allocator);
                if (val == .list) {
                    for (val.list.items) |li| {
                        try vals.append(allocator, li);
                    }
                }
            },
        }
    }
    const result_items = try vals.toOwnedSlice(allocator);
    return Value{ .list = .{ .items = result_items, .cap = result_items.len } };
}

fn evalTuple(items: []const TypedExpr, frame: *Frame, allocator: std.mem.Allocator) !Value {
    var vals: std.ArrayListUnmanaged(Value) = .empty;
    defer vals.deinit(allocator);
    for (items) |item| {
        const val = try eval(&item, frame, allocator);
        try vals.append(allocator, val);
    }
    return Value{ .tuple = .{ .items = try vals.toOwnedSlice(allocator) } };
}

fn evalRecord(fields: []const typed.RecordField, frame: *Frame, allocator: std.mem.Allocator) !Value {
    const result_fields = try allocator.alloc(RecordFieldValue, fields.len);
    for (fields, 0..) |f, i| {
        const val = try eval(f.value, frame, allocator);
        result_fields[i] = RecordFieldValue{ .name = f.name, .value = val };
    }
    return Value{ .record = .{ .fields = result_fields } };
}

fn evalRecordAccess(record_expr: *const TypedExpr, field_name: []const u8, frame: *Frame, allocator: std.mem.Allocator) !Value {
    const rec = try eval(record_expr, frame, allocator);
    if (rec == .record) {
        for (rec.record.fields) |f| {
            if (std.mem.eql(u8, f.name, field_name)) {
                return f.value;
            }
        }
    }
    return error.UnknownField;
}

fn evalCase(subject_expr: *const TypedExpr, branches: []const typed.Branch, frame: *Frame, allocator: std.mem.Allocator) !Value {
    const subject = try eval(subject_expr, frame, allocator);
    for (branches) |branch| {
        if (try matchPattern(branch.pattern, subject, frame, allocator)) |local| {
            const local_frame = try allocator.create(Frame);
            local_frame.* = Frame{ .bindings = local.bindings, .parent = frame };
            return eval(branch.body, local_frame, allocator);
        }
    }
    return error.NoMatch;
}

fn matchPattern(
    pattern: ast.Pattern,
    value: Value,
    frame: *Frame,
    allocator: std.mem.Allocator,
) !?Frame {
    return switch (pattern) {
        .wildcard => Frame{ .bindings = .empty, .parent = null },
        .literal => |l| {
            const lit_val = try evalLiteral(l, allocator);
            if (valueEqual(value, lit_val)) {
                return Frame{ .bindings = .empty, .parent = null };
            }
            return null;
        },
        .ident => |id| {
            if (id.name.len > 0 and id.name[0] >= 'A' and id.name[0] <= 'Z') {
                if (std.mem.eql(u8, id.name, "True") and value == .bool and value.bool == true)
                    return Frame{ .bindings = .empty, .parent = null };
                if (std.mem.eql(u8, id.name, "False") and value == .bool and value.bool == false)
                    return Frame{ .bindings = .empty, .parent = null };
                if (std.mem.eql(u8, id.name, "Nil") and value == .nil)
                    return Frame{ .bindings = .empty, .parent = null };
                return null;
            }
            var bindings: std.StringHashMapUnmanaged(Value) = .empty;
            try bindings.put(allocator, id.name, value);
            return Frame{ .bindings = bindings, .parent = null };
        },
        .variant => |v| {
            _ = v;
            return Frame{ .bindings = .empty, .parent = null };
        },
        .tuple => |t| {
            if (value != .tuple) return null;
            if (t.items.len != value.tuple.items.len) return null;
            var bindings: std.StringHashMapUnmanaged(Value) = .empty;
            for (t.items, value.tuple.items) |pat, val| {
                if (try matchPattern(pat, val, frame, allocator)) |sub| {
                    var it = sub.bindings.iterator();
                    while (it.next()) |entry| {
                        try bindings.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                    }
                } else return null;
            }
            return Frame{ .bindings = bindings, .parent = null };
        },
        .list => return null,
        .record => return null,
        .guard => |g| {
            if (try matchPattern(g.inner.*, value, frame, allocator)) |sub| {
                _ = sub;
                return Frame{ .bindings = .empty, .parent = null };
            }
            return null;
        },
    };
}

fn evalLiteral(literal: *const ast.Expr, allocator: std.mem.Allocator) !Value {
    _ = allocator;
    return switch (literal.*) {
        .int_literal => |v| Value{ .int = v.value },
        .float_literal => |v| Value{ .float = v.value },
        .string_literal => |v| Value{ .string = v.value },
        .bool_literal => |v| Value{ .bool = v.value },
        .char_literal => |v| Value{ .char = @intCast(v.value) },
        .nil_literal => Value{ .nil = {} },
        else => error.Unimplemented,
    };
}

fn valueEqual(a: Value, b: Value) bool {
    if (@intFromEnum(a) != @intFromEnum(b)) return false;
    return switch (a) {
        .int => |ai| b.int == ai,
        .float => |af| b.float == af,
        .bool => |ab| b.bool == ab,
        .char => |ac| b.char == ac,
        .string => |as| std.mem.eql(u8, as, b.string),
        .bytes => |ab| std.mem.eql(u8, ab, b.bytes),
        .path => |ap| std.mem.eql(u8, ap, b.path),
        .nil => true,
        .unit => true,
        .duration => |ad| b.duration == ad,
        .datetime => |ad| b.datetime == ad,
        .decimal => |ad| ad.mantissa == b.decimal.mantissa and ad.exponent == b.decimal.exponent,
        .stream => |as| @intFromPtr(as) == @intFromPtr(b.stream),
        .map, .set, .command, .regex, .adt, .list, .tuple, .record, .closure, .primitive => false,
    };
}

fn evalMapLiteral(entries: []const MapEntry, frame: *Frame, allocator: std.mem.Allocator) !Value {
    _ = entries;
    _ = frame;
    _ = allocator;
    return Value{ .map = .{ .entries = @as([*]u8, @ptrFromInt(0x1)), .len = 0, .cap = 0 } };
}

fn evalSetLiteral(items: []const TypedExpr, frame: *Frame, allocator: std.mem.Allocator) !Value {
    _ = items;
    _ = frame;
    _ = allocator;
    return Value{ .set = .{ .entries = @as([*]u8, @ptrFromInt(0x1)), .len = 0, .cap = 0 } };
}

pub fn evalModule(decls: []const TypedDecl, allocator: std.mem.Allocator) !void {
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    for (decls) |decl| {
        if (decl.kind == .function_def) {
            const f = decl.kind.function_def;
            if (!std.mem.eql(u8, f.name, "main")) {
                const fn_val = try eval(f.body, global, allocator);
                try global.bindings.put(allocator, f.name, fn_val);
            }
        }
    }

    for (decls) |decl| {
        if (decl.kind == .function_def and std.mem.eql(u8, decl.kind.function_def.name, "main")) {
            _ = try eval(decl.kind.function_def.body, global, allocator);
            return;
        }
    }

    for (decls) |decl| {
        if (decl.kind == .function_def) {
            _ = try eval(decl.kind.function_def.body, global, allocator);
            return;
        }
    }
}
