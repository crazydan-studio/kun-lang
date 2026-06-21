const std = @import("std");
const env_mod = @import("env.zig");
const unify_mod = @import("unify.zig");
const TypeEnv = env_mod.TypeEnv;

test "unify same base types" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    try unify_mod.unify(&env, std.testing.allocator, env_mod.int_type, env_mod.int_type);
}

test "unify different base types" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);
    try std.testing.expectError(error.Mismatch, unify_mod.unify(&env, std.testing.allocator, env_mod.int_type, env_mod.bool_type));
}

test "unify variable with base type" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const a = try env.newVar(std.testing.allocator, 1);
    try unify_mod.unify(&env, std.testing.allocator, a, env_mod.int_type);
    try std.testing.expectEqual(env_mod.int_type, env.applySubst(a));
}

test "unify two variables" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const a = try env.newVar(std.testing.allocator, 1);
    const b = try env.newVar(std.testing.allocator, 2);
    try unify_mod.unify(&env, std.testing.allocator, a, b);
}

test "unify nilable types" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const a = try env.newVar(std.testing.allocator, 1);
    const nil_a = try env.registerType(std.testing.allocator, .{ .nilable = a });
    const nil_int = try env.registerType(std.testing.allocator, .{ .nilable = env_mod.int_type });

    try unify_mod.unify(&env, std.testing.allocator, nil_a, nil_int);
    try std.testing.expectEqual(env_mod.int_type, env.applySubst(a));
}

test "unify nilable with base type errors" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const a = try env.newVar(std.testing.allocator, 1);
    const nil_a = try env.registerType(std.testing.allocator, .{ .nilable = a });

    try std.testing.expectError(error.NilToNonNilable, unify_mod.unify(&env, std.testing.allocator, nil_a, env_mod.int_type));
    try std.testing.expectError(error.NilToNonNilable, unify_mod.unify(&env, std.testing.allocator, env_mod.int_type, nil_a));
}

test "unify function types" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const fn1 = try env.registerFunctionType(std.testing.allocator, false, env_mod.int_type, env_mod.bool_type);
    const a = try env.newVar(std.testing.allocator, 1);
    const b = try env.newVar(std.testing.allocator, 2);
    const fn2 = try env.registerFunctionType(std.testing.allocator, false, a, b);

    try unify_mod.unify(&env, std.testing.allocator, fn1, fn2);
    try std.testing.expectEqual(env_mod.int_type, env.applySubst(a));
    try std.testing.expectEqual(env_mod.bool_type, env.applySubst(b));
}

test "unify effect_fn with function errors" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const pure_fn = try env.registerFunctionType(std.testing.allocator, false, env_mod.int_type, env_mod.int_type);
    const eff = try env.registerFunctionType(std.testing.allocator, true, env_mod.int_type, env_mod.int_type);

    try std.testing.expectError(error.EffectFnPureMismatch, unify_mod.unify(&env, std.testing.allocator, pure_fn, eff));
    try std.testing.expectError(error.EffectFnPureMismatch, unify_mod.unify(&env, std.testing.allocator, eff, pure_fn));
}

test "unify list types" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const list_int = try env.registerType(std.testing.allocator, .{ .list = env_mod.int_type });
    const a = try env.newVar(std.testing.allocator, 1);
    const list_a = try env.registerType(std.testing.allocator, .{ .list = a });

    try unify_mod.unify(&env, std.testing.allocator, list_int, list_a);
    try std.testing.expectEqual(env_mod.int_type, env.applySubst(a));
}

test "unify occurs check prevents infinite type" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const a = try env.newVar(std.testing.allocator, 1);
    const list_a = try env.registerType(std.testing.allocator, .{ .list = a });

    try std.testing.expectError(error.InfiniteType, unify_mod.unify(&env, std.testing.allocator, a, list_a));
}

test "unify tuple types" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const t1 = try env.registerType(std.testing.allocator, .{ .tuple = &.{ env_mod.int_type, env_mod.bool_type } });
    const a = try env.newVar(std.testing.allocator, 1);
    const t2 = try env.registerType(std.testing.allocator, .{ .tuple = &.{ env_mod.int_type, a } });

    try unify_mod.unify(&env, std.testing.allocator, t1, t2);
    try std.testing.expectEqual(env_mod.bool_type, env.applySubst(a));
}

test "unify tuple length mismatch" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const t1 = try env.registerType(std.testing.allocator, .{ .tuple = &.{ env_mod.int_type, env_mod.bool_type } });
    const t2 = try env.registerType(std.testing.allocator, .{ .tuple = &.{ env_mod.int_type } });

    try std.testing.expectError(error.TupleLengthMismatch, unify_mod.unify(&env, std.testing.allocator, t1, t2));
}

test "unify record types" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const r1 = try env.registerType(std.testing.allocator, .{ .record = &.{
        .{ .name = "x", .type_ = env_mod.int_type },
        .{ .name = "y", .type_ = env_mod.bool_type },
    } });
    const r2 = try env.registerType(std.testing.allocator, .{ .record = &.{
        .{ .name = "x", .type_ = env_mod.int_type },
        .{ .name = "y", .type_ = env_mod.bool_type },
    } });

    try unify_mod.unify(&env, std.testing.allocator, r1, r2);
}

test "unify record field name mismatch" {
    var env = try TypeEnv.init(std.testing.allocator);
    defer env.deinit(std.testing.allocator);

    const r1 = try env.registerType(std.testing.allocator, .{ .record = &.{
        .{ .name = "x", .type_ = env_mod.int_type },
    } });
    const r2 = try env.registerType(std.testing.allocator, .{ .record = &.{
        .{ .name = "y", .type_ = env_mod.int_type },
    } });

    try std.testing.expectError(error.RecordFieldMismatch, unify_mod.unify(&env, std.testing.allocator, r1, r2));
}
