const std = @import("std");
const nilable = @import("nilable.zig");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const RuntimeEnv = @import("../runtime/primitive.zig").RuntimeEnv;
const env_mod = @import("../typecheck/env.zig");
const primitive_mod = @import("../runtime/primitive.zig");

fn emptyEnv() RuntimeEnv {
    const pt = primitive_mod.buildPrimitiveTable(
        env_mod.int_type, env_mod.string_type, env_mod.unit_type,
        env_mod.string_type, env_mod.bool_type, env_mod.bytes_type,
    );
    return RuntimeEnv.init(undefined, pt, std.testing.allocator);
}

test "nilable isNil" {
    const env = emptyEnv();
    try std.testing.expect(nilable.isNilImpl(@constCast(&env), &.{Value{ .nil = {} }}).bool);
    try std.testing.expect(!nilable.isNilImpl(@constCast(&env), &.{Value{ .int = 42 }}).bool);
}

test "nilable isSome" {
    const env = emptyEnv();
    try std.testing.expect(!nilable.isSomeImpl(@constCast(&env), &.{Value{ .nil = {} }}).bool);
    try std.testing.expect(nilable.isSomeImpl(@constCast(&env), &.{Value{ .int = 42 }}).bool);
}

test "nilable withDefault" {
    const env = emptyEnv();
    const result = nilable.withDefaultImpl(@constCast(&env), &.{ Value{ .int = 0 }, Value{ .nil = {} } });
    try std.testing.expectEqual(@as(i64, 0), result.int);
    const present = nilable.withDefaultImpl(@constCast(&env), &.{ Value{ .int = 0 }, Value{ .int = 42 } });
    try std.testing.expectEqual(@as(i64, 42), present.int);
}

test "nilable orElse" {
    const env = emptyEnv();
    const result = nilable.orElseImpl(@constCast(&env), &.{ Value{ .nil = {} }, Value{ .int = 42 } });
    try std.testing.expectEqual(@as(i64, 42), result.int);
    const first = nilable.orElseImpl(@constCast(&env), &.{ Value{ .int = 1 }, Value{ .int = 2 } });
    try std.testing.expectEqual(@as(i64, 1), first.int);
}
