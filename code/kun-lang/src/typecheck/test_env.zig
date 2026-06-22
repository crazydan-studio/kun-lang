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

test "env typeName compound list" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const list_int = try env.registerType(std.testing.allocator, .{ .list = env_mod.int_type });
    try std.testing.expectEqualStrings("List Int", try env.typeName(std.testing.allocator, list_int));
}

test "env typeName compound map" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const map_ty = try env.registerType(std.testing.allocator, .{ .map = .{ .key = env_mod.string_type, .value = env_mod.bool_type } });
    try std.testing.expectEqualStrings("Map String Bool", try env.typeName(std.testing.allocator, map_ty));
}

test "env typeName compound set" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const set_ty = try env.registerType(std.testing.allocator, .{ .set = env_mod.int_type });
    try std.testing.expectEqualStrings("Set Int", try env.typeName(std.testing.allocator, set_ty));
}

test "env typeName compound stream" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const stream_ty = try env.registerType(std.testing.allocator, .{ .stream = env_mod.string_type });
    try std.testing.expectEqualStrings("Stream String", try env.typeName(std.testing.allocator, stream_ty));
}

test "env typeName compound function" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const fn_ty = try env.registerFunctionType(std.testing.allocator, false, env_mod.int_type, env_mod.bool_type);
    try std.testing.expectEqualStrings("Fn(Int, Bool)", try env.typeName(std.testing.allocator, fn_ty));
}

test "env typeName compound effect_fn" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const eff_ty = try env.registerFunctionType(std.testing.allocator, true, env_mod.string_type, env_mod.unit_type);
    try std.testing.expectEqualStrings("EffectFn(String, Unit)", try env.typeName(std.testing.allocator, eff_ty));
}

test "env typeName compound nilable" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const nil_ty = try env.registerType(std.testing.allocator, .{ .nilable = env_mod.int_type });
    try std.testing.expectEqualStrings("?Int", try env.typeName(std.testing.allocator, nil_ty));
}

test "env typeName compound tuple" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const tup_ty = try env.registerType(std.testing.allocator, .{ .tuple = &.{ env_mod.int_type, env_mod.bool_type } });
    try std.testing.expectEqualStrings("(Int, Bool)", try env.typeName(std.testing.allocator, tup_ty));
}

test "env typeName compound record" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const rec_ty = try env.registerType(std.testing.allocator, .{ .record = &.{
        .{ .name = "x", .type_ = env_mod.int_type },
        .{ .name = "y", .type_ = env_mod.bool_type },
    } });
    try std.testing.expectEqualStrings("{ x: Int, y: Bool }", try env.typeName(std.testing.allocator, rec_ty));
}

test "env generalize base type unchanged" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    try std.testing.expectEqual(env_mod.int_type, try env.generalize(std.testing.allocator, env_mod.int_type, 0));
}

test "env generalize variable at higher level becomes polymorphic" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const a = try env.newVar(std.testing.allocator, 5);
    const g = try env.generalize(std.testing.allocator, a, 3);
    try std.testing.expect(a != g);
    try std.testing.expect(env.resolveType(g) == .variable);
    try std.testing.expectEqual(std.math.maxInt(u32), env.resolveType(g).variable.level);
}

test "env generalize variable at same level unchanged" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const a = try env.newVar(std.testing.allocator, 1);
    try std.testing.expectEqual(a, try env.generalize(std.testing.allocator, a, 1));
}

test "env generalize function type" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const a = try env.newVar(std.testing.allocator, 5);
    const b = try env.newVar(std.testing.allocator, 5);
    const fn_ty = try env.registerFunctionType(std.testing.allocator, false, a, b);
    const g = try env.generalize(std.testing.allocator, fn_ty, 3);
    try std.testing.expect(env.resolveType(g) == .function);
}

test "env freshInstance on set type" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const set_int = try env.registerType(std.testing.allocator, .{ .set = env_mod.int_type });
    const fresh = try env.freshInstance(std.testing.allocator, set_int);
    try std.testing.expect(fresh != set_int);
    try std.testing.expect(env.getType(fresh) == .set);
}

test "env freshInstance on stream type" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const s = try env.registerType(std.testing.allocator, .{ .stream = env_mod.string_type });
    const fresh = try env.freshInstance(std.testing.allocator, s);
    try std.testing.expect(fresh != s);
    try std.testing.expect(env.getType(fresh) == .stream);
}

test "env freshInstance on map type" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    const m = try env.registerType(std.testing.allocator, .{ .map = .{ .key = env_mod.string_type, .value = env_mod.int_type } });
    const fresh = try env.freshInstance(std.testing.allocator, m);
    try std.testing.expect(fresh != m);
    try std.testing.expect(env.getType(fresh) == .map);
}

test "env decimal_type constant" {
    try std.testing.expectEqual(@as(TypeId, 10), env_mod.decimal_type);
}

test "env command_type constant" {
    try std.testing.expectEqual(@as(TypeId, 11), env_mod.command_type);
}

test "env datetime_type constant" {
    try std.testing.expectEqual(@as(TypeId, 12), env_mod.datetime_type);
}
