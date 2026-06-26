const std = @import("std");
const lexer = @import("lexer.zig");
const TokenKind = lexer.TokenKind;
const tokenize = lexer.tokenize;

test "lexer int literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "42 0xFF 0o77 0b1010 1_000_000";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.int_literal, tokens[0].kind);
    try std.testing.expectEqualStrings("42", tokens[0].slice);
    try std.testing.expectEqual(TokenKind.int_literal, tokens[1].kind);
    try std.testing.expectEqualStrings("0xFF", tokens[1].slice);
    try std.testing.expectEqual(TokenKind.int_literal, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.int_literal, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.int_literal, tokens[4].kind);
    try std.testing.expectEqualStrings("1_000_000", tokens[4].slice);
}

test "lexer float literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "3.14 2.5e10 1.0";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.float_literal, tokens[0].kind);
    try std.testing.expectEqualStrings("3.14", tokens[0].slice);
    try std.testing.expectEqual(TokenKind.float_literal, tokens[1].kind);
    try std.testing.expectEqualStrings("2.5e10", tokens[1].slice);
    try std.testing.expectEqual(TokenKind.float_literal, tokens[2].kind);
}

test "lexer bool and nil" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "true false Nil";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.kw_true, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.kw_false, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.type_ident, tokens[2].kind);
}

test "lexer string with escapes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "\"hello\\nworld\" \"tab\\there\"";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.string_literal, tokens[0].kind);
    try std.testing.expectEqualStrings("\"hello\\nworld\"", tokens[0].slice);
    try std.testing.expectEqual(TokenKind.string_literal, tokens[1].kind);
}

test "lexer char literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "'A' '\\n' '好'";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.char_literal, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.char_literal, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.char_literal, tokens[2].kind);
}

test "lexer hex int vs bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "0xFF 0x48656C6C6F48656C6C6F4865";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.int_literal, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.bytes_literal, tokens[1].kind);
    try std.testing.expectEqualStrings("0x48656C6C6F48656C6C6F4865", tokens[1].slice);
}

test "lexer multiline string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "\"\"\"\nhello\nworld\n\"\"\"";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.multiline_string, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.eof, tokens[1].kind);
}

test "lexer single char operators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "= + - * / % < > , . :";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.assign, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.plus, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.minus, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.star, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.slash, tokens[4].kind);
    try std.testing.expectEqual(TokenKind.mod_op, tokens[5].kind);
    try std.testing.expectEqual(TokenKind.lt, tokens[6].kind);
    try std.testing.expectEqual(TokenKind.gt, tokens[7].kind);
    try std.testing.expectEqual(TokenKind.comma, tokens[8].kind);
    try std.testing.expectEqual(TokenKind.dot, tokens[9].kind);
    try std.testing.expectEqual(TokenKind.colon, tokens[10].kind);
}

test "lexer multi-char operators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "|> <| >> << ++ ?. ?? && || == /= <= >= -> | \\";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.pipe, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.pipe_rev, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.compose, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.compose_rev, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.concat, tokens[4].kind);
    try std.testing.expectEqual(TokenKind.opt_chain, tokens[5].kind);
    try std.testing.expectEqual(TokenKind.nil_coal, tokens[6].kind);
    try std.testing.expectEqual(TokenKind.and_op, tokens[7].kind);
    try std.testing.expectEqual(TokenKind.or_op, tokens[8].kind);
    try std.testing.expectEqual(TokenKind.eq, tokens[9].kind);
    try std.testing.expectEqual(TokenKind.neq, tokens[10].kind);
    try std.testing.expectEqual(TokenKind.lte, tokens[11].kind);
    try std.testing.expectEqual(TokenKind.gte, tokens[12].kind);
    try std.testing.expectEqual(TokenKind.arrow, tokens[13].kind);
    try std.testing.expectEqual(TokenKind.pipe_pat, tokens[14].kind);
    try std.testing.expectEqual(TokenKind.backslash, tokens[15].kind);
}

test "lexer all keywords" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "type case of if then else do in let defer import export as when not true false Nil";
    const tokens = try tokenize(allocator, source);
    const expected = [_]TokenKind{
        .kw_type, .kw_case, .kw_of, .kw_if, .kw_then, .kw_else,
        .kw_do, .kw_in, .kw_let, .kw_defer, .kw_import, .kw_export,
        .kw_as, .kw_when, .kw_not, .kw_true, .kw_false,
    };
    for (expected, 0..) |exp_kind, i| {
        try std.testing.expectEqual(exp_kind, tokens[i].kind);
    }
}

test "lexer basic brackets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "( ) [ ] { }";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.lparen, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.rparen, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.lbrack, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.rbrack, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.lbrace, tokens[4].kind);
    try std.testing.expectEqual(TokenKind.rbrace, tokens[5].kind);
}

test "lexer hash brackets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "#( #[ #{";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.hash_lparen, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.hash_lbrack, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.hash_lbrace, tokens[2].kind);
}

test "lexer comment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "42 // this is a comment\n1";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.int_literal, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.int_literal, tokens[1].kind);
}

test "lexer path and f-string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "p\"/tmp\" f\"hello {name}\" r\"[0-9]+\"";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.path_literal, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.f_string_literal, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.regex_literal, tokens[2].kind);
}

test "lexer multiline f-string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "f\"\"\"\nhello {name}\n\"\"\"";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.f_multiline_string, tokens[0].kind);
}

test "lexer duration all units" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "5s 100ms 2h 30m 1d 500us 200ns";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.duration_literal, tokens[0].kind);
    try std.testing.expectEqualStrings("5s", tokens[0].slice);
    try std.testing.expectEqual(TokenKind.duration_literal, tokens[1].kind);
    try std.testing.expectEqualStrings("100ms", tokens[1].slice);
    try std.testing.expectEqual(TokenKind.duration_literal, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.duration_literal, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.duration_literal, tokens[4].kind);
    try std.testing.expectEqual(TokenKind.duration_literal, tokens[5].kind);
    try std.testing.expectEqualStrings("500us", tokens[5].slice);
    try std.testing.expectEqual(TokenKind.duration_literal, tokens[6].kind);
    try std.testing.expectEqualStrings("200ns", tokens[6].slice);
}

test "lexer type ident" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "Int String MyType";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.type_ident, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.type_ident, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.type_ident, tokens[2].kind);
}

test "lexer ident underscores" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "my_var _private __magic";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.ident, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.ident, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.ident, tokens[2].kind);
}

test "lexer expression integration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "add 1 (2 + 3)";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.ident, tokens[0].kind);
    try std.testing.expectEqualStrings("add", tokens[0].slice);
    try std.testing.expectEqual(TokenKind.int_literal, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.lparen, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.int_literal, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.plus, tokens[4].kind);
    try std.testing.expectEqual(TokenKind.int_literal, tokens[5].kind);
    try std.testing.expectEqual(TokenKind.rparen, tokens[6].kind);
}

test "lexer empty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try tokenize(allocator, "");
    try std.testing.expectEqual(@as(usize, 1), tokens.len);
    try std.testing.expectEqual(TokenKind.eof, tokens[0].kind);
}

test "lexer only comment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try tokenize(allocator, "// just a comment");
    try std.testing.expectEqual(@as(usize, 1), tokens.len);
    try std.testing.expectEqual(TokenKind.eof, tokens[0].kind);
}

test "lexer multi-char op precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "|>";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqual(TokenKind.pipe, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.eof, tokens[1].kind);
}

test "lexer minus vs arrow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "- ->";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.minus, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.arrow, tokens[1].kind);
}

test "lexer invalid tokens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try tokenize(allocator, "\"unclosed");
    try std.testing.expectEqual(TokenKind.invalid, tokens[0].kind);
}

test "lexer exclamation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "!";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.exclamation, tokens[0].kind);
}

test "lexer ident with apostrophe" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "map' value'";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.ident, tokens[0].kind);
    try std.testing.expectEqualStrings("map'", tokens[0].slice);
    try std.testing.expectEqual(TokenKind.ident, tokens[1].kind);
    try std.testing.expectEqualStrings("value'", tokens[1].slice);
}

test "lexer negative duration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "-5s";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.minus, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.duration_literal, tokens[1].kind);
}

test "lexer bare question mark" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try tokenize(allocator, "?");
    try std.testing.expectEqual(TokenKind.question, tokens[0].kind);
}

test "lexer hash alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try tokenize(allocator, "#");
    try std.testing.expectEqual(TokenKind.invalid, tokens[0].kind);
}

test "lexer only whitespace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try tokenize(allocator, "   \t\n  ");
    try std.testing.expectEqual(@as(usize, 1), tokens.len);
    try std.testing.expectEqual(TokenKind.eof, tokens[0].kind);
}
