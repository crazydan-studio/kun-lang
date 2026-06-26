const std = @import("std");
const int_mod = @import("int.zig");
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

test "int abs" {
    const env = emptyEnv();
    try std.testing.expectEqual(@as(i64, 42), int_mod.absImpl(@constCast(&env), &.{Value{ .int = -42 }}).int);
    try std.testing.expectEqual(@as(i64, 42), int_mod.absImpl(@constCast(&env), &.{Value{ .int = 42 }}).int);
}

test "int min" {
    const env = emptyEnv();
    const result = int_mod.minImpl(@constCast(&env), &.{ Value{ .int = 5 }, Value{ .int = 10 } });
    try std.testing.expectEqual(@as(i64, 5), result.int);
}

test "int max" {
    const env = emptyEnv();
    const result = int_mod.maxImpl(@constCast(&env), &.{ Value{ .int = 5 }, Value{ .int = 10 } });
    try std.testing.expectEqual(@as(i64, 10), result.int);
}

test "int clamp" {
    const env = emptyEnv();
    const result = int_mod.clampImpl(@constCast(&env), &.{ Value{ .int = 50 }, Value{ .int = 0 }, Value{ .int = 100 } });
    try std.testing.expectEqual(@as(i64, 50), result.int);
    const clamped = int_mod.clampImpl(@constCast(&env), &.{ Value{ .int = 150 }, Value{ .int = 0 }, Value{ .int = 100 } });
    try std.testing.expectEqual(@as(i64, 100), clamped.int);
}

test "int toFloat" {
    const env = emptyEnv();
    const result = int_mod.toFloatImpl(@constCast(&env), &.{Value{ .int = 42 }});
    try std.testing.expectEqual(@as(f64, 42.0), result.float);
}
