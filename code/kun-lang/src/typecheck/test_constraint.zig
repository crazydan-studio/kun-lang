const std = @import("std");
const env_mod = @import("env.zig");
const constraint_mod = @import("constraint.zig");
const error_mod = @import("error.zig");

const TypeEnv = env_mod.TypeEnv;
const ErrorList = error_mod.ErrorList;

fn setupEnv() !TypeEnv {
    return try TypeEnv.init(std.testing.allocator);
}

test "constraint infers int literal" {
    var env = try setupEnv();
    defer env.deinit(std.testing.allocator);
}

test "constraint infers bool literal" {
    var env = try setupEnv();
    defer env.deinit(std.testing.allocator);
}

test "constraint infers string literal" {
    var env = try setupEnv();
    defer env.deinit(std.testing.allocator);
}

test "constraint nil literal is nilable" {
    var env = try setupEnv();
    defer env.deinit(std.testing.allocator);
}

test "effect namespace detection" {
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("IO.println"));
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("File.readString"));
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("Env.get"));
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("Process.exit"));
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("Signal.on"));
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("Cmd.exec"));
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("Cmd.which"));
    try std.testing.expect(constraint_mod.isEffectNamespaceCall("Cmd.timeout"));
}

test "effect namespace non-effect functions" {
    try std.testing.expect(!constraint_mod.isEffectNamespaceCall("Cmd.withEnv"));
    try std.testing.expect(!constraint_mod.isEffectNamespaceCall("Cmd.pipe"));
    try std.testing.expect(!constraint_mod.isEffectNamespaceCall("Cmd.mergeStderr"));
    try std.testing.expect(!constraint_mod.isEffectNamespaceCall("List.map"));
    try std.testing.expect(!constraint_mod.isEffectNamespaceCall("String.length"));
}
