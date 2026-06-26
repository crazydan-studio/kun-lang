const std = @import("std");
const char_mod = @import("char.zig");
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

test "char isDigit" {
    const env = emptyEnv();
    try std.testing.expect(char_mod.isDigitImpl(@constCast(&env), &.{Value{ .char = '5' }}).bool);
    try std.testing.expect(!char_mod.isDigitImpl(@constCast(&env), &.{Value{ .char = 'a' }}).bool);
}

test "char isAlpha" {
    const env = emptyEnv();
    try std.testing.expect(char_mod.isAlphaImpl(@constCast(&env), &.{Value{ .char = 'a' }}).bool);
    try std.testing.expect(!char_mod.isAlphaImpl(@constCast(&env), &.{Value{ .char = '5' }}).bool);
}

test "char isUpper isLower" {
    const env = emptyEnv();
    try std.testing.expect(char_mod.isUpperImpl(@constCast(&env), &.{Value{ .char = 'A' }}).bool);
    try std.testing.expect(char_mod.isLowerImpl(@constCast(&env), &.{Value{ .char = 'a' }}).bool);
}

test "char toUpper toLower" {
    const env = emptyEnv();
    try std.testing.expectEqual(@as(u32, 'A'), char_mod.toUpperImpl(@constCast(&env), &.{Value{ .char = 'a' }}).char);
    try std.testing.expectEqual(@as(u32, 'a'), char_mod.toLowerImpl(@constCast(&env), &.{Value{ .char = 'A' }}).char);
}

test "char toInt" {
    const env = emptyEnv();
    try std.testing.expectEqual(@as(i64, 65), char_mod.toIntImpl(@constCast(&env), &.{Value{ .char = 'A' }}).int);
}
