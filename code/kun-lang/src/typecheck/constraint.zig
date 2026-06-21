const std = @import("std");
const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");
const parser = @import("../parser/parser.zig");
const env_mod = @import("env.zig");
const unify_mod = @import("unify.zig");
const error_mod = @import("error.zig");

const Type = typed.Type;
const TypeId = typed.TypeId;
const TypeEnv = env_mod.TypeEnv;
const TypedExpr = typed.TypedExpr;
const TypedDecl = typed.TypedDecl;
const Param = typed.Param;
const Binding = typed.Binding;
const Stmt = typed.Stmt;
const Branch = typed.Branch;
const ExprItem = typed.ExprItem;
const RecordField = typed.RecordField;
const MapEntry = typed.MapEntry;
const ErrorList = error_mod.ErrorList;
const TypeError = error_mod.TypeError;

const int_type = env_mod.int_type;
const float_type = env_mod.float_type;
const bool_type = env_mod.bool_type;
const string_type = env_mod.string_type;
const char_type = env_mod.char_type;
const bytes_type = env_mod.bytes_type;
const unit_type = env_mod.unit_type;
const path_type = env_mod.path_type;
const duration_type = env_mod.duration_type;
const regex_type = env_mod.regex_type;

const InferenceError = error{
    OutOfMemory,
    TypeCheckFailed,
    Unimplemented,
};

pub fn inferModule(
    allocator: std.mem.Allocator,
    decls: []const parser.Decl,
    env: *TypeEnv,
    errors: *ErrorList,
) InferenceError![]const TypedDecl {
    const ea = env.exprAllocator();
    var typed_decls: std.ArrayListUnmanaged(TypedDecl) = .empty;
    errdefer typed_decls.deinit(ea);

    for (decls) |decl| {
        const typed_decl = try inferDecl(allocator, decl, env, errors);
        try typed_decls.append(ea, typed_decl);
    }

    if (errors.hasErrors()) return error.TypeCheckFailed;
    return try typed_decls.toOwnedSlice(ea);
}

fn inferDecl(
    allocator: std.mem.Allocator,
    decl: parser.Decl,
    env: *TypeEnv,
    errors: *ErrorList,
) InferenceError!TypedDecl {
    return switch (decl) {
        .function_def => |f| {
            return try inferFunction(allocator, f.name, f.params, f.body, f.span, env, errors);
        },
        .import => |i| TypedDecl{
            .kind = .{ .import = .{ .module = i.module, .alias = i.alias } },
            .span = i.span,
        },
        .export_ => |e| TypedDecl{
            .kind = .{ .export_ = .{ .names = e.names } },
            .span = e.span,
        },
        .type_def => |t| TypedDecl{
            .kind = .{ .type_def = .{ .name = t.name, .type_ = 0 } },
            .span = t.span,
        },
    };
}

fn inferFunction(
    allocator: std.mem.Allocator,
    name: []const u8,
    params: []const ast.Param,
    body: *const ast.Expr,
    span: ast.Span,
    env: *TypeEnv,
    errors: *ErrorList,
) InferenceError!TypedDecl {
    const ea = env.exprAllocator();
    const typed_body = try inferExpr(allocator, body, env, errors);

    var param_types: std.ArrayListUnmanaged(Param) = .empty;
    defer param_types.deinit(ea);
    for (params) |p| {
        const pty = try env.newVar(allocator, 1);
        try param_types.append(ea, Param{ .name = p.name, .type_ = pty });
    }

    const has_effect = hasEffect(body);

    return TypedDecl{
        .kind = .{ .function_def = .{
            .name = name,
            .params = try param_types.toOwnedSlice(ea),
            .body = typed_body,
            .type_ = exprType(typed_body),
            .is_effect = has_effect,
        } },
        .span = span,
    };
}

pub fn inferExpr(
    allocator: std.mem.Allocator,
    expr: *const ast.Expr,
    env: *TypeEnv,
    errors: *ErrorList,
) InferenceError!*const TypedExpr {
    const ea = env.exprAllocator();
    return switch (expr.*) {
        .int_literal => |v| {
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .int_literal = .{ .value = v.value, .type_ = int_type, .span = v.span } };
            return node;
        },
        .float_literal => |v| {
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .float_literal = .{ .value = v.value, .type_ = float_type, .span = v.span } };
            return node;
        },
        .string_literal => |v| {
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .string_literal = .{ .value = v.value, .type_ = string_type, .span = v.span } };
            return node;
        },
        .bool_literal => |v| {
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .bool_literal = .{ .value = v.value, .type_ = bool_type, .span = v.span } };
            return node;
        },
        .char_literal => |v| {
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .char_literal = .{ .value = @intCast(v.value), .type_ = char_type, .span = v.span } };
            return node;
        },
        .nil_literal => |v| {
            const a = try env.newVar(allocator, std.math.maxInt(u32));
            const nilable_id = try env.registerType(allocator, Type{ .nilable = a });
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .nil_literal = .{ .type_ = nilable_id, .span = v } };
            return node;
        },
        .duration_literal => |v| {
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .duration_literal = .{ .value = v.value, .unit = v.unit, .type_ = duration_type, .span = v.span } };
            return node;
        },
        .path_literal => |v| {
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .path_literal = .{ .value = v.value, .type_ = path_type, .span = v.span } };
            return node;
        },
        .regex_literal => |v| {
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .regex_literal = .{ .value = v.value, .type_ = regex_type, .span = v.span } };
            return node;
        },
        .bytes_literal => |v| {
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .bytes_literal = .{ .value = v.value, .type_ = bytes_type, .span = v.span } };
            return node;
        },
        .ident => |v| {
            const node = try ea.create(TypedExpr);
            const ty = try env.newVar(allocator, std.math.maxInt(u32));
            node.* = TypedExpr{ .ident = .{ .name = v.name, .type_ = ty, .span = v.span } };
            return node;
        },
        .lambda => |v| {
            const typed_body = try inferExpr(allocator, v.body, env, errors);
            const typed_params = try ea.alloc(Param, v.params.len);
            for (v.params, 0..) |p, i| {
                const pty = try env.newVar(allocator, 1);
                typed_params[i] = Param{ .name = p.name, .type_ = pty };
            }
            const param_id = if (typed_params.len > 0) typed_params[0].type_ else try env.newVar(allocator, 1);
            const has_effect = hasEffect(v.body);
            const body_type = exprType(typed_body);
            const fn_ty_id = try env.registerFunctionType(allocator, has_effect, param_id, body_type);
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .lambda = .{ .params = typed_params, .body = typed_body, .type_ = fn_ty_id, .span = v.span } };
            return node;
        },
        .call => |v| {
            const typed_func = try inferExpr(allocator, v.func, env, errors);
            const typed_arg = try inferExpr(allocator, v.arg, env, errors);
            const result_id = try env.newVar(allocator, std.math.maxInt(u32));
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .call = .{ .func = typed_func, .arg = typed_arg, .type_ = result_id, .span = v.span } };
            return node;
        },
        .let_in => |v| {
            var typed_bindings: std.ArrayListUnmanaged(Binding) = .empty;
            defer typed_bindings.deinit(ea);
            for (v.bindings) |b| {
                const typed_val = try inferExpr(allocator, b.value, env, errors);
                try typed_bindings.append(ea, Binding{ .name = b.name, .value = typed_val });
            }
            const typed_body = try inferExpr(allocator, v.body, env, errors);
            const body_type = exprType(typed_body);
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .let_in = .{ .bindings = try typed_bindings.toOwnedSlice(ea), .body = typed_body, .type_ = body_type, .span = v.span } };
            return node;
        },
        .do_block => |v| {
            var typed_stmts: std.ArrayListUnmanaged(Stmt) = .empty;
            defer typed_stmts.deinit(ea);
            for (v.body) |stmt| {
                const typed_stmt = try inferStmt(allocator, stmt, env, errors);
                try typed_stmts.append(ea, typed_stmt);
            }
            const typed_result = if (v.result) |r| try inferExpr(allocator, r, env, errors) else null;
            const result_type = if (typed_result) |r| exprType(r) else unit_type;
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .do_block = .{ .body = try typed_stmts.toOwnedSlice(ea), .result = typed_result, .type_ = result_type, .span = v.span } };
            return node;
        },
        .if_expr => |v| {
            const typed_cond = try inferExpr(allocator, v.cond, env, errors);
            const typed_then = try inferExpr(allocator, v.then, env, errors);
            const typed_else = try inferExpr(allocator, v.else_, env, errors);
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .if_expr = .{ .cond = typed_cond, .then = typed_then, .else_ = typed_else, .type_ = exprType(typed_then), .span = v.span } };
            return node;
        },
        .case_expr => |v| {
            const typed_subject = try inferExpr(allocator, v.subject, env, errors);
            var typed_branches: std.ArrayListUnmanaged(Branch) = .empty;
            defer typed_branches.deinit(ea);
            for (v.branches) |b| {
                const typed_body = try inferExpr(allocator, b.body, env, errors);
                try typed_branches.append(ea, Branch{ .pattern = b.pattern, .body = typed_body, .type_ = exprType(typed_body) });
            }
            const branches = try typed_branches.toOwnedSlice(ea);
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .case_expr = .{ .subject = typed_subject, .branches = branches, .type_ = if (branches.len > 0) branches[0].type_ else unit_type, .span = v.span } };
            return node;
        },
        .binary_op => |v| {
            const typed_left = try inferExpr(allocator, v.left, env, errors);
            const typed_right = try inferExpr(allocator, v.right, env, errors);
            const left_type = exprType(typed_left);
            const right_type = exprType(typed_right);

            switch (v.op) {
                .add, .sub, .mul, .div, .mod => {
                    unify_mod.unify(env, allocator, left_type, right_type) catch |err| switch (err) {
                        error.Mismatch => try errors.add(allocator, .{ .mismatch = .{ .expected = left_type, .found = right_type, .span = v.span } }),
                        error.InfiniteType => try errors.add(allocator, .{ .infinite_type = v.span }),
                        error.NilToNonNilable => try errors.add(allocator, .{ .nil_to_non_nilable = v.span }),
                        else => try errors.add(allocator, .{ .mismatch = .{ .expected = left_type, .found = right_type, .span = v.span } }),
                    };
                },
                .eq, .neq, .lt, .le, .gt, .ge => {
                    unify_mod.unify(env, allocator, left_type, right_type) catch |err| switch (err) {
                        error.Mismatch => try errors.add(allocator, .{ .mismatch = .{ .expected = left_type, .found = right_type, .span = v.span } }),
                        error.InfiniteType => try errors.add(allocator, .{ .infinite_type = v.span }),
                        error.NilToNonNilable => try errors.add(allocator, .{ .nil_to_non_nilable = v.span }),
                        else => try errors.add(allocator, .{ .mismatch = .{ .expected = left_type, .found = right_type, .span = v.span } }),
                    };
                },
                .and_, .or_ => {
                    unify_mod.unify(env, allocator, left_type, bool_type) catch |err| switch (err) {
                        error.Mismatch => try errors.add(allocator, .{ .mismatch = .{ .expected = bool_type, .found = left_type, .span = v.span } }),
                        error.InfiniteType => try errors.add(allocator, .{ .infinite_type = v.span }),
                        error.NilToNonNilable => try errors.add(allocator, .{ .nil_to_non_nilable = v.span }),
                        else => try errors.add(allocator, .{ .mismatch = .{ .expected = bool_type, .found = left_type, .span = v.span } }),
                    };
                    unify_mod.unify(env, allocator, right_type, bool_type) catch |err| switch (err) {
                        error.Mismatch => try errors.add(allocator, .{ .mismatch = .{ .expected = bool_type, .found = right_type, .span = v.span } }),
                        error.InfiniteType => try errors.add(allocator, .{ .infinite_type = v.span }),
                        error.NilToNonNilable => try errors.add(allocator, .{ .nil_to_non_nilable = v.span }),
                        else => try errors.add(allocator, .{ .mismatch = .{ .expected = bool_type, .found = right_type, .span = v.span } }),
                    };
                },
                .concat => {
                    unify_mod.unify(env, allocator, left_type, right_type) catch |err| switch (err) {
                        error.Mismatch => try errors.add(allocator, .{ .mismatch = .{ .expected = left_type, .found = right_type, .span = v.span } }),
                        error.InfiniteType => try errors.add(allocator, .{ .infinite_type = v.span }),
                        error.NilToNonNilable => try errors.add(allocator, .{ .nil_to_non_nilable = v.span }),
                        else => try errors.add(allocator, .{ .mismatch = .{ .expected = left_type, .found = right_type, .span = v.span } }),
                    };
                },
                .nil_coal, .range => {},
            }

            const result_type = switch (v.op) {
                .add, .sub, .mul, .div, .mod => left_type,
                .eq, .neq, .lt, .le, .gt, .ge => bool_type,
                .and_, .or_ => bool_type,
                .concat => left_type,
                .nil_coal => right_type,
                .range => path_type,
            };
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .binary_op = .{ .op = v.op, .left = typed_left, .right = typed_right, .type_ = result_type, .span = v.span } };
            return node;
        },
        .unary_op => |v| {
            const typed_operand = try inferExpr(allocator, v.operand, env, errors);
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .unary_op = .{ .op = v.op, .operand = typed_operand, .type_ = exprType(typed_operand), .span = v.span } };
            return node;
        },
        .list_literal => |v| {
            var typed_items: std.ArrayListUnmanaged(ExprItem) = .empty;
            defer typed_items.deinit(ea);
            for (v.items) |item| {
                const typed_item = try inferExprItem(allocator, item, env, errors);
                try typed_items.append(ea, typed_item);
            }
            const list_ty_id = try env.newVar(allocator, std.math.maxInt(u32));
            const list_id = try env.registerType(allocator, Type{ .list = list_ty_id });
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .list_literal = .{ .items = try typed_items.toOwnedSlice(ea), .type_ = list_id, .span = v.span } };
            return node;
        },
        .tuple_literal => |v| {
            var typed_elems: std.ArrayListUnmanaged(TypedExpr) = .empty;
            defer typed_elems.deinit(ea);
            var elem_types: std.ArrayListUnmanaged(TypeId) = .empty;
            defer elem_types.deinit(ea);
            for (v.items) |item| {
                const typed_item = try inferExpr(allocator, item, env, errors);
                try typed_elems.append(ea, typed_item.*);
                try elem_types.append(ea, exprType(typed_item));
            }
            const tuple_ty_id = try env.registerType(allocator, Type{ .tuple = try elem_types.toOwnedSlice(ea) });
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .tuple_literal = .{ .items = try typed_elems.toOwnedSlice(ea), .type_ = tuple_ty_id, .span = v.span } };
            return node;
        },
        .record_literal => |v| {
            var typed_fields: std.ArrayListUnmanaged(RecordField) = .empty;
            defer typed_fields.deinit(ea);
            var field_types: std.ArrayListUnmanaged(typed.RecordFieldType) = .empty;
            defer field_types.deinit(ea);
            for (v.fields) |f| {
                const typed_val = try inferExpr(allocator, f.value, env, errors);
                try typed_fields.append(ea, RecordField{ .name = f.name, .value = typed_val });
                try field_types.append(ea, typed.RecordFieldType{ .name = f.name, .type_ = exprType(typed_val) });
            }
            const rec_ty_id = try env.registerType(allocator, Type{ .record = try field_types.toOwnedSlice(ea) });
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .record_literal = .{ .fields = try typed_fields.toOwnedSlice(ea), .type_ = rec_ty_id, .span = v.span } };
            return node;
        },
        .record_access => |v| {
            const typed_rec = try inferExpr(allocator, v.record, env, errors);
            const result_id = try env.newVar(allocator, std.math.maxInt(u32));
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .record_access = .{ .record = typed_rec, .field = v.field, .type_ = result_id, .span = v.span } };
            return node;
        },
        .pipe => |v| {
            const typed_left = try inferExpr(allocator, v.left, env, errors);
            const typed_right = try inferExpr(allocator, v.right, env, errors);
            const result_id = try env.newVar(allocator, std.math.maxInt(u32));
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .call = .{ .func = typed_right, .arg = typed_left, .type_ = result_id, .span = v.span } };
            return node;
        },
        .pipe_reverse => |v| {
            const typed_left = try inferExpr(allocator, v.left, env, errors);
            const typed_right = try inferExpr(allocator, v.right, env, errors);
            const result_id = try env.newVar(allocator, std.math.maxInt(u32));
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .call = .{ .func = typed_left, .arg = typed_right, .type_ = result_id, .span = v.span } };
            return node;
        },
        .compose => |v| {
            const typed_left = try inferExpr(allocator, v.left, env, errors);
            const typed_right = try inferExpr(allocator, v.right, env, errors);
            const result_id = try env.newVar(allocator, std.math.maxInt(u32));
            const param_name = try ea.alloc(Param, 1);
            param_name[0] = .{ .name = "x", .type_ = try env.newVar(allocator, 1) };
            const x_ref = try ea.create(TypedExpr);
            x_ref.* = .{ .ident = .{ .name = "x", .type_ = param_name[0].type_, .span = v.span } };
            const f_call = try ea.create(TypedExpr);
            f_call.* = .{ .call = .{ .func = typed_left, .arg = x_ref, .type_ = result_id, .span = v.span } };
            const g_call = try ea.create(TypedExpr);
            g_call.* = .{ .call = .{ .func = typed_right, .arg = f_call, .type_ = result_id, .span = v.span } };
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .lambda = .{ .params = param_name, .body = g_call, .type_ = result_id, .span = v.span } };
            return node;
        },
        .compose_reverse => |v| {
            const typed_left = try inferExpr(allocator, v.left, env, errors);
            const typed_right = try inferExpr(allocator, v.right, env, errors);
            const result_id = try env.newVar(allocator, std.math.maxInt(u32));
            const param_name = try ea.alloc(Param, 1);
            param_name[0] = .{ .name = "x", .type_ = try env.newVar(allocator, 1) };
            const x_ref = try ea.create(TypedExpr);
            x_ref.* = .{ .ident = .{ .name = "x", .type_ = param_name[0].type_, .span = v.span } };
            const g_call = try ea.create(TypedExpr);
            g_call.* = .{ .call = .{ .func = typed_right, .arg = x_ref, .type_ = result_id, .span = v.span } };
            const f_call = try ea.create(TypedExpr);
            f_call.* = .{ .call = .{ .func = typed_left, .arg = g_call, .type_ = result_id, .span = v.span } };
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .lambda = .{ .params = param_name, .body = f_call, .type_ = result_id, .span = v.span } };
            return node;
        },
        .map_literal => |v| {
            var typed_entries: std.ArrayListUnmanaged(MapEntry) = .empty;
            defer typed_entries.deinit(ea);
            for (v.entries) |e| {
                const typed_key = try inferExpr(allocator, e.key, env, errors);
                const typed_val = try inferExpr(allocator, e.value, env, errors);
                try typed_entries.append(ea, MapEntry{ .key = typed_key, .value = typed_val });
            }
            const map_ty_id = try env.newVar(allocator, std.math.maxInt(u32));
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .map_literal = .{ .entries = try typed_entries.toOwnedSlice(ea), .type_ = map_ty_id, .span = v.span } };
            return node;
        },
        .set_literal => |v| {
            var typed_items: std.ArrayListUnmanaged(TypedExpr) = .empty;
            defer typed_items.deinit(ea);
            for (v.items) |item| {
                const typed_item = try inferExpr(allocator, item, env, errors);
                try typed_items.append(ea, typed_item.*);
            }
            const set_ty_id = try env.newVar(allocator, std.math.maxInt(u32));
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .set_literal = .{ .items = try typed_items.toOwnedSlice(ea), .type_ = set_ty_id, .span = v.span } };
            return node;
        },
        .record_update, .range_literal, .ternary => return error.Unimplemented,
    };
}

fn inferStmt(
    allocator: std.mem.Allocator,
    stmt: ast.Stmt,
    env: *TypeEnv,
    errors: *ErrorList,
) InferenceError!Stmt {
    return switch (stmt.kind) {
        .binding => |b| {
            const typed_val = try inferExpr(allocator, b.value, env, errors);
            return Stmt{ .kind = .{ .binding = Binding{ .name = b.name, .value = typed_val } }, .type_ = exprType(typed_val) };
        },
        .defer_ => |d| {
            const typed_expr = try inferExpr(allocator, d.expr, env, errors);
            return Stmt{ .kind = .{ .defer_ = .{ .expr = typed_expr } }, .type_ = unit_type };
        },
        .expr => |e| {
            const typed_expr = try inferExpr(allocator, e, env, errors);
            return Stmt{ .kind = .{ .expr = typed_expr }, .type_ = exprType(typed_expr) };
        },
    };
}

fn inferExprItem(
    allocator: std.mem.Allocator,
    item: ast.ExprItem,
    env: *TypeEnv,
    errors: *ErrorList,
) InferenceError!ExprItem {
    return switch (item) {
        .expr => |e| ExprItem{ .expr = try inferExpr(allocator, e, env, errors) },
        .spread => |s| ExprItem{ .spread = try inferExpr(allocator, s, env, errors) },
    };
}

fn exprType(expr: *const TypedExpr) TypeId {
    return switch (expr.*) {
        inline else => |v| v.type_,
    };
}

pub fn hasEffect(expr: *const ast.Expr) bool {
    return switch (expr.*) {
        .do_block => true,
        .call => |c| isEffectCall(c.func) or hasEffect(c.arg),
        .let_in => |l| {
            for (l.bindings) |b| {
                if (hasEffect(b.value)) return true;
            }
            return hasEffect(l.body);
        },
        .if_expr => |i| hasEffect(i.then) or hasEffect(i.else_),
        .case_expr => |c| {
            for (c.branches) |b| {
                if (hasEffect(b.body)) return true;
            }
            return false;
        },
        .binary_op => |b| hasEffect(b.left) or hasEffect(b.right),
        .unary_op => |u| hasEffect(u.operand),
        .pipe => |p| hasEffect(p.left) or hasEffect(p.right),
        .pipe_reverse => |p| hasEffect(p.left) or hasEffect(p.right),
        .compose => |c| hasEffect(c.left) or hasEffect(c.right),
        .compose_reverse => |c| hasEffect(c.left) or hasEffect(c.right),
        .list_literal => |l| {
            for (l.items) |item| {
                switch (item) {
                    .expr => |e| { if (hasEffect(e)) return true; },
                    .spread => |s| { if (hasEffect(s)) return true; },
                }
            }
            return false;
        },
        .tuple_literal => |t| {
            for (t.items) |item| {
                if (hasEffect(item)) return true;
            }
            return false;
        },
        .record_literal => |r| {
            for (r.fields) |f| {
                if (hasEffect(f.value)) return true;
            }
            return false;
        },
        .record_access => |r| hasEffect(r.record),
        .record_update => |r| {
            for (r.fields) |f| {
                if (hasEffect(f.value)) return true;
            }
            return false;
        },
        .map_literal => |m| {
            for (m.entries) |e| {
                if (hasEffect(e.key)) return true;
                if (hasEffect(e.value)) return true;
            }
            return false;
        },
        .set_literal => |s| {
            for (s.items) |item| {
                if (hasEffect(item)) return true;
            }
            return false;
        },
        .range_literal, .ternary => false,
        else => false,
    };
}

fn isEffectCall(func: *const ast.Expr) bool {
    return switch (func.*) {
        .ident => |id| isEffectNamespaceCall(id.name),
        .call => |c| isEffectCall(c.func),
        .pipe => |p| isEffectCall(p.right),
        .pipe_reverse => |p| isEffectCall(p.left),
        else => false,
    };
}

pub fn isEffectNamespaceCall(name: []const u8) bool {
    if (std.mem.eql(u8, name, "Signal.on")) return true;

    if (std.mem.startsWith(u8, name, "Cmd.")) {
        const rest = name["Cmd.".len..];
        if (std.mem.containsAtLeast(u8, rest, 1, "?")) return true;
        if (std.mem.containsAtLeast(u8, rest, 1, "!")) return true;
        if (std.mem.startsWith(u8, rest, "pipe?")) return true;
        if (std.mem.startsWith(u8, rest, "pipe!")) return true;
        inline for (.{ "exec", "which", "timeout", "retry", "execSafe" }) |efn| {
            if (std.mem.eql(u8, rest, efn)) return true;
        }
        return false;
    }

    inline for (.{ "IO", "File", "Env", "Process", "Task", "Random" }) |ns| {
        if (std.mem.startsWith(u8, name, ns)) {
            if (name.len == ns.len) return true;
            if (name.len > ns.len and name[ns.len] == '.') return true;
        }
    }
    return false;
}
