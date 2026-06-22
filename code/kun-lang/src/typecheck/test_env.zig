const std = @import("std");
const env_mod = @import("env.zig");
const TypeEnv = env_mod.TypeEnv;
const TypeId = env_mod.TypeId;

test "env init has 13 built-in types" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 13), env.types.items.len);
    try std.testing.expect(env.getType(0) == .int);
    try std.testing.expect(env.getType(1) == .float);
    try std.testing.expect(env.getType(2) == .bool);
    try std.testing.expect(env.getType(3) == .string);
    try std.testing.expect(env.getType(4) == .char);
    try std.testing.expect(env.getType(5) == .bytes);
    try std.testing.expect(env.getType(6) == .unit);
    try std.testing.expect(env.getType(7) == .path);
    try std.testing.expect(env.getType(8) == .duration);
    try std.testing.expect(env.getType(9) == .regex);
    try std.testing.expect(env.getType(10) == .decimal_t);
    try std.testing.expect(env.getType(11) == .command_t);
    try std.testing.expect(env.getType(12) == .datetime_t);
}

test "env built-in type constants" {
    try std.testing.expectEqual(env_mod.int_type, @as(TypeId, 0));
    try std.testing.expectEqual(env_mod.float_type, @as(TypeId, 1));
    try std.testing.expectEqual(env_mod.bool_type, @as(TypeId, 2));
    try std.testing.expectEqual(env_mod.string_type, @as(TypeId, 3));
    try std.testing.expectEqual(env_mod.char_type, @as(TypeId, 4));
    try std.testing.expectEqual(env_mod.bytes_type, @as(TypeId, 5));
    try std.testing.expectEqual(env_mod.unit_type, @as(TypeId, 6));
    try std.testing.expectEqual(env_mod.path_type, @as(TypeId, 7));
    try std.testing.expectEqual(env_mod.duration_type, @as(TypeId, 8));
    try std.testing.expectEqual(env_mod.regex_type, @as(TypeId, 9));
}

test "env newVar creates fresh type variable" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const a = try env.newVar(std.testing.allocator, 1);
    const b = try env.newVar(std.testing.allocator, 2);

    try std.testing.expect(a != b);
    try std.testing.expectEqual(@as(usize, 15), env.types.items.len);

    const ta = env.getType(a);
    try std.testing.expect(ta == .variable);
    try std.testing.expectEqual(@as(u32, 1), ta.variable.level);

    const tb = env.getType(b);
    try std.testing.expectEqual(@as(u32, 2), tb.variable.level);
}

test "env registerType" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const a = try env.newVar(std.testing.allocator, 1);
    const nil_id = try env.registerType(std.testing.allocator, .{ .nilable = a });
    try std.testing.expect(nil_id >= 10);
    try std.testing.expect(env.getType(nil_id) == .nilable);
}

test "env registerFunctionType" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const fn_id = try env.registerFunctionType(std.testing.allocator, false, env_mod.int_type, env_mod.bool_type);
    try std.testing.expect(fn_id >= 10);
    try std.testing.expect(env.getType(fn_id) == .function);
    try std.testing.expectEqual(env_mod.int_type, env.getType(fn_id).function.param);
    try std.testing.expectEqual(env_mod.bool_type, env.getType(fn_id).function.result);

    const eff_id = try env.registerFunctionType(std.testing.allocator, true, env_mod.string_type, env_mod.unit_type);
    try std.testing.expect(env.getType(eff_id) == .effect_fn);
}

test "env resolveType follows substitution chain" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const a = try env.newVar(std.testing.allocator, 1);
    try env.subst.put(std.testing.allocator, a, env_mod.int_type);

    try std.testing.expectEqual(env_mod.int_type, env.applySubst(a));
    try std.testing.expect(env.getType(env.applySubst(a)) == .int);
}

test "env typeName" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("Int", try env.typeName(std.testing.allocator, env_mod.int_type));
    try std.testing.expectEqualStrings("Bool", try env.typeName(std.testing.allocator, env_mod.bool_type));
    try std.testing.expectEqualStrings("String", try env.typeName(std.testing.allocator, env_mod.string_type));
    try std.testing.expectEqualStrings("Decimal", try env.typeName(std.testing.allocator, env_mod.decimal_type));
    try std.testing.expectEqualStrings("Command", try env.typeName(std.testing.allocator, env_mod.command_type));
}

test "env freshInstance on base type returns same" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const fresh = try env.freshInstance(std.testing.allocator, env_mod.int_type);
    try std.testing.expectEqual(env_mod.int_type, fresh);
}

test "env freshInstance on variable creates new" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const a = try env.newVar(std.testing.allocator, 1);
    const fresh = try env.freshInstance(std.testing.allocator, a);
    try std.testing.expect(a != fresh);
    try std.testing.expect(env.getType(fresh) == .variable);
}

test "env freshInstance on function creates fresh inner types" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const fn_id = try env.registerFunctionType(std.testing.allocator, false, env_mod.int_type, env_mod.bool_type);
    const fresh = try env.freshInstance(std.testing.allocator, fn_id);
    try std.testing.expect(fresh != fn_id);
    try std.testing.expect(env.getType(fresh) == .function);
}
