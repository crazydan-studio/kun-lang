const std = @import("std");
const primitive = @import("primitive.zig");
const typed = @import("../ast/typed.zig");
const env_mod = @import("../typecheck/env.zig");

test "primitive table builds at comptime" {
    const int_t = env_mod.int_type;
    const string_t = env_mod.string_type;
    const unit_t = env_mod.unit_type;
    const stream_str = env_mod.string_type;
    const table = primitive.buildPrimitiveTable(int_t, string_t, unit_t, stream_str);
    try std.testing.expect(table.bindings.len >= 2);
}

test "primitive is_effect query" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type);
    try std.testing.expect(table.bindings[0].is_effect == true);
    try std.testing.expect(table.bindings[1].is_effect == true);
}

test "primitive println outputs to stdout" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type);
    try std.testing.expect(table.bindings[0].module[0] == 'I');
    try std.testing.expect(table.bindings[0].module[1] == 'O');
    try std.testing.expect(std.mem.eql(u8, table.bindings[0].name, "println"));
    try std.testing.expect(std.mem.eql(u8, table.bindings[1].name, "readln"));
}
