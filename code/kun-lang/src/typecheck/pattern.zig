const std = @import("std");
const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");
const env_mod = @import("env.zig");

const TypeEnv = env_mod.TypeEnv;
const TypeId = typed.TypeId;

pub fn checkExhaustive(
    allocator: std.mem.Allocator,
    env: *TypeEnv,
    scrutinee_ty: TypeId,
    branches: []const typed.Branch,
) !?[][]const u8 {
    _ = allocator;
    const arena = env.exprAllocator();
    const resolved = env.resolveType(scrutinee_ty);
    if (branches.len == 0) {
        var missing: std.ArrayListUnmanaged([]const u8) = .empty;
        try missing.append(arena, "_");
            return @as(?[][]const u8, try missing.toOwnedSlice(arena));
    }

    switch (resolved) {
        .adt => |adt_ty| {
            var uncovered: std.ArrayListUnmanaged([]const u8) = .empty;
            for (adt_ty.variants) |variant| {
                var covered = false;
                for (branches) |b| {
                    if (b.pattern == .wildcard or b.pattern == .ident) {
                        const name = if (b.pattern == .wildcard) "" else b.pattern.ident.name;
                        if (name.len == 0 or (name.len > 0 and name[0] >= 'a' and name[0] <= 'z')) {
                            covered = true;
                            break;
                        }
                        if (std.mem.eql(u8, name, variant.name)) {
                            covered = true;
                            break;
                        }
                    }
                    if (b.pattern == .variant) {
                        if (std.mem.eql(u8, b.pattern.variant.name, variant.name)) {
                            covered = true;
                            break;
                        }
                    }
                }
                if (!covered) {
                    try uncovered.append(arena, try std.fmt.allocPrint(arena, "{s}", .{variant.name}));
                }
            }
            if (uncovered.items.len > 0) {
                return @as(?[][]const u8, try uncovered.toOwnedSlice(arena));
            }
            return null;
        },
        .bool => {
            var has_wildcard = false;
            var has_true = false;
            var has_false = false;
            for (branches) |b| {
                if (b.pattern == .wildcard) { has_wildcard = true; break; }
                if (b.pattern == .ident) {
                    const name = b.pattern.ident.name;
                    if (std.mem.eql(u8, name, "True")) has_true = true;
                    if (std.mem.eql(u8, name, "False")) has_false = true;
                }
                if (b.pattern == .literal) {
                    if (b.pattern.literal.* == .bool_literal) {
                        if (b.pattern.literal.bool_literal.value) has_true = true else has_false = true;
                    }
                }
            }
            if (!has_wildcard) {
                var missing: std.ArrayListUnmanaged([]const u8) = .empty;
                if (!has_true) try missing.append(arena, "True");
                if (!has_false) try missing.append(arena, "False");
                if (missing.items.len > 0) return @as(?[][]const u8, try missing.toOwnedSlice(arena));
            }
            return null;
        },
        .int, .float, .string, .char, .bytes, .unit, .path, .duration, .regex, .decimal_t, .command_t, .datetime_t, .nilable, .list, .set, .stream, .map, .function, .effect_fn, .tuple, .record, .variable, .error_ => {
            var has_wildcard = false;
            for (branches) |b| {
                if (b.pattern == .wildcard) { has_wildcard = true; break; }
                if (b.pattern == .ident) {
                    const name = b.pattern.ident.name;
                    if (name.len > 0 and name[0] >= 'A' and name[0] <= 'Z') continue;
                    has_wildcard = true;
                    break;
                }
            }
            if (!has_wildcard) {
                var missing: std.ArrayListUnmanaged([]const u8) = .empty;
        try missing.append(arena, "_");
        return @as(?[][]const u8, try missing.toOwnedSlice(arena));
            }
            return null;
        },
    }
}

pub fn narrowType(
    pattern: ast.Pattern,
    scrutinee_ty: TypeId,
    env: *TypeEnv,
    allocator: std.mem.Allocator,
) !TypeId {
    _ = allocator;
    const resolved = env.resolveType(scrutinee_ty);

    if (resolved == .nilable) {
        const inner = resolved.nilable;
        if (pattern == .wildcard) return scrutinee_ty;
        if (pattern == .ident) {
            const name = pattern.ident.name;
            if (std.mem.eql(u8, name, "Nil")) return scrutinee_ty;
            if (name.len > 0 and name[0] >= 'a' and name[0] <= 'z') return inner;
        }
        if (pattern == .literal) {
            if (pattern.literal.* == .nil_literal) return scrutinee_ty;
        }
    }

    return scrutinee_ty;
}

