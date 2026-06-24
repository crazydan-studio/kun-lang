const std = @import("std");
const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");
const parser = @import("../parser/parser.zig");
const env_mod = @import("env.zig");
const unify_mod = @import("unify.zig");
const error_mod = @import("error.zig");
const pattern_mod = @import("pattern.zig");
const effect_mod = @import("effect.zig");
const primitive_mod = @import("../runtime/primitive.zig");

const Type = typed.Type;
const TypeId = typed.TypeId;
const TypeEnv = env_mod.TypeEnv;
const PrimitiveTable = primitive_mod.PrimitiveTable;
const PrimitiveBinding = primitive_mod.PrimitiveBinding;
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
const command_type = env_mod.command_type;

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
    primitives: PrimitiveTable,
) InferenceError![]const TypedDecl {
    const ea = env.exprAllocator();
    var typed_decls: std.ArrayListUnmanaged(TypedDecl) = .empty;
    errdefer typed_decls.deinit(ea);

    try registerPrimitiveSignatures(allocator, env, primitives);

    for (decls) |decl| {
        const typed_decl = try inferDecl(allocator, decl, env, errors);
        try typed_decls.append(ea, typed_decl);
    }

    if (errors.hasErrors()) return error.TypeCheckFailed;
    return try typed_decls.toOwnedSlice(ea);
}

fn registerPrimitiveSignatures(
    allocator: std.mem.Allocator,
    env: *TypeEnv,
    primitives: PrimitiveTable,
) !void {
    const ea = env.exprAllocator();
    for (primitives.bindings) |binding| {
        if (binding.is_polymorphic) continue;

        const full_name = try std.fmt.allocPrint(ea, "{s}.{s}", .{ binding.module, binding.name });
        var ty = binding.return_type;
        var i: u8 = binding.arg_count;
        while (i > 0) : (i -= 1) {
            const param_ty = try env.newVar(allocator, 0);
            ty = try env.registerFunctionType(allocator, binding.is_effect and i == 1, param_ty, ty);
        }
        if (binding.arg_count == 0) {
            const dummy_param = try env.newVar(allocator, 0);
            ty = try env.registerFunctionType(allocator, binding.is_effect, dummy_param, ty);
        }
        try env.let_types.put(ea, full_name, ty);
    }
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

    const has_effect = effect_mod.hasEffectInExpr(body);
    if (!has_effect) {
        try effect_mod.checkPureFunctionBody(allocator, body, errors);
        try effect_mod.checkPureUnitReturn(allocator, name, exprType(typed_body), env, span, errors);
    }

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
            const ty = if (std.mem.startsWith(u8, v.name, "Cmd.") and !isKnownCmdApi(v.name))
                command_type
            else if (env.let_types.get(v.name)) |poly_id|
                try env.freshInstance(allocator, poly_id)
            else
                try env.newVar(allocator, std.math.maxInt(u32));
            node.* = TypedExpr{ .ident = .{ .name = v.name, .type_ = ty, .span = v.span } };
            return node;
        },
        .lambda => |v| {
            const typed_body = try inferExpr(allocator, v.body, env, errors);
            const typed_params = try ea.alloc(Param, v.params.len);
            var param_type_ids = try ea.alloc(TypeId, v.params.len);
            for (v.params, 0..) |p, i| {
                const pty = try env.newVar(allocator, 1);
                typed_params[i] = Param{ .name = p.name, .type_ = pty };
                param_type_ids[i] = pty;
            }
            const has_effect = effect_mod.hasEffectInExpr(v.body);
            const body_type = exprType(typed_body);
            if (!has_effect) {
                try effect_mod.checkPureFunctionBody(allocator, v.body, errors);
                try effect_mod.checkPureUnitReturn(allocator, "lambda", body_type, env, v.span, errors);
            }
            var fn_ty_id = body_type;
            var i: usize = param_type_ids.len;
            while (i > 0) : (i -= 1) {
                const is_outer = i > 1;
                const level_effect = if (is_outer) false else has_effect;
                fn_ty_id = try env.registerFunctionType(allocator, level_effect, param_type_ids[i - 1], fn_ty_id);
            }
            if (param_type_ids.len == 0) {
                const dummy_param = try env.newVar(allocator, 1);
                fn_ty_id = try env.registerFunctionType(allocator, has_effect, dummy_param, body_type);
            }
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .lambda = .{ .params = typed_params, .body = typed_body, .type_ = fn_ty_id, .span = v.span } };
            return node;
        },
        .call => |v| {
            const typed_func = try inferExpr(allocator, v.func, env, errors);
            const typed_arg = try inferExpr(allocator, v.arg, env, errors);
            const result_id = try env.newVar(allocator, std.math.maxInt(u32));
            const func_type = exprType(typed_func);
            const arg_type = exprType(typed_arg);
            const is_effect_fn = env.isEffectFn(func_type);
            const expected_fn = try env.registerFunctionType(allocator, is_effect_fn, arg_type, result_id);
            unify_mod.unify(env, allocator, func_type, expected_fn) catch |err| switch (err) {
                error.Mismatch => {
                    const func_name = if (typed_func.* == .ident) typed_func.ident.name else "function";
                    try errors.add(allocator, .{ .function_apply_arg = .{ .func_name = func_name, .expected = arg_type, .found = arg_type, .span = v.span } });
                },
                error.InfiniteType => try errors.add(allocator, .{ .infinite_type = v.span }),
                error.NilToNonNilable => try errors.add(allocator, .{ .nil_to_non_nilable = v.span }),
                else => {
                    const func_name = if (typed_func.* == .ident) typed_func.ident.name else "function";
                    try errors.add(allocator, .{ .function_apply_arg = .{ .func_name = func_name, .expected = arg_type, .found = arg_type, .span = v.span } });
                },
            };
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .call = .{ .func = typed_func, .arg = typed_arg, .type_ = result_id, .span = v.span } };
            return node;
        },
        .let_in => |v| {
            var typed_bindings: std.ArrayListUnmanaged(Binding) = .empty;
            defer typed_bindings.deinit(ea);

            if (try effect_mod.checkDuplicateBindings(allocator, v.bindings)) {
                for (v.bindings, 0..) |b1, i| {
                    for (v.bindings[i + 1 ..]) |b2| {
                        if (std.mem.eql(u8, b1.name, b2.name)) {
                            try errors.add(allocator, .{ .duplicate_binding = .{ .name = b1.name, .span = b1.span } });
                        }
                    }
                }
            }
            try effect_mod.checkLetInPurity(allocator, v.bindings, v.body, errors);
            try effect_mod.checkEmptyBody(allocator, expr, "let in", errors);
            try effect_mod.checkDoLetExclusion(allocator, expr, errors);

            const saved_let_types = env.let_types;
            defer {
                env.let_types.deinit(ea);
                env.let_types = saved_let_types;
            }
            env.let_types = .empty;

            for (v.bindings) |b| {
                const typed_val = try inferExpr(allocator, b.value, env, errors);
                const generalized = try env.generalize(allocator, exprType(typed_val), 1);
                const gen_val = try ea.create(TypedExpr);
                gen_val.* = typed_val.*;
                setExprType(gen_val, generalized);
                try env.let_types.put(ea, b.name, generalized);
                try typed_bindings.append(ea, Binding{ .name = b.name, .value = gen_val });
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

            try effect_mod.checkEmptyBody(allocator, expr, "do block", errors);
            try effect_mod.checkDoLetExclusion(allocator, expr, errors);

            {
                var names: std.StringHashMapUnmanaged(void) = .empty;
                defer names.deinit(ea);
                for (v.body) |stmt| {
                    if (stmt.kind == .binding) {
                        const name = stmt.kind.binding.name;
                        if (names.contains(name)) {
                            try errors.add(allocator, .{ .duplicate_binding = .{ .name = name, .span = stmt.span } });
                        } else {
                            try names.put(ea, name, {});
                        }
                    }
                }
            }

            for (v.body) |stmt| {
                const typed_stmt = try inferStmt(allocator, stmt, env, errors);
                try typed_stmts.append(ea, typed_stmt);
            }
            const typed_result = if (v.result) |r| try inferExpr(allocator, r, env, errors) else null;
            const result_type = if (typed_result) |r| exprType(r) else unit_type;
            try effect_mod.checkDoInResult(allocator, expr, typed_result, errors);
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .do_block = .{ .body = try typed_stmts.toOwnedSlice(ea), .result = typed_result, .type_ = result_type, .span = v.span } };
            return node;
        },
        .if_expr => |v| {
            const typed_cond = try inferExpr(allocator, v.cond, env, errors);
            const typed_then = try inferExpr(allocator, v.then, env, errors);
            const typed_else = try inferExpr(allocator, v.else_, env, errors);
            const node = try ea.create(TypedExpr);
            const result_type = exprType(typed_then);
            unify_mod.unify(env, allocator, result_type, exprType(typed_else)) catch {
                try errors.add(allocator, .{ .if_branch_mismatch = .{ .then_type = result_type, .else_type = exprType(typed_else), .span = v.span } });
            };
            unify_mod.unify(env, allocator, exprType(typed_cond), bool_type) catch {
                try errors.add(allocator, .{ .mismatch = .{ .expected = bool_type, .found = exprType(typed_cond), .span = v.span } });
            };
            node.* = TypedExpr{ .if_expr = .{ .cond = typed_cond, .then = typed_then, .else_ = typed_else, .type_ = result_type, .span = v.span } };
            return node;
        },
        .case_expr => |v| {
            const typed_subject = try inferExpr(allocator, v.subject, env, errors);
            var typed_branches: std.ArrayListUnmanaged(Branch) = .empty;
            defer typed_branches.deinit(ea);
            for (v.branches) |b| {
                const typed_body = try inferExpr(allocator, b.body, env, errors);
                const typed_guard = if (b.guard) |g| try inferExpr(allocator, g, env, errors) else null;
                try typed_branches.append(ea, Branch{ .pattern = b.pattern, .body = typed_body, .type_ = exprType(typed_body), .guard_cond = typed_guard });
            }
            const branches = try typed_branches.toOwnedSlice(ea);
            if (pattern_mod.checkExhaustive(allocator, env, exprType(typed_subject), branches) catch null) |missing| {
                try errors.add(allocator, .{ .non_exhaustive = .{ .missing = missing, .span = v.span } });
            }
            const result_type = if (branches.len > 0) branches[0].type_ else unit_type;
            for (branches[1..]) |b| {
                unify_mod.unify(env, allocator, result_type, b.type_) catch |err| {
                    switch (err) {
                        error.Mismatch, error.EffectFnPureMismatch => try errors.add(allocator, .{ .if_branch_mismatch = .{
                            .then_type = result_type, .else_type = b.type_, .span = v.span,
                        } }),
                        error.InfiniteType => try errors.add(allocator, .{ .infinite_type = v.span }),
                        error.NilToNonNilable => try errors.add(allocator, .{ .nil_to_non_nilable = v.span }),
                        else => try errors.add(allocator, .{ .mismatch = .{
                            .expected = result_type, .found = b.type_, .span = v.span,
                        } }),
                    }
                };
            }
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .case_expr = .{ .subject = typed_subject, .branches = branches, .type_ = result_type, .span = v.span } };
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
                .nil_coal => {
                    const nilable_right = try env.registerType(allocator, Type{ .nilable = right_type });
                    unify_mod.unify(env, allocator, left_type, nilable_right) catch |err| switch (err) {
                        error.Mismatch => try errors.add(allocator, .{ .mismatch = .{ .expected = nilable_right, .found = left_type, .span = v.span } }),
                        error.InfiniteType => try errors.add(allocator, .{ .infinite_type = v.span }),
                        error.NilToNonNilable => try errors.add(allocator, .{ .nil_to_non_nilable = v.span }),
                        else => try errors.add(allocator, .{ .mismatch = .{ .expected = nilable_right, .found = left_type, .span = v.span } }),
                    };
                },
                .range => {},
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
            const elem_ty = try env.newVar(allocator, std.math.maxInt(u32));
            for (v.items) |item| {
                const typed_item = try inferExprItem(allocator, item, env, errors);
                const item_type = switch (typed_item) {
                    .expr => |e| exprType(e),
                    .spread => |s| exprType(s),
                };
                unify_mod.unify(env, allocator, item_type, elem_ty) catch {};
                try typed_items.append(ea, typed_item);
            }
            const list_id = try env.registerType(allocator, Type{ .list = elem_ty });
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
            const rec_type = exprType(typed_rec);
            const field_types = try ea.alloc(typed.RecordFieldType, 1);
            field_types[0] = typed.RecordFieldType{ .name = v.field, .type_ = result_id };
            const expected_rec = try env.registerType(allocator, Type{ .record = field_types });
            unify_mod.unify(env, allocator, rec_type, expected_rec) catch {};
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .record_access = .{ .record = typed_rec, .field = v.field, .type_ = result_id, .span = v.span } };
            return node;
        },
        .pipe => |v| {
            const typed_left = try inferExpr(allocator, v.left, env, errors);
            const typed_right = try inferExpr(allocator, v.right, env, errors);
            const result_id = try env.newVar(allocator, std.math.maxInt(u32));
            const node = try ea.create(TypedExpr);
            if (isCommandIdent(v.left)) {
                node.* = TypedExpr{ .pipe = .{ .left = typed_left, .right = typed_right, .type_ = result_id, .span = v.span } };
            } else {
                node.* = TypedExpr{ .call = .{ .func = typed_right, .arg = typed_left, .type_ = result_id, .span = v.span } };
            }
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
            const intermediate_id = try env.newVar(allocator, std.math.maxInt(u32));
            const result_id = try env.newVar(allocator, std.math.maxInt(u32));
            const param_name = try ea.alloc(Param, 1);
            param_name[0] = .{ .name = "x", .type_ = try env.newVar(allocator, 1) };
            const x_ref = try ea.create(TypedExpr);
            x_ref.* = .{ .ident = .{ .name = "x", .type_ = param_name[0].type_, .span = v.span } };

            const left_fn = try env.registerFunctionType(allocator, false, param_name[0].type_, intermediate_id);
            unify_mod.unify(env, allocator, exprType(typed_left), left_fn) catch |err| {
                switch (err) {
                    error.Mismatch, error.EffectFnPureMismatch => try errors.add(allocator, .{ .function_apply_arg = .{ .func_name = "compose-left", .expected = param_name[0].type_, .found = param_name[0].type_, .span = v.span } }),
                    error.InfiniteType => try errors.add(allocator, .{ .infinite_type = v.span }),
                    else => {},
                }
            };
            const right_fn = try env.registerFunctionType(allocator, false, intermediate_id, result_id);
            unify_mod.unify(env, allocator, exprType(typed_right), right_fn) catch |err| {
                switch (err) {
                    error.Mismatch, error.EffectFnPureMismatch => try errors.add(allocator, .{ .function_apply_arg = .{ .func_name = "compose-right", .expected = intermediate_id, .found = intermediate_id, .span = v.span } }),
                    error.InfiniteType => try errors.add(allocator, .{ .infinite_type = v.span }),
                    else => {},
                }
            };

            const f_call = try ea.create(TypedExpr);
            f_call.* = .{ .call = .{ .func = typed_left, .arg = x_ref, .type_ = intermediate_id, .span = v.span } };
            const g_call = try ea.create(TypedExpr);
            g_call.* = .{ .call = .{ .func = typed_right, .arg = f_call, .type_ = result_id, .span = v.span } };
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .lambda = .{ .params = param_name, .body = g_call, .type_ = result_id, .span = v.span } };
            return node;
        },
        .compose_reverse => |v| {
            const typed_left = try inferExpr(allocator, v.left, env, errors);
            const typed_right = try inferExpr(allocator, v.right, env, errors);
            const intermediate_id = try env.newVar(allocator, std.math.maxInt(u32));
            const result_id = try env.newVar(allocator, std.math.maxInt(u32));
            const param_name = try ea.alloc(Param, 1);
            param_name[0] = .{ .name = "x", .type_ = try env.newVar(allocator, 1) };
            const x_ref = try ea.create(TypedExpr);
            x_ref.* = .{ .ident = .{ .name = "x", .type_ = param_name[0].type_, .span = v.span } };

            const right_fn = try env.registerFunctionType(allocator, false, param_name[0].type_, intermediate_id);
            unify_mod.unify(env, allocator, exprType(typed_right), right_fn) catch |err| {
                switch (err) {
                    error.Mismatch, error.EffectFnPureMismatch => try errors.add(allocator, .{ .function_apply_arg = .{ .func_name = "compose-left", .expected = param_name[0].type_, .found = param_name[0].type_, .span = v.span } }),
                    error.InfiniteType => try errors.add(allocator, .{ .infinite_type = v.span }),
                    else => {},
                }
            };
            const left_fn = try env.registerFunctionType(allocator, false, intermediate_id, result_id);
            unify_mod.unify(env, allocator, exprType(typed_left), left_fn) catch |err| {
                switch (err) {
                    error.Mismatch, error.EffectFnPureMismatch => try errors.add(allocator, .{ .function_apply_arg = .{ .func_name = "compose-right", .expected = intermediate_id, .found = intermediate_id, .span = v.span } }),
                    error.InfiniteType => try errors.add(allocator, .{ .infinite_type = v.span }),
                    else => {},
                }
            };

            const g_call = try ea.create(TypedExpr);
            g_call.* = .{ .call = .{ .func = typed_right, .arg = x_ref, .type_ = intermediate_id, .span = v.span } };
            const f_call = try ea.create(TypedExpr);
            f_call.* = .{ .call = .{ .func = typed_left, .arg = g_call, .type_ = result_id, .span = v.span } };
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .lambda = .{ .params = param_name, .body = f_call, .type_ = result_id, .span = v.span } };
            return node;
        },
        .map_literal => |v| {
            var typed_entries: std.ArrayListUnmanaged(MapEntry) = .empty;
            defer typed_entries.deinit(ea);
            const key_ty = try env.newVar(allocator, std.math.maxInt(u32));
            const val_ty = try env.newVar(allocator, std.math.maxInt(u32));
            for (v.entries) |e| {
                const typed_key = try inferExpr(allocator, e.key, env, errors);
                const typed_val = try inferExpr(allocator, e.value, env, errors);
                unify_mod.unify(env, allocator, exprType(typed_key), key_ty) catch {};
                unify_mod.unify(env, allocator, exprType(typed_val), val_ty) catch {};
                try typed_entries.append(ea, MapEntry{ .key = typed_key, .value = typed_val });
            }
            const map_id = try env.registerType(allocator, Type{ .map = .{ .key = key_ty, .value = val_ty } });
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .map_literal = .{ .entries = try typed_entries.toOwnedSlice(ea), .type_ = map_id, .span = v.span } };
            return node;
        },
        .set_literal => |v| {
            var typed_items: std.ArrayListUnmanaged(TypedExpr) = .empty;
            defer typed_items.deinit(ea);
            const elem_ty = try env.newVar(allocator, std.math.maxInt(u32));
            for (v.items) |item| {
                const typed_item = try inferExpr(allocator, item, env, errors);
                unify_mod.unify(env, allocator, exprType(typed_item), elem_ty) catch {};
                try typed_items.append(ea, typed_item.*);
            }
            const set_id = try env.registerType(allocator, Type{ .set = elem_ty });
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .set_literal = .{ .items = try typed_items.toOwnedSlice(ea), .type_ = set_id, .span = v.span } };
            return node;
        },
        .record_update => |v| {
            const typed_rec = try inferExpr(allocator, v.record, env, errors);
            const rec_type = env.applySubst(exprType(typed_rec));
            var typed_fields: std.ArrayListUnmanaged(RecordField) = .empty;
            defer typed_fields.deinit(ea);
            if (rec_type < env.types.items.len and env.types.items[rec_type] == .record) {
                const rec = env.types.items[rec_type].record;
                for (v.fields) |f| {
                    const typed_val = try inferExpr(allocator, f.value, env, errors);
                    for (rec) |rf| {
                        if (std.mem.eql(u8, f.name, rf.name)) {
                            unify_mod.unify(env, allocator, exprType(typed_val), rf.type_) catch |err| {
                                switch (err) {
                                    error.Mismatch => try errors.add(allocator, .{ .mismatch = .{ .expected = rf.type_, .found = exprType(typed_val), .span = v.span } }),
                                    error.InfiniteType => try errors.add(allocator, .{ .infinite_type = v.span }),
                                    error.NilToNonNilable => try errors.add(allocator, .{ .nil_to_non_nilable = v.span }),
                                    else => {},
                                }
                            };
                            break;
                        }
                    } else {
                        try errors.add(allocator, .{ .unknown_field = .{ .name = f.name, .span = v.span } });
                    }
                    try typed_fields.append(ea, RecordField{ .name = f.name, .value = typed_val });
                }
            } else {
                for (v.fields) |f| {
                    const typed_val = try inferExpr(allocator, f.value, env, errors);
                    try typed_fields.append(ea, RecordField{ .name = f.name, .value = typed_val });
                }
            }
            const result_id = try env.newVar(allocator, std.math.maxInt(u32));
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .record_update = .{ .record = typed_rec, .fields = try typed_fields.toOwnedSlice(ea), .type_ = result_id, .span = v.span } };
            return node;
        },
        .range_literal => |v| {
            const typed_from = try inferExpr(allocator, v.from, env, errors);
            const typed_to = try inferExpr(allocator, v.to, env, errors);
            unify_mod.unify(env, allocator, exprType(typed_from), int_type) catch |err| {
                switch (err) {
                    error.Mismatch => try errors.add(allocator, .{ .mismatch = .{ .expected = int_type, .found = exprType(typed_from), .span = v.span } }),
                    else => {},
                }
            };
            unify_mod.unify(env, allocator, exprType(typed_to), int_type) catch |err| {
                switch (err) {
                    error.Mismatch => try errors.add(allocator, .{ .mismatch = .{ .expected = int_type, .found = exprType(typed_to), .span = v.span } }),
                    else => {},
                }
            };
            const typed_step = if (v.step) |s| blk: {
                const ts = try inferExpr(allocator, s, env, errors);
                unify_mod.unify(env, allocator, exprType(ts), int_type) catch {};
                break :blk ts;
            } else null;
            const stream_id = try env.registerType(allocator, Type{ .stream = int_type });
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .range_literal = .{ .from = typed_from, .to = typed_to, .step = typed_step, .type_ = stream_id, .span = v.span } };
            return node;
        },
        .ternary => |v| {
            const typed_cond = try inferExpr(allocator, v.cond, env, errors);
            const typed_then = try inferExpr(allocator, v.then, env, errors);
            const typed_else = try inferExpr(allocator, v.else_, env, errors);
            const result_type = exprType(typed_then);
            unify_mod.unify(env, allocator, result_type, exprType(typed_else)) catch {
                try errors.add(allocator, .{ .if_branch_mismatch = .{ .then_type = result_type, .else_type = exprType(typed_else), .span = v.span } });
            };
            const node = try ea.create(TypedExpr);
            node.* = TypedExpr{ .ternary = .{ .cond = typed_cond, .then = typed_then, .else_ = typed_else, .type_ = result_type, .span = v.span } };
            return node;
        },
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

fn setExprType(expr: *TypedExpr, ty: TypeId) void {
    switch (expr.*) {
        inline else => |*v| v.type_ = ty,
    }
}

pub fn isEffectNamespaceCall(name: []const u8) bool {
    return @import("../runtime/primitive.zig").isEffectBinding(name);
}

fn isCommandIdent(expr: *const ast.Expr) bool {
    if (expr.* == .ident) {
        const name = expr.ident.name;
        return std.mem.startsWith(u8, name, "Cmd.") and !isKnownCmdApi(name) and name[name.len - 1] != '?' and name[name.len - 1] != '!';
    }
    return false;
}

fn isKnownCmdApi(name: []const u8) bool {
    return @import("../runtime/cmd.zig").isKnownCmdApi(name);
}
