const std = @import("std");
const float_mod = @import("float.zig");
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

test "float pi and e" {
    const env = emptyEnv();
    try std.testing.expect(float_mod.piImpl(@constCast(&env), &.{}).float > 3.14);
    try std.testing.expect(float_mod.eImpl(@constCast(&env), &.{}).float > 2.71);
}

test "float abs" {
    const env = emptyEnv();
    try std.testing.expectEqual(@as(f64, 3.14), float_mod.absImpl(@constCast(&env), &.{Value{ .float = -3.14 }}).float);
}

test "float floor ceil round" {
    const env = emptyEnv();
    try std.testing.expectEqual(@as(f64, 3.0), float_mod.floorImpl(@constCast(&env), &.{Value{ .float = 3.7 }}).float);
    try std.testing.expectEqual(@as(f64, 4.0), float_mod.ceilImpl(@constCast(&env), &.{Value{ .float = 3.1 }}).float);
    try std.testing.expectEqual(@as(f64, 4.0), float_mod.roundImpl(@constCast(&env), &.{Value{ .float = 3.7 }}).float);
}

test "float min max clamp" {
    const env = emptyEnv();
    try std.testing.expectEqual(@as(f64, 3.0), float_mod.minImpl(@constCast(&env), &.{ Value{ .float = 3 }, Value{ .float = 7 } }).float);
    try std.testing.expectEqual(@as(f64, 7.0), float_mod.maxImpl(@constCast(&env), &.{ Value{ .float = 3 }, Value{ .float = 7 } }).float);
    try std.testing.expectEqual(@as(f64, 5.0), float_mod.clampImpl(@constCast(&env), &.{ Value{ .float = 10 }, Value{ .float = 0 }, Value{ .float = 5 } }).float);
}

test "float toInt" {
    const env = emptyEnv();
    const result = float_mod.toIntImpl(@constCast(&env), &.{Value{ .float = 3.7 }});
    try std.testing.expectEqual(@as(i64, 3), result.int);
}
