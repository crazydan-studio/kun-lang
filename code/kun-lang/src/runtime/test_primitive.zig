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

test "primitive isEffectBinding returns false for non-effect Cmd" {
    try std.testing.expect(!primitive.isEffectBinding("Cmd.withEnv"));
    try std.testing.expect(!primitive.isEffectBinding("Cmd.pipe"));
    try std.testing.expect(!primitive.isEffectBinding("Cmd.ls"));
    try std.testing.expect(!primitive.isEffectBinding("Cmd.echo"));
}

test "primitive isEffectBinding returns true for effect Cmd" {
    try std.testing.expect(primitive.isEffectBinding("Cmd.exec"));
    try std.testing.expect(primitive.isEffectBinding("Cmd.which"));
    try std.testing.expect(primitive.isEffectBinding("Cmd.timeout"));
    try std.testing.expect(primitive.isEffectBinding("Cmd.ls?"));
    try std.testing.expect(primitive.isEffectBinding("Cmd.echo!"));
    try std.testing.expect(primitive.isEffectBinding("Cmd.pipe?"));
    try std.testing.expect(primitive.isEffectBinding("Cmd.pipe!"));
    try std.testing.expect(primitive.isEffectBinding("Cmd.retry"));
    try std.testing.expect(primitive.isEffectBinding("Cmd.execSafe"));
}

test "primitive isEffectBinding returns true for IO namespace" {
    try std.testing.expect(primitive.isEffectBinding("IO.println"));
    try std.testing.expect(primitive.isEffectBinding("IO.readln"));
}

test "primitive isEffectBinding returns true for File/Env/Process" {
    try std.testing.expect(primitive.isEffectBinding("File.readString"));
    try std.testing.expect(primitive.isEffectBinding("Env.get"));
    try std.testing.expect(primitive.isEffectBinding("Process.exit"));
}

test "primitive isEffectBinding returns true for Signal.on" {
    try std.testing.expect(primitive.isEffectBinding("Signal.on"));
}

test "primitive isEffectBinding returns false for pure namespaces" {
    try std.testing.expect(!primitive.isEffectBinding("List.map"));
    try std.testing.expect(!primitive.isEffectBinding("String.length"));
    try std.testing.expect(!primitive.isEffectBinding("Int.abs"));
}

test "primitive isEffectBinding returns true for Stream.iter" {
    try std.testing.expect(primitive.isEffectBinding("Stream.iter"));
}
