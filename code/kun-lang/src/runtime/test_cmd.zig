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
    const node = try cmd_mod.execCommand(&.{ .bin = "echo", .options = &.{}, .positional = &.{} }, std.testing.allocator);
    defer std.testing.allocator.destroy(node);
    defer std.testing.allocator.free(node.cmd.buf);
    try std.testing.expect(node.* == .cmd);
}

test "Phase4 execCommand with empty args returns StreamNode" {
    const node = try cmd_mod.execCommand(&.{ .bin = "ls", .options = &.{}, .positional = &.{} }, std.testing.allocator);
    defer std.testing.allocator.destroy(node);
    defer std.testing.allocator.free(node.cmd.buf);
    try std.testing.expect(node.* == .cmd);
}

test "Phase4 known_cmd_apis has 15 entries" {
    try std.testing.expectEqual(@as(usize, 15), cmd_mod.known_cmd_apis.len);
}

test "Phase4 execCommand pipe buffer contains data" {
    const node = try cmd_mod.execCommand(&.{ .bin = "echo", .options = &.{}, .positional = &.{} }, std.testing.allocator);
    defer std.testing.allocator.destroy(node);
    defer std.testing.allocator.free(node.cmd.buf);
    try std.testing.expect(node.* == .cmd);
    try std.testing.expect(node.cmd.fd > 0);
    try std.testing.expect(node.cmd.pid > 0);

    var status: i32 = 0;
    const waited = std.os.linux.waitpid(node.cmd.pid, &status, 0);
    try std.testing.expect(waited > 0);

    var buf: [256]u8 = undefined;
    const n = std.os.linux.read(node.cmd.fd, &buf, buf.len);
    if (n > 0 and n <= buf.len) {
        try std.testing.expect(std.mem.startsWith(u8, buf[0..n], "hello"));
    }
}

test "Phase4 execCommand invalid bin returns StreamNode" {
    const node = try cmd_mod.execCommand(&.{ .bin = "nonexistent_bin_xyz", .options = &.{}, .positional = &.{} }, std.testing.allocator);
    defer std.testing.allocator.destroy(node);
    defer std.testing.allocator.free(node.cmd.buf);
    defer _ = std.os.linux.close(node.cmd.fd);
    try std.testing.expect(node.* == .cmd);
    var status: i32 = 0;
    _ = std.os.linux.waitpid(node.cmd.pid, &status, 0);
    try std.testing.expect(status != 0);
}
