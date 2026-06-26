const std = @import("std");
const datetime_fmt = @import("datetime_fmt.zig");
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

test "datetime now returns positive value" {
    const env = emptyEnv();
    const result = datetime_fmt.nowImpl(@constCast(&env), &.{});
    try std.testing.expect(result == .int);
    try std.testing.expect(result.int > 0);
}
