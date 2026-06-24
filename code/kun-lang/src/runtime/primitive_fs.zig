const std = @import("std");
const value_mod = @import("value.zig");
const RuntimeEnv = @import("primitive.zig").RuntimeEnv;
const io = @import("primitive_io.zig");

const Value = value_mod.Value;
const StreamNode = value_mod.StreamNode;

pub fn readStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "invalid arg" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
    const fd = std.os.linux.open(path_z, .{}, 0);
    if (fd < 0) return value_mod.makeErr(0, Value{ .string = "file not found" }, env.allocator) catch return Value{ .nil = {} };
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
    defer env.allocator.free(path_z);
    const fd = std.os.linux.open(path_z, .{ .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (fd < 0) return value_mod.makeErr(0, Value{ .string = "dir not found" }, env.allocator) catch return Value{ .nil = {} };
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
    defer env.allocator.free(path_z);
    if (std.os.linux.access(path_z, std.os.linux.F_OK) != 0) {
        return value_mod.makeErr(0, Value{ .string = "stat error" }, env.allocator) catch return Value{ .nil = {} };
    }
    const fields = env.allocator.alloc(value_mod.RecordFieldValue, 8) catch return Value{ .nil = {} };
    fields[0] = .{ .name = "size", .value = Value{ .int = 0 } };
    fields[1] = .{ .name = "mode", .value = Value{ .int = 0 } };
    fields[2] = .{ .name = "type_", .value = Value{ .int = 0 } };
    fields[3] = .{ .name = "atime", .value = Value{ .int = 0 } };
    fields[4] = .{ .name = "mtime", .value = Value{ .int = 0 } };
    fields[5] = .{ .name = "ctime", .value = Value{ .int = 0 } };
    fields[6] = .{ .name = "uid", .value = Value{ .int = 0 } };
    fields[7] = .{ .name = "gid", .value = Value{ .int = 0 } };
    return value_mod.makeOk(Value{ .record = .{ .fields = fields } }, env.allocator) catch return Value{ .nil = {} };
}

pub fn mkdirImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "invalid arg" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
    if (std.os.linux.mkdir(path_z, 0o755) != 0) {
        return value_mod.makeErr(1, Value{ .string = "mkdir error" }, env.allocator) catch return Value{ .nil = {} };
    }
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn mkdirAllImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "invalid arg" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
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
    defer env.allocator.free(path_z);
    const fd = std.os.linux.open(path_z, .{ .CREAT = true, .TRUNC = true }, 0o644);
    if (fd < 0) return value_mod.makeErr(1, Value{ .string = "open error" }, env.allocator) catch return Value{ .nil = {} };
    defer _ = std.os.linux.close(@intCast(fd));
    _ = std.os.linux.write(@intCast(fd), args[1].string.ptr, args[1].string.len);
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn touchImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
    const fd = std.os.linux.open(path_z, .{ .CREAT = true }, 0o644);
    if (fd >= 0) _ = std.os.linux.close(@intCast(fd));
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn removeImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
    if (std.os.linux.unlink(path_z) != 0) {
        return value_mod.makeErr(1, Value{ .string = "remove error" }, env.allocator) catch return Value{ .nil = {} };
    }
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn removeDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
    if (std.os.linux.rmdir(path_z) != 0) {
        return value_mod.makeErr(1, Value{ .string = "rmdir error" }, env.allocator) catch return Value{ .nil = {} };
    }
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn currentDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    return Value{ .path = env.allocator.dupe(u8, "/") catch return Value{ .nil = {} } };
}

pub fn homeDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    return Value{ .path = env.allocator.dupe(u8, "/root") catch return Value{ .nil = {} } };
}

pub fn tempDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    return Value{ .path = env.allocator.dupe(u8, "/tmp") catch return Value{ .nil = {} } };
}

pub fn readBytesImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(0, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
    const fd = std.os.linux.open(path_z, .{}, 0);
    if (fd < 0) return value_mod.makeErr(0, Value{ .string = "not found" }, env.allocator) catch return Value{ .nil = {} };
    const buf = env.allocator.alloc(u8, 4096) catch { _ = std.os.linux.close(@intCast(fd)); return Value{ .nil = {} }; };
    const node = env.allocator.create(StreamNode) catch return Value{ .nil = {} };
    node.* = .{ .cmd = .{ .fd = @intCast(fd), .pid = -1, .buf = buf } };
    return value_mod.makeOk(Value{ .stream = node }, env.allocator) catch return Value{ .nil = {} };
}

pub fn writeBytesImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn appendStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .path or args[1] != .string)
        return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = io.allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
    const fd = std.os.linux.open(path_z, .{ .CREAT = true, .TRUNC = false }, 0o644);
    if (fd < 0) return value_mod.makeErr(0, Value{ .string = "open" }, env.allocator) catch return Value{ .nil = {} };
    defer _ = std.os.linux.close(@intCast(fd));
    _ = std.os.linux.lseek(@intCast(fd), 0, std.os.linux.SEEK.END);
    _ = std.os.linux.write(@intCast(fd), args[1].string.ptr, args[1].string.len);
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn appendBytesImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn readLinesImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn walkDirImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn globImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn createTempFileImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    const name = std.fmt.allocPrint(env.allocator, "/tmp/kun_XXXXXX", .{}) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .path = name }, env.allocator) catch return Value{ .nil = {} };
}
pub fn createTempDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    const name = std.fmt.allocPrint(env.allocator, "/tmp/kun_XXXXXX", .{}) catch return Value{ .nil = {} };
    _ = std.os.linux.mkdir(@ptrCast(name.ptr), 0o700);
    return value_mod.makeOk(Value{ .path = name }, env.allocator) catch return Value{ .nil = {} };
}
pub fn copyImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn renameImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn removeAllImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn atomicWriteImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
