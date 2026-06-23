const std = @import("std");
const value_mod = @import("value.zig");

const Value = value_mod.Value;
const StreamNode = value_mod.StreamNode;

pub fn execCommand(bin: []const u8, args: []const []const u8, allocator: std.mem.Allocator) !*StreamNode {
    _ = args;
    var pipe_fds: [2]std.os.linux.fd_t = undefined;
    if (std.os.linux.pipe2(&pipe_fds, std.os.linux.O{ .NONBLOCK = true }) != 0) {
        return error.PipeFailed;
    }

    const pid = std.os.linux.fork();
    if (pid == 0) {
        _ = std.os.linux.close(pipe_fds[0]);
        _ = std.os.linux.dup2(pipe_fds[1], std.os.linux.STDOUT_FILENO);
        _ = std.os.linux.close(pipe_fds[1]);
        const resolved = resolvePath(bin, allocator) catch std.process.exit(127);
        defer allocator.free(resolved);
        const resolved_z: [*:0]const u8 = @ptrCast(resolved.ptr);
        const argv = [_:null]?[*:0]const u8{ resolved_z, null };
        _ = std.os.linux.execve(resolved_z, @ptrCast(&argv), @ptrCast(&[_:null]?[*:0]const u8{null}));
        std.process.exit(126);
    } else if (pid < 0) {
        _ = std.os.linux.close(pipe_fds[0]);
        _ = std.os.linux.close(pipe_fds[1]);
        return error.ForkFailed;
    }

    _ = std.os.linux.close(pipe_fds[1]);

    const node = try allocator.create(StreamNode);
    const buf = try allocator.alloc(u8, 4096);
    node.* = .{ .cmd = .{ .fd = pipe_fds[0], .pid = @intCast(pid), .buf = buf } };
    return node;
}

fn resolvePath(bin: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, bin);
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
