const std = @import("std");
const ast = @import("../ast/ast.zig");
const lexer = @import("../lexer/lexer.zig");
const parser = @import("parser.zig");

const parseModule = parser.parseModule;

test "parser import" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "import Cli");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expectEqualStrings("Cli", decls[0].import.module);
    try std.testing.expect(decls[0].import.alias == null);
}

test "parser import with alias" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "import DateTime as DT");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expectEqualStrings("DateTime", decls[0].import.module);
    try std.testing.expectEqualStrings("DT", decls[0].import.alias.?);
}

test "parser type alias" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "type Config = { name: String }");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expectEqualStrings("Config", decls[0].type_def.name);
    try std.testing.expectEqual(@as(usize, 1), decls[0].type_def.def.alias.fields.len);
    try std.testing.expectEqualStrings("name", decls[0].type_def.def.alias.fields[0].name);
    try std.testing.expectEqualStrings("String", decls[0].type_def.def.alias.fields[0].type_name);
}

test "parser type union" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "type Color = Red | Green | Blue");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expectEqualStrings("Color", decls[0].type_def.name);
    try std.testing.expectEqual(@as(usize, 3), decls[0].type_def.def.union_.variants.len);
    try std.testing.expectEqualStrings("Red", decls[0].type_def.def.union_.variants[0]);
    try std.testing.expectEqualStrings("Green", decls[0].type_def.def.union_.variants[1]);
    try std.testing.expectEqualStrings("Blue", decls[0].type_def.def.union_.variants[2]);
}

test "parser function def" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "greet name = \"hello\" ++ name");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expectEqualStrings("greet", decls[0].function_def.name);
    try std.testing.expectEqual(@as(usize, 1), decls[0].function_def.params.len);
}

test "parser literal expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "x = 42");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const body = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(i64, 42), body.int_literal.value);
}

test "parser let in" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "x = let y = 1 in y");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 1), e.let_in.bindings.len);
    try std.testing.expectEqualStrings("y", e.let_in.bindings[0].name);
}

test "parser if then else" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = if true then 1 else 0");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(true, e.if_expr.cond.*.bool_literal.value);
    try std.testing.expectEqual(@as(i64, 1), e.if_expr.then.*.int_literal.value);
    try std.testing.expectEqual(@as(i64, 0), e.if_expr.else_.*.int_literal.value);
}

test "parser function call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = add 1 2");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("add", e.call.func.*.ident.name);
}

test "parser lambda" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = \\x -> x");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 1), e.lambda.params.len);
    try std.testing.expectEqualStrings("x", e.lambda.params[0].name);
}

test "parser list literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "xs = [1, 2, 3]");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 3), e.list_literal.items.len);
}

test "parser record literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = { name = \"test\" }");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 1), e.record_literal.fields.len);
    try std.testing.expectEqualStrings("name", e.record_literal.fields[0].name);
}

test "parser record access" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "n = r.name");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("r", e.record_access.record.*.ident.name);
    try std.testing.expectEqualStrings("name", e.record_access.field);
}

test "parser pipe" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = x |> f");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("x", e.pipe.left.*.ident.name);
    try std.testing.expectEqualStrings("f", e.pipe.right.*.ident.name);
}

test "parser boolean ops" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = a && b || c");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(ast.BinaryOp.or_, e.binary_op.op);
}

test "parser arithmetic ops" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = 1 + 2 * 3");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(ast.BinaryOp.add, e.binary_op.op);
    try std.testing.expectEqual(@as(i64, 2), e.binary_op.right.*.binary_op.left.*.int_literal.value);
    try std.testing.expectEqual(@as(i64, 1), e.binary_op.left.*.int_literal.value);
}

test "parser not expr" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = not true");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(ast.UnaryOp.not, e.unary_op.op);
    try std.testing.expectEqual(true, e.unary_op.operand.*.bool_literal.value);
}

test "parser neg expr" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = -42");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(ast.UnaryOp.neg, e.unary_op.op);
    try std.testing.expectEqual(@as(i64, 42), e.unary_op.operand.*.int_literal.value);
}

test "parser parenthesized expr" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = (1)");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(i64, 1), e.int_literal.value);
}

test "parser do block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = do x = 1");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expect(e.do_block.result == null);
}

test "parser do in" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = do x = 1 in x");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expect(e.do_block.result != null);
}

test "parser multiple imports" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "import A\nimport B\nimport C");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 3), decls.len);
    try std.testing.expectEqualStrings("A", decls[0].import.module);
    try std.testing.expectEqualStrings("B", decls[1].import.module);
    try std.testing.expectEqualStrings("C", decls[2].import.module);
}

test "parser tuple literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "t = (1, \"a\", true)");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 3), e.tuple_literal.items.len);
    try std.testing.expectEqual(@as(i64, 1), e.tuple_literal.items[0].*.int_literal.value);
    try std.testing.expectEqual(true, e.tuple_literal.items[2].*.bool_literal.value);
}

test "parser duration literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "t = 5s");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(i64, 5), e.duration_literal.value);
    try std.testing.expectEqual(ast.DurationUnit.s, e.duration_literal.unit);
}

test "parser path literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "p = p\"/tmp\"");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("/tmp", e.path_literal.value);
}

test "parser string literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "s = \"hello\"");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("hello", e.string_literal.value);
}

test "parser nil and bool" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "a = Nil\nb = true\nc = false");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 3), decls.len);
    try std.testing.expectEqual(true, decls[1].function_def.body.*.bool_literal.value);
    try std.testing.expectEqual(false, decls[2].function_def.body.*.bool_literal.value);
}

test "parser comparison chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = a == b && c /= d");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(ast.BinaryOp.and_, e.binary_op.op);
    try std.testing.expectEqual(ast.BinaryOp.eq, e.binary_op.left.*.binary_op.op);
    try std.testing.expectEqual(ast.BinaryOp.neq, e.binary_op.right.*.binary_op.op);
}

test "parser float literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "x = 3.14");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expect(e.float_literal.value > 3.13 and e.float_literal.value < 3.15);
}

test "parser char literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "c = 'A'");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(u21, 'A'), e.char_literal.value);
}

test "parser regex literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = r\"[0-9]+\"");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("[0-9]+", e.regex_literal.value);
}

test "parser bytes literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "b = 0x48656C6C6F48656C6C6F4865");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("0x48656C6C6F48656C6C6F4865", e.bytes_literal.value);
}

test "parser pipe reverse" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = f <| x");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("f", e.pipe_reverse.left.*.ident.name);
    try std.testing.expectEqualStrings("x", e.pipe_reverse.right.*.ident.name);
}

test "parser compose" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = f >> g >> h");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("f", e.compose.left.*.compose.left.*.ident.name);
    try std.testing.expectEqualStrings("g", e.compose.left.*.compose.right.*.ident.name);
    try std.testing.expectEqualStrings("h", e.compose.right.*.ident.name);
}

test "parser compose reverse" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = f << g");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("f", e.compose_reverse.left.*.ident.name);
    try std.testing.expectEqualStrings("g", e.compose_reverse.right.*.ident.name);
}

test "parser export declaration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "export (map, filter, fold)");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expectEqual(@as(usize, 3), decls[0].export_.names.len);
    try std.testing.expectEqualStrings("map", decls[0].export_.names[0]);
    try std.testing.expectEqualStrings("filter", decls[0].export_.names[1]);
    try std.testing.expectEqualStrings("fold", decls[0].export_.names[2]);
}

test "parser multiline string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "s = \"\"\"\nhello\n\"\"\"");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expect(e.string_literal.value.len > 0);
}

test "parser do block body content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = do x = 1 in x");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expect(e.do_block.result != null);
    try std.testing.expectEqual(@as(usize, 1), e.do_block.body.len);
}

test "parser concat precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = \"a\" ++ \"b\" + \"c\"");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(ast.BinaryOp.add, e.binary_op.op);
    try std.testing.expectEqual(ast.BinaryOp.concat, e.binary_op.left.*.binary_op.op);
}

test "parser case expr" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = case x of A -> 1 B -> 2");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 2), e.case_expr.branches.len);
}

test "parser list spread" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "xs = [1, ..rest]");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("rest", e.list_literal.items[1].spread.*.ident.name);
}

test "parser list literal values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "xs = [1, 2, 3]");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 3), e.list_literal.items.len);
    try std.testing.expectEqual(@as(i64, 1), e.list_literal.items[0].expr.*.int_literal.value);
    try std.testing.expectEqual(@as(i64, 2), e.list_literal.items[1].expr.*.int_literal.value);
    try std.testing.expectEqual(@as(i64, 3), e.list_literal.items[2].expr.*.int_literal.value);
}

test "parser when guard" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = case x of n when n > 0 -> n");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 1), e.case_expr.branches.len);
    try std.testing.expect(e.case_expr.branches[0].guard != null);
}

test "parser defer in do block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = do defer cleanup");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 1), e.do_block.body.len);
}

test "parser big int literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "x = 9223372036854775807");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(i64, 9223372036854775807), e.int_literal.value);
}

test "parser map literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "x = #{ \"a\" = 1, \"b\" = 2 }");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 2), e.map_literal.entries.len);
}

test "parser map literal empty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "x = #{}");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 0), e.map_literal.entries.len);
}

test "parser set literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "x = #[1, 2, 3]");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 3), e.set_literal.items.len);
}

test "parser set literal empty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "x = #[]");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 0), e.set_literal.items.len);
}

test "parser let in verifies binding value and body" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "x = let y = 42 in y");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 1), e.let_in.bindings.len);
    try std.testing.expectEqualStrings("y", e.let_in.bindings[0].name);
    try std.testing.expectEqual(@as(i64, 42), e.let_in.bindings[0].value.*.int_literal.value);
}

test "parser error unexpected token" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "x = }");
    const result = parseModule(allocator, tokens);
    try std.testing.expectError(error.UnexpectedToken, result);
}

test "parser error empty decl" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 0), decls.len);
}

test "parser import dotted path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "import Foo.Bar");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expect(decls[0] == .import);
    try std.testing.expectEqualStrings("Foo.Bar", decls[0].import.module);
}

test "parser ternary expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = \\x -> x > 0 ? 1 : 0");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expect(decls[0] == .function_def);
    const body = decls[0].function_def.body.*;
    try std.testing.expect(body == .lambda);
    const inner = body.lambda.body.*;
    try std.testing.expect(inner == .ternary);
    try std.testing.expectEqual(@as(i64, 1), inner.ternary.then.*.int_literal.value);
    try std.testing.expectEqual(@as(i64, 0), inner.ternary.else_.*.int_literal.value);
}

test "parser ternary nested" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = \\x -> x > 0 ? 1 : x < 0 ? -1 : 0");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const inner = decls[0].function_def.body.*.lambda.body.*;
    try std.testing.expect(inner == .ternary);
    try std.testing.expect(inner.ternary.else_.* == .ternary);
}

test "parser range literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = [1..10]");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expect(e == .range_literal);
    try std.testing.expectEqual(@as(i64, 1), e.range_literal.from.*.int_literal.value);
    try std.testing.expectEqual(@as(i64, 10), e.range_literal.to.*.int_literal.value);
}

test "parser range literal with step" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = [0..100..5]");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expect(e == .range_literal);
    try std.testing.expectEqual(@as(i64, 0), e.range_literal.from.*.int_literal.value);
    try std.testing.expectEqual(@as(i64, 100), e.range_literal.to.*.int_literal.value);
    try std.testing.expect(e.range_literal.step != null);
    try std.testing.expectEqual(@as(i64, 5), e.range_literal.step.?.*.int_literal.value);
}

test "parser record update syntax" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = \\r -> { r | x = 1, y = 2 }");
    const decls = try parseModule(allocator, tokens);
    const inner = decls[0].function_def.body.*.lambda.body.*;
    try std.testing.expect(inner == .record_update);
    try std.testing.expectEqualStrings("r", inner.record_update.record.*.ident.name);
    try std.testing.expectEqual(@as(usize, 2), inner.record_update.fields.len);
    try std.testing.expectEqual(@as(i64, 1), inner.record_update.fields[0].value.*.int_literal.value);
    try std.testing.expectEqual(@as(i64, 2), inner.record_update.fields[1].value.*.int_literal.value);
}

test "parser or-pattern in case" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = \\x -> case x of True | False -> 0 _ -> 1");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    const case_expr = e.lambda.body.*;
    try std.testing.expectEqual(@as(usize, 2), case_expr.case_expr.branches.len);
    try std.testing.expect(case_expr.case_expr.branches[0].pattern == .or_);
}

test "parser record pattern in case" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = \\r -> case r of { x = 1 } -> 0 _ -> 1");
    const decls = try parseModule(allocator, tokens);
    const case_expr = decls[0].function_def.body.*.lambda.body.*;
    try std.testing.expectEqual(@as(usize, 2), case_expr.case_expr.branches.len);
    try std.testing.expect(case_expr.case_expr.branches[0].pattern == .record);
}

test "parser lambda destructure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = \\(x, y) -> x + y");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 1), e.lambda.params.len);
    try std.testing.expectEqualStrings("x", e.lambda.params[0].name);
    try std.testing.expect(e.lambda.body.* == .lambda);
    try std.testing.expectEqual(@as(usize, 1), e.lambda.body.*.lambda.params.len);
    try std.testing.expectEqualStrings("y", e.lambda.body.*.lambda.params[0].name);
    try std.testing.expect(e.lambda.body.*.lambda.body.* == .binary_op);
}

test "parser dot shorthand lambda" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = List.map .name names");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expect(e == .call);
}

test "parser import dot paths multiple segments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "import Cli.Options.Parse");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expectEqualStrings("Cli.Options.Parse", decls[0].import.module);
}

test "parser import dot path with alias" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "import Foo.Bar as FB");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqualStrings("Foo.Bar", decls[0].import.module);
    try std.testing.expectEqualStrings("FB", decls[0].import.alias.?);
}

test "parser else if chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = \\x -> if x > 10 then \"big\" else if x > 5 then \"mid\" else \"small\"");
    const decls = try parseModule(allocator, tokens);
    const inner = decls[0].function_def.body.*.lambda.body.*;
    try std.testing.expect(inner == .if_expr);
    try std.testing.expectEqualStrings("big", inner.if_expr.then.*.string_literal.value);
    try std.testing.expect(inner.if_expr.else_.* == .if_expr);
    try std.testing.expectEqualStrings("mid", inner.if_expr.else_.*.if_expr.then.*.string_literal.value);
}

test "parser optional chaining" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = \\x -> x?.name");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    const inner = e.lambda.body.*;
    try std.testing.expect(inner == .optional_chaining);
    try std.testing.expectEqualStrings("x", inner.optional_chaining.object.*.ident.name);
    try std.testing.expectEqualStrings("name", inner.optional_chaining.field);
}

test "parser optional chaining nested" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "f = \\x -> x?.a?.b?.c");
    const decls = try parseModule(allocator, tokens);
    const inner = decls[0].function_def.body.*.lambda.body.*;
    try std.testing.expect(inner == .optional_chaining);
    try std.testing.expectEqualStrings("c", inner.optional_chaining.field);
    try std.testing.expect(inner.optional_chaining.object.* == .optional_chaining);
}

test "parser nil coalesce operator" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try lexer.tokenize(allocator, "r = a ?? b");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(ast.BinaryOp.nil_coal, e.binary_op.op);
}

