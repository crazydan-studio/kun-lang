const std = @import("std");
const value_mod = @import("value.zig");

const Value = value_mod.Value;
const StreamNode = value_mod.StreamNode;

pub fn execCommand(bin: []const u8, args: []const []const u8, allocator: std.mem.Allocator) !*StreamNode {
    _ = bin;
    _ = args;
    const node = try allocator.create(StreamNode);
    const buf = try allocator.alloc(u8, 0);
    node.* = .{ .cmd = .{ .fd = -1, .pid = -1, .buf = buf } };
    return node;
}

pub const known_cmd_apis = [_][]const u8{ "pipe", "withEnv", "withWorkDir", "withStdin", "withStdinFile", "withRawOpt", "mergeStderr", "withRunAs", "andThen", "orElse", "exec", "timeout", "retry", "execSafe", "which" };

pub fn isKnownCmdApi(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "Cmd.")) return false;
    const rest = name["Cmd.".len..];
    if (std.mem.containsAtLeast(u8, rest, 1, "?")) return true;
    if (std.mem.containsAtLeast(u8, rest, 1, "!")) return true;
    for (known_cmd_apis) |api| {
        if (std.mem.eql(u8, rest, api)) return true;
    }
    return false;
}
