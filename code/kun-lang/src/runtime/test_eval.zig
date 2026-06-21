const std = @import("std");
const typed = @import("../ast/typed.zig");
const value_mod = @import("value.zig");
const eval_mod = @import("eval.zig");
const env_mod = @import("env.zig");

const Value = value_mod.Value;
const Frame = env_mod.Frame;

test "eval int literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const global = try arena.allocator().create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const expr = typed.TypedExpr{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, arena.allocator());
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "eval bool literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const global = try arena.allocator().create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const expr = typed.TypedExpr{ .bool_literal = .{ .value = true, .type_ = 2, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, arena.allocator());
    try std.testing.expectEqual(true, result.bool);
}

test "eval string literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const global = try arena.allocator().create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const expr = typed.TypedExpr{ .string_literal = .{ .value = "hello", .type_ = 3, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, arena.allocator());
    try std.testing.expectEqualStrings("hello", result.string);
}

test "eval nil literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const global = try arena.allocator().create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const expr = typed.TypedExpr{ .nil_literal = .{ .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, arena.allocator());
    try std.testing.expect(result == .nil);
}

test "eval char literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const global = try arena.allocator().create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const expr = typed.TypedExpr{ .char_literal = .{ .value = 'A', .type_ = 4, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, arena.allocator());
    try std.testing.expectEqual(@as(u32, 'A'), result.char);
}

test "eval float literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const global = try arena.allocator().create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const expr = typed.TypedExpr{ .float_literal = .{ .value = 3.14, .type_ = 1, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, arena.allocator());
    try std.testing.expectApproxEqRel(3.14, result.float, 1e-10);
}

test "eval if_expr true" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const cond = try allocator.create(typed.TypedExpr);
    cond.* = .{ .bool_literal = .{ .value = true, .type_ = 2, .span = undefined } };
    const then_expr = try allocator.create(typed.TypedExpr);
    then_expr.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const else_expr = try allocator.create(typed.TypedExpr);
    else_expr.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .if_expr = .{ .cond = cond, .then = then_expr, .else_ = else_expr, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 1), result.int);
}

test "eval if_expr false" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const cond = try allocator.create(typed.TypedExpr);
    cond.* = .{ .bool_literal = .{ .value = false, .type_ = 2, .span = undefined } };
    const then_expr = try allocator.create(typed.TypedExpr);
    then_expr.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const else_expr = try allocator.create(typed.TypedExpr);
    else_expr.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .if_expr = .{ .cond = cond, .then = then_expr, .else_ = else_expr, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 0), result.int);
}

test "eval binary add int" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .int_literal = .{ .value = 2, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .binary_op = .{ .op = .add, .left = left, .right = right, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 3), result.int);
}

test "eval binary sub" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .int_literal = .{ .value = 5, .type_ = 0, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .int_literal = .{ .value = 3, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .binary_op = .{ .op = .sub, .left = left, .right = right, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 2), result.int);
}

test "eval binary mul" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .int_literal = .{ .value = 6, .type_ = 0, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .int_literal = .{ .value = 7, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .binary_op = .{ .op = .mul, .left = left, .right = right, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "eval binary eq true" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .binary_op = .{ .op = .eq, .left = left, .right = right, .type_ = 2, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(true, result.bool);
}

test "eval binary eq false" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .int_literal = .{ .value = 2, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .binary_op = .{ .op = .eq, .left = left, .right = right, .type_ = 2, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(false, result.bool);
}

test "eval binary lt gt" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const l = try allocator.create(typed.TypedExpr);
    l.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const r = try allocator.create(typed.TypedExpr);
    r.* = .{ .int_literal = .{ .value = 2, .type_ = 0, .span = undefined } };

    const lt = typed.TypedExpr{ .binary_op = .{ .op = .lt, .left = l, .right = r, .type_ = 2, .span = undefined } };
    try std.testing.expectEqual(true, (try eval_mod.eval(&lt, global, allocator)).bool);

    const gt = typed.TypedExpr{ .binary_op = .{ .op = .gt, .left = l, .right = r, .type_ = 2, .span = undefined } };
    try std.testing.expectEqual(false, (try eval_mod.eval(&gt, global, allocator)).bool);
}

test "eval binary and or short circuit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const t = try allocator.create(typed.TypedExpr);
    t.* = .{ .bool_literal = .{ .value = true, .type_ = 2, .span = undefined } };
    const f = try allocator.create(typed.TypedExpr);
    f.* = .{ .bool_literal = .{ .value = false, .type_ = 2, .span = undefined } };

    const and_expr = typed.TypedExpr{ .binary_op = .{ .op = .and_, .left = f, .right = t, .type_ = 2, .span = undefined } };
    try std.testing.expectEqual(false, (try eval_mod.eval(&and_expr, global, allocator)).bool);

    const or_expr = typed.TypedExpr{ .binary_op = .{ .op = .or_, .left = t, .right = f, .type_ = 2, .span = undefined } };
    try std.testing.expectEqual(true, (try eval_mod.eval(&or_expr, global, allocator)).bool);
}

test "eval binary concat strings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .string_literal = .{ .value = "hello", .type_ = 3, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .string_literal = .{ .value = " world", .type_ = 3, .span = undefined } };

    const expr = typed.TypedExpr{ .binary_op = .{ .op = .concat, .left = left, .right = right, .type_ = 3, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqualStrings("hello world", result.string);
}

test "eval binary nil coalesce" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .nil_literal = .{ .type_ = 0, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .binary_op = .{ .op = .nil_coal, .left = left, .right = right, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "eval unary neg" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const operand = try allocator.create(typed.TypedExpr);
    operand.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const expr = typed.TypedExpr{ .unary_op = .{ .op = .neg, .operand = operand, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, -42), result.int);
}

test "eval unary not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const operand = try allocator.create(typed.TypedExpr);
    operand.* = .{ .bool_literal = .{ .value = true, .type_ = 2, .span = undefined } };
    const expr = typed.TypedExpr{ .unary_op = .{ .op = .not, .operand = operand, .type_ = 2, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(false, result.bool);
}

test "eval let_in" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const val_expr = try allocator.create(typed.TypedExpr);
    val_expr.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const bindings = try allocator.alloc(typed.Binding, 1);
    bindings[0] = .{ .name = "x", .value = val_expr };
    const body = try allocator.create(typed.TypedExpr);
    body.* = .{ .ident = .{ .name = "x", .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .let_in = .{ .bindings = bindings, .body = body, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 1), result.int);
}

test "eval lambda and call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const params = try allocator.alloc(typed.Param, 1);
    params[0] = .{ .name = "x", .type_ = 0 };
    const body = try allocator.create(typed.TypedExpr);
    body.* = .{ .ident = .{ .name = "x", .type_ = 0, .span = undefined } };

    const lam = try allocator.create(typed.TypedExpr);
    lam.* = .{ .lambda = .{ .params = params, .body = body, .type_ = 0, .span = undefined } };
    const arg = try allocator.create(typed.TypedExpr);
    arg.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .call = .{ .func = lam, .arg = arg, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "eval record literal and access" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const val = try allocator.create(typed.TypedExpr);
    val.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const fields = try allocator.alloc(typed.RecordField, 1);
    fields[0] = .{ .name = "x", .value = val };
    const rec = try allocator.create(typed.TypedExpr);
    rec.* = .{ .record_literal = .{ .fields = fields, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .record_access = .{ .record = rec, .field = "x", .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "eval tuple literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    var items: [2]typed.TypedExpr = undefined;
    items[0] = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    items[1] = .{ .bool_literal = .{ .value = true, .type_ = 2, .span = undefined } };

    const expr = typed.TypedExpr{ .tuple_literal = .{ .items = &items, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .tuple);
    try std.testing.expectEqual(@as(i64, 1), result.tuple.items[0].int);
    try std.testing.expectEqual(true, result.tuple.items[1].bool);
}

test "eval list literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const e1 = try allocator.create(typed.TypedExpr);
    e1.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const e2 = try allocator.create(typed.TypedExpr);
    e2.* = .{ .int_literal = .{ .value = 2, .type_ = 0, .span = undefined } };
    const items = try allocator.alloc(typed.ExprItem, 2);
    items[0] = .{ .expr = e1 };
    items[1] = .{ .expr = e2 };

    const expr = typed.TypedExpr{ .list_literal = .{ .items = items, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .list);
    try std.testing.expectEqual(@as(usize, 2), result.list.items.len);
}

test "eval case wildcard" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const subject = try allocator.create(typed.TypedExpr);
    subject.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const body = try allocator.create(typed.TypedExpr);
    body.* = .{ .int_literal = .{ .value = 99, .type_ = 0, .span = undefined } };
    const branches = try allocator.alloc(typed.Branch, 1);
    branches[0] = .{ .pattern = .{ .wildcard = undefined }, .body = body, .type_ = 0 };

    const expr = typed.TypedExpr{ .case_expr = .{ .subject = subject, .branches = branches, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 99), result.int);
}

test "eval case nil vs value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    const subject = try allocator.create(typed.TypedExpr);
    subject.* = .{ .nil_literal = .{ .type_ = 0, .span = undefined } };
    const nil_body = try allocator.create(typed.TypedExpr);
    nil_body.* = .{ .string_literal = .{ .value = "none", .type_ = 3, .span = undefined } };
    const val_body = try allocator.create(typed.TypedExpr);
    val_body.* = .{ .string_literal = .{ .value = "exists", .type_ = 3, .span = undefined } };

    const branches = try allocator.alloc(typed.Branch, 2);
    branches[0] = .{ .pattern = .{ .ident = .{ .name = "Nil", .span = undefined } }, .body = nil_body, .type_ = 3 };
    branches[1] = .{ .pattern = .{ .ident = .{ .name = "val", .span = undefined } }, .body = val_body, .type_ = 3 };

    const expr = typed.TypedExpr{ .case_expr = .{ .subject = subject, .branches = branches, .type_ = 3, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqualStrings("none", result.string);
}
