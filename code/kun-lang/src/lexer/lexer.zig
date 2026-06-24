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
    question,    // ?
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

        if (next_ch == '0') {
            if (state.peekN(1)) |n1| {
                if (n1 == 'x' or n1 == 'X') {
                    _ = state.advance(); // 0
                    _ = state.advance(); // x/X
                    try readHexLiteral(&state, start);
                    continue;
                }
                if (n1 == 'o' or n1 == 'O') {
                    _ = state.advance(); // 0
                    _ = state.advance(); // o/O
                    try readOctalLiteral(&state, start);
                    continue;
                }
                if (n1 == 'b' or n1 == 'B') {
                    _ = state.advance(); // 0
                    _ = state.advance(); // b/B
                    try readBinaryLiteral(&state, start);
                    continue;
                }
            }
        }

        if (isDigit(next_ch)) {
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
            '?' => { _ = state.advance(); try state.pushToken(.question, "?", state.span(start)); },
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
                    if (text[text.len - 1] == '_') {
                        try state.pushToken(.invalid, text, state.span(start));
                        return;
                    }
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
    if (text.len > 0 and text[text.len - 1] == '_') {
        try state.pushToken(.invalid, text, state.span(start));
        return;
    }
    if (state.peek()) |ch| {
        switch (ch) {
            's' => {
                _ = state.advance();
                try state.pushToken(.duration_literal, state.source[start.offset..state.pos], state.span(start));
                return;
            },
            'm' => {
                if (state.peekN(1)) |n| {
                    if (n == 's') {
                        _ = state.advance(); // m
                        _ = state.advance(); // s
                        try state.pushToken(.duration_literal, state.source[start.offset..state.pos], state.span(start));
                        return;
                    }
                }
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
    if (hex_count > 16) {
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
        if (ch == '\'') {
            _ = state.advance();
            try state.pushToken(.invalid, state.source[start.offset..state.pos], state.span(start));
            return;
        }
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

