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
        const end = if (self.pos > 0) self.tokens[self.pos - 1].span.end else self.current().span.end;
        return .{ .start = start, .end = end };
    }
};

const ParserError = error{
    UnexpectedToken,
    ExpectedKeyword,
    OutOfMemory,
    Overflow,
    InvalidCharacter,
    DuplicateVariantName,
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
            var module_name = module_tok.slice;
            while (state.peek() == .dot or state.peek() == .opt_chain) {
                _ = state.advance();
                const next = state.advance();
                const combined = try std.fmt.allocPrint(state.allocator, "{s}.{s}", .{ module_name, next.slice });
                module_name = combined;
            }
            var alias: ?[]const u8 = null;
            if (state.peek() == .kw_as) {
                _ = state.advance();
                const alias_tok = state.advance();
                alias = alias_tok.slice;
            }
            return Decl{ .import = .{
                .module = module_name,
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
                while (state.peek() != .eof and state.peek() != .kw_import and state.peek() != .kw_export and state.peek() != .kw_type and state.peek() != .assign) {
                    if (state.peek() == .pipe_pat) { _ = state.advance(); continue; }
                    const v = state.advance();
                    if (v.kind != .ident and v.kind != .type_ident) return error.UnexpectedToken;
                    try variants.append(state.allocator, v.slice);
                }
                for (variants.items, 0..) |v1, i| {
                    for (variants.items[i + 1 ..]) |v2| {
                        if (std.mem.eql(u8, v1, v2)) return error.DuplicateVariantName;
                    }
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
                // After type annotation, if there's no '=' on the same logical
                // block, this was a standalone type signature. Return a minimal
                // function_def so the next line can be parsed independently.
                if (state.peek() != .assign) {
                    return Decl{ .function_def = .{
                        .name = name_tok.slice,
                        .params = params.items,
                        .return_type = null,
                        .body = try heapExpr(state, &Expr{ .int_literal = .{ .value = 0, .span = name_tok.span } }),
                        .span = state.span(start),
                    } };
                }
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

        // Handle ternary ?: (only at top precedence level)
        if (kind == .question and min_prec == 0) {
            _ = state.advance();
            const then_expr = try parseExpr(state);
            try state.expect(.colon);
            const else_expr = try parseExpr(state);
            const start_span = spanOf(&left).start;
            const end_span = spanOf(&else_expr).end;
            left = Expr{ .ternary = .{ .cond = try heapExpr(state, &left), .then = try heapExpr(state, &then_expr), .else_ = try heapExpr(state, &else_expr), .span = .{ .start = start_span, .end = end_span } } };
            continue;
        }

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

fn parseTypeAnn(state: *ParserState) ParserError!TypeAnn {
    switch (state.peek()) {
        .type_ident => {
            const tok = state.advance();
            return TypeAnn{ .ident = tok.slice };
        },
        .question => {
            _ = state.advance();
            const inner = try state.allocator.create(TypeAnn);
            inner.* = try parseTypeAnn(state);
            return TypeAnn{ .nilable = inner };
        },
        else => {
            // Skip unknown tokens as a fallback (type annotations are optional)
            _ = state.advance();
            return TypeAnn{ .ident = "_" };
        },
    }
}

fn skipTypeAnn(state: *ParserState) ParserError!void {
    // Parse type annotation but discard the result
    // This maintains backward compatibility while we transition to full TypeAnn usage
    _ = parseTypeAnn(state) catch {};




}

fn spanOf(expr: *const Expr) Span {
    return switch (expr.*) {
        .int_literal => |v| v.span,
        .float_literal => |v| v.span,
        .string_literal => |v| v.span,
        .bool_literal => |v| v.span,
        .char_literal => |v| v.span,
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
        .optional_chaining => |v| v.span,
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
            const value = if (std.mem.indexOfScalar(u8, stripped, '_')) |_| blk: {
                var clean = try state.allocator.alloc(u8, stripped.len);
                var i: usize = 0;
                for (stripped) |c| {
                    if (c != '_') {
                        clean[i] = c;
                        i += 1;
                    }
                }
                break :blk try std.fmt.parseInt(i64, clean[0..i], radix);
            } else try std.fmt.parseInt(i64, stripped, radix);
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
            else if (std.mem.eql(u8, suffix, "m")) .min
            else if (std.mem.eql(u8, suffix, "h")) .h
            else if (std.mem.eql(u8, suffix, "d")) .d
            else if (std.mem.eql(u8, suffix, "us")) .us
            else if (std.mem.eql(u8, suffix, "ns")) .ns
            else .s;
            return Expr{ .duration_literal = .{ .value = value, .unit = unit, .span = tok.span } };
        },
        .ident, .type_ident => {
            const tok = state.advance();
            // Nil is handled as a regular ident expression
            if (std.mem.eql(u8, tok.slice, "Nil")) {
                return Expr{ .ident = .{ .name = "Nil", .span = tok.span } };
            }
            var left = Expr{ .ident = .{ .name = tok.slice, .span = tok.span } };

            var args = std.ArrayListUnmanaged(*const Expr).empty;
            while (true) {
                switch (state.peek()) {
                    .int_literal, .float_literal, .string_literal, .multiline_string,
                    .path_literal, .regex_literal, .char_literal, .bytes_literal,
                    .kw_true, .kw_false, .duration_literal,
                    .type_ident,
                    .lparen, .lbrack, .lbrace, .hash_lparen, .hash_lbrack, .hash_lbrace,
                    .minus, .kw_not, .backslash => {
                        const arg = try parsePrefix(state);
                        try args.append(state.allocator, try heapExpr(state, &arg));
                    },
                    .ident => {
                        const next_slice = state.tokens[state.pos].slice;
                        if (std.mem.eql(u8, next_slice, "import") or
                            std.mem.eql(u8, next_slice, "export"))
                            break;
                        const arg = try parsePrefix(state);
                        try args.append(state.allocator, try heapExpr(state, &arg));
                    },
                    .dot, .opt_chain => {
                        if (args.items.len > 0) break;
                        const dot_tok = state.advance();
                        const field = state.advance();
                        const span = Span{ .start = spanOf(&left).start, .end = field.span.end };
                        if (dot_tok.kind == .opt_chain) {
                            left = Expr{ .optional_chaining = .{ .object = try heapExpr(state, &left), .field = field.slice, .span = span } };
                        } else {
                            left = Expr{ .record_access = .{ .record = try heapExpr(state, &left), .field = field.slice, .span = span } };
                        }
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

            // Handle chained record access after call: f a .field or f a ?.field
            while (state.peek() == .dot or state.peek() == .opt_chain) {
                const dot_tok = state.advance();
                const field = state.advance();
                const span = Span{ .start = spanOf(&left).start, .end = field.span.end };
                if (dot_tok.kind == .opt_chain) {
                    left = Expr{ .optional_chaining = .{ .object = try heapExpr(state, &left), .field = field.slice, .span = span } };
                } else {
                    left = Expr{ .record_access = .{ .record = try heapExpr(state, &left), .field = field.slice, .span = span } };
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
            if (state.peek() == .lparen) {
                _ = state.advance();
                while (state.peek() == .ident) {
                    const p = state.advance();
                    try params.append(state.allocator, .{ .name = p.slice, .span = p.span });
                    if (state.peek() == .comma) _ = state.advance();
                }
                try state.expect(.rparen);
                try state.expect(.arrow);
                var body = try parseExpr(state);
                var i: usize = params.items.len;
                while (i > 0) : (i -= 1) {
                    const span = Span{ .start = params.items[i - 1].span.start, .end = spanOf(&body).end };
                    const inner = try heapExpr(state, &body);
                    const heap_params = try state.allocator.alloc(ast.Param, 1);
                    heap_params[0] = params.items[i - 1];
                    body = Expr{ .lambda = .{
                        .params = heap_params,
                        .body = inner,
                        .span = span,
                    } };
                }
                const span = Span{ .start = start, .end = spanOf(&body).end };
                if (params.items.len == 0) {
                    return Expr{ .lambda = .{ .params = &.{}, .body = try heapExpr(state, &body), .span = span } };
                }
                return body;
            }
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
            if (state.peek() == .rparen) return error.UnexpectedToken;
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
            if (state.peek() == .rbrack) {
                _ = state.advance();
                return Expr{ .list_literal = .{ .items = &.{}, .span = Span{ .start = start, .end = state.current().span.end } } };
            }
            const first = try parseExpr(state);
            // Check for range literal: [expr .. expr]
            if (state.peek() == .dot and state.pos + 1 < state.tokens.len and state.tokens[state.pos + 1].kind == .dot) {
                const after_dots = if (state.pos + 2 < state.tokens.len) state.tokens[state.pos + 2].kind else null;
                if (after_dots != null and after_dots != .rbrack and after_dots != .comma) {
                    _ = state.advance(); // .
                    _ = state.advance(); // .
                    const to = try parseExpr(state);
                    const step = if (state.peek() == .dot and state.pos + 1 < state.tokens.len and state.tokens[state.pos + 1].kind == .dot) blk: {
                        _ = state.advance();
                        _ = state.advance();
                        break :blk try heapExpr(state, &(try parseExpr(state)));
                    } else null;
                    try state.expect(.rbrack);
                    return Expr{ .range_literal = .{ .from = try heapExpr(state, &first), .to = try heapExpr(state, &to), .step = step, .span = Span{ .start = start, .end = state.current().span.end } } };
                }
            }
            try items.append(state.allocator, .{ .expr = try heapExpr(state, &first) });
            while (state.peek() != .rbrack and state.peek() != .eof) {
                if (state.peek() == .comma) _ = state.advance();
                if (state.peek() == .dot and state.pos + 1 < state.tokens.len and state.tokens[state.pos + 1].kind == .dot) {
                    _ = state.advance(); // .
                    _ = state.advance(); // .
                    const rest = try parseExpr(state);
                    try items.append(state.allocator, .{ .spread = try heapExpr(state, &rest) });
                    continue;
                }
                const item = try parseExpr(state);
                try items.append(state.allocator, .{ .expr = try heapExpr(state, &item) });
            }
            try state.expect(.rbrack);
            const span = Span{ .start = start, .end = state.current().span.end };
            return Expr{ .list_literal = .{ .items = items.items, .span = span } };
        },
        .lbrace => {
            _ = state.advance();
            if (state.peek() == .rbrace) {
                _ = state.advance();
                return Expr{ .record_literal = .{ .fields = &.{}, .span = Span{ .start = start, .end = state.current().span.end } } };
            }
            // Try parsing as record update: { expr | field = value, ... }
            const first = try parseExpr(state);
            if (state.peek() == .pipe_pat) {
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
                return Expr{ .record_update = .{ .record = try heapExpr(state, &first), .fields = fields.items, .span = span } };
            }
            // Fall through: record literal
            var fields = std.ArrayListUnmanaged(ast.RecordField).empty;
            if (first == .ident and state.peek() == .assign) {
                const name = first.ident.name;
                _ = state.advance(); // =
                const value = try parseExpr(state);
                try fields.append(state.allocator, .{ .name = name, .value = try heapExpr(state, &value) });
                if (state.peek() == .comma) _ = state.advance();
            } else {
                // Expression without = or |: treat as record literal with expr value
                try fields.append(state.allocator, .{ .name = "_", .value = try heapExpr(state, &first) });
            }
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
        .hash_lbrace => {
            _ = state.advance();
            var entries = std.ArrayListUnmanaged(ast.MapEntry).empty;
            while (state.peek() != .rbrace and state.peek() != .eof) {
                const key = try parseExpr(state);
                try state.expect(.assign);
                const value = try parseExpr(state);
                try entries.append(state.allocator, .{ .key = try heapExpr(state, &key), .value = try heapExpr(state, &value) });
                if (state.peek() == .comma) _ = state.advance();
            }
            try state.expect(.rbrace);
            const span = Span{ .start = start, .end = state.current().span.end };
            return Expr{ .map_literal = .{ .entries = entries.items, .span = span } };
        },
        .hash_lbrack => {
            _ = state.advance();
            var items = std.ArrayListUnmanaged(*const Expr).empty;
            while (state.peek() != .rbrack and state.peek() != .eof) {
                const item = try parseExpr(state);
                try items.append(state.allocator, try heapExpr(state, &item));
                if (state.peek() == .comma) _ = state.advance();
            }
            try state.expect(.rbrack);
            const span = Span{ .start = start, .end = state.current().span.end };
            return Expr{ .set_literal = .{ .items = items.items, .span = span } };
        },
        .hash_lparen => {
            _ = state.advance();
            const inner = try parseExpr(state);
            try state.expect(.rparen);
            return inner;
        },
        .bytes_literal => {
            const tok = state.advance();
            return Expr{ .bytes_literal = .{ .value = tok.slice, .span = tok.span } };
        },
        .dot => {
            _ = state.advance();
            const field = state.advance();
            const x_param = ast.Param{ .name = "x", .span = state.span(start) };
            const x_ref = try heapExpr(state, &Expr{ .ident = .{ .name = "x", .span = state.span(start) } });
            const access = Expr{ .record_access = .{ .record = x_ref, .field = field.slice, .span = state.span(start) } };
            const body = try heapExpr(state, &access);
            return Expr{ .lambda = .{ .params = &.{x_param}, .body = body, .span = state.span(start) } };
        },
        else => {
            return error.UnexpectedToken;
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
    while (state.peek() != .kw_in and state.peek() != .eof and state.peek() != .rbrace and state.peek() != .rbrack and state.peek() != .rparen and state.peek() != .assign) {
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
    while (state.peek() != .eof and state.peek() != .kw_import and state.peek() != .kw_export and state.peek() != .kw_type and state.peek() != .assign and state.peek() != .kw_let and state.peek() != .kw_do and state.peek() != .kw_if) {
        const pat = try parsePattern(state);
        var guard: ?*const Expr = null;
        if (state.peek() == .kw_when) {
            _ = state.advance();
            const g = try parseExpr(state);
            guard = try heapExpr(state, &g);
        }
        // Handle or-pattern: pat1 | pat2
        var final_pat = pat;
        while (state.peek() == .pipe_pat) {
            _ = state.advance();
            const right_pat = try parsePattern(state);
            final_pat = ast.Pattern{ .or_ = .{
                .left = try heapPattern(state, final_pat),
                .right = try heapPattern(state, right_pat),
                .span = state.span(start),
            } };
        }
        try state.expect(.arrow);
        const body = try parseExpr(state);
        try branches.append(state.allocator, .{
            .pattern = final_pat,
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
                return ast.Pattern{ .variant = .{ .name = tok.slice, .inner = try heapPattern(state, arg), .span = tok.span } };
            }
            return ast.Pattern{ .variant = .{ .name = tok.slice, .inner = null, .span = tok.span } };
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
        .lbrace => {
            _ = state.advance();
            var fields = std.ArrayListUnmanaged(ast.RecordPatternField).empty;
            while (state.peek() != .rbrace and state.peek() != .eof) {
                const name_tok = state.advance();
                try state.expect(.assign);
                const p = try parsePattern(state);
                try fields.append(state.allocator, .{ .name = name_tok.slice, .pattern = p });
                if (state.peek() == .comma) _ = state.advance();
            }
            try state.expect(.rbrace);
            return ast.Pattern{ .record = fields.items };
        },
        else => return error.UnexpectedToken,
    }
}

// ============ Declarations ============