const std = @import("std");
const duration = @import("duration.zig");
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

test "duration toNanos" {
    const env = emptyEnv();
    const args = [_]Value{Value{ .duration = 5000000000 }};
    const result = duration.toNanosImpl(@constCast(&env), &args);
    try std.testing.expectEqual(@as(i64, 5000000000), result.int);
}

test "duration toSeconds" {
    const env = emptyEnv();
    const args = [_]Value{Value{ .duration = 5000000000 }};
    const result = duration.toSecondsImpl(@constCast(&env), &args);
    try std.testing.expectEqual(@as(i64, 5), result.int);
}

test "duration negate" {
    const env = emptyEnv();
    const args = [_]Value{Value{ .duration = 5000000000 }};
    const result = duration.negateImpl(@constCast(&env), &args);
    try std.testing.expectEqual(@as(i64, -5000000000), result.duration);
}

test "duration isNegative" {
    const env = emptyEnv();
    const pos = [_]Value{Value{ .duration = 5000000000 }};
    try std.testing.expectEqual(false, duration.isNegativeImpl(@constCast(&env), &pos).bool);
    const neg = [_]Value{Value{ .duration = -5000000000 }};
    try std.testing.expectEqual(true, duration.isNegativeImpl(@constCast(&env), &neg).bool);
}

test "duration abs" {
    const env = emptyEnv();
    const args = [_]Value{Value{ .duration = -5000000000 }};
    const result = duration.absImpl(@constCast(&env), &args);
    try std.testing.expectEqual(@as(i64, 5000000000), result.duration);
}
