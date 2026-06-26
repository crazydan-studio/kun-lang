const std = @import("std");
const typed = @import("../ast/typed.zig");
const ast = @import("../ast/ast.zig");
const value_mod = @import("value.zig");
const regex = @import("regex");
const env_mod = @import("env.zig");
const defer_mod = @import("defer.zig");
const primitive_mod = @import("primitive.zig");
const cmd_mod = @import("../command/cmd.zig");
const hash_map = @import("hash_map.zig");

const Value = value_mod.Value;
const Closure = value_mod.Closure;
const RecordFieldValue = value_mod.RecordFieldValue;
const Frame = env_mod.Frame;
const DeferStack = defer_mod.DeferStack;
const PrimitiveFn = primitive_mod.PrimitiveFn;
const PrimitiveBinding = primitive_mod.PrimitiveBinding;
const PrimitiveTable = primitive_mod.PrimitiveTable;
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
    MissingArgument,
    StackOverflow,
};

threadlocal var recursion_depth: u32 = 0;
const MAX_RECURSION_DEPTH: u32 = 10000;

pub fn eval(expr: *const TypedExpr, frame: *Frame, allocator: std.mem.Allocator) EvalError!Value {
    recursion_depth += 1;
    defer recursion_depth -= 1;
    if (recursion_depth > MAX_RECURSION_DEPTH) return error.StackOverflow;
    return switch (expr.*) {
        .int_literal => |v| Value{ .int = v.value },
        .float_literal => |v| Value{ .float = v.value },
        .string_literal => |v| Value{ .string = v.value },
        .bool_literal => |v| Value{ .bool = v.value },
        .char_literal => |v| Value{ .char = v.value },
        .nil_literal => Value{ .nil = {} },
        .duration_literal => |v| Value{ .duration = v.value },
        .path_literal => |v| Value{ .path = v.value },
        .regex_literal => |v| {
            const re = allocator.create(value_mod.RegexHandle) catch @panic("OOM");
            re.* = regex.Regex.compile(allocator, v.value) catch @panic("invalid regex");
            return Value{ .regex = re };
        },
        .bytes_literal => |v| Value{ .bytes = v.value },
        .ident => |v| {
            if (frame.lookup(v.name)) |val| return val;
            if (frame.primitives) |pt_ptr| {
                const pt: *const PrimitiveTable = @ptrCast(@alignCast(pt_ptr));
                if (std.mem.indexOfScalar(u8, v.name, '.')) |dot| {
                    const module = v.name[0..dot];
                    const name = v.name[dot + 1 ..];
                    for (pt.bindings) |binding| {
                        if (std.mem.eql(u8, binding.module, module) and std.mem.eql(u8, binding.name, name)) {
                            if (binding.arg_count > 1) {
                                const args = try allocator.alloc(Value, 0);
                                return Value{ .partial = .{ .fn_ptr = binding.fn_ptr, .args = args, .remaining = binding.arg_count } };
                            }
                            return Value{ .primitive = binding.fn_ptr };
                        }
                    }
                }
            }
            if (std.mem.startsWith(u8, v.name, "Cmd.") and !isKnownCmdApi(v.name)) {
                const bin_name = if (std.mem.indexOf(u8, v.name, ".")) |dot| v.name[dot + 1 ..] else v.name;
                const bin = try allocator.dupe(u8, bin_name);
                return Value{ .command = .{ .bin = bin, .options = &.{}, .positional = &.{} } };
            }
            return error.UnboundVariable;
        },
        .lambda => |v| {
            const names = try allocator.alloc([]const u8, v.params.len);
            for (v.params, 0..) |p, i| {
                names[i] = try allocator.dupe(u8, p.name);
            }
            return Value{ .closure = Closure{ .param_names = names, .body = v.body, .env = frame } };
        },
        .call => |v| {
            const func = try eval(v.func, frame, allocator);
            const arg = try eval(v.arg, frame, allocator);
            const eval_opaque: ?*anyopaque = @ptrCast(@constCast(&eval));
            return apply(func, arg, allocator, eval_opaque);
        },
        .let_in => |v| {
            const local = try allocator.create(Frame);
            local.* = Frame{ .bindings = .empty, .parent = frame, .primitives = frame.primitives };
            for (v.bindings) |b| {
                const val = try eval(b.value, frame, allocator);
                try local.bindings.put(allocator, b.name, val);
            }
            return eval(v.body, local, allocator);
        },
        .do_block => |v| {
            const local = try allocator.create(Frame);
            local.* = Frame{ .bindings = .empty, .parent = frame, .primitives = frame.primitives };
            var defers = DeferStack.init(allocator);
            defer defers.deinit();
            var stmt_err: ?EvalError = null;
            for (v.body) |stmt| {
                switch (stmt.kind) {
                    .binding => |b| {
                        const val = eval(b.value, local, allocator) catch |e| { stmt_err = e; break; };
                        try local.bindings.put(allocator, b.name, val);
                    },
                    .defer_ => |d| try defers.push(d.expr),
                    .expr => |e| _ = eval(e, local, allocator) catch |err| { stmt_err = err; break; },
                }
            }
            while (defers.pop()) |deferred| _ = eval(deferred, local, allocator) catch {};
            if (stmt_err) |e| return e;
            if (v.result) |r| return eval(r, local, allocator);
            return Value{ .unit = {} };
        },
        .if_expr => |v| {
            const cond = try eval(v.cond, frame, allocator);
            if (cond != .bool) return error.TypeMismatch;
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
            const right = try eval(v.right, frame, allocator);
            if (left == .command) {
                const cmd = left.command;
                if (cmd.bin.len > 0) {
                    const stream_node = cmd_mod.execCommand(&cmd, allocator) catch return error.Unimplemented;
                    const eval_opaque2: ?*anyopaque = @ptrCast(@constCast(&eval));
                    return apply(right, Value{ .stream = stream_node }, allocator, eval_opaque2);
                }
                return error.Unimplemented;
            }
            const eval_opaque3: ?*anyopaque = @ptrCast(@constCast(&eval));
            return apply(right, left, allocator, eval_opaque3);
        },
        .pipe_reverse => return error.Unimplemented,
        .compose => |v| {
            _ = v;
            return error.Unimplemented;
        },
        .compose_reverse => |v| {
            _ = v;
            return error.Unimplemented;
        },
        .map_literal => |v| evalMapLiteral(v.entries, frame, allocator),
        .set_literal => |v| evalSetLiteral(v.items, frame, allocator),
        .record_update => |v| {
            const rec_val = try eval(v.record, frame, allocator);
            if (rec_val != .record) return error.TypeMismatch;
            var fields = std.ArrayListUnmanaged(RecordFieldValue).empty;
            try fields.ensureTotalCapacity(allocator, rec_val.record.fields.len + v.fields.len);
            for (rec_val.record.fields) |rf| {
                fields.appendAssumeCapacity(rf);
            }
            for (v.fields) |f| {
                const new_val = try eval(f.value, frame, allocator);
                var found = false;
                for (fields.items) |*rf| {
                    if (std.mem.eql(u8, rf.name, f.name)) {
                        rf.value = new_val;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    fields.appendAssumeCapacity(.{ .name = f.name, .value = new_val });
                }
            }
            return Value{ .record = .{ .fields = fields.items } };
        },
        .range_literal => |v| {
            const from_val = try eval(v.from, frame, allocator);
            const to_val = try eval(v.to, frame, allocator);
            const step_val = if (v.step) |s| try eval(s, frame, allocator) else Value{ .int = 1 };
            if (from_val != .int or to_val != .int or step_val != .int) return error.TypeMismatch;
            if (step_val.int <= 0) return Value{ .nil = {} };
            const count: i64 = @divTrunc(to_val.int - from_val.int, step_val.int) + 1;
            if (count <= 0) return Value{ .nil = {} };
            const items = try allocator.alloc(Value, @intCast(count));
            var i: i64 = 0;
            while (i < count) : (i += 1) {
                items[@intCast(i)] = Value{ .int = from_val.int + i * step_val.int };
            }
            const node = try value_mod.streamFromList(allocator, items);
            return Value{ .stream = node };
        },
        .ternary => |v| {
            const cond = try eval(v.cond, frame, allocator);
            if (cond == .bool) {
                if (cond.bool) return eval(v.then, frame, allocator);
                return eval(v.else_, frame, allocator);
            }
            return error.TypeMismatch;
        },
        .case_expr => |v| evalCase(v.subject, v.branches, frame, allocator),
        .opt_chain => |v| {
            const obj = try eval(v.object, frame, allocator);
            if (obj == .nil) return Value.nil;
            if (obj != .record) return Value.nil;
            for (obj.record.fields) |f| {
                if (std.mem.eql(u8, f.name, v.field)) {
                    return f.value;
                }
            }
            return Value.nil;
        },
    };
}

fn apply(func: Value, arg: Value, allocator: std.mem.Allocator, eval_ptr: ?*anyopaque) EvalError!Value {
    return switch (func) {
        .closure => |c| {
            const frame = try allocator.create(Frame);
            frame.* = Frame{ .bindings = .empty, .parent = c.env, .primitives = c.env.primitives };
            if (c.param_names.len == 1) {
                try frame.bindings.put(allocator, c.param_names[0], arg);
            } else if (c.param_names.len > 1) {
                if (arg == .tuple) {
                    const elems = arg.tuple.items;
                    if (elems.len < c.param_names.len) return error.MissingArgument;
                    for (c.param_names, 0..) |_, i| {
                        try frame.bindings.put(allocator, c.param_names[i], elems[i]);
                    }
                }
            }
            return eval(c.body, frame, allocator);
        },
        .primitive => |p| {
            var renv = RuntimeEnv{ .frame = undefined, .primitives = .{ .bindings = &.{} }, .allocator = allocator, .eval_fn = eval_ptr };
            const args = try allocator.alloc(Value, 1);
            args[0] = arg;
            return p(&renv, args);
        },
        .partial => |p| {
            const new_len = p.args.len + 1;
            const new_args = try allocator.alloc(Value, new_len);
            @memcpy(new_args[0..p.args.len], p.args);
            new_args[p.args.len] = arg;
            if (p.remaining > 1) {
                return Value{ .partial = .{ .fn_ptr = p.fn_ptr, .args = new_args, .remaining = p.remaining - 1 } };
            }
            var renv = RuntimeEnv{ .frame = undefined, .primitives = .{ .bindings = &.{} }, .allocator = allocator, .eval_fn = eval_ptr };
            return p.fn_ptr(&renv, new_args);
        },
        .command => |c| {
            if (arg == .record) {
                const opts = try allocator.alloc(value_mod.CmdOption, arg.record.fields.len);
                for (arg.record.fields, 0..) |f, i| {
                    opts[i] = .{ .name = f.name, .value = f.value };
                }
                return Value{ .command = .{ .bin = c.bin, .options = opts, .positional = c.positional } };
            }
            const new_pos = try allocator.alloc(Value, c.positional.len + 1);
            @memcpy(new_pos[0..c.positional.len], c.positional);
            new_pos[c.positional.len] = arg;
            return Value{ .command = .{ .bin = c.bin, .options = c.options, .positional = new_pos } };
        },
        else => error.NotAFunction,
    };
}

fn isKnownCmdApi(name: []const u8) bool {
    return cmd_mod.isKnownCmdApi(name);
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
            if (branch.guard_cond) |guard| {
                const guard_frame = try allocator.create(Frame);
                guard_frame.* = Frame{ .bindings = local.bindings, .parent = frame, .primitives = frame.primitives };
                const cond = try eval(guard, guard_frame, allocator);
                if (cond == .bool and cond.bool) {
                    const local_frame = try allocator.create(Frame);
                    local_frame.* = Frame{ .bindings = local.bindings, .parent = frame, .primitives = frame.primitives };
                    return eval(branch.body, local_frame, allocator);
                }
                guard_frame.bindings.deinit(allocator);
                allocator.destroy(guard_frame);
                continue;
            }
            const local_frame = try allocator.create(Frame);
            local_frame.* = Frame{ .bindings = local.bindings, .parent = frame, .primitives = frame.primitives };
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
        .wildcard => Frame{ .bindings = .empty, .parent = null, .primitives = null },
        .literal => |l| {
            const lit_val = try evalLiteral(l, allocator);
            if (valueEqual(value, lit_val)) {
                return Frame{ .bindings = .empty, .parent = null, .primitives = null };
            }
            return null;
        },
        .ident => |id| {
            if (id.name.len > 0 and id.name[0] >= 'A' and id.name[0] <= 'Z') {
                if (std.mem.eql(u8, id.name, "True") and value == .bool and value.bool == true)
                    return Frame{ .bindings = .empty, .parent = null, .primitives = null };
                if (std.mem.eql(u8, id.name, "False") and value == .bool and value.bool == false)
                    return Frame{ .bindings = .empty, .parent = null, .primitives = null };
                if (std.mem.eql(u8, id.name, "Nil") and value == .nil)
                    return Frame{ .bindings = .empty, .parent = null, .primitives = null };
                return null;
            }
            var bindings: std.StringHashMapUnmanaged(Value) = .empty;
            try bindings.put(allocator, id.name, value);
            return Frame{ .bindings = bindings, .parent = null, .primitives = null };
        },
        .variant => |v| {
            if (value != .adt) return null;
            const expected_tag: u8 = if (std.mem.eql(u8, v.name, "Ok")) @as(u8, 0)
                else if (std.mem.eql(u8, v.name, "Err")) @as(u8, 1)
                else blk: {
                    if (std.fmt.parseInt(u8, v.name, 10)) |n| break :blk n else |_| return null;
                };
            if (value.adt.tag != expected_tag) return null;
            if (v.inner) |arg| {
                const payload_val = value.adt.payload.*;
                if (try matchPattern(arg.*, payload_val, frame, allocator)) |sub| {
                    var merged: std.StringHashMapUnmanaged(Value) = .empty;
                    var it = sub.bindings.iterator();
                    while (it.next()) |entry| {
                        try merged.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                    }
                    return Frame{ .bindings = merged, .parent = null, .primitives = null };
                }
                return null;
            }
            return Frame{ .bindings = .empty, .parent = null, .primitives = null };
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
            return Frame{ .bindings = bindings, .parent = null, .primitives = null };
        },
        .list => return null,
        .record => return null,
        .guard => |g| {
            if (try matchPattern(g.inner.*, value, frame, allocator)) |sub| {
                var merged: std.StringHashMapUnmanaged(Value) = .empty;
                var it = sub.bindings.iterator();
                while (it.next()) |entry| {
                    try merged.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                }
                return Frame{ .bindings = merged, .parent = null, .primitives = null };
            }
            return null;
        },
        .or_ => |o| {
            if (try matchPattern(o.left.*, value, frame, allocator)) |sub| {
                return sub;
            }
            if (try matchPattern(o.right.*, value, frame, allocator)) |sub| {
                return sub;
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
        .list => |al| listEqual(al.items, al.cap, b.list.items, b.list.cap),
        .tuple => |at| listEqual(at.items, 0, b.tuple.items, 0),
        .record => |ar| recordFieldsEqual(ar.fields, b.record.fields),
        .adt => |aa| aa.tag == b.adt.tag and valueEqual(aa.payload.*, b.adt.payload.*),
        .closure => |ac| @intFromPtr(ac.body) == @intFromPtr(b.closure.body),
        .map, .set, .command, .regex, .primitive, .partial => false,
    };
}

fn listEqual(a_items: []const Value, a_cap: usize, b_items: []const Value, b_cap: usize) bool {
    _ = a_cap;
    _ = b_cap;
    if (a_items.len != b_items.len) return false;
    for (a_items, b_items) |ai, bi| {
        if (!valueEqual(ai, bi)) return false;
    }
    return true;
}

fn recordFieldsEqual(a_fields: []const RecordFieldValue, b_fields: []const RecordFieldValue) bool {
    if (a_fields.len != b_fields.len) return false;
    for (a_fields) |af| {
        const bf = for (b_fields) |bf_| {
            if (std.mem.eql(u8, af.name, bf_.name)) break bf_;
        } else return false;
        if (!valueEqual(af.value, bf.value)) return false;
    }
    return true;
}

fn evalMapLiteral(entries: []const MapEntry, frame: *Frame, allocator: std.mem.Allocator) !Value {
    var result = Value{ .map = .{ .entries = @constCast(&[0]u8{}), .len = 0, .cap = 0 } };
    for (entries) |e| {
        const k = try eval(e.key, frame, allocator);
        const v = try eval(e.value, frame, allocator);
        const new_rep = try hash_map.mapInsert(allocator, result.map.entries, result.map.len, result.map.cap, k, v);
        result.map = new_rep;
    }
    return result;
}

fn evalSetLiteral(items: []const TypedExpr, frame: *Frame, allocator: std.mem.Allocator) !Value {
    var result = Value{ .set = .{ .entries = @constCast(&[0]u8{}), .len = 0, .cap = 0 } };
    for (items) |*item| {
        const v = try eval(item, frame, allocator);
        const new_rep = try hash_map.setInsert(allocator, result.set.entries, result.set.len, result.set.cap, v);
        result.set = new_rep;
    }
    return result;
}

pub fn evalModule(decls: []const TypedDecl, allocator: std.mem.Allocator, primitives: PrimitiveTable) !void {
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = @constCast(@ptrCast(&primitives)) };

    for (decls) |decl| {
        switch (decl.kind) {
            .function_def => |f| {
                if (!std.mem.eql(u8, f.name, "main")) {
                    const fn_val = try eval(f.body, global, allocator);
                    try global.bindings.put(allocator, f.name, fn_val);
                }
            },
            .import, .export_, .type_def => {},
        }
    }

    for (decls) |decl| {
        if (decl.kind == .function_def) {
            const f = decl.kind.function_def;
            if (std.mem.eql(u8, f.name, "main")) {
                _ = try eval(f.body, global, allocator);
                return;
            }
        }
    }
}
