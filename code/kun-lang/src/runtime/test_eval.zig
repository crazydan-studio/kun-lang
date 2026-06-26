const std = @import("std");
const typed = @import("../ast/typed.zig");
const ast = @import("../ast/ast.zig");
const value_mod = @import("value.zig");
const eval_mod = @import("eval.zig");
const env_mod = @import("env.zig");
const primitive_mod = @import("primitive.zig");
const tc_env = @import("../typecheck/env.zig");
const hash_map = @import("hash_map.zig");

const Value = value_mod.Value;
const Frame = env_mod.Frame;

test "eval int literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const global = try arena.allocator().create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const expr = typed.TypedExpr{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, arena.allocator());
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "eval bool literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const global = try arena.allocator().create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const expr = typed.TypedExpr{ .bool_literal = .{ .value = true, .type_ = 2, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, arena.allocator());
    try std.testing.expectEqual(true, result.bool);
}

test "eval string literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const global = try arena.allocator().create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const expr = typed.TypedExpr{ .string_literal = .{ .value = "hello", .type_ = 3, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, arena.allocator());
    try std.testing.expectEqualStrings("hello", result.string);
}

test "eval nil literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const global = try arena.allocator().create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const expr = typed.TypedExpr{ .ident = .{ .name = "Nil", .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, arena.allocator());
    try std.testing.expect(result == .nil);
}

test "eval char literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const global = try arena.allocator().create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const expr = typed.TypedExpr{ .char_literal = .{ .value = 'A', .type_ = 4, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, arena.allocator());
    try std.testing.expectEqual(@as(u32, 'A'), result.char);
}

test "eval float literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const global = try arena.allocator().create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const expr = typed.TypedExpr{ .float_literal = .{ .value = 3.14, .type_ = 1, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, arena.allocator());
    try std.testing.expectApproxEqRel(3.14, result.float, 1e-10);
}

test "eval if_expr true" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .ident = .{ .name = "Nil", .type_ = 0, .span = undefined } };
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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

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
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const subject = try allocator.create(typed.TypedExpr);
    subject.* = .{ .ident = .{ .name = "Nil", .type_ = 0, .span = undefined } };
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

test "eval duration literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const expr = typed.TypedExpr{ .duration_literal = .{ .value = 5000, .unit = .ms, .type_ = 8, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 5000), result.duration);
}

test "eval path literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const expr = typed.TypedExpr{ .path_literal = .{ .value = "/tmp/test", .type_ = 7, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqualStrings("/tmp/test", result.path);
}

test "eval bytes literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const expr = typed.TypedExpr{ .bytes_literal = .{ .value = "deadbeef", .type_ = 5, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqualStrings("deadbeef", result.bytes);
}

test "eval do_block returns unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const expr = typed.TypedExpr{ .do_block = .{ .body = &.{}, .result = null, .type_ = 6, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .unit);
}

test "eval do_block with binding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const val_expr = try allocator.create(typed.TypedExpr);
    val_expr.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const stmts = try allocator.alloc(typed.Stmt, 1);
    stmts[0] = .{ .kind = .{ .binding = .{ .name = "x", .value = val_expr } }, .type_ = 0 };

    const expr = typed.TypedExpr{ .do_block = .{ .body = stmts, .result = null, .type_ = 6, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .unit);
}

test "eval binary div" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .int_literal = .{ .value = 10, .type_ = 0, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .int_literal = .{ .value = 2, .type_ = 0, .span = undefined } };
    const expr = typed.TypedExpr{ .binary_op = .{ .op = .div, .left = left, .right = right, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 5), result.int);
}

test "eval binary div by zero" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .int_literal = .{ .value = 10, .type_ = 0, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const expr = typed.TypedExpr{ .binary_op = .{ .op = .div, .left = left, .right = right, .type_ = 0, .span = undefined } };
    try std.testing.expectError(error.DivisionByZero, eval_mod.eval(&expr, global, allocator));
}

test "eval binary mod" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .int_literal = .{ .value = 10, .type_ = 0, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .int_literal = .{ .value = 3, .type_ = 0, .span = undefined } };
    const expr = typed.TypedExpr{ .binary_op = .{ .op = .mod, .left = left, .right = right, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 1), result.int);
}

test "eval binary neq" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .int_literal = .{ .value = 2, .type_ = 0, .span = undefined } };
    const expr = typed.TypedExpr{ .binary_op = .{ .op = .neq, .left = left, .right = right, .type_ = 2, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(true, result.bool);
}

test "eval binary le ge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const l = try allocator.create(typed.TypedExpr);
    l.* = .{ .int_literal = .{ .value = 5, .type_ = 0, .span = undefined } };
    const r = try allocator.create(typed.TypedExpr);
    r.* = .{ .int_literal = .{ .value = 5, .type_ = 0, .span = undefined } };

    const le = typed.TypedExpr{ .binary_op = .{ .op = .le, .left = l, .right = r, .type_ = 2, .span = undefined } };
    try std.testing.expectEqual(true, (try eval_mod.eval(&le, global, allocator)).bool);

    const ge = typed.TypedExpr{ .binary_op = .{ .op = .ge, .left = l, .right = r, .type_ = 2, .span = undefined } };
    try std.testing.expectEqual(true, (try eval_mod.eval(&ge, global, allocator)).bool);
}

test "eval ident unbound variable error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const expr = typed.TypedExpr{ .ident = .{ .name = "undefined_var", .type_ = 0, .span = undefined } };
    try std.testing.expectError(error.UnboundVariable, eval_mod.eval(&expr, global, allocator));
}

test "eval call with non-function error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const func = try allocator.create(typed.TypedExpr);
    func.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const arg = try allocator.create(typed.TypedExpr);
    arg.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const expr = typed.TypedExpr{ .call = .{ .func = func, .arg = arg, .type_ = 0, .span = undefined } };
    try std.testing.expectError(error.NotAFunction, eval_mod.eval(&expr, global, allocator));
}

test "eval nil coalesce non-nil returns left" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .int_literal = .{ .value = 99, .type_ = 0, .span = undefined } };
    const expr = typed.TypedExpr{ .binary_op = .{ .op = .nil_coal, .left = left, .right = right, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "eval list literal with spread" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const e1 = try allocator.create(typed.TypedExpr);
    e1.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const e2 = try allocator.create(typed.TypedExpr);
    e2.* = .{ .int_literal = .{ .value = 2, .type_ = 0, .span = undefined } };
    const e3 = try allocator.create(typed.TypedExpr);
    e3.* = .{ .int_literal = .{ .value = 3, .type_ = 0, .span = undefined } };

    const inner = try allocator.create(typed.TypedExpr);
    inner.* = .{ .int_literal = .{ .value = 4, .type_ = 0, .span = undefined } };
    const spread_items = try allocator.alloc(typed.ExprItem, 1);
    spread_items[0] = .{ .expr = inner };
    const spread_list = try allocator.create(typed.TypedExpr);
    spread_list.* = .{ .list_literal = .{ .items = spread_items, .type_ = 0, .span = undefined } };

    const items = try allocator.alloc(typed.ExprItem, 4);
    items[0] = .{ .expr = e1 };
    items[1] = .{ .expr = e2 };
    items[2] = .{ .expr = e3 };
    items[3] = .{ .spread = spread_list };

    const expr = typed.TypedExpr{ .list_literal = .{ .items = items, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .list);
    try std.testing.expectEqual(@as(usize, 4), result.list.items.len);
}

test "eval let_in with body expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const val_expr = try allocator.create(typed.TypedExpr);
    val_expr.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const bindings = try allocator.alloc(typed.Binding, 1);
    bindings[0] = .{ .name = "x", .value = val_expr };

    const one = try allocator.create(typed.TypedExpr);
    one.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const x_ref = try allocator.create(typed.TypedExpr);
    x_ref.* = .{ .ident = .{ .name = "x", .type_ = 0, .span = undefined } };
    const body = try allocator.create(typed.TypedExpr);
    body.* = .{ .binary_op = .{ .op = .add, .left = x_ref, .right = one, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .let_in = .{ .bindings = bindings, .body = body, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 2), result.int);
}

test "eval nested let_in" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const y_val = try allocator.create(typed.TypedExpr);
    y_val.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const y_bindings = try allocator.alloc(typed.Binding, 1);
    y_bindings[0] = .{ .name = "y", .value = y_val };

    const y_ref = try allocator.create(typed.TypedExpr);
    y_ref.* = .{ .ident = .{ .name = "y", .type_ = 0, .span = undefined } };
    const one = try allocator.create(typed.TypedExpr);
    one.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const inner_body = try allocator.create(typed.TypedExpr);
    inner_body.* = .{ .binary_op = .{ .op = .add, .left = y_ref, .right = one, .type_ = 0, .span = undefined } };
    const inner_let = try allocator.create(typed.TypedExpr);
    inner_let.* = .{ .let_in = .{ .bindings = y_bindings, .body = inner_body, .type_ = 0, .span = undefined } };

    const x_bindings = try allocator.alloc(typed.Binding, 1);
    x_bindings[0] = .{ .name = "x", .value = inner_let };
    const x_ref = try allocator.create(typed.TypedExpr);
    x_ref.* = .{ .ident = .{ .name = "x", .type_ = 0, .span = undefined } };
    const add_one = try allocator.create(typed.TypedExpr);
    add_one.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const outer_body = try allocator.create(typed.TypedExpr);
    outer_body.* = .{ .binary_op = .{ .op = .add, .left = x_ref, .right = add_one, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .let_in = .{ .bindings = x_bindings, .body = outer_body, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 3), result.int);
}

test "eval nested do_block with defer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const defer_expr = try allocator.create(typed.TypedExpr);
    defer_expr.* = .{ .int_literal = .{ .value = 99, .type_ = 0, .span = undefined } };
    const body_expr = try allocator.create(typed.TypedExpr);
    body_expr.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };

    const inner_stmts = try allocator.alloc(typed.Stmt, 2);
    inner_stmts[0] = .{ .kind = .{ .defer_ = .{ .expr = defer_expr } }, .type_ = 6 };
    inner_stmts[1] = .{ .kind = .{ .expr = body_expr }, .type_ = 0 };

    const inner_do = try allocator.create(typed.TypedExpr);
    inner_do.* = .{ .do_block = .{ .body = inner_stmts, .result = null, .type_ = 6, .span = undefined } };

    const outer_stmts = try allocator.alloc(typed.Stmt, 1);
    outer_stmts[0] = .{ .kind = .{ .expr = inner_do }, .type_ = 6 };

    const expr = typed.TypedExpr{ .do_block = .{ .body = outer_stmts, .result = null, .type_ = 6, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .unit);
}

test "eval do_block defer runs LIFO with bindings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const val_expr = try allocator.create(typed.TypedExpr);
    val_expr.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const first_defer = try allocator.create(typed.TypedExpr);
    first_defer.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const second_defer = try allocator.create(typed.TypedExpr);
    second_defer.* = .{ .int_literal = .{ .value = 2, .type_ = 0, .span = undefined } };

    const stmts = try allocator.alloc(typed.Stmt, 3);
    stmts[0] = .{ .kind = .{ .binding = .{ .name = "x", .value = val_expr } }, .type_ = 0 };
    stmts[1] = .{ .kind = .{ .defer_ = .{ .expr = first_defer } }, .type_ = 6 };
    stmts[2] = .{ .kind = .{ .defer_ = .{ .expr = second_defer } }, .type_ = 6 };

    const expr = typed.TypedExpr{ .do_block = .{ .body = stmts, .result = null, .type_ = 6, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .unit);
}

test "eval pipe expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const body = try allocator.create(typed.TypedExpr);
    body.* = .{ .ident = .{ .name = "x", .type_ = 0, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    const params = [_]typed.Param{.{
        .name = "x",
        .type_ = 0,
    }};
    right.* = typed.TypedExpr{ .lambda = .{ .params = &params, .body = body, .type_ = 0, .span = undefined } };
    try global.bindings.put(allocator, "x", Value{ .int = 1 });

    const expr = typed.TypedExpr{ .pipe = .{ .left = left, .right = right, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 1), result.int);
}

test "eval case tuple pattern with Nil narrowing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const nil_item = try allocator.create(typed.TypedExpr);
    nil_item.* = .{ .ident = .{ .name = "Nil", .type_ = 0, .span = undefined } };
    const int_item = try allocator.create(typed.TypedExpr);
    int_item.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const tuple_items = try allocator.alloc(typed.TypedExpr, 2);
    tuple_items[0] = .{ .ident = .{ .name = "Nil", .type_ = 0, .span = undefined } };
    tuple_items[1] = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };

    const subject = try allocator.create(typed.TypedExpr);
    subject.* = .{ .tuple_literal = .{ .items = tuple_items, .type_ = 0, .span = undefined } };

    const nil_pattern = ast.Pattern{ .ident = .{ .name = "Nil", .span = undefined } };
    const n_pattern = ast.Pattern{ .ident = .{ .name = "n", .span = undefined } };
    const tuple_pattern_items = try allocator.alloc(ast.Pattern, 2);
    tuple_pattern_items[0] = nil_pattern;
    tuple_pattern_items[1] = n_pattern;

    const one = try allocator.create(typed.TypedExpr);
    one.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const n_ref = try allocator.create(typed.TypedExpr);
    n_ref.* = .{ .ident = .{ .name = "n", .type_ = 0, .span = undefined } };
    const branch_body = try allocator.create(typed.TypedExpr);
    branch_body.* = .{ .binary_op = .{ .op = .add, .left = n_ref, .right = one, .type_ = 0, .span = undefined } };

    const branches = try allocator.alloc(typed.Branch, 1);
    branches[0] = .{ .pattern = .{ .tuple = .{ .items = tuple_pattern_items, .span = undefined } }, .body = branch_body, .type_ = 0 };

    const expr = typed.TypedExpr{ .case_expr = .{ .subject = subject, .branches = branches, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 43), result.int);
}

test "eval case True literal match" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const subject = try allocator.create(typed.TypedExpr);
    subject.* = .{ .bool_literal = .{ .value = true, .type_ = 2, .span = undefined } };
    const ok_body = try allocator.create(typed.TypedExpr);
    ok_body.* = .{ .string_literal = .{ .value = "ok", .type_ = 3, .span = undefined } };
    const branches = try allocator.alloc(typed.Branch, 1);
    branches[0] = .{ .pattern = .{ .ident = .{ .name = "True", .span = undefined } }, .body = ok_body, .type_ = 3 };

    const expr = typed.TypedExpr{ .case_expr = .{ .subject = subject, .branches = branches, .type_ = 3, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqualStrings("ok", result.string);
}

test "eval case no match error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const subject = try allocator.create(typed.TypedExpr);
    subject.* = .{ .int_literal = .{ .value = 99, .type_ = 0, .span = undefined } };
    const body = try allocator.create(typed.TypedExpr);
    body.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const branches = try allocator.alloc(typed.Branch, 1);
    branches[0] = .{ .pattern = .{ .ident = .{ .name = "Nil", .span = undefined } }, .body = body, .type_ = 0 };

    const expr = typed.TypedExpr{ .case_expr = .{ .subject = subject, .branches = branches, .type_ = 0, .span = undefined } };
    try std.testing.expectError(error.NoMatch, eval_mod.eval(&expr, global, allocator));
}

test "eval record access on non-record error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const int_val = try allocator.create(typed.TypedExpr);
    int_val.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const expr = typed.TypedExpr{ .record_access = .{ .record = int_val, .field = "x", .type_ = 0, .span = undefined } };
    try std.testing.expectError(error.UnknownField, eval_mod.eval(&expr, global, allocator));
}

test "eval unary not on non-bool error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const operand = try allocator.create(typed.TypedExpr);
    operand.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const expr = typed.TypedExpr{ .unary_op = .{ .op = .not, .operand = operand, .type_ = 2, .span = undefined } };
    try std.testing.expectError(error.TypeMismatch, eval_mod.eval(&expr, global, allocator));
}

test "eval unary neg on non-numeric error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const operand = try allocator.create(typed.TypedExpr);
    operand.* = .{ .bool_literal = .{ .value = true, .type_ = 2, .span = undefined } };
    const expr = typed.TypedExpr{ .unary_op = .{ .op = .neg, .operand = operand, .type_ = 0, .span = undefined } };
    try std.testing.expectError(error.TypeMismatch, eval_mod.eval(&expr, global, allocator));
}

test "eval do_in with result" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const result = try allocator.create(typed.TypedExpr);
    result.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const expr = typed.TypedExpr{ .do_block = .{ .body = &.{}, .result = result, .type_ = 0, .span = undefined } };
    const val = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 42), val.int);
}

test "eval defer with observable side effect" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const val_expr = try allocator.create(typed.TypedExpr);
    val_expr.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const result_expr = try allocator.create(typed.TypedExpr);
    result_expr.* = .{ .ident = .{ .name = "x", .type_ = 0, .span = undefined } };
    const stmts = try allocator.alloc(typed.Stmt, 2);
    stmts[0] = .{ .kind = .{ .binding = .{ .name = "x", .value = val_expr } }, .type_ = 0 };
    stmts[1] = .{ .kind = .{ .expr = result_expr }, .type_ = 0 };

    const expr = typed.TypedExpr{ .do_block = .{ .body = stmts, .result = null, .type_ = 6, .span = undefined } };
    const val = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(val == .unit);
}

test "eval binary add float operands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .float_literal = .{ .value = 1.5, .type_ = 1, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .float_literal = .{ .value = 2.5, .type_ = 1, .span = undefined } };
    const expr = typed.TypedExpr{ .binary_op = .{ .op = .add, .left = left, .right = right, .type_ = 1, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectApproxEqRel(4.0, result.float, 1e-10);
}

test "eval string equality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .string_literal = .{ .value = "abc", .type_ = 3, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .string_literal = .{ .value = "abc", .type_ = 3, .span = undefined } };
    const expr = typed.TypedExpr{ .binary_op = .{ .op = .eq, .left = left, .right = right, .type_ = 2, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(true, result.bool);
}

test "eval record access missing field error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const val = try allocator.create(typed.TypedExpr);
    val.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const fields = try allocator.alloc(typed.RecordField, 1);
    fields[0] = .{ .name = "x", .value = val };
    const rec = try allocator.create(typed.TypedExpr);
    rec.* = .{ .record_literal = .{ .fields = fields, .type_ = 0, .span = undefined } };
    const expr = typed.TypedExpr{ .record_access = .{ .record = rec, .field = "y", .type_ = 0, .span = undefined } };
    try std.testing.expectError(error.UnknownField, eval_mod.eval(&expr, global, allocator));
}

test "eval binary div float" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const left = try allocator.create(typed.TypedExpr);
    left.* = .{ .float_literal = .{ .value = 6.0, .type_ = 1, .span = undefined } };
    const right = try allocator.create(typed.TypedExpr);
    right.* = .{ .float_literal = .{ .value = 2.0, .type_ = 1, .span = undefined } };
    const expr = typed.TypedExpr{ .binary_op = .{ .op = .div, .left = left, .right = right, .type_ = 1, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectApproxEqRel(3.0, result.float, 1e-10);
}

test "eval map literal returns map with content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const key1 = try allocator.create(typed.TypedExpr);
    key1.* = .{ .string_literal = .{ .value = "a", .type_ = 3, .span = undefined } };
    const val1 = try allocator.create(typed.TypedExpr);
    val1.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const key2 = try allocator.create(typed.TypedExpr);
    key2.* = .{ .string_literal = .{ .value = "b", .type_ = 3, .span = undefined } };
    const val2 = try allocator.create(typed.TypedExpr);
    val2.* = .{ .int_literal = .{ .value = 2, .type_ = 0, .span = undefined } };
    const entries = try allocator.alloc(typed.MapEntry, 2);
    entries[0] = .{ .key = key1, .value = val1 };
    entries[1] = .{ .key = key2, .value = val2 };

    const expr = typed.TypedExpr{ .map_literal = .{ .entries = entries, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .map);
    try std.testing.expectEqual(@as(u64, 2), result.map.len);

    const v = hash_map.mapGet(result.map.entries, result.map.len, result.map.cap, Value{ .string = "a" });
    try std.testing.expect(v != null);
    try std.testing.expectEqual(@as(i64, 1), v.?.int);
}

test "eval set literal returns set with content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const e1 = try allocator.create(typed.TypedExpr);
    e1.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const e2 = try allocator.create(typed.TypedExpr);
    e2.* = .{ .int_literal = .{ .value = 2, .type_ = 0, .span = undefined } };
    const items = try allocator.alloc(typed.TypedExpr, 2);
    items[0] = e1.*;
    items[1] = e2.*;

    const expr = typed.TypedExpr{ .set_literal = .{ .items = items, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .set);
    try std.testing.expectEqual(@as(u64, 2), result.set.len);
    try std.testing.expect(hash_map.setContains(result.set.entries, result.set.len, result.set.cap, Value{ .int = 1 }));
    try std.testing.expect(hash_map.setContains(result.set.entries, result.set.len, result.set.cap, Value{ .int = 2 }));
    try std.testing.expect(!hash_map.setContains(result.set.entries, result.set.len, result.set.cap, Value{ .int = 3 }));
}

test "eval Cmd.echo ident returns command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const expr = typed.TypedExpr{ .ident = .{ .name = "Cmd.echo", .type_ = 11, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .command);
}

test "eval Cmd.ls ident returns command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const expr = typed.TypedExpr{ .ident = .{ .name = "Cmd.ls", .type_ = 11, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .command);
}

test "eval record_update existing field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const val_rec = try allocator.create(typed.TypedExpr);
    val_rec.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const fields_rec = try allocator.alloc(typed.RecordField, 1);
    fields_rec[0] = .{ .name = "x", .value = val_rec };
    const rec = try allocator.create(typed.TypedExpr);
    rec.* = .{ .record_literal = .{ .fields = fields_rec, .type_ = 0, .span = undefined } };

    const new_val = try allocator.create(typed.TypedExpr);
    new_val.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const update_fields = try allocator.alloc(typed.RecordField, 1);
    update_fields[0] = .{ .name = "x", .value = new_val };

    const expr = typed.TypedExpr{ .record_update = .{ .record = rec, .fields = update_fields, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .record);
    try std.testing.expectEqual(@as(usize, 1), result.record.fields.len);
    try std.testing.expectEqualStrings("x", result.record.fields[0].name);
    try std.testing.expectEqual(@as(i64, 42), result.record.fields[0].value.int);
}

test "eval record_update add field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const val_rec = try allocator.create(typed.TypedExpr);
    val_rec.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const fields_rec = try allocator.alloc(typed.RecordField, 1);
    fields_rec[0] = .{ .name = "x", .value = val_rec };
    const rec = try allocator.create(typed.TypedExpr);
    rec.* = .{ .record_literal = .{ .fields = fields_rec, .type_ = 0, .span = undefined } };

    const new_val = try allocator.create(typed.TypedExpr);
    new_val.* = .{ .int_literal = .{ .value = 99, .type_ = 0, .span = undefined } };
    const update_fields = try allocator.alloc(typed.RecordField, 1);
    update_fields[0] = .{ .name = "y", .value = new_val };

    const expr = typed.TypedExpr{ .record_update = .{ .record = rec, .fields = update_fields, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .record);
    try std.testing.expectEqual(@as(usize, 2), result.record.fields.len);
}

test "eval record_update non-record base error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const int_rec = try allocator.create(typed.TypedExpr);
    int_rec.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const new_val = try allocator.create(typed.TypedExpr);
    new_val.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const update_fields = try allocator.alloc(typed.RecordField, 1);
    update_fields[0] = .{ .name = "x", .value = new_val };

    const expr = typed.TypedExpr{ .record_update = .{ .record = int_rec, .fields = update_fields, .type_ = 0, .span = undefined } };
    try std.testing.expectError(error.TypeMismatch, eval_mod.eval(&expr, global, allocator));
}

test "eval ternary true branch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const cond = try allocator.create(typed.TypedExpr);
    cond.* = .{ .bool_literal = .{ .value = true, .type_ = 2, .span = undefined } };
    const then_val = try allocator.create(typed.TypedExpr);
    then_val.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const else_val = try allocator.create(typed.TypedExpr);
    else_val.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const expr = typed.TypedExpr{ .ternary = .{ .cond = cond, .then = then_val, .else_ = else_val, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 1), result.int);
}

test "eval ternary false branch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const cond = try allocator.create(typed.TypedExpr);
    cond.* = .{ .bool_literal = .{ .value = false, .type_ = 2, .span = undefined } };
    const then_val = try allocator.create(typed.TypedExpr);
    then_val.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const else_val = try allocator.create(typed.TypedExpr);
    else_val.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const expr = typed.TypedExpr{ .ternary = .{ .cond = cond, .then = then_val, .else_ = else_val, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 0), result.int);
}

test "eval ternary non-bool cond returns error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const cond = try allocator.create(typed.TypedExpr);
    cond.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const then_val = try allocator.create(typed.TypedExpr);
    then_val.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const else_val = try allocator.create(typed.TypedExpr);
    else_val.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const expr = typed.TypedExpr{ .ternary = .{ .cond = cond, .then = then_val, .else_ = else_val, .type_ = 0, .span = undefined } };
    try std.testing.expectError(error.TypeMismatch, eval_mod.eval(&expr, global, allocator));
}

test "eval ident lookup via PrimitiveTable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    const table = primitive_mod.buildPrimitiveTable(tc_env.int_type, tc_env.string_type, tc_env.unit_type, tc_env.string_type, tc_env.bool_type, tc_env.bytes_type);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = @constCast(@ptrCast(&table)) };

    const expr = typed.TypedExpr{ .ident = .{ .name = "IO.println", .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .primitive);
}

test "eval ident lookup PrimitiveTable File.readString" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    const table = primitive_mod.buildPrimitiveTable(tc_env.int_type, tc_env.string_type, tc_env.unit_type, tc_env.string_type, tc_env.bool_type, tc_env.bytes_type);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = @constCast(@ptrCast(&table)) };

    const expr = typed.TypedExpr{ .ident = .{ .name = "File.readString", .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .primitive);
}

test "eval ident lookup PrimitiveTable unbound still error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    const table = primitive_mod.buildPrimitiveTable(tc_env.int_type, tc_env.string_type, tc_env.unit_type, tc_env.string_type, tc_env.bool_type, tc_env.bytes_type);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = @constCast(@ptrCast(&table)) };

    const expr = typed.TypedExpr{ .ident = .{ .name = "Undefined.var", .type_ = 0, .span = undefined } };
    try std.testing.expectError(error.UnboundVariable, eval_mod.eval(&expr, global, allocator));
}

test "eval range_literal with from and to" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const from_expr = try allocator.create(typed.TypedExpr);
    from_expr.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const to_expr = try allocator.create(typed.TypedExpr);
    to_expr.* = .{ .int_literal = .{ .value = 5, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .range_literal = .{ .from = from_expr, .to = to_expr, .step = null, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .stream);
}

test "eval range_literal with step" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const from_expr = try allocator.create(typed.TypedExpr);
    from_expr.* = .{ .int_literal = .{ .value = 0, .type_ = 0, .span = undefined } };
    const to_expr = try allocator.create(typed.TypedExpr);
    to_expr.* = .{ .int_literal = .{ .value = 10, .type_ = 0, .span = undefined } };
    const step_expr = try allocator.create(typed.TypedExpr);
    step_expr.* = .{ .int_literal = .{ .value = 2, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .range_literal = .{ .from = from_expr, .to = to_expr, .step = step_expr, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .stream);
}

test "eval range_literal from equals to" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const from_expr = try allocator.create(typed.TypedExpr);
    from_expr.* = .{ .int_literal = .{ .value = 5, .type_ = 0, .span = undefined } };
    const to_expr = try allocator.create(typed.TypedExpr);
    to_expr.* = .{ .int_literal = .{ .value = 5, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .range_literal = .{ .from = from_expr, .to = to_expr, .step = null, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .stream);
}

test "eval opt_chain on record" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const val = try allocator.create(typed.TypedExpr);
    val.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };
    const fields = try allocator.alloc(typed.RecordField, 1);
    fields[0] = .{ .name = "x", .value = val };
    const rec = try allocator.create(typed.TypedExpr);
    rec.* = .{ .record_literal = .{ .fields = fields, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .opt_chain = .{ .object = rec, .field = "x", .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "eval opt_chain nil returns nil" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const nil_val = try allocator.create(typed.TypedExpr);
    nil_val.* = .{ .ident = .{ .name = "Nil", .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .opt_chain = .{ .object = nil_val, .field = "x", .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .nil);
}

test "eval opt_chain non-record returns nil" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const int_val = try allocator.create(typed.TypedExpr);
    int_val.* = .{ .int_literal = .{ .value = 42, .type_ = 0, .span = undefined } };

    const expr = typed.TypedExpr{ .opt_chain = .{ .object = int_val, .field = "x", .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .nil);
}

test "eval map empty literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const entries = try allocator.alloc(typed.MapEntry, 0);
    const expr = typed.TypedExpr{ .map_literal = .{ .entries = entries, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .map);
    try std.testing.expectEqual(@as(u64, 0), result.map.len);
}

test "eval set empty literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const items = try allocator.alloc(typed.TypedExpr, 0);
    const expr = typed.TypedExpr{ .set_literal = .{ .items = items, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .set);
    try std.testing.expectEqual(@as(u64, 0), result.set.len);
}

test "eval record update add field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null, .primitives = null };

    const val_x = try allocator.create(typed.TypedExpr);
    val_x.* = .{ .int_literal = .{ .value = 1, .type_ = 0, .span = undefined } };
    const fields_rec = try allocator.alloc(typed.RecordField, 1);
    fields_rec[0] = .{ .name = "x", .value = val_x };
    const rec = try allocator.create(typed.TypedExpr);
    rec.* = .{ .record_literal = .{ .fields = fields_rec, .type_ = 0, .span = undefined } };

    const new_y = try allocator.create(typed.TypedExpr);
    new_y.* = .{ .int_literal = .{ .value = 2, .type_ = 0, .span = undefined } };
    const update_fields = try allocator.alloc(typed.RecordField, 2);
    update_fields[0] = .{ .name = "x", .value = val_x };
    update_fields[1] = .{ .name = "y", .value = new_y };

    const expr = typed.TypedExpr{ .record_update = .{ .record = rec, .fields = update_fields, .type_ = 0, .span = undefined } };
    const result = try eval_mod.eval(&expr, global, allocator);
    try std.testing.expect(result == .record);
    try std.testing.expectEqual(@as(usize, 2), result.record.fields.len);
}
