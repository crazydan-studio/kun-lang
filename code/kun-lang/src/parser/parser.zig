const std = @import("std");
const ast = @import("../ast/ast.zig");
const Token = @import("../lexer/lexer.zig").Token;
const TokenKind = @import("../lexer/lexer.zig").TokenKind;

const Span = ast.Span;
const SourceLoc = ast.SourceLoc;
const Expr = ast.Expr;
pub const Decl = union(enum) {
    import: struct { module: []const u8, alias: ?[]const u8, span: Span },
    export_: struct { names: []const []const u8, span: Span },
    type_def: struct { name: []const u8, def: *const TypeDef, span: Span },
    function_def: struct { name: []const u8, params: []const ast.Param, return_type: ?*const TypeAnn, body: *const Expr, span: Span },
};

pub const TypeAnn = union(enum) {
    ident: []const u8,
    list: *const TypeAnn,
    nilable: *const TypeAnn,
    function: struct { args: []const TypeAnn, ret: *const TypeAnn },
    tuple: []const TypeAnn,
    record: []const RecordTypeFieldAnn,
};

pub const RecordTypeFieldAnn = struct {
    name: []const u8,
    type_: TypeAnn,
};

pub const TypeDef = union(enum) {
    alias: struct { fields: []const TypeFieldDef },
    union_: struct { variants: []const []const u8 },
};

pub const TypeFieldDef = struct {
    name: []const u8,
    type_name: []const u8,
};

pub const ExprItem = ast.ExprItem;

const ParserState = struct {
    tokens: []const Token,
    pos: usize,
    allocator: std.mem.Allocator,

    fn current(self: *const ParserState) Token {
        return self.tokens[self.pos];
    }

    fn peek(self: *const ParserState) TokenKind {
        return self.tokens[self.pos].kind;
    }

    fn advance(self: *ParserState) Token {
        const tok = self.tokens[self.pos];
        self.pos += 1;
        return tok;
    }

    fn skip(self: *ParserState, kind: TokenKind) bool {
        if (self.peek() == kind) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    fn expect(self: *ParserState, kind: TokenKind) ParserError!void {
        if (self.peek() != kind) {
            return error.UnexpectedToken;
        }
        _ = self.advance();
    }

    fn expectKeyword(self: *ParserState, kw: TokenKind) ParserError!void {
        if (self.peek() != kw) {
            return error.ExpectedKeyword;
        }
        _ = self.advance();
    }

    fn span(self: *ParserState, start: SourceLoc) Span {
        return .{ .start = start, .end = self.current().span.start };
    }
};

const ParserError = error{
    UnexpectedToken,
    ExpectedKeyword,
    OutOfMemory,
    Overflow,
    InvalidCharacter,
};

pub fn parseModule(allocator: std.mem.Allocator, tokens: []const Token) ParserError![]const Decl {
    var state = ParserState{
        .tokens = tokens,
        .pos = 0,
        .allocator = allocator,
    };

    var decls = std.ArrayListUnmanaged(Decl).empty;

    while (state.peek() != .eof) {
        const decl = try parseDecl(&state);
        try decls.append(allocator, decl);
    }

    return decls.items;
}

fn parseDecl(state: *ParserState) ParserError!Decl {
    const start = state.current().span.start;
    switch (state.peek()) {
        .kw_import => {
            _ = state.advance();
            const module_tok = state.advance();
            var alias: ?[]const u8 = null;
            if (state.peek() == .kw_as) {
                _ = state.advance();
                const alias_tok = state.advance();
                alias = alias_tok.slice;
            }
            return Decl{ .import = .{
                .module = module_tok.slice,
                .alias = alias,
                .span = state.span(start),
            } };
        },
        .kw_export => {
            _ = state.advance();
            var names = std.ArrayListUnmanaged([]const u8).empty;
            try state.expect(.lparen);
            while (state.peek() != .rparen and state.peek() != .eof) {
                const name_tok = state.advance();
                try names.append(state.allocator, name_tok.slice);
                if (state.peek() == .comma) {
                    _ = state.advance();
                } else break;
            }
            try state.expect(.rparen);
            return Decl{ .export_ = .{
                .names = names.items,
                .span = state.span(start),
            } };
        },
        .kw_type => {
            _ = state.advance();
            const name_tok = state.advance();
            try state.expect(.assign);
            if (state.peek() == .lbrace) {
                _ = state.advance();
                var fields = std.ArrayListUnmanaged(TypeFieldDef).empty;
                while (state.peek() != .rbrace and state.peek() != .eof) {
                    const fname = state.advance();
                    try state.expect(.colon);
                    const ftype = state.advance();
                    try fields.append(state.allocator, .{
                        .name = fname.slice,
                        .type_name = ftype.slice,
                    });
                    if (state.peek() == .comma) _ = state.advance();
                }
                try state.expect(.rbrace);
                const def = try state.allocator.create(TypeDef);
                def.* = TypeDef{ .alias = .{ .fields = fields.items } };
                return Decl{ .type_def = .{
                    .name = name_tok.slice,
                    .def = def,
                    .span = state.span(start),
                } };
            } else {
                var variants = std.ArrayListUnmanaged([]const u8).empty;
                while (state.peek() != .eof and state.peek() != .kw_import and state.peek() != .kw_export and state.peek() != .kw_type) {
                    if (state.peek() == .pipe_pat) { _ = state.advance(); continue; }
                    const v = state.advance();
                    try variants.append(state.allocator, v.slice);
                }
                const def = try state.allocator.create(TypeDef);
                def.* = TypeDef{ .union_ = .{ .variants = variants.items } };
                return Decl{ .type_def = .{
                    .name = name_tok.slice,
                    .def = def,
                    .span = state.span(start),
                } };
            }
        },
        else => {
            const name_tok = state.advance();
            var params = std.ArrayListUnmanaged(ast.Param).empty;
            // Skip optional type signature (name : Type)
            if (state.peek() == .colon) {
                _ = state.advance();
                try skipTypeAnn(state);
            }
            if (state.peek() != .arrow and state.peek() != .assign) {
                while (state.peek() == .ident) {
                    const p = state.advance();
                    try params.append(state.allocator, .{ .name = p.slice, .span = p.span });
                }
            }
            try state.expect(.assign);
            const body = try parseExpr(state);
            return Decl{ .function_def = .{
                .name = name_tok.slice,
                .params = params.items,
                .return_type = null,
                .body = try heapExpr(state, &body),
                .span = state.span(start),
            } };
        },
    }
}

fn parseExpr(state: *ParserState) ParserError!Expr {
    return parseBinaryOp(state, 0);
}

const OpPrecedence = struct {
    op: union(enum) {
        binary: ast.BinaryOp,
        pipe: void,
        pipe_rev: void,
        compose: void,
        compose_rev: void,
    },
    prec: u8,
};

fn getPrecedence(kind: TokenKind) ?OpPrecedence {
    return switch (kind) {
        .pipe => OpPrecedence{ .op = .{ .pipe = {} }, .prec = 0 },
        .pipe_rev => OpPrecedence{ .op = .{ .pipe_rev = {} }, .prec = 0 },
        .compose => OpPrecedence{ .op = .{ .compose = {} }, .prec = 3 },
        .compose_rev => OpPrecedence{ .op = .{ .compose_rev = {} }, .prec = 3 },
        .or_op => OpPrecedence{ .op = .{ .binary = .or_ }, .prec = 4 },
        .nil_coal => OpPrecedence{ .op = .{ .binary = .nil_coal }, .prec = 5 },
        .and_op => OpPrecedence{ .op = .{ .binary = .and_ }, .prec = 6 },
        .eq => OpPrecedence{ .op = .{ .binary = .eq }, .prec = 7 },
        .neq => OpPrecedence{ .op = .{ .binary = .neq }, .prec = 7 },
        .lt => OpPrecedence{ .op = .{ .binary = .lt }, .prec = 7 },
        .lte => OpPrecedence{ .op = .{ .binary = .le }, .prec = 7 },
        .gt => OpPrecedence{ .op = .{ .binary = .gt }, .prec = 7 },
        .gte => OpPrecedence{ .op = .{ .binary = .ge }, .prec = 7 },
        .concat => OpPrecedence{ .op = .{ .binary = .concat }, .prec = 8 },
        .plus => OpPrecedence{ .op = .{ .binary = .add }, .prec = 8 },
        .minus => OpPrecedence{ .op = .{ .binary = .sub }, .prec = 8 },
        .star => OpPrecedence{ .op = .{ .binary = .mul }, .prec = 9 },
        .slash => OpPrecedence{ .op = .{ .binary = .div }, .prec = 9 },
        .mod_op => OpPrecedence{ .op = .{ .binary = .mod }, .prec = 9 },
        else => null,
    };
}

fn parseBinaryOp(state: *ParserState, min_prec: u8) ParserError!Expr {
    var left = try parsePrefix(state);

    while (true) {
        const kind = state.peek();
        // Stop at expression terminators
        if (kind == .rbrace or kind == .rbrack or kind == .rparen or kind == .comma or kind == .eof) break;
        
        const prec_info = getPrecedence(kind);
        if (prec_info) |info| {
            if (info.prec < min_prec) break;
            _ = state.advance();

            var right = try parseBinaryOp(state, info.prec + 1);

            const end = state.current().span.end;
            switch (info.op) {
                .pipe => {
                    left = Expr{ .pipe = .{ .left = try heapExpr(state, &left), .right = try heapExpr(state, &right), .span = .{ .start = spanOf(&left).start, .end = end } } };
                },
                .pipe_rev => {
                    left = Expr{ .pipe_reverse = .{ .left = try heapExpr(state, &left), .right = try heapExpr(state, &right), .span = .{ .start = spanOf(&left).start, .end = end } } };
                },
                .compose => {
                    left = Expr{ .compose = .{ .left = try heapExpr(state, &left), .right = try heapExpr(state, &right), .span = .{ .start = spanOf(&left).start, .end = end } } };
                },
                .compose_rev => {
                    left = Expr{ .compose_reverse = .{ .left = try heapExpr(state, &left), .right = try heapExpr(state, &right), .span = .{ .start = spanOf(&left).start, .end = end } } };
                },
                .binary => |op| {
                    left = Expr{ .binary_op = .{ .op = op, .left = try heapExpr(state, &left), .right = try heapExpr(state, &right), .span = .{ .start = spanOf(&left).start, .end = end } } };
                },
            }
        } else {
            break;
        }
    }

    return left;
}

fn heapExpr(state: *ParserState, expr: *const Expr) ParserError!*const Expr {
    const ptr = try state.allocator.create(Expr);
    ptr.* = expr.*;
    return ptr;
}

fn heapPattern(state: *ParserState, pattern: ast.Pattern) ParserError!*const ast.Pattern {
    const ptr = try state.allocator.create(ast.Pattern);
    ptr.* = pattern;
    return ptr;
}

fn skipTypeAnn(state: *ParserState) ParserError!void {
    while (state.peek() != .assign and state.peek() != .eof and state.peek() != .rparen and state.peek() != .rbrace and state.peek() != .rbrack) {
        switch (state.peek()) {
            .ident, .type_ident, .kw_nil, .arrow, .lparen, .rparen, .comma, .dot => {
                _ = state.advance();
            },
            else => break,
        }
    }
}

fn spanOf(expr: *const Expr) Span {
    return switch (expr.*) {
        .int_literal => |v| v.span,
        .float_literal => |v| v.span,
        .string_literal => |v| v.span,
        .bool_literal => |v| v.span,
        .char_literal => |v| v.span,
        .nil_literal => |v| v,
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

fn unescapeString(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, raw, '\\') == null) return raw;

    var result = std.ArrayListUnmanaged(u8).empty;
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        if (raw[i] == '\\') {
            i += 1;
            if (i >= raw.len) break;
            const c: u8 = switch (raw[i]) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '0' => 0,
                '\\' => '\\',
                '"' => '"',
                '\'' => '\'',
                'x' => blk: {
                    if (i + 2 < raw.len) {
                        const hex = raw[i + 1 .. i + 3];
                        const val = std.fmt.parseInt(u8, hex, 16) catch break :blk raw[i];
                        i += 2;
                        break :blk val;
                    }
                    break :blk raw[i];
                },
                'u' => blk: {
                    if (raw.len > i + 1 and raw[i + 1] == '{') {
                        const close = std.mem.indexOfScalarPos(u8, raw, i + 2, '}') orelse break :blk raw[i];
                        const code_str = raw[i + 2 .. close];
                        const cp = std.fmt.parseInt(u21, code_str, 16) catch break :blk raw[i];
                        var buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(cp, &buf) catch break :blk raw[i];
                        try result.appendSlice(allocator, buf[0..len]);
                        i = close;
                        continue;
                    }
                    break :blk raw[i];
                },
                else => raw[i],
            };
            try result.append(allocator, c);
        } else {
            try result.append(allocator, raw[i]);
        }
    }
    return result.items;
}

fn parsePrefix(state: *ParserState) ParserError!Expr {
    const start = state.current().span.start;
    switch (state.peek()) {
        .int_literal => {
            const tok = state.advance();
            const slice = tok.slice;
            const radix: u8 = if (slice.len > 2 and slice[0] == '0') blk: {
                break :blk switch (slice[1]) {
                    'x', 'X' => 16,
                    'o', 'O' => 8,
                    'b', 'B' => 2,
                    else => 10,
                };
            } else 10;
            // Strip 0x/0o/0b prefix for parseInt
            const value_start: usize = if (radix != 10) 2 else 0;
            const stripped = slice[value_start..];
            const value = try std.fmt.parseInt(i64, stripped, radix);
            return Expr{ .int_literal = .{ .value = value, .span = tok.span } };
        },
        .float_literal => {
            const tok = state.advance();
            const value = try std.fmt.parseFloat(f64, tok.slice);
            return Expr{ .float_literal = .{ .value = value, .span = tok.span } };
        },
        .string_literal => {
            const tok = state.advance();
            const inner = try unescapeString(state.allocator, tok.slice[1 .. tok.slice.len - 1]);
            return Expr{ .string_literal = .{ .value = inner, .span = tok.span } };
        },
        .multiline_string => {
            const tok = state.advance();
            const inner = tok.slice[3 .. tok.slice.len - 3];
            return Expr{ .string_literal = .{ .value = inner, .span = tok.span } };
        },
        .path_literal => {
            const tok = state.advance();
            const inner = tok.slice[2 .. tok.slice.len - 1];
            return Expr{ .path_literal = .{ .value = inner, .span = tok.span } };
        },
        .regex_literal => {
            const tok = state.advance();
            const inner = tok.slice[2 .. tok.slice.len - 1];
            return Expr{ .regex_literal = .{ .value = inner, .span = tok.span } };
        },
        .char_literal => {
            const tok = state.advance();
            var ch: u21 = 0;
            if (tok.slice.len >= 3) {
                const inner = tok.slice[1 .. tok.slice.len - 1];
                if (inner[0] == '\\') {
                    const unescaped = try unescapeString(state.allocator, inner);
                    if (unescaped.len > 0) ch = unescaped[0];
                } else {
                    const bytes = std.unicode.utf8ByteSequenceLength(inner[0]) catch 1;
                    ch = std.unicode.utf8Decode(inner[0..bytes]) catch @intCast(inner[0]);
                }
            }
            return Expr{ .char_literal = .{ .value = ch, .span = tok.span } };
        },
        .kw_true => {
            const tok = state.advance();
            return Expr{ .bool_literal = .{ .value = true, .span = tok.span } };
        },
        .kw_false => {
            const tok = state.advance();
            return Expr{ .bool_literal = .{ .value = false, .span = tok.span } };
        },
        .kw_nil => {
            const tok = state.advance();
            return Expr{ .nil_literal = tok.span };
        },
        .kw_not => {
            _ = state.advance();
            const operand = try parsePrefix(state);
            const span = Span{ .start = start, .end = spanOf(&operand).end };
            return Expr{ .unary_op = .{ .op = .not, .operand = try heapExpr(state, &operand), .span = span } };
        },
        .kw_let => {
            _ = state.advance();
            return parseLetIn(state, start);
        },
        .kw_do => {
            _ = state.advance();
            return parseDoBlock(state, start);
        },
        .kw_if => {
            _ = state.advance();
            return parseIfExpr(state, start);
        },
        .kw_case => {
            _ = state.advance();
            return parseCaseExpr(state, start);
        },
        .duration_literal => {
            const tok = state.advance();
            const slice = tok.slice;
            var i: usize = 0;
            while (i < slice.len and slice[i] >= '0' and slice[i] <= '9') {
                i += 1;
            }
            const num_str = slice[0..i];
            const value = try std.fmt.parseInt(i64, num_str, 10);
            const suffix = slice[i..];
            const unit: ast.DurationUnit = if (std.mem.eql(u8, suffix, "s")) .s
            else if (std.mem.eql(u8, suffix, "ms")) .ms
            else if (std.mem.eql(u8, suffix, "min")) .min
            else if (std.mem.eql(u8, suffix, "h")) .h
            else if (std.mem.eql(u8, suffix, "d")) .d
            else if (std.mem.eql(u8, suffix, "us")) .us
            else if (std.mem.eql(u8, suffix, "ns")) .ns
            else .s;
            return Expr{ .duration_literal = .{ .value = value, .unit = unit, .span = tok.span } };
        },
        .ident, .type_ident => {
            const tok = state.advance();
            var left = Expr{ .ident = .{ .name = tok.slice, .span = tok.span } };

            var args = std.ArrayListUnmanaged(*const Expr).empty;
            while (true) {
                switch (state.peek()) {
                    .int_literal, .float_literal, .string_literal, .multiline_string,
                    .path_literal, .regex_literal, .char_literal, .bytes_literal,
                    .kw_true, .kw_false, .kw_nil, .duration_literal,
                    .ident, .type_ident,
                    .lparen, .lbrack, .lbrace, .hash_lparen, .hash_lbrack, .hash_lbrace,
                    .minus, .kw_not, .backslash => {
                        const arg = try parsePrefix(state);
                        try args.append(state.allocator, try heapExpr(state, &arg));
                    },
                    .dot => {
                        if (args.items.len > 0) break;
                        _ = state.advance();
                        const field = state.advance();
                        const span = Span{ .start = spanOf(&left).start, .end = field.span.end };
                        left = Expr{ .record_access = .{ .record = try heapExpr(state, &left), .field = field.slice, .span = span } };
                    },
                    else => break,
                }
            }

            if (args.items.len > 0) {
                const arg: *const Expr = if (args.items.len == 1) args.items[0] else blk: {
                    const tuple_span = Span{
                        .start = spanOf(args.items[0]).start,
                        .end = spanOf(args.items[args.items.len - 1]).end,
                    };
                    break :blk try heapExpr(state, &Expr{ .tuple_literal = .{ .items = args.items, .span = tuple_span } });
                };
                const span = Span{ .start = spanOf(&left).start, .end = spanOf(arg).end };
                left = Expr{ .call = .{ .func = try heapExpr(state, &left), .arg = arg, .span = span } };
            }

            // Handle chained record access after call: f a .field
            while (state.peek() == .dot) {
                _ = state.advance();
                const field = state.advance();
                const span = Span{ .start = spanOf(&left).start, .end = field.span.end };
                left = Expr{ .record_access = .{ .record = try heapExpr(state, &left), .field = field.slice, .span = span } };
            }

            return left;
        },
        .minus => {
            _ = state.advance();
            const operand = try parsePrefix(state);
            const span = Span{ .start = start, .end = spanOf(&operand).end };
            return Expr{ .unary_op = .{ .op = .neg, .operand = try heapExpr(state, &operand), .span = span } };
        },
        .backslash => {
            _ = state.advance();
            var params = std.ArrayListUnmanaged(ast.Param).empty;
            while (state.peek() == .ident) {
                const p = state.advance();
                try params.append(state.allocator, .{ .name = p.slice, .span = p.span });
            }
            try state.expect(.arrow);
            const body = try parseExpr(state);
            const span = Span{ .start = start, .end = spanOf(&body).end };
            return Expr{ .lambda = .{
                .params = params.items,
                .body = try heapExpr(state, &body),
                .span = span,
            } };
        },
        .lparen => {
            _ = state.advance();
            const first = try parseExpr(state);
            if (state.peek() == .comma) {
                var items = std.ArrayListUnmanaged(*const Expr).empty;
                try items.append(state.allocator, try heapExpr(state, &first));
                while (state.peek() == .comma) {
                    _ = state.advance();
                    const item = try parseExpr(state);
                    try items.append(state.allocator, try heapExpr(state, &item));
                }
                try state.expect(.rparen);
                const span = Span{ .start = start, .end = state.current().span.end };
                return Expr{ .tuple_literal = .{ .items = items.items, .span = span } };
            }
            try state.expect(.rparen);
            return first;
        },
        .lbrack => {
            _ = state.advance();
            var items = std.ArrayListUnmanaged(ExprItem).empty;
            while (state.peek() != .rbrack and state.peek() != .eof) {
                if (state.peek() == .dot and state.pos + 1 < state.tokens.len and state.tokens[state.pos + 1].kind == .dot) {
                    _ = state.advance(); // .
                    _ = state.advance(); // .
                    const rest = try parseExpr(state);
                    try items.append(state.allocator, .{ .spread = try heapExpr(state, &rest) });
                    break;
                }
                const item = try parseExpr(state);
                try items.append(state.allocator, .{ .expr = try heapExpr(state, &item) });
                if (state.peek() == .comma) _ = state.advance();
            }
            try state.expect(.rbrack);
            const span = Span{ .start = start, .end = state.current().span.end };
            return Expr{ .list_literal = .{ .items = items.items, .span = span } };
        },
        .lbrace => {
            _ = state.advance();
            var fields = std.ArrayListUnmanaged(ast.RecordField).empty;
            while (state.peek() != .rbrace and state.peek() != .eof) {
                const name_tok = state.advance();
                try state.expect(.assign);
                const value = try parseExpr(state);
                try fields.append(state.allocator, .{ .name = name_tok.slice, .value = try heapExpr(state, &value) });
                if (state.peek() == .comma) _ = state.advance();
            }
            try state.expect(.rbrace);
            const span = Span{ .start = start, .end = state.current().span.end };
            return Expr{ .record_literal = .{ .fields = fields.items, .span = span } };
        },
        .bytes_literal => {
            const tok = state.advance();
            return Expr{ .bytes_literal = .{ .value = tok.slice, .span = tok.span } };
        },
        else => {
            return Expr{ .int_literal = .{ .value = 0, .span = state.current().span } };
        },
    }
}

fn parseLetIn(state: *ParserState, start: SourceLoc) ParserError!Expr {
    var bindings = std.ArrayListUnmanaged(ast.Binding).empty;
    while (state.peek() == .ident) {
        const name_tok = state.advance();
        try state.expect(.assign);
        const value = try parseExpr(state);
        try bindings.append(state.allocator, .{
            .name = name_tok.slice,
            .value = try heapExpr(state, &value),
            .span = state.span(name_tok.span.start),
        });
        if (state.peek() == .comma) _ = state.advance();
    }
    try state.expectKeyword(.kw_in);
    const in_expr = try parseExpr(state);
    const span = Span{ .start = start, .end = spanOf(&in_expr).end };
    return Expr{ .let_in = .{ .bindings = bindings.items, .body = try heapExpr(state, &in_expr), .span = span } };
}

fn parseDoBlock(state: *ParserState, start: SourceLoc) ParserError!Expr {
    var stmts = std.ArrayListUnmanaged(ast.Stmt).empty;
    while (state.peek() != .kw_in and state.peek() != .eof and state.peek() != .rbrace and state.peek() != .rbrack and state.peek() != .rparen) {
        if (state.peek() == .kw_defer) {
            _ = state.advance();
            const expr = try parseExpr(state);
            try stmts.append(state.allocator, .{ .kind = .{ .defer_ = .{ .expr = try heapExpr(state, &expr) } }, .span = spanOf(&expr) });
        } else if (state.peek() == .ident and state.tokens[state.pos + 1].kind == .assign) {
            const name = state.advance();
            _ = state.advance(); // =
            const value = try parseExpr(state);
            try stmts.append(state.allocator, .{ .kind = .{ .binding = .{ .name = name.slice, .value = try heapExpr(state, &value) } }, .span = state.span(start) });
        } else {
            const expr = try parseExpr(state);
            try stmts.append(state.allocator, .{ .kind = .{ .expr = try heapExpr(state, &expr) }, .span = spanOf(&expr) });
        }
    }

    if (state.peek() == .kw_in) {
        _ = state.advance();
        const result = try parseExpr(state);
        const span = Span{ .start = start, .end = spanOf(&result).end };
        return Expr{ .do_block = .{ .body = stmts.items, .result = try heapExpr(state, &result), .span = span } };
    }

    const span = Span{ .start = start, .end = state.current().span.end };
    return Expr{ .do_block = .{ .body = stmts.items, .result = null, .span = span } };
}

fn parseIfExpr(state: *ParserState, start: SourceLoc) ParserError!Expr {
    const cond = try parseExpr(state);
    try state.expectKeyword(.kw_then);
    const then_expr = try parseExpr(state);
    try state.expectKeyword(.kw_else);
    const else_expr = try parseExpr(state);
    const span = Span{ .start = start, .end = spanOf(&else_expr).end };
    return Expr{ .if_expr = .{
        .cond = try heapExpr(state, &cond),
        .then = try heapExpr(state, &then_expr),
        .else_ = try heapExpr(state, &else_expr),
        .span = span,
    } };
}

fn parseCaseExpr(state: *ParserState, start: SourceLoc) ParserError!Expr {
    const subject = try parseExpr(state);
    try state.expectKeyword(.kw_of);
    var branches = std.ArrayListUnmanaged(ast.Branch).empty;
    while (state.peek() != .eof and state.peek() != .kw_import and state.peek() != .kw_export and state.peek() != .kw_type) {
        const pat = try parsePattern(state);
        var guard: ?*const Expr = null;
        if (state.peek() == .kw_when) {
            _ = state.advance();
            const g = try parseExpr(state);
            guard = try heapExpr(state, &g);
        }
        try state.expect(.arrow);
        const body = try parseExpr(state);
        try branches.append(state.allocator, .{
            .pattern = pat,
            .guard = guard,
            .body = try heapExpr(state, &body),
            .is_unbound = false,
            .span = state.span(start),
        });
    }
    const span = Span{ .start = start, .end = state.current().span.end };
    return Expr{ .case_expr = .{ .subject = try heapExpr(state, &subject), .branches = branches.items, .span = span } };
}

fn parsePattern(state: *ParserState) ParserError!ast.Pattern {
    const start = state.current().span.start;
    switch (state.peek()) {
        .kw_nil => {
            const tok = state.advance();
            return ast.Pattern{ .literal = try heapExpr(state, &Expr{ .nil_literal = tok.span }) };
        },
        .kw_true => {
            const tok = state.advance();
            return ast.Pattern{ .literal = try heapExpr(state, &Expr{ .bool_literal = .{ .value = true, .span = tok.span } }) };
        },
        .kw_false => {
            const tok = state.advance();
            return ast.Pattern{ .literal = try heapExpr(state, &Expr{ .bool_literal = .{ .value = false, .span = tok.span } }) };
        },
        .int_literal, .float_literal, .string_literal => {
            const expr = try parsePrefix(state);
            return ast.Pattern{ .literal = try heapExpr(state, &expr) };
        },
        .type_ident => {
            const tok = state.advance();
            if (state.peek() == .lparen) {
                _ = state.advance();
                const arg = try parsePattern(state);
                try state.expect(.rparen);
                return ast.Pattern{ .variant = .{ .name = tok.slice, .arg = try heapPattern(state, arg), .span = tok.span } };
            }
            return ast.Pattern{ .variant = .{ .name = tok.slice, .arg = null, .span = tok.span } };
        },
        .ident => {
            const tok = state.advance();
            return ast.Pattern{ .ident = .{ .name = tok.slice, .span = tok.span } };
        },
        .lbrack => {
            _ = state.advance();
            var items = std.ArrayListUnmanaged(ast.Pattern).empty;
            var rest: ?*const ast.Pattern = null;
            while (state.peek() != .rbrack and state.peek() != .eof) {
                if (state.peek() == .dot and state.pos + 1 < state.tokens.len and state.tokens[state.pos + 1].kind == .dot) {
                    _ = state.advance(); // .
                    _ = state.advance(); // .
                    const r = try parsePattern(state);
                    rest = try heapPattern(state, r);
                    break;
                }
                const p = try parsePattern(state);
                try items.append(state.allocator, p);
                if (state.peek() == .comma) _ = state.advance();
            }
            try state.expect(.rbrack);
            return ast.Pattern{ .list = .{ .items = items.items, .rest = rest, .span = state.span(start) } };
        },
        .lparen => {
            _ = state.advance();
            var items = std.ArrayListUnmanaged(ast.Pattern).empty;
            while (state.peek() != .rparen and state.peek() != .eof) {
                const p = try parsePattern(state);
                try items.append(state.allocator, p);
                if (state.peek() == .comma) _ = state.advance();
            }
            try state.expect(.rparen);
            return ast.Pattern{ .tuple = .{ .items = items.items, .span = state.span(start) } };
        },
        else => return ast.Pattern{ .wildcard = state.advance().span },
    }
}

// Add span method for Expr via spanOf
fn exprSpan(expr: *const Expr) Span {
    return spanOf(expr);
}

// ============ Declarations ============

test "parser import" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "import Cli");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expectEqualStrings("Cli", decls[0].import.module);
    try std.testing.expect(decls[0].import.alias == null);
}

test "parser import with alias" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "import DateTime as DT");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expectEqualStrings("DateTime", decls[0].import.module);
    try std.testing.expectEqualStrings("DT", decls[0].import.alias.?);
}

test "parser type alias" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "type Config = { name: String }");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "type Color = Red | Green | Blue");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "greet name = \"hello\" ++ name");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expectEqualStrings("greet", decls[0].function_def.name);
    try std.testing.expectEqual(@as(usize, 1), decls[0].function_def.params.len);
}

// ============ Expressions ============

test "parser literal expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "x = 42");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const body = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(i64, 42), body.int_literal.value);
}

test "parser let in" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "x = let y = 1 in y");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "f = if true then 1 else 0");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "r = add 1 2");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("add", e.call.func.*.ident.name);
}

test "parser lambda" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "f = \\x -> x");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "xs = [1, 2, 3]");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 3), e.list_literal.items.len);
}

test "parser record literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "r = { name = \"test\" }");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "n = r.name");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "r = x |> f");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "r = a && b || c");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(ast.BinaryOp.or_, e.binary_op.op);
}

test "parser arithmetic ops" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "r = 1 + 2 * 3");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    // * has higher precedence, so it should be: 1 + (2 * 3)
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(ast.BinaryOp.add, e.binary_op.op);
    try std.testing.expectEqual(@as(i64, 2), e.binary_op.right.*.binary_op.left.*.int_literal.value);
    try std.testing.expectEqual(@as(i64, 1), e.binary_op.left.*.int_literal.value);
}

test "parser not expr" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "r = not true");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "r = -42");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "r = (1)");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(i64, 1), e.int_literal.value);
}

test "parser do block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "f = do x = 1");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expect(e.do_block.result == null);
}

test "parser do in" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "f = do x = 1 in x");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expect(e.do_block.result != null);
}

test "parser multiple imports" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "import A\nimport B\nimport C");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "t = (1, \"a\", true)");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "t = 5s");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "p = p\"/tmp\"");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("/tmp", e.path_literal.value);
}

test "parser string literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "s = \"hello\"");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("hello", e.string_literal.value);
}

test "parser nil and bool" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "a = Nil\nb = true\nc = false");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 3), decls.len);
    try std.testing.expectEqual(true, decls[1].function_def.body.*.bool_literal.value);
    try std.testing.expectEqual(false, decls[2].function_def.body.*.bool_literal.value);
}

test "parser comparison chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "r = a == b && c /= d");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    // && has lower precedence than == and /=
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(ast.BinaryOp.and_, e.binary_op.op);
    try std.testing.expectEqual(ast.BinaryOp.eq, e.binary_op.left.*.binary_op.op);
    try std.testing.expectEqual(ast.BinaryOp.neq, e.binary_op.right.*.binary_op.op);
}

test "parser float literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "x = 3.14");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expect(e.float_literal.value > 3.13 and e.float_literal.value < 3.15);
}

test "parser char literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "c = 'A'");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(u21, 'A'), e.char_literal.value);
}

test "parser regex literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "r = r\"[0-9]+\"");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("[0-9]+", e.regex_literal.value);
}

test "parser bytes literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "b = 0x48656C6C6F");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("0x48656C6C6F", e.bytes_literal.value);
}

test "parser pipe reverse" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "r = f <| x");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("f", e.pipe_reverse.left.*.ident.name);
    try std.testing.expectEqualStrings("x", e.pipe_reverse.right.*.ident.name);
}

test "parser compose" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "r = f >> g >> h");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "r = f << g");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("f", e.compose_reverse.left.*.ident.name);
    try std.testing.expectEqualStrings("g", e.compose_reverse.right.*.ident.name);
}

test "parser export declaration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "export (map, filter, fold)");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "s = \"\"\"\nhello\n\"\"\"");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expect(e.string_literal.value.len > 0);
}

test "parser do block body content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "f = do x = 1 in x");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expect(e.do_block.result != null);
    try std.testing.expectEqual(@as(usize, 1), e.do_block.body.len);
}

test "parser concat precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    // "++" same precedence as "+": "a" ++ "b" + "c" → ("a" ++ "b") + "c" (left-assoc)
    const tokens = try lexer_mod.tokenize(allocator, "r = \"a\" ++ \"b\" + \"c\"");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(ast.BinaryOp.add, e.binary_op.op);
    try std.testing.expectEqual(ast.BinaryOp.concat, e.binary_op.left.*.binary_op.op);
}

test "parser case expr" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "f = case x of A -> 1 B -> 2");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 2), e.case_expr.branches.len);
}

test "parser list spread" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "xs = [1, ..rest]");
    const decls = try parseModule(allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqualStrings("rest", e.list_literal.items[1].spread.*.ident.name);
}

test "parser list literal values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "xs = [1, 2, 3]");
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
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "f = case x of n when n > 0 -> n");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 1), e.case_expr.branches.len);
    try std.testing.expect(e.case_expr.branches[0].guard != null);
}

test "parser defer in do block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "f = do defer cleanup ()");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(usize, 1), e.do_block.body.len);
}

test "parser big int literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lexer_mod = @import("../lexer/lexer.zig");
    const tokens = try lexer_mod.tokenize(allocator, "x = 9223372036854775807");
    const decls = try parseModule(allocator, tokens);
    const e = decls[0].function_def.body.*;
    try std.testing.expectEqual(@as(i64, 9223372036854775807), e.int_literal.value);
}
