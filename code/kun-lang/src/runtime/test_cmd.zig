const std = @import("std");
const cmd_mod = @import("cmd.zig");

test "isKnownCmdApi covers all known patterns" {
    const cases = [_]struct { name: []const u8, expected: bool }{
        .{ .name = "Cmd.pipe", .expected = true },
        .{ .name = "Cmd.withEnv", .expected = true },
        .{ .name = "Cmd.withWorkDir", .expected = true },
        .{ .name = "Cmd.withStdin", .expected = true },
        .{ .name = "Cmd.exec", .expected = true },
        .{ .name = "Cmd.timeout", .expected = true },
        .{ .name = "Cmd.retry", .expected = true },
        .{ .name = "Cmd.execSafe", .expected = true },
        .{ .name = "Cmd.which", .expected = true },
        .{ .name = "Cmd.ls?", .expected = true },
        .{ .name = "Cmd.echo!", .expected = true },
        .{ .name = "Cmd.pipe?", .expected = true },
        .{ .name = "Cmd.pipe!", .expected = true },
        .{ .name = "Cmd.nonexistent", .expected = false },
        .{ .name = "Cmd.foo", .expected = false },
        .{ .name = "IO.println", .expected = false },
        .{ .name = "File.readString", .expected = false },
        .{ .name = "List.map", .expected = false },
        .{ .name = "exec", .expected = false },
    };
    for (cases) |c| {
        try std.testing.expectEqual(c.expected, cmd_mod.isKnownCmdApi(c.name));
    }
}

test "known_cmd_apis size" {
    try std.testing.expectEqual(@as(usize, 15), cmd_mod.known_cmd_apis.len);
}

test "execCommand returns StreamNode with valid fields" {
    const commands = [_]struct { bin: []const u8, expect_failure: bool }{
        .{ .bin = "echo", .expect_failure = false },
        .{ .bin = "ls", .expect_failure = false },
        .{ .bin = "nonexistent_bin_xyz", .expect_failure = true },
    };
    for (commands) |cmd| {
        {
            const node = try cmd_mod.execCommand(&.{ .bin = cmd.bin, .options = &.{}, .positional = &.{} }, std.testing.allocator);
            defer std.testing.allocator.destroy(node);
            defer std.testing.allocator.free(node.cmd.buf);
            defer if (node.cmd.pid > 0) {
                var status: i32 = 0;
                _ = std.os.linux.waitpid(node.cmd.pid, &status, 0);
            };
            defer if (node.cmd.fd > 0) {
                _ = std.os.linux.close(node.cmd.fd);
            };

            try std.testing.expect(node.* == .cmd);
            if (!cmd.expect_failure) {
                try std.testing.expect(node.cmd.fd > 0);
                try std.testing.expect(node.cmd.pid > 0);
            }
        }
    }
}
