const std = @import("std");
const cmd_mod = @import("cmd.zig");

test "Phase4 isKnownCmdApi returns true for known Cmd APIs" {
    try std.testing.expect(cmd_mod.isKnownCmdApi("Cmd.pipe"));
    try std.testing.expect(cmd_mod.isKnownCmdApi("Cmd.withEnv"));
    try std.testing.expect(cmd_mod.isKnownCmdApi("Cmd.withWorkDir"));
    try std.testing.expect(cmd_mod.isKnownCmdApi("Cmd.withStdin"));
    try std.testing.expect(cmd_mod.isKnownCmdApi("Cmd.exec"));
    try std.testing.expect(cmd_mod.isKnownCmdApi("Cmd.timeout"));
    try std.testing.expect(cmd_mod.isKnownCmdApi("Cmd.retry"));
    try std.testing.expect(cmd_mod.isKnownCmdApi("Cmd.execSafe"));
    try std.testing.expect(cmd_mod.isKnownCmdApi("Cmd.which"));
}

test "Phase4 isKnownCmdApi returns true for effect-style Cmd APIs" {
    try std.testing.expect(cmd_mod.isKnownCmdApi("Cmd.ls?"));
    try std.testing.expect(cmd_mod.isKnownCmdApi("Cmd.echo!"));
    try std.testing.expect(cmd_mod.isKnownCmdApi("Cmd.pipe?"));
    try std.testing.expect(cmd_mod.isKnownCmdApi("Cmd.pipe!"));
}

test "Phase4 isKnownCmdApi returns false for unknown Cmd" {
    try std.testing.expect(!cmd_mod.isKnownCmdApi("Cmd.nonexistent"));
    try std.testing.expect(!cmd_mod.isKnownCmdApi("Cmd.foo"));
}

test "Phase4 isKnownCmdApi returns false for non-Cmd prefix" {
    try std.testing.expect(!cmd_mod.isKnownCmdApi("IO.println"));
    try std.testing.expect(!cmd_mod.isKnownCmdApi("File.readString"));
    try std.testing.expect(!cmd_mod.isKnownCmdApi("List.map"));
    try std.testing.expect(!cmd_mod.isKnownCmdApi("exec"));
}

test "Phase4 execCommand returns StreamNode with cmd variant" {
    const node = try cmd_mod.execCommand("echo", &.{"hello"}, std.testing.allocator);
    defer std.testing.allocator.destroy(node);
    defer std.testing.allocator.free(node.cmd.buf);
    try std.testing.expect(node.* == .cmd);
}

test "Phase4 execCommand with empty args returns StreamNode" {
    const node = try cmd_mod.execCommand("ls", &.{}, std.testing.allocator);
    defer std.testing.allocator.destroy(node);
    defer std.testing.allocator.free(node.cmd.buf);
    try std.testing.expect(node.* == .cmd);
}

test "Phase4 known_cmd_apis has 15 entries" {
    try std.testing.expectEqual(@as(usize, 15), cmd_mod.known_cmd_apis.len);
}
