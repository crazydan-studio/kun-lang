const std = @import("std");
const validator = @import("validator.zig");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const RuntimeEnv = @import("../runtime/primitive.zig").RuntimeEnv;
const env_mod = @import("../typecheck/env.zig");
const primitive_mod = @import("../runtime/primitive.zig");

test "validator nonEmpty returns nil for empty input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const pt = primitive_mod.buildPrimitiveTable(
        env_mod.int_type, env_mod.string_type, env_mod.unit_type,
        env_mod.string_type, env_mod.bool_type, env_mod.bytes_type,
    );
    const env = RuntimeEnv.init(undefined, pt, arena.allocator());
    const result = validator.nonEmptyImpl(@constCast(&env), &.{Value{ .string = "" }});
    try std.testing.expect(result == .adt);
    try std.testing.expect(result.adt.tag != 0);
}
