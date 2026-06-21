const std = @import("std");
const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");

pub fn checkExhaustive(
    allocator: std.mem.Allocator,
    scrutinee_ty: typed.TypeId,
    branches: []const typed.Branch,
) !?[][]const u8 {
    _ = allocator;
    _ = scrutinee_ty;
    if (branches.len == 0) {
        var missing = std.ArrayList([]const u8).init(allocator);
        try missing.append("_");
        return try missing.toOwnedSlice();
    }

    var has_wildcard = false;
    for (branches) |b| {
        if (b.pattern == .wildcard) {
            has_wildcard = true;
            break;
        }
        if (b.pattern == .ident) {
            const name = b.pattern.ident.name;
            if (name.len > 0 and name[0] >= 'A' and name[0] <= 'Z') continue;
            has_wildcard = true;
            break;
        }
    }

    if (!has_wildcard) {
        var missing = std.ArrayList([]const u8).init(allocator);
        try missing.append("_");
        return try missing.toOwnedSlice();
    }
    return null;
}

pub fn narrowType(
    pattern: ast.Pattern,
    scrutinee_ty: typed.TypeId,
    env: anytype,
    allocator: std.mem.Allocator,
) !typed.TypeId {
    _ = env;
    _ = allocator;
    return switch (pattern) {
        .wildcard => scrutinee_ty,
        .literal => scrutinee_ty,
        .ident => scrutinee_ty,
        .variant => scrutinee_ty,
        .list => scrutinee_ty,
        .tuple => scrutinee_ty,
        .record => scrutinee_ty,
        .guard => |g| narrowType(g.inner.*, scrutinee_ty, env, allocator),
    };
}
