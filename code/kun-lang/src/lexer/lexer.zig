const std = @import("std");
const ast = @import("../ast/ast.zig");

const Span = ast.Span;
const SourceLoc = ast.SourceLoc;
const DurationUnit = ast.DurationUnit;

pub const TokenKind = enum {
    // keywords
    kw_type,
    kw_case,
    kw_of,
    kw_if,
    kw_then,
    kw_else,
    kw_do,
    kw_in,
    kw_let,
    kw_defer,
    kw_import,
    kw_export,
    kw_as,
    kw_when,
    kw_not,
    kw_true,
    kw_false,
    kw_nil,
    // identifiers
    ident,
    type_ident,
    // literals
    int_literal,
    float_literal,
    string_literal,
    char_literal,
    duration_literal,
    path_literal,
    regex_literal,
    bytes_literal,
    // operators
    pipe,       // |>
    pipe_rev,   // <|
    compose,    // >>
    compose_rev,// <<
    concat,     // ++
    opt_chain,  // ?.
    nil_coal,   // ??
    and_op,     // &&
    or_op,      // ||
    eq,         // ==
    neq,        // /=
    lte,        // <=
    gte,        // >=
    lt,         // <
    gt,         // >
    plus,       // +
    minus,      // -
    star,       // *
    slash,      // /
    mod_op,     // %
    assign,     // =
    colon,      // :
    dot,        // .
    comma,      // ,
    arrow,      // ->
    pipe_pat,   // |
    backslash,  // \
    // brackets
    lparen,     // (
    rparen,     // )
    lbrack,     // [
    rbrack,     // ]
    lbrace,     // {
    rbrace,     // }
    hash_lparen,// #(
    hash_lbrack,// #[
    hash_lbrace,// #{
    // multiline string
    multiline_string,
    // special
    exclamation, // !
    eof,
    invalid,
};

pub const Token = struct {
    kind: TokenKind,
    slice: []const u8,
    span: Span,
};

const KeywordEntry = struct { text: []const u8, kind: TokenKind };

const keywords = blk: {
    const entries = [_]KeywordEntry{
        .{ .text = "type", .kind = .kw_type },
        .{ .text = "case", .kind = .kw_case },
        .{ .text = "of", .kind = .kw_of },
        .{ .text = "if", .kind = .kw_if },
        .{ .text = "then", .kind = .kw_then },
        .{ .text = "else", .kind = .kw_else },
        .{ .text = "do", .kind = .kw_do },
        .{ .text = "in", .kind = .kw_in },
        .{ .text = "let", .kind = .kw_let },
        .{ .text = "defer", .kind = .kw_defer },
        .{ .text = "import", .kind = .kw_import },
        .{ .text = "export", .kind = .kw_export },
        .{ .text = "as", .kind = .kw_as },
        .{ .text = "when", .kind = .kw_when },
        .{ .text = "not", .kind = .kw_not },
        .{ .text = "true", .kind = .kw_true },
        .{ .text = "false", .kind = .kw_false },
        .{ .text = "Nil", .kind = .kw_nil },
    };
    break :blk entries;
};

const LexerState = struct {
    source: []const u8,
    pos: usize,
    line: u32,
    col: u32,
    tokens: std.ArrayListUnmanaged(Token),
    allocator: std.mem.Allocator,

    fn peek(self: *const LexerState) ?u8 {
        if (self.pos >= self.source.len) return null;
        return self.source[self.pos];
    }

    fn peekN(self: *const LexerState, n: usize) ?u8 {
        if (self.pos + n >= self.source.len) return null;
        return self.source[self.pos + n];
    }

    fn advance(self: *LexerState) u8 {
        const ch = self.source[self.pos];
        self.pos += 1;
        if (ch == '\n') {
            self.line += 1;
            self.col = 1;
        } else {
            self.col += 1;
        }
        return ch;
    }

    fn loc(self: *const LexerState) SourceLoc {
        return .{ .line = self.line, .col = self.col, .offset = self.pos };
    }

    fn span(self: *const LexerState, start: SourceLoc) Span {
        return .{ .start = start, .end = self.loc() };
    }

    fn skipWhitespace(self: *LexerState) void {
        while (self.peek()) |ch| {
            if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
                _ = self.advance();
            } else {
                break;
            }
        }
    }

    fn skipComment(self: *LexerState) void {
        while (self.peek()) |ch| {
            if (ch == '\n') {
                _ = self.advance();
                return;
            }
            _ = self.advance();
        }
    }

    fn pushToken(self: *LexerState, kind: TokenKind, slice: []const u8, tok_span: Span) !void {
        try self.tokens.append(self.allocator, .{
            .kind = kind,
            .slice = slice,
            .span = tok_span,
        });
    }
};

pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) ![]const Token {
    var state = LexerState{
        .source = source,
        .pos = 0,
        .line = 1,
        .col = 1,
        .tokens = .empty,
        .allocator = allocator,
    };

    while (state.peek()) |_| {
        state.skipWhitespace();

        const start = state.loc();
        const next_ch = state.peek() orelse break;

        if (next_ch == '/') {
            if (state.peekN(1)) |n| {
                if (n == '/') {
                    _ = state.advance(); // /
                    _ = state.advance(); // /
                    state.skipComment();
                    continue;
                }
            }
        }

        if (next_ch == '\n' or next_ch == ' ' or next_ch == '\t' or next_ch == '\r') {
            state.skipWhitespace();
            continue;
        }

        if (next_ch == 'f') {
            const n1 = state.peekN(1);
            if (n1 == @as(u8, '"')) {
                const n2 = state.peekN(2);
                const n3 = state.peekN(3);
                if (n2 == @as(u8, '"') and n3 == @as(u8, '"')) {
                    // f""" multiline interpolated string
                    _ = state.advance(); _ = state.advance(); _ = state.advance(); _ = state.advance();
                    try readMultilineString(&state, start, true);
                    continue;
                }
                // f" interpolated string
                _ = state.advance(); _ = state.advance();
                try readString(&state, start, true);
                continue;
            }
        }

        if (next_ch == '"') {
            const n1 = state.peekN(1);
            const n2 = state.peekN(2);
            if (n1 == @as(u8, '"') and n2 == @as(u8, '"')) {
                // """ multiline string
                _ = state.advance(); _ = state.advance(); _ = state.advance();
                try readMultilineString(&state, start, false);
                continue;
            }
            // Regular string
            _ = state.advance();
            try readString(&state, start, false);
            continue;
        }

        if (next_ch == 'p') {
            if (state.peekN(1)) |n| {
                if (n == '"') {
                    _ = state.advance(); // p
                    _ = state.advance(); // "
                    try readRawString(&state, start, .path_literal);
                    continue;
                }
            }
        }

        if (next_ch == 'r') {
            if (state.peekN(1)) |n| {
                if (n == '"') {
                    _ = state.advance(); // r
                    _ = state.advance(); // "
                    try readRawString(&state, start, .regex_literal);
                    continue;
                }
            }
        }

        if (isAsciiAlpha(next_ch) or next_ch == '_') {
            try readIdentifier(&state, start);
            continue;
        }

        if (isDigit(next_ch) or (next_ch == '0' and (state.peekN(1) == @as(u8, 'x') or state.peekN(1) == @as(u8, 'o') or state.peekN(1) == @as(u8, 'b')))) {
            if (next_ch == '0') {
                const n1 = state.peekN(1);
                if (n1 == @as(u8, 'x')) {
                    // Hex or bytes
                    _ = state.advance(); // 0
                    _ = state.advance(); // x
                    try readHexLiteral(&state, start);
                    continue;
                }
                if (n1 == @as(u8, 'o')) {
                    // Octal
                    _ = state.advance(); // 0
                    _ = state.advance(); // o
                    try readOctalLiteral(&state, start);
                    continue;
                }
                if (n1 == @as(u8, 'b')) {
                    // Binary
                    _ = state.advance(); // 0
                    _ = state.advance(); // b
                    try readBinaryLiteral(&state, start);
                    continue;
                }
            }
            try readNumber(&state, start);
            continue;
        }

        if (next_ch == '\'') {
            _ = state.advance(); // '
            try readChar(&state, start);
            continue;
        }

        // Multi-char operators
        if (try tryReadMultiCharOp(&state, start)) continue;

        // Single char operators and brackets
        switch (next_ch) {
            '(' => { _ = state.advance(); try state.pushToken(.lparen, "(", state.span(start)); },
            ')' => { _ = state.advance(); try state.pushToken(.rparen, ")", state.span(start)); },
            '[' => { _ = state.advance(); try state.pushToken(.lbrack, "[", state.span(start)); },
            ']' => { _ = state.advance(); try state.pushToken(.rbrack, "]", state.span(start)); },
            '{' => { _ = state.advance(); try state.pushToken(.lbrace, "{", state.span(start)); },
            '}' => { _ = state.advance(); try state.pushToken(.rbrace, "}", state.span(start)); },
            '#' => {
                _ = state.advance();
                const n = state.peek() orelse {
                    try state.pushToken(.invalid, "#", state.span(start));
                    continue;
                };
                switch (n) {
                    '(' => { _ = state.advance(); try state.pushToken(.hash_lparen, "#(", state.span(start)); },
                    '[' => { _ = state.advance(); try state.pushToken(.hash_lbrack, "#[", state.span(start)); },
                    '{' => { _ = state.advance(); try state.pushToken(.hash_lbrace, "#{", state.span(start)); },
                    else => try state.pushToken(.invalid, "#", state.span(start)),
                }
            },
            '|' => { _ = state.advance(); try state.pushToken(.pipe_pat, "|", state.span(start)); },
            '\\' => { _ = state.advance(); try state.pushToken(.backslash, "\\", state.span(start)); },
            '=' => { _ = state.advance(); try state.pushToken(.assign, "=", state.span(start)); },
            '+' => { _ = state.advance(); try state.pushToken(.plus, "+", state.span(start)); },
            '-' => { _ = state.advance(); try state.pushToken(.minus, "-", state.span(start)); },
            '*' => { _ = state.advance(); try state.pushToken(.star, "*", state.span(start)); },
            '/' => { _ = state.advance(); try state.pushToken(.slash, "/", state.span(start)); },
            '%' => { _ = state.advance(); try state.pushToken(.mod_op, "%", state.span(start)); },
            '<' => { _ = state.advance(); try state.pushToken(.lt, "<", state.span(start)); },
            '>' => { _ = state.advance(); try state.pushToken(.gt, ">", state.span(start)); },
            ',' => { _ = state.advance(); try state.pushToken(.comma, ",", state.span(start)); },
            '.' => { _ = state.advance(); try state.pushToken(.dot, ".", state.span(start)); },
            ':' => { _ = state.advance(); try state.pushToken(.colon, ":", state.span(start)); },
            '!' => { _ = state.advance(); try state.pushToken(.exclamation, "!", state.span(start)); },
            else => {
                // Duration literal: number + unit suffix
                if (isDigit(next_ch)) {
                    try readNumber(&state, start);
                    continue;
                }
                _ = state.advance();
                try state.pushToken(.invalid, source[start.offset..state.pos], state.span(start));
            },
        }
    }

    state.skipWhitespace();
    try state.pushToken(.eof, "", .{
        .start = state.loc(),
        .end = state.loc(),
    });

    return state.tokens.items;
}

fn isAsciiAlpha(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z');
}

fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

fn readIdentifier(state: *LexerState, start: ast.SourceLoc) !void {
    while (state.peek()) |ch| {
        if (isAsciiAlpha(ch) or isDigit(ch) or ch == '_' or ch == '\'') {
            _ = state.advance();
        } else {
            break;
        }
    }
    const text = state.source[start.offset..state.pos];
    const is_type = text.len > 0 and text[0] >= 'A' and text[0] <= 'Z';

    for (keywords) |kw| {
        if (std.mem.eql(u8, text, kw.text)) {
            try state.pushToken(kw.kind, text, state.span(start));
            return;
        }
    }

    const kind: TokenKind = if (is_type) .type_ident else .ident;
    try state.pushToken(kind, text, state.span(start));
}

fn readNumber(state: *LexerState, start: ast.SourceLoc) !void {
    while (state.peek()) |ch| {
        if (isDigit(ch) or ch == '_') {
            _ = state.advance();
        } else if (ch == '.') {
            // Check if it's a float (next char is digit)
            if (state.peekN(1)) |n| {
                if (isDigit(n)) {
                    _ = state.advance(); // .
                    while (state.peek()) |ch2| {
                        if (isDigit(ch2) or ch2 == '_') {
                            _ = state.advance();
                        } else break;
                    }
                    // Check for exponent
                    if (state.peek()) |e| {
                        if (e == 'e' or e == 'E') {
                            _ = state.advance();
                            if (state.peek()) |sign| {
                                if (sign == '+' or sign == '-') _ = state.advance();
                            }
                            while (state.peek()) |ch2| {
                                if (isDigit(ch2)) {
                                    _ = state.advance();
                                } else break;
                            }
                        }
                    }
                    const text = state.source[start.offset..state.pos];
                    try state.pushToken(.float_literal, text, state.span(start));
                    return;
                }
            }
            break;
        } else {
            break;
        }
    }

    // Check for duration suffix
    const text = state.source[start.offset..state.pos];
    if (state.peek()) |ch| {
        switch (ch) {
            's' => {
                _ = state.advance();
                try state.pushToken(.duration_literal, state.source[start.offset..state.pos], state.span(start));
                return;
            },
            'm' => {
                // Check for ms or min
                if (state.peekN(1)) |n| {
                    if (n == 's') {
                        _ = state.advance(); // m
                        _ = state.advance(); // s
                        try state.pushToken(.duration_literal, state.source[start.offset..state.pos], state.span(start));
                        return;
                    }
                    if (n == 'i') {
                        if (state.peekN(2)) |n2| {
                            if (n2 == 'n') {
                                _ = state.advance(); // m
                                _ = state.advance(); // i
                                _ = state.advance(); // n
                                try state.pushToken(.duration_literal, state.source[start.offset..state.pos], state.span(start));
                                return;
                            }
                        }
                    }
                }
                // single m = minute
                _ = state.advance();
                try state.pushToken(.duration_literal, state.source[start.offset..state.pos], state.span(start));
                return;
            },
            'h' => {
                _ = state.advance();
                try state.pushToken(.duration_literal, state.source[start.offset..state.pos], state.span(start));
                return;
            },
            'd' => {
                _ = state.advance();
                try state.pushToken(.duration_literal, state.source[start.offset..state.pos], state.span(start));
                return;
            },
            'u' => {
                _ = state.advance();
                if (state.peek()) |n| {
                    if (n == 's') _ = state.advance();
                }
                try state.pushToken(.duration_literal, state.source[start.offset..state.pos], state.span(start));
                return;
            },
            'n' => {
                _ = state.advance();
                if (state.peek()) |n| {
                    if (n == 's') _ = state.advance();
                }
                try state.pushToken(.duration_literal, state.source[start.offset..state.pos], state.span(start));
                return;
            },
            else => {
                try state.pushToken(.int_literal, text, state.span(start));
                return;
            },
        }
    }

    try state.pushToken(.int_literal, text, state.span(start));
}

fn readHexLiteral(state: *LexerState, start: ast.SourceLoc) !void {
    // Could be bytes literal (0xABCDEF) or hex int (0xFF)
    var hex_count: usize = 0;
    while (state.peek()) |ch| {
        if (isHexDigit(ch)) {
            _ = state.advance();
            hex_count += 1;
        } else if (ch == '_') {
            _ = state.advance();
        } else {
            break;
        }
    }
    const text = state.source[start.offset..state.pos];
    if (hex_count > 2) {
        // Bytes literal: pairs of hex digits
        try state.pushToken(.bytes_literal, text, state.span(start));
    } else {
        try state.pushToken(.int_literal, text, state.span(start));
    }
}

fn readOctalLiteral(state: *LexerState, start: ast.SourceLoc) !void {
    while (state.peek()) |ch| {
        if (ch >= '0' and ch <= '7') {
            _ = state.advance();
        } else if (ch == '_') {
            _ = state.advance();
        } else {
            break;
        }
    }
    const text = state.source[start.offset..state.pos];
    try state.pushToken(.int_literal, text, state.span(start));
}

fn readBinaryLiteral(state: *LexerState, start: ast.SourceLoc) !void {
    while (state.peek()) |ch| {
        if (ch == '0' or ch == '1') {
            _ = state.advance();
        } else if (ch == '_') {
            _ = state.advance();
        } else {
            break;
        }
    }
    const text = state.source[start.offset..state.pos];
    try state.pushToken(.int_literal, text, state.span(start));
}

fn isHexDigit(ch: u8) bool {
    return isDigit(ch) or (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F');
}

fn readString(state: *LexerState, start: ast.SourceLoc, is_f_string: bool) !void {
    _ = is_f_string;
    while (state.peek()) |ch| {
        if (ch == '\\') {
            _ = state.advance(); // backslash
            if (state.peek()) |_| _ = state.advance(); // escaped char
        } else if (ch == '"') {
            _ = state.advance(); // closing "
            const text = state.source[start.offset..state.pos];
            try state.pushToken(.string_literal, text, state.span(start));
            return;
        } else {
            _ = state.advance();
        }
    }
    // Unterminated string
    try state.pushToken(.invalid, state.source[start.offset..state.pos], state.span(start));
}

fn readRawString(state: *LexerState, start: ast.SourceLoc, kind: TokenKind) !void {
    while (state.peek()) |ch| {
        if (ch == '\\') {
            _ = state.advance();
            if (state.peek()) |n| {
                if (n == '"') _ = state.advance();
            }
        } else if (ch == '"') {
            _ = state.advance();
            const text = state.source[start.offset..state.pos];
            try state.pushToken(kind, text, state.span(start));
            return;
        } else {
            _ = state.advance();
        }
    }
    try state.pushToken(.invalid, state.source[start.offset..state.pos], state.span(start));
}

fn readMultilineString(state: *LexerState, start: ast.SourceLoc, is_f_string: bool) !void {
    _ = is_f_string;
    // Skip newline after opening """
    if (state.peek()) |ch| {
        if (ch == '\n') _ = state.advance();
    }

    while (state.peek()) |ch| {
        if (ch == '"') {
            if (state.peekN(1) == @as(u8, '"') and state.peekN(2) == @as(u8, '"')) {
                _ = state.advance(); // "
                _ = state.advance(); // "
                _ = state.advance(); // "
                const text = state.source[start.offset..state.pos];
                try state.pushToken(.multiline_string, text, state.span(start));
                return;
            }
        }
        _ = state.advance();
    }
    try state.pushToken(.invalid, state.source[start.offset..state.pos], state.span(start));
}

fn utf8ByteLen(lead: u8) usize {
    if (lead < 0x80) return 1;
    if (lead < 0xE0) return 2;
    if (lead < 0xF0) return 3;
    return 4;
}

fn readChar(state: *LexerState, start: ast.SourceLoc) !void {
    if (state.peek()) |ch| {
        if (ch == '\\') {
            _ = state.advance(); // backslash
            if (state.peek()) |_| _ = state.advance(); // escaped char
        } else {
            const len = utf8ByteLen(ch);
            var i: usize = 0;
            while (i < len) : (i += 1) {
                if (state.peek()) |_| _ = state.advance() else break;
            }
        }
    }
    if (state.peek()) |ch| {
        if (ch == '\'') {
            _ = state.advance();
            const text = state.source[start.offset..state.pos];
            try state.pushToken(.char_literal, text, state.span(start));
            return;
        }
    }
    try state.pushToken(.invalid, state.source[start.offset..state.pos], state.span(start));
}

fn tryReadMultiCharOp(state: *LexerState, start: ast.SourceLoc) !bool {
    const ch1 = state.peek() orelse return false;
    const ch2 = state.peekN(1);

    const ops = [_]struct { pattern: []const u8, kind: TokenKind }{
        .{ .pattern = "|>", .kind = .pipe },
        .{ .pattern = "<|", .kind = .pipe_rev },
        .{ .pattern = ">>", .kind = .compose },
        .{ .pattern = "<<", .kind = .compose_rev },
        .{ .pattern = "++", .kind = .concat },
        .{ .pattern = "?.", .kind = .opt_chain },
        .{ .pattern = "??", .kind = .nil_coal },
        .{ .pattern = "&&", .kind = .and_op },
        .{ .pattern = "||", .kind = .or_op },
        .{ .pattern = "==", .kind = .eq },
        .{ .pattern = "/=", .kind = .neq },
        .{ .pattern = "<=", .kind = .lte },
        .{ .pattern = ">=", .kind = .gte },
        .{ .pattern = "->", .kind = .arrow },
    };

    for (ops) |op| {
        if (ch2) |c2| {
            if (op.pattern.len == 2 and ch1 == op.pattern[0] and c2 == op.pattern[1]) {
                _ = state.advance();
                _ = state.advance();
                try state.pushToken(op.kind, op.pattern, state.span(start));
                return true;
            }
        }
        if (op.pattern.len == 1 and ch1 == op.pattern[0]) {
            _ = state.advance();
            try state.pushToken(op.kind, op.pattern, state.span(start));
            return true;
        }
    }
    return false;
}

// ============ Basic tokens ============

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
    try std.testing.expectEqual(TokenKind.kw_nil, tokens[2].kind);
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
    // 0xFF has 2 hex digits -> int; 0x48656C6C6F has 10 hex digits -> bytes
    const source = "0xFF 0x48656C6C6F";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.int_literal, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.bytes_literal, tokens[1].kind);
    try std.testing.expectEqualStrings("0x48656C6C6F", tokens[1].slice);
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

// ============ Multi-char operators ============

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

// ============ Keywords ============

test "lexer all keywords" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "type case of if then else do in let defer import export as when not true false Nil";
    const tokens = try tokenize(allocator, source);
    const expected = [_]TokenKind{
        .kw_type, .kw_case, .kw_of, .kw_if, .kw_then, .kw_else,
        .kw_do, .kw_in, .kw_let, .kw_defer, .kw_import, .kw_export,
        .kw_as, .kw_when, .kw_not, .kw_true, .kw_false, .kw_nil,
    };
    for (expected, 0..) |exp_kind, i| {
        try std.testing.expectEqual(exp_kind, tokens[i].kind);
    }
}

// ============ Brackets ============

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

// ============ Comments ============

test "lexer comment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "42 // this is a comment\n1";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.int_literal, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.int_literal, tokens[1].kind);
}

// ============ Prefix strings ============

test "lexer path and f-string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "p\"/tmp\" f\"hello {name}\" r\"[0-9]+\"";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.path_literal, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.string_literal, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.regex_literal, tokens[2].kind);
}

test "lexer multiline f-string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "f\"\"\"\nhello {name}\n\"\"\"";
    const tokens = try tokenize(allocator, source);
    try std.testing.expectEqual(TokenKind.multiline_string, tokens[0].kind);
}

// ============ Duration ============

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

// ============ Identifiers ============

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

// ============ Integration ============

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
    // |> should be one token, not pipe then gt
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
    // Unterminated string
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
