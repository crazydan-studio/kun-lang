const std = @import("std");
const typed = @import("../ast/typed.zig");

const Type = typed.Type;
pub const TypeId = typed.TypeId;

pub const int_type: TypeId = 0;
pub const float_type: TypeId = 1;
pub const bool_type: TypeId = 2;
pub const string_type: TypeId = 3;
pub const char_type: TypeId = 4;
pub const bytes_type: TypeId = 5;
pub const unit_type: TypeId = 6;
pub const path_type: TypeId = 7;
pub const duration_type: TypeId = 8;
pub const regex_type: TypeId = 9;

pub const TypeEnv = struct {
    types: std.ArrayListUnmanaged(Type),
    subst: std.AutoArrayHashMapUnmanaged(TypeId, TypeId),

    pub fn init(allocator: std.mem.Allocator) !TypeEnv {
        var types: std.ArrayListUnmanaged(Type) = .empty;
        try types.append(allocator, .{ .int = {} });
        try types.append(allocator, .{ .float = {} });
        try types.append(allocator, .{ .bool = {} });
        try types.append(allocator, .{ .string = {} });
        try types.append(allocator, .{ .char = {} });
        try types.append(allocator, .{ .bytes = {} });
        try types.append(allocator, .{ .unit = {} });
        try types.append(allocator, .{ .path = {} });
        try types.append(allocator, .{ .duration = {} });
        try types.append(allocator, .{ .regex = {} });

        return TypeEnv{
            .types = types,
            .subst = .empty,
        };
    }

    pub fn deinit(self: *TypeEnv, allocator: std.mem.Allocator) void {
        self.types.deinit(allocator);
        self.subst.deinit(allocator);
    }

    pub fn newVar(self: *TypeEnv, allocator: std.mem.Allocator, level: u32) !TypeId {
        const id: TypeId = @intCast(self.types.items.len);
        try self.types.append(allocator, Type{ .variable = .{ .id = id, .level = level } });
        return id;
    }

    pub fn getType(self: *const TypeEnv, id: TypeId) Type {
        return self.types.items[id];
    }

    pub fn resolveType(self: *const TypeEnv, id: TypeId) Type {
        var current = id;
        for (0..256) |_| {
            if (self.subst.get(current)) |target| {
                current = target;
            } else {
                return self.types.items[current];
            }
        }
        return self.types.items[current];
    }

    pub fn freshInstance(self: *TypeEnv, allocator: std.mem.Allocator, id: TypeId) !TypeId {
        const ty = self.resolveType(id);
        return switch (ty) {
            .variable => |v| {
                const fresh = try self.newVar(allocator, std.math.maxInt(u32));
                _ = v;
                return fresh;
            },
            .function => |f| {
                const p = try self.freshInstance(allocator, f.param);
                const r = try self.freshInstance(allocator, f.result);
                return self.registerFunctionType(allocator, false, p, r);
            },
            .effect_fn => |f| {
                const p = try self.freshInstance(allocator, f.param);
                const r = try self.freshInstance(allocator, f.result);
                return self.registerFunctionType(allocator, true, p, r);
            },
            .nilable => |inner| {
                const i = try self.freshInstance(allocator, inner);
                return self.registerType(allocator, .{ .nilable = i });
            },
            .list => |inner| {
                const i = try self.freshInstance(allocator, inner);
                return self.registerType(allocator, .{ .list = i });
            },
            else => return id,
        };
    }

    pub fn registerType(self: *TypeEnv, allocator: std.mem.Allocator, ty: Type) !TypeId {
        const id: TypeId = @intCast(self.types.items.len);
        try self.types.append(allocator, ty);
        return id;
    }

    pub fn registerFunctionType(
        self: *TypeEnv,
        allocator: std.mem.Allocator,
        is_effect: bool,
        param: TypeId,
        result: TypeId,
    ) !TypeId {
        const id: TypeId = @intCast(self.types.items.len);
        if (is_effect) {
            try self.types.append(allocator, Type{ .effect_fn = .{ .param = param, .result = result } });
        } else {
            try self.types.append(allocator, Type{ .function = .{ .param = param, .result = result } });
        }
        return id;
    }

    pub fn typeName(self: *const TypeEnv, id: TypeId) []const u8 {
        const resolved = self.resolveType(id);
        return @tagName(resolved);
    }

    pub fn applySubst(self: *TypeEnv, ty: TypeId) TypeId {
        var current = ty;
        for (0..256) |_| {
            if (self.subst.get(current)) |target| {
                current = target;
            } else {
                return current;
            }
        }
        return current;
    }
};
