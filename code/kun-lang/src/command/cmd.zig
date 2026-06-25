const std = @import("std");
const value_mod = @import("../runtime/value.zig");

const Value = value_mod.Value;
const StreamNode = value_mod.StreamNode;
const CommandPayload = value_mod.CommandPayload;

pub fn execCommand(cmd: *const CommandPayload, allocator: std.mem.Allocator) !*StreamNode {
    if (cmd.bin.len == 0) {
        const node = try allocator.create(StreamNode);
        const buf = try allocator.alloc(u8, 4096);
        node.* = .{ .cmd = .{ .fd = 0, .pid = 0, .buf = buf } };
        return node;
    }

    const argv = try buildArgv(cmd, allocator);
    defer {
        for (argv[1..]) |a| allocator.free(a);
        allocator.free(argv);
    }

    var pipe_fds: [2]std.os.linux.fd_t = undefined;
    if (std.os.linux.pipe2(&pipe_fds, std.os.linux.O{ .NONBLOCK = false }) != 0) {
        return error.PipeFailed;
    }

    const pid = std.os.linux.fork();
    if (pid == 0) {
        _ = std.os.linux.close(pipe_fds[0]);
        _ = std.os.linux.dup2(pipe_fds[1], std.os.linux.STDOUT_FILENO);
        _ = std.os.linux.close(pipe_fds[1]);
        const resolved = resolvePath(cmd.bin, allocator) catch std.process.exit(127);
        defer allocator.free(resolved);
        const argv_z = try allocator.allocSentinel(?[*:0]const u8, argv.len, null);
        defer allocator.free(argv_z);
        argv_z[0] = resolved.ptr;
        for (argv[1..], 1..) |a, i| {
            const z = try allocator.allocSentinel(u8, a.len, 0);
            @memcpy(z[0..a.len], a);
            argv_z[i] = z.ptr;
        }
        _ = std.os.linux.execve(argv_z[0].?, @ptrCast(argv_z.ptr), @ptrCast(&[_:null]?[*:0]const u8{null}));
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

pub fn execPipeCommand(cmd1: *const CommandPayload, cmd2: *const CommandPayload, allocator: std.mem.Allocator) !*StreamNode {
    const argv1 = try buildArgv(cmd1, allocator);
    defer allocator.free(argv1);
    const argv2 = try buildArgv(cmd2, allocator);
    defer allocator.free(argv2);

    var pipe_fds: [2]std.os.linux.fd_t = undefined;
    if (std.os.linux.pipe2(&pipe_fds, std.os.linux.O{ .NONBLOCK = false }) != 0) {
        return error.PipeFailed;
    }

    const pid1 = std.os.linux.fork();
    if (pid1 == 0) {
        _ = std.os.linux.close(pipe_fds[0]);
        _ = std.os.linux.dup2(pipe_fds[1], std.os.linux.STDOUT_FILENO);
        _ = std.os.linux.close(pipe_fds[1]);
        const resolved = resolvePath(cmd1.bin, allocator) catch std.process.exit(127);
        defer allocator.free(resolved);
        const argv_z = try allocator.allocSentinel(?[*:0]const u8, argv1.len, null);
        defer allocator.free(argv_z);
        argv_z[0] = resolved.ptr;
        for (argv1[1..], 1..) |a, i| {
            const z = try allocator.allocSentinel(u8, a.len, 0);
            @memcpy(z[0..a.len], a);
            argv_z[i] = z.ptr;
        }
        _ = std.os.linux.execve(argv_z[0].?, @ptrCast(argv_z.ptr), @ptrCast(&[_:null]?[*:0]const u8{null}));
        std.process.exit(126);
    }

    const pid2 = std.os.linux.fork();
    if (pid2 == 0) {
        _ = std.os.linux.close(pipe_fds[1]);
        _ = std.os.linux.dup2(pipe_fds[0], std.os.linux.STDIN_FILENO);
        _ = std.os.linux.close(pipe_fds[0]);
        const resolved = resolvePath(cmd2.bin, allocator) catch std.process.exit(127);
        defer allocator.free(resolved);
        const argv_z = try allocator.allocSentinel(?[*:0]const u8, argv2.len, null);
        defer allocator.free(argv_z);
        argv_z[0] = resolved.ptr;
        for (argv2[1..], 1..) |a, i| {
            const z = try allocator.allocSentinel(u8, a.len, 0);
            @memcpy(z[0..a.len], a);
            argv_z[i] = z.ptr;
        }
        _ = std.os.linux.execve(argv_z[0].?, @ptrCast(argv_z.ptr), @ptrCast(&[_:null]?[*:0]const u8{null}));
        std.process.exit(126);
    }

    _ = std.os.linux.close(pipe_fds[0]);
    _ = std.os.linux.close(pipe_fds[1]);

    if (pid1 < 0 or pid2 < 0) return error.ForkFailed;

    const node = try allocator.create(StreamNode);
    const buf = try allocator.alloc(u8, 4096);
    node.* = .{ .cmd = .{ .fd = -1, .pid = @intCast(pid2), .buf = buf } };
    return node;
}

fn buildArgv(cmd: *const CommandPayload, allocator: std.mem.Allocator) ![]const []const u8 {
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    try list.append(allocator, cmd.bin);
    for (cmd.options) |opt| {
        const flag = try camelToKebab(allocator, opt.name);
        defer allocator.free(flag);
        switch (opt.value) {
            .bool => |b| {
                if (b) {
                    const flag_str = try std.fmt.allocPrint(allocator, "--{s}", .{flag});
                    try list.append(allocator, flag_str);
                }
            },
            .nil => {},
            else => {
                const flag_str = try std.fmt.allocPrint(allocator, "--{s}", .{flag});
                try list.append(allocator, flag_str);
                const val_str = try formatValue(allocator, opt.value);
                try list.append(allocator, val_str);
            },
        }
    }
    for (cmd.positional) |pos| {
        const s = try formatValue(allocator, pos);
        try list.append(allocator, s);
    }
    return try list.toOwnedSlice(allocator);
}

fn camelToKebab(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    if (name.len == 0) return try allocator.dupe(u8, name);
    var new_len: usize = 0;
    for (name, 0..) |c, i| {
        if (c >= 'A' and c <= 'Z' and i > 0) {
            new_len += 2;
        } else {
            new_len += 1;
        }
    }
    var buf = try allocator.alloc(u8, new_len);
    var j: usize = 0;
    for (name, 0..) |c, i| {
        if (c >= 'A' and c <= 'Z' and i > 0) {
            buf[j] = '-';
            j += 1;
            buf[j] = c + ('a' - 'A');
            j += 1;
        } else if (c >= 'A' and c <= 'Z') {
            buf[j] = c + ('a' - 'A');
            j += 1;
        } else {
            buf[j] = c;
            j += 1;
        }
    }
    return buf[0..j];
}

fn formatValue(allocator: std.mem.Allocator, value: Value) ![]const u8 {
    return switch (value) {
        .string => |s| try allocator.dupe(u8, s),
        .int => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| try std.fmt.allocPrint(allocator, "{d}", .{f}),
        .bool => |b| try allocator.dupe(u8, if (b) "true" else "false"),
        .path => |p| try allocator.dupe(u8, p),
        else => try allocator.dupe(u8, ""),
    };
}

fn resolvePath(bin: []const u8, allocator: std.mem.Allocator) ![:0]const u8 {
    if (std.mem.indexOfScalar(u8, bin, '/') != null) {
        const result = try allocator.allocSentinel(u8, bin.len, 0);
        @memcpy(result[0..bin.len], bin);
        return result;
    }
    const path_env = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
    var it = std.mem.splitSequence(u8, path_env, ":");
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const full = std.fs.path.join(allocator, &.{ dir, bin }) catch continue;
        defer allocator.free(full);
        const full_z = try allocator.allocSentinel(u8, full.len, 0);
        @memcpy(full_z[0..full.len], full);
        if (std.os.linux.access(full_z, std.os.linux.X_OK) == 0) {
            return full_z;
        }
    }
    return error.CommandNotFound;
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
