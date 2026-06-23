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

pub const decimal_type: TypeId = 10;
pub const command_type: TypeId = 11;
pub const datetime_type: TypeId = 12;

pub const TypeEnv = struct {
    types: std.ArrayListUnmanaged(Type),
    subst: std.AutoArrayHashMapUnmanaged(TypeId, TypeId),
    _allocator: std.mem.Allocator,
    expr_arena: std.heap.ArenaAllocator,

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
        try types.append(allocator, .{ .decimal_t = {} });
        try types.append(allocator, .{ .command_t = {} });
        try types.append(allocator, .{ .datetime_t = {} });

        return TypeEnv{
            .types = types,
            .subst = .empty,
            ._allocator = allocator,
            .expr_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *TypeEnv, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.types.deinit(self._allocator);
        self.subst.deinit(self._allocator);
        self.expr_arena.deinit();
    }

    pub fn exprAllocator(self: *TypeEnv) std.mem.Allocator {
        return self.expr_arena.allocator();
    }

    pub fn newVar(self: *TypeEnv, allocator: std.mem.Allocator, level: u32) !TypeId {
        _ = allocator;
        const id: TypeId = @intCast(self.types.items.len);
        try self.types.append(self._allocator, Type{ .variable = .{ .id = id, .level = level } });
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
        var map: std.AutoHashMapUnmanaged(TypeId, TypeId) = .empty;
        defer map.deinit(allocator);
        return self.freshInstanceMapped(allocator, id, &map);
    }

    fn freshInstanceMapped(self: *TypeEnv, allocator: std.mem.Allocator, id: TypeId, map: *std.AutoHashMapUnmanaged(TypeId, TypeId)) !TypeId {
        const resolved = self.applySubst(id);
        if (map.get(resolved)) |existing| return existing;
        const ty = self.resolveType(resolved);
        const result = switch (ty) {
            .variable => try self.newVar(allocator, std.math.maxInt(u32)),
            .function => |f| {
                const p = try self.freshInstanceMapped(allocator, f.param, map);
                const r = try self.freshInstanceMapped(allocator, f.result, map);
                return self.registerFunctionType(allocator, false, p, r);
            },
            .effect_fn => |f| {
                const p = try self.freshInstanceMapped(allocator, f.param, map);
                const r = try self.freshInstanceMapped(allocator, f.result, map);
                return self.registerFunctionType(allocator, true, p, r);
            },
            .nilable => |inner| {
                const i = try self.freshInstanceMapped(allocator, inner, map);
                return self.registerType(allocator, .{ .nilable = i });
            },
            .list => |inner| {
                const i = try self.freshInstanceMapped(allocator, inner, map);
                return self.registerType(allocator, .{ .list = i });
            },
            .set => |inner| {
                const i = try self.freshInstanceMapped(allocator, inner, map);
                return self.registerType(allocator, .{ .set = i });
            },
            .stream => |inner| {
                const i = try self.freshInstanceMapped(allocator, inner, map);
                return self.registerType(allocator, .{ .stream = i });
            },
            .map => |m| {
                const k = try self.freshInstanceMapped(allocator, m.key, map);
                const v = try self.freshInstanceMapped(allocator, m.value, map);
                return self.registerType(allocator, .{ .map = .{ .key = k, .value = v } });
            },
            .tuple => |t| {
                var new_elems = try allocator.alloc(TypeId, t.len);
                for (t, 0..) |elem, i| {
                    new_elems[i] = try self.freshInstanceMapped(allocator, elem, map);
                }
                return self.registerType(allocator, .{ .tuple = new_elems });
            },
            .record => |r| {
                var new_fields = try allocator.alloc(typed.RecordFieldType, r.len);
                for (r, 0..) |f, i| {
                    new_fields[i] = .{ .name = f.name, .type_ = try self.freshInstanceMapped(allocator, f.type_, map) };
                }
                return self.registerType(allocator, .{ .record = new_fields });
            },
            .adt => |a| {
                var new_variants = try allocator.alloc(typed.AdtVariant, a.variants.len);
                for (a.variants, 0..) |v, i| {
                    var new_payload = try allocator.alloc(TypeId, v.payload.len);
                    for (v.payload, 0..) |pt, j| {
                        new_payload[j] = try self.freshInstanceMapped(allocator, pt, map);
                    }
                    new_variants[i] = .{ .name = v.name, .payload = new_payload };
                }
                return self.registerType(allocator, .{ .adt = .{ .name = a.name, .variants = new_variants } });
            },
            else => return id,
        };
        try map.put(allocator, resolved, result);
        return result;
    }

    pub fn generalize(self: *TypeEnv, allocator: std.mem.Allocator, id: TypeId, level: u32) !TypeId {
        const ty = self.resolveType(id);
        return switch (ty) {
            .variable => |v| {
                if (v.level >= std.math.maxInt(u32)) return id;
                if (v.level > level) {
                    const polymorphic = try self.newVar(allocator, std.math.maxInt(u32));
                    try self.subst.put(allocator, id, polymorphic);
                    return polymorphic;
                }
                return id;
            },
            .function => |f| {
                const p = try self.generalize(allocator, f.param, level);
                const r = try self.generalize(allocator, f.result, level);
                return self.registerFunctionType(allocator, false, p, r);
            },
            .effect_fn => |f| {
                const p = try self.generalize(allocator, f.param, level);
                const r = try self.generalize(allocator, f.result, level);
                return self.registerFunctionType(allocator, true, p, r);
            },
            .nilable => |inner| {
                const i = try self.generalize(allocator, inner, level);
                return self.registerType(allocator, .{ .nilable = i });
            },
            .list => |inner| {
                const i = try self.generalize(allocator, inner, level);
                return self.registerType(allocator, .{ .list = i });
            },
            .set => |inner| {
                const i = try self.generalize(allocator, inner, level);
                return self.registerType(allocator, .{ .set = i });
            },
            .stream => |inner| {
                const i = try self.generalize(allocator, inner, level);
                return self.registerType(allocator, .{ .stream = i });
            },
            .map => |m| {
                const k = try self.generalize(allocator, m.key, level);
                const v = try self.generalize(allocator, m.value, level);
                return self.registerType(allocator, .{ .map = .{ .key = k, .value = v } });
            },
            .tuple => |t| {
                var elems: std.ArrayListUnmanaged(TypeId) = .empty;
                defer elems.deinit(self._allocator);
                for (t) |ti| {
                    const gi = try self.generalize(allocator, ti, level);
                    try elems.append(self._allocator, gi);
                }
                return self.registerType(allocator, .{ .tuple = try elems.toOwnedSlice(self._allocator) });
            },
            .record => |r| {
                var fields: std.ArrayListUnmanaged(typed.RecordFieldType) = .empty;
                defer fields.deinit(self._allocator);
                for (r) |f| {
                    const gf = try self.generalize(allocator, f.type_, level);
                    try fields.append(self._allocator, .{ .name = f.name, .type_ = gf });
                }
                return self.registerType(allocator, .{ .record = try fields.toOwnedSlice(self._allocator) });
            },
            .adt => |a| {
                var variants: std.ArrayListUnmanaged(typed.AdtVariant) = .empty;
                defer variants.deinit(self._allocator);
                for (a.variants) |va| {
                    var payload: std.ArrayListUnmanaged(TypeId) = .empty;
                    defer payload.deinit(self._allocator);
                    for (va.payload) |p| {
                        const gp = try self.generalize(allocator, p, level);
                        try payload.append(self._allocator, gp);
                    }
                    try variants.append(self._allocator, .{ .name = va.name, .payload = try payload.toOwnedSlice(self._allocator) });
                }
                return self.registerType(allocator, .{ .adt = .{ .name = a.name, .variants = try variants.toOwnedSlice(self._allocator) } });
            },
            else => return id,
        };
    }

    pub fn registerType(self: *TypeEnv, allocator: std.mem.Allocator, ty: Type) !TypeId {
        _ = allocator;
        const id: TypeId = @intCast(self.types.items.len);
        try self.types.append(self._allocator, ty);
        return id;
    }

    pub fn registerFunctionType(
        self: *TypeEnv,
        allocator: std.mem.Allocator,
        is_effect: bool,
        param: TypeId,
        result: TypeId,
    ) !TypeId {
        _ = allocator;
        const id: TypeId = @intCast(self.types.items.len);
        if (is_effect) {
            try self.types.append(self._allocator, Type{ .effect_fn = .{ .param = param, .result = result } });
        } else {
            try self.types.append(self._allocator, Type{ .function = .{ .param = param, .result = result } });
        }
        return id;
    }

    pub fn typeName(self: *TypeEnv, allocator: std.mem.Allocator, id: TypeId) ![]const u8 {
        _ = allocator;
        const arena = self.expr_arena.allocator();
        const resolved = self.resolveType(id);
        return switch (resolved) {
            .int => "Int",
            .float => "Float",
            .bool => "Bool",
            .string => "String",
            .char => "Char",
            .bytes => "Bytes",
            .unit => "Unit",
            .path => "Path",
            .duration => "Duration",
            .regex => "Regex",
            .decimal_t => "Decimal",
            .command_t => "Command",
            .datetime_t => "DateTime",
            .nilable => |inner| {
                const inner_name = try self.typeName(arena, inner);
                return std.fmt.allocPrint(arena, "?{s}", .{inner_name});
            },
            .list => |inner| {
                const inner_name = try self.typeName(arena, inner);
                return std.fmt.allocPrint(arena, "List {s}", .{inner_name});
            },
            .set => |inner| {
                const inner_name = try self.typeName(arena, inner);
                return std.fmt.allocPrint(arena, "Set {s}", .{inner_name});
            },
            .stream => |inner| {
                const inner_name = try self.typeName(arena, inner);
                return std.fmt.allocPrint(arena, "Stream {s}", .{inner_name});
            },
            .map => |m| {
                const key_name = try self.typeName(arena, m.key);
                const val_name = try self.typeName(arena, m.value);
                return std.fmt.allocPrint(arena, "Map {s} {s}", .{ key_name, val_name });
            },
            .function => |f| {
                const param_name = try self.typeName(arena, f.param);
                const result_name = try self.typeName(arena, f.result);
                return std.fmt.allocPrint(arena, "Fn({s}, {s})", .{ param_name, result_name });
            },
            .effect_fn => |f| {
                const param_name = try self.typeName(arena, f.param);
                const result_name = try self.typeName(arena, f.result);
                return std.fmt.allocPrint(arena, "EffectFn({s}, {s})", .{ param_name, result_name });
            },
            .tuple => |t| {
                var result: []const u8 = "(";
                for (t, 0..) |ti, i| {
                    const name = try self.typeName(arena, ti);
                    if (i == 0) {
                        result = try std.fmt.allocPrint(arena, "({s}", .{name});
                    } else {
                        result = try std.fmt.allocPrint(arena, "{s}, {s}", .{ result, name });
                    }
                }
                return try std.fmt.allocPrint(arena, "{s})", .{result});
            },
            .record => |r| {
                var result: []const u8 = "{";
                for (r, 0..) |f, i| {
                    const name = try self.typeName(arena, f.type_);
                    if (i == 0) {
                        result = try std.fmt.allocPrint(arena, "{{ {s}: {s}", .{ f.name, name });
                    } else {
                        result = try std.fmt.allocPrint(arena, "{s}, {s}: {s}", .{ result, f.name, name });
                    }
                }
                return try std.fmt.allocPrint(arena, "{s} }}", .{result});
            },
            .adt => |a| {
                return std.fmt.allocPrint(arena, "{s}", .{a.name});
            },
            .variable => |v| {
                return std.fmt.allocPrint(arena, "a{d}", .{v.id});
            },
            .error_ => "Error",
        };
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
