const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const RuntimeEnv = @import("../runtime/primitive.zig").RuntimeEnv;
const io = @import("io.zig");

const Value = value_mod.Value;
const StreamNode = value_mod.StreamNode;

fn openFile(path: [*:0]const u8, flags: std.os.linux.O, perm: u32) isize {
    return @bitCast(std.os.linux.open(path, flags, perm));
}

pub fn readStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "invalid arg" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    const fd = openFile(path_z, .{}, 0);
    if (fd < 0) return value_mod.makeErr(1, Value{ .string = "file not found" }, env.allocator) catch return Value{ .nil = {} };
    defer _ = std.os.linux.close(@intCast(fd));
    var buf: [1048576]u8 = undefined;
    const n = std.os.linux.read(@intCast(fd), &buf, buf.len);
    if (n <= 0) return Value{ .string = "" };
    const content = env.allocator.dupe(u8, buf[0..n]) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .string = content }, env.allocator) catch return Value{ .nil = {} };
}

pub fn listDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "invalid arg" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    const fd = openFile(path_z, .{ .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (fd < 0) return value_mod.makeErr(1, Value{ .string = "dir not found" }, env.allocator) catch return Value{ .nil = {} };
    defer _ = std.os.linux.close(@intCast(fd));
    var buf: [4096]u8 align(8) = undefined;
    var list: std.ArrayListUnmanaged(Value) = .empty;
    var pos: usize = 0;
    var nread: usize = 0;
    while (true) {
        if (pos >= nread) {
            const result = std.os.linux.getdents64(@intCast(fd), &buf, buf.len);
            if (result <= 0) break;
            nread = @intCast(result);
            pos = 0;
            if (nread == 0) break;
        }
        const de = @as(*align(1) std.os.linux.dirent64, @ptrCast(&buf[pos]));
        if (de.ino != 0 and de.reclen != 0) {
            const name = std.mem.sliceTo(@as([*:0]u8, @ptrCast(&de.name)), 0);
            if (!std.mem.eql(u8, name, ".") and !std.mem.eql(u8, name, "..")) {
                const duped = env.allocator.dupe(u8, name) catch break;
                list.append(env.allocator, Value{ .path = duped }) catch break;
            }
        }
        pos += de.reclen;
    }
    return value_mod.makeOk(Value{ .list = .{ .items = list.items, .cap = list.items.len } }, env.allocator) catch return Value{ .nil = {} };
}

pub fn statImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    var stx: std.os.linux.Statx = undefined;
    const rc = std.os.linux.statx(0, path_z, 0, std.os.linux.STATX.BASIC_STATS, &stx);
    if (rc != 0) return value_mod.makeErr(1, Value{ .string = "stat error" }, env.allocator) catch return Value{ .nil = {} };
    const fields = env.allocator.alloc(value_mod.RecordFieldValue, 8) catch return Value{ .nil = {} };
    fields[0] = .{ .name = "size", .value = Value{ .int = @intCast(stx.size) } };
    fields[1] = .{ .name = "mode", .value = Value{ .int = stx.mode } };
    fields[2] = .{ .name = "type_", .value = Value{ .int = @intCast(stx.mode & 0o170000) } };
    fields[3] = .{ .name = "atime", .value = Value{ .int = stx.atime.sec } };
    fields[4] = .{ .name = "mtime", .value = Value{ .int = stx.mtime.sec } };
    fields[5] = .{ .name = "ctime", .value = Value{ .int = stx.ctime.sec } };
    fields[6] = .{ .name = "uid", .value = Value{ .int = stx.uid } };
    fields[7] = .{ .name = "gid", .value = Value{ .int = stx.gid } };
    return value_mod.makeOk(Value{ .record = .{ .fields = fields } }, env.allocator) catch return Value{ .nil = {} };
}

pub fn mkdirImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "invalid arg" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    if (std.os.linux.mkdir(path_z, 0o755) != 0) {
        return value_mod.makeErr(1, Value{ .string = "mkdir error" }, env.allocator) catch return Value{ .nil = {} };
    }
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn mkdirAllImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "invalid arg" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    var tmp: [4096]u8 = undefined;
    @memcpy(tmp[0..path_z.len], path_z);
    tmp[path_z.len] = 0;
    for (1..path_z.len) |i| {
        if (tmp[i] == '/') {
            tmp[i] = 0;
            _ = std.os.linux.mkdir(@ptrCast(&tmp), 0o755);
            tmp[i] = '/';
        }
    }
    if (std.os.linux.mkdir(path_z, 0o755) != 0 and std.os.linux.access(path_z, std.os.linux.F_OK) != 0) {
        return value_mod.makeErr(1, Value{ .string = "mkdirAll error" }, env.allocator) catch return Value{ .nil = {} };
    }
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn writeStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .path or args[1] != .string)
        return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    const fd = openFile(path_z, .{ .CREAT = true, .TRUNC = true, .ACCMODE = .WRONLY }, 0o644);
    if (fd < 0) return value_mod.makeErr(1, Value{ .string = "open error" }, env.allocator) catch return Value{ .nil = {} };
    defer _ = std.os.linux.close(@intCast(fd));
    if (@as(isize, @bitCast(std.os.linux.write(@intCast(fd), args[1].string.ptr, args[1].string.len))) < 0) return value_mod.makeErr(1, Value{ .string = "write error" }, env.allocator) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn touchImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    const fd = openFile(path_z, .{ .CREAT = true, .ACCMODE = .WRONLY }, 0o644);
    if (fd >= 0) _ = std.os.linux.close(@intCast(fd));
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn removeImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    if (std.os.linux.unlink(path_z) != 0) {
        return value_mod.makeErr(1, Value{ .string = "remove error" }, env.allocator) catch return Value{ .nil = {} };
    }
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn removeDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    if (std.os.linux.rmdir(path_z) != 0) {
        return value_mod.makeErr(1, Value{ .string = "rmdir error" }, env.allocator) catch return Value{ .nil = {} };
    }
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn currentDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    var buf: [4096]u8 = undefined;
    const result = std.os.linux.getcwd(&buf, buf.len);
    if (result != 0) return Value{ .path = env.allocator.dupe(u8, "/") catch return Value{ .nil = {} } };
    const len = std.mem.indexOfScalar(u8, buf[0..], 0) orelse buf.len;
    return Value{ .path = env.allocator.dupe(u8, buf[0..len]) catch return Value{ .nil = {} } };
}

pub fn homeDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    const val = getEnvValue(env.allocator, "HOME");
    return Value{ .path = val orelse env.allocator.dupe(u8, "/root") catch return Value{ .nil = {} } };
}

pub fn tempDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    const val = getEnvValue(env.allocator, "TMPDIR") orelse getEnvValue(env.allocator, "TMP");
    return Value{ .path = val orelse env.allocator.dupe(u8, "/tmp") catch return Value{ .nil = {} } };
}

fn getEnvValue(allocator: std.mem.Allocator, key: []const u8) ?[]const u8 {
    const fd = openFile("/proc/self/environ", .{}, 0);
    if (fd < 0) return null;
    defer _ = std.os.linux.close(@intCast(fd));
    var buf: [8192]u8 = undefined;
    const n = std.os.linux.read(@intCast(fd), &buf, buf.len);
    if (n <= 0) return null;
    var start: usize = 0;
    var i: usize = 0;
    const data = buf[0..@intCast(n)];
    while (i < data.len) : (i += 1) {
        if (data[i] == 0) {
            if (i > start) {
                const entry = data[start..i];
                if (std.mem.indexOfScalar(u8, entry, '=')) |eq_pos| {
                    if (std.mem.eql(u8, entry[0..eq_pos], key)) {
                        return allocator.dupe(u8, entry[eq_pos + 1 ..]) catch return null;
                    }
                }
            }
            start = i + 1;
        }
    }
    return null;
}

pub fn readBytesImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    const fd = openFile(path_z, .{}, 0);
    if (fd < 0) return value_mod.makeErr(1, Value{ .string = "not found" }, env.allocator) catch return Value{ .nil = {} };
    const buf = env.allocator.alloc(u8, 4096) catch { _ = std.os.linux.close(@intCast(fd)); return Value{ .nil = {} }; };
    const node = env.allocator.create(StreamNode) catch return Value{ .nil = {} };
    node.* = .{ .cmd = .{ .fd = @intCast(fd), .pid = -1, .buf = buf } };
    return value_mod.makeOk(Value{ .stream = node }, env.allocator) catch return Value{ .nil = {} };
}

pub fn writeBytesImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .path or args[1] != .bytes)
        return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    const fd = openFile(path_z, .{ .CREAT = true, .TRUNC = true, .ACCMODE = .WRONLY }, 0o644);
    if (fd < 0) return value_mod.makeErr(1, Value{ .string = "open error" }, env.allocator) catch return Value{ .nil = {} };
    defer _ = std.os.linux.close(@intCast(fd));
    if (@as(isize, @bitCast(std.os.linux.write(@intCast(fd), args[1].bytes.ptr, args[1].bytes.len))) < 0) return value_mod.makeErr(1, Value{ .string = "write error" }, env.allocator) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn appendBytesImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .path or args[1] != .bytes)
        return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    const fd = openFile(path_z, .{ .CREAT = true, .TRUNC = false, .ACCMODE = .WRONLY }, 0o644);
    if (fd < 0) return value_mod.makeErr(1, Value{ .string = "open" }, env.allocator) catch return Value{ .nil = {} };
    defer _ = std.os.linux.close(@intCast(fd));
    _ = std.os.linux.lseek(@intCast(fd), 0, std.os.linux.SEEK.END);
    if (@as(isize, @bitCast(std.os.linux.write(@intCast(fd), args[1].bytes.ptr, args[1].bytes.len))) < 0) return value_mod.makeErr(1, Value{ .string = "write error" }, env.allocator) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn readLinesImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path)
        return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    const fd = openFile(path_z, .{}, 0);
    if (fd < 0) return value_mod.makeErr(1, Value{ .string = "not found" }, env.allocator) catch return Value{ .nil = {} };
    const buf = env.allocator.alloc(u8, 4096) catch {
        _ = std.os.linux.close(@intCast(fd));
        return Value{ .nil = {} };
    };
    const raw_node = env.allocator.create(StreamNode) catch return Value{ .nil = {} };
    raw_node.* = .{ .cmd = .{ .fd = @intCast(fd), .pid = -1, .buf = buf } };
    const lines_node = value_mod.streamLines(env.allocator, raw_node, 65536) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .stream = lines_node }, env.allocator) catch return Value{ .nil = {} };
}

pub fn walkDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return Value{ .nil = {} };
    var list: std.ArrayListUnmanaged(Value) = .empty;
    walkDirRecursive(env.allocator, args[0].path, &list);
    const items = list.toOwnedSlice(env.allocator) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .list = .{ .items = items, .cap = items.len } }, env.allocator) catch return Value{ .nil = {} };
}

fn walkDirRecursive(allocator: std.mem.Allocator, root: []const u8, list: *std.ArrayListUnmanaged(Value)) void {
    const path_z = allocator.allocSentinel(u8, root.len, 0) catch return;
    @memcpy(path_z[0..root.len], root);
    const fd = openFile(path_z, .{ .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (fd < 0) return;
    defer _ = std.os.linux.close(@intCast(fd));
    var buf: [4096]u8 align(8) = undefined;
    var pos: usize = 0;
    var nread: usize = 0;
    while (true) {
        if (pos >= nread) {
            const r = std.os.linux.getdents64(@intCast(fd), &buf, buf.len);
            if (r <= 0) break;
            nread = @intCast(r);
            pos = 0;
            if (nread == 0) break;
        }
        const de = @as(*align(1) std.os.linux.dirent64, @ptrCast(&buf[pos]));
        if (de.ino != 0 and de.reclen != 0) {
            const name = std.mem.sliceTo(@as([*:0]u8, @ptrCast(&de.name)), 0);
            if (!std.mem.eql(u8, name, ".") and !std.mem.eql(u8, name, "..")) {
                const full = std.fs.path.join(allocator, &.{ root, name }) catch continue;
                list.append(allocator, Value{ .path = full }) catch continue;
                walkDirRecursive(allocator, full, list);
            }
        }
        pos += de.reclen;
    }
}

pub fn appendStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .path or args[1] != .string)
        return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    const fd = openFile(path_z, .{ .CREAT = true, .TRUNC = false, .ACCMODE = .WRONLY }, 0o644);
    if (fd < 0) return value_mod.makeErr(1, Value{ .string = "open" }, env.allocator) catch return Value{ .nil = {} };
    defer _ = std.os.linux.close(@intCast(fd));
    _ = std.os.linux.lseek(@intCast(fd), 0, std.os.linux.SEEK.END);
    if (@as(isize, @bitCast(std.os.linux.write(@intCast(fd), args[1].string.ptr, args[1].string.len))) < 0) return value_mod.makeErr(1, Value{ .string = "write error" }, env.allocator) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn globImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .string or args[1] != .path)
        return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const pattern = args[0].string;
    const dir_path = args[1].path;
    const dir_z = io.allocSentinel(env.allocator, dir_path) catch return Value{ .nil = {} };
    const fd = openFile(dir_z, .{ .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (fd < 0) return value_mod.makeErr(1, Value{ .string = "dir not found" }, env.allocator) catch return Value{ .nil = {} };
    defer _ = std.os.linux.close(@intCast(fd));
    var list: std.ArrayListUnmanaged(Value) = .empty;
    var buf: [4096]u8 align(8) = undefined;
    var pos: usize = 0;
    var nread: usize = 0;
    const glob_mod = @import("../runtime/glob_engine.zig");
    while (true) {
        if (pos >= nread) {
            const r = std.os.linux.getdents64(@intCast(fd), &buf, buf.len);
            if (r <= 0) break;
            nread = @intCast(r);
            pos = 0;
            if (nread == 0) break;
        }
        const de = @as(*align(1) std.os.linux.dirent64, @ptrCast(&buf[pos]));
        if (de.ino != 0 and de.reclen != 0) {
            const name = std.mem.sliceTo(@as([*:0]u8, @ptrCast(&de.name)), 0);
            if (!std.mem.eql(u8, name, ".") and !std.mem.eql(u8, name, "..")) {
                if (glob_mod.match(pattern, name)) {
                    const full = std.fs.path.join(env.allocator, &.{ dir_path, name }) catch continue;
                    list.append(env.allocator, Value{ .path = full }) catch continue;
                }
            }
        }
        pos += de.reclen;
    }
    const items = list.toOwnedSlice(env.allocator) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .list = .{ .items = items, .cap = items.len } }, env.allocator) catch return Value{ .nil = {} };
}
pub fn createTempFileImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    var random_bytes: [6]u8 = undefined;
    const urandom = openFile("/dev/urandom", .{}, 0);
    if (urandom >= 0) {
        _ = std.os.linux.read(@intCast(urandom), &random_bytes, random_bytes.len);
        _ = std.os.linux.close(@intCast(urandom));
    } else {
        @memset(&random_bytes, 'X');
    }
    const name = std.fmt.allocPrint(env.allocator, "/tmp/kun_{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
        random_bytes[0], random_bytes[1], random_bytes[2],
        random_bytes[3], random_bytes[4], random_bytes[5],
    }) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .path = name }, env.allocator) catch return Value{ .nil = {} };
}
pub fn createTempDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    var random_bytes: [6]u8 = undefined;
    const urandom = openFile("/dev/urandom", .{}, 0);
    if (urandom >= 0) {
        _ = std.os.linux.read(@intCast(urandom), &random_bytes, random_bytes.len);
        _ = std.os.linux.close(@intCast(urandom));
    } else {
        @memset(&random_bytes, 'X');
    }
    const name = std.fmt.allocPrint(env.allocator, "/tmp/kun_{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
        random_bytes[0], random_bytes[1], random_bytes[2],
        random_bytes[3], random_bytes[4], random_bytes[5],
    }) catch return Value{ .nil = {} };
    _ = std.os.linux.mkdir(@ptrCast(name.ptr), 0o700);
    return value_mod.makeOk(Value{ .path = name }, env.allocator) catch return Value{ .nil = {} };
}
pub fn copyImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .path or args[1] != .path)
        return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const src_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    const dst_z = io.allocSentinel(env.allocator, args[1].path) catch return Value{ .nil = {} };
    const src_fd = openFile(src_z, .{}, 0);
    if (src_fd < 0) return value_mod.makeErr(1, Value{ .string = "open src" }, env.allocator) catch return Value{ .nil = {} };
    defer _ = std.os.linux.close(@intCast(src_fd));
    const dst_fd = openFile(dst_z, .{ .CREAT = true, .TRUNC = true, .ACCMODE = .WRONLY }, 0o644);
    if (dst_fd < 0) return value_mod.makeErr(1, Value{ .string = "open dst" }, env.allocator) catch return Value{ .nil = {} };
    defer _ = std.os.linux.close(@intCast(dst_fd));
    var buf: [65536]u8 = undefined;
    while (true) {
        const n = std.os.linux.read(@intCast(src_fd), &buf, buf.len);
        if (n <= 0) break;
        if (std.os.linux.write(@intCast(dst_fd), buf[0..@intCast(n)].ptr, @intCast(n)) < 0)
            return value_mod.makeErr(1, Value{ .string = "write error" }, env.allocator) catch return Value{ .nil = {} };
    }
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn renameImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .path or args[1] != .path)
        return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const old_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    const new_z = io.allocSentinel(env.allocator, args[1].path) catch return Value{ .nil = {} };
    if (std.os.linux.rename(old_z, new_z) != 0) {
        return value_mod.makeErr(1, Value{ .string = "rename error" }, env.allocator) catch return Value{ .nil = {} };
    }
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn removeAllImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path)
        return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    removeRecursive(env.allocator, path_z);
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

fn removeRecursive(allocator: std.mem.Allocator, path: [:0]u8) void {
    const fd = openFile(path, .{ .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (fd < 0) {
        _ = std.os.linux.unlink(path);
        return;
    }
    defer _ = std.os.linux.close(@intCast(fd));
    var buf: [4096]u8 align(8) = undefined;
    var pos: usize = 0;
    var nread: usize = 0;
    while (true) {
        if (pos >= nread) {
            const r = std.os.linux.getdents64(@intCast(fd), &buf, buf.len);
            if (r <= 0) break;
            nread = @intCast(r);
            pos = 0;
            if (nread == 0) break;
        }
        const de = @as(*align(1) std.os.linux.dirent64, @ptrCast(&buf[pos]));
        if (de.ino != 0 and de.reclen != 0) {
            const name = std.mem.sliceTo(@as([*:0]u8, @ptrCast(&de.name)), 0);
            if (!std.mem.eql(u8, name, ".") and !std.mem.eql(u8, name, "..")) {
                const sub_path = std.fs.path.joinZ(allocator, &.{ path, name }) catch continue;
                removeRecursive(allocator, sub_path);
            }
        }
        pos += de.reclen;
    }
    _ = std.os.linux.rmdir(path);
}

pub fn atomicWriteImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .path or args[1] != .string)
        return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const tmp_name = std.fmt.allocPrint(env.allocator, "{s}.tmp", .{args[0].path}) catch return Value{ .nil = {} };
    const tmp_z = io.allocSentinel(env.allocator, tmp_name) catch return Value{ .nil = {} };
    const fd = openFile(tmp_z, .{ .CREAT = true, .TRUNC = true, .ACCMODE = .WRONLY }, 0o644);
    if (fd < 0) return value_mod.makeErr(1, Value{ .string = "open error" }, env.allocator) catch return Value{ .nil = {} };
    defer _ = std.os.linux.close(@intCast(fd));
    if (@as(isize, @bitCast(std.os.linux.write(@intCast(fd), args[1].string.ptr, args[1].string.len))) < 0) return value_mod.makeErr(1, Value{ .string = "write error" }, env.allocator) catch return Value{ .nil = {} };
    const dst_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    if (std.os.linux.rename(tmp_z, dst_z) != 0) {
        return value_mod.makeErr(1, Value{ .string = "rename error" }, env.allocator) catch return Value{ .nil = {} };
    }
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}
