const std = @import("std");
const ast = @import("../ast/ast.zig");
const Token = @import("../lexer/lexer.zig").Token;
const TokenKind = @import("../lexer/lexer.zig").TokenKind;

const Span = ast.Span;
const SourceLoc = ast.SourceLoc;
const Expr = ast.Expr;
pub const Decl = union(enum) {
    import: struct { module: []const u8, alias: ?[]const u8, span: Span },
    export_: struct { bindings: []const ast.Binding, span: Span },
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
            var bindings = std.ArrayListUnmanaged(ast.Binding).empty;
            try state.expect(.lparen);
            while (state.peek() != .rparen and state.peek() != .eof) {
                const name_tok = state.advance();
                try state.expect(.assign);
                const value = try parseExpr(state);
                try bindings.append(state.allocator, .{
                    .name = name_tok.slice,
                    .value = try heapExpr(state, &value),
                    .span = state.span(start),
                });
                if (state.peek() == .comma) {
                    _ = state.advance();
                } else break;
            }
            try state.expect(.rparen);
            return Decl{ .export_ = .{
                .bindings = bindings.items,
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
        .pipe => OpPrecedence{ .op = .{ .pipe = {} }, .prec = 1 },
        .pipe_rev => OpPrecedence{ .op = .{ .pipe_rev = {} }, .prec = 1 },
        .compose => OpPrecedence{ .op = .{ .compose = {} }, .prec = 2 },
        .compose_rev => OpPrecedence{ .op = .{ .compose_rev = {} }, .prec = 2 },
        .or_op => OpPrecedence{ .op = .{ .binary = .or_ }, .prec = 3 },
        .and_op => OpPrecedence{ .op = .{ .binary = .and_ }, .prec = 4 },
        .eq => OpPrecedence{ .op = .{ .binary = .eq }, .prec = 5 },
        .neq => OpPrecedence{ .op = .{ .binary = .neq }, .prec = 5 },
        .lt => OpPrecedence{ .op = .{ .binary = .lt }, .prec = 6 },
        .lte => OpPrecedence{ .op = .{ .binary = .le }, .prec = 6 },
        .gt => OpPrecedence{ .op = .{ .binary = .gt }, .prec = 6 },
        .gte => OpPrecedence{ .op = .{ .binary = .ge }, .prec = 6 },
        .concat => OpPrecedence{ .op = .{ .binary = .concat }, .prec = 7 },
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
    _ = state;
    return expr;
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

fn parsePrefix(state: *ParserState) ParserError!Expr {
    const start = state.current().span.start;
    switch (state.peek()) {
        .int_literal => {
            const tok = state.advance();
            const value = try std.fmt.parseInt(i64, tok.slice, 10);
            return Expr{ .int_literal = .{ .value = value, .span = tok.span } };
        },
        .float_literal => {
            const tok = state.advance();
            const value = try std.fmt.parseFloat(f64, tok.slice);
            return Expr{ .float_literal = .{ .value = value, .span = tok.span } };
        },
        .string_literal => {
            const tok = state.advance();
            const inner = tok.slice[1 .. tok.slice.len - 1];
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
                    ch = switch (inner[1]) {
                        'n' => '\n',
                        't' => '\t',
                        'r' => '\r',
                        '0' => 0,
                        '\'' => '\'',
                        '\\' => '\\',
                        else => @intCast(inner[1]),
                    };
                } else {
                    ch = @intCast(inner[0]);
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
            var value: i64 = 0;
            var unit: ast.DurationUnit = .s;
            const slice = tok.slice;
            var i: usize = 0;
            while (i < slice.len and slice[i] >= '0' and slice[i] <= '9') {
                value = value * 10 + @as(i64, slice[i] - '0');
                i += 1;
            }
            const suffix = slice[i..];
            unit = if (std.mem.eql(u8, suffix, "s")) .s
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

            while (true) {
                switch (state.peek()) {
                    .int_literal, .float_literal, .string_literal, .multiline_string,
                    .path_literal, .regex_literal, .char_literal, .bytes_literal,
                    .kw_true, .kw_false, .kw_nil, .duration_literal,
                    .ident, .type_ident,
                    .lparen, .lbrack, .lbrace, .hash_lparen, .hash_lbrack, .hash_lbrace,
                    .minus, .kw_not, .backslash => {
                        const arg = try parsePrefix(state);
                        const span = Span{ .start = spanOf(&left).start, .end = spanOf(&arg).end };
                        left = Expr{ .call = .{ .func = try heapExpr(state, &left), .arg = try heapExpr(state, &arg), .span = span } };
                    },
                    .dot => {
                        _ = state.advance();
                        const field = state.advance();
                        const span = Span{ .start = spanOf(&left).start, .end = field.span.end };
                        left = Expr{ .record_access = .{ .record = try heapExpr(state, &left), .field = field.slice, .span = span } };
                    },
                    else => break,
                }
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
                if (state.peek() == .pipe_pat) {
                    // Check if it's ".." spread - peek at the next pos slice
                    const tok = state.current();
                    if (tok.slice.len >= 2 and tok.slice[0] == '.' and tok.slice[1] == '.') {
                        _ = state.advance();
                        const rest = try parseExpr(state);
                        try items.append(state.allocator, .{ .spread = try heapExpr(state, &rest) });
                        break;
                    }
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
                if (state.peek() == .pipe_pat) {
                    const tok = state.current();
                    if (tok.slice.len >= 2 and tok.slice[0] == '.' and tok.slice[1] == '.') {
                        _ = state.advance();
                        const r = try parsePattern(state);
                        rest = try heapPattern(state, r);
                        break;
                    }
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

// Override the default span() method to capture the span from Expr value references
// We need an adapter that stores the span alongside
test "parser simple expression" {
    const lexer_mod = @import("../lexer/lexer.zig");
    const source = "42";
    const tokens = try lexer_mod.tokenize(std.testing.allocator, source);
    const decls = try parseModule(std.testing.allocator, tokens);
    try std.testing.expectEqual(@as(usize, 0), decls.len);
}

test "parser addition" {
    const lexer_mod = @import("../lexer/lexer.zig");
    const source = "add 1 2";
    const tokens = try lexer_mod.tokenize(std.testing.allocator, source);
    const decls = try parseModule(std.testing.allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
}

test "parser let in" {
    const lexer_mod = @import("../lexer/lexer.zig");
    const source = "let x = 42 in x";
    const tokens = try lexer_mod.tokenize(std.testing.allocator, source);
    const decls = try parseModule(std.testing.allocator, tokens);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
}
