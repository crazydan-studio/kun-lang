const std = @import("std");
const value_mod = @import("value.zig");
const typed = @import("../ast/typed.zig");
const stream_consumer = @import("stream_consumer.zig");

const Value = value_mod.Value;
const TypeId = typed.TypeId;
const Frame = @import("env.zig").Frame;
const StreamNode = value_mod.StreamNode;
const StreamFn = value_mod.StreamFn;

pub const RuntimeEnv = struct {
    frame: *Frame,
    primitives: PrimitiveTable,
    allocator: std.mem.Allocator,

    pub fn init(frame: *Frame, primitives: PrimitiveTable, allocator: std.mem.Allocator) RuntimeEnv {
        return .{ .frame = frame, .primitives = primitives, .allocator = allocator };
    }
};

pub const PrimitiveFn = *const fn (env: *RuntimeEnv, args: []const Value) Value;

pub const PrimitiveBinding = struct {
    module: []const u8,
    name: []const u8,
    fn_ptr: PrimitiveFn,
    arg_count: u8,
    return_type: TypeId,
    is_polymorphic: bool,
    is_effect: bool,
};

pub const PrimitiveTable = struct {
    bindings: []const PrimitiveBinding,
};

fn printlnImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len > 0 and args[0] == .string) {
        const msg = std.fmt.allocPrint(env.allocator, "{s}\n", .{args[0].string}) catch return Value{ .unit = {} };
        defer env.allocator.free(msg);
        _ = std.os.linux.write(1, msg.ptr, msg.len);
    }
    return Value{ .unit = {} };
}

fn readlnImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    var buf: [65536]u8 = undefined;
    const n = std.os.linux.read(0, &buf, buf.len);
    if (n <= 0) return Value{ .string = "" };
    const end = for (buf[0..n], 0..) |b, i| {
        if (b == '\n') break i;
    } else n;
    const line = env.allocator.dupe(u8, buf[0..end]) catch return Value{ .string = "" };
    return Value{ .string = line };
}

fn readStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "invalid arg" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
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

fn listDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "invalid arg" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
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

fn statImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return Value{ .nil = {} };
    const path_z = allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
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

fn allocSentinel(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
    const buf = try allocator.allocSentinel(u8, s.len, 0);
    @memcpy(buf[0..s.len], s);
    return buf;
}

fn getenvImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .string) return Value{ .nil = {} };
    const key = args[0].string;
    const result = if (std.mem.eql(u8, key, "HOME"))
        env.allocator.dupe(u8, "/root") catch return Value{ .nil = {} }
    else if (std.mem.eql(u8, key, "PATH"))
        env.allocator.dupe(u8, "/usr/bin:/bin") catch return Value{ .nil = {} }
    else if (std.mem.eql(u8, key, "USER"))
        env.allocator.dupe(u8, "root") catch return Value{ .nil = {} }
    else
        return Value{ .nil = {} };
    return Value{ .string = result };
}

fn containsEnvImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .string) return Value{ .bool = false };
    const key = args[0].string;
    return Value{ .bool = std.mem.eql(u8, key, "HOME") or std.mem.eql(u8, key, "PATH") or std.mem.eql(u8, key, "USER") };
}

fn exitImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    const code: u8 = if (args.len > 0 and args[0] == .int) @intCast(@min(args[0].int, 255)) else 0;
    std.process.exit(code);
}

fn pidImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .int = @intCast(std.os.linux.getpid()) };
}

fn uidImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .int = @intCast(std.os.linux.getuid()) };
}

fn gidImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .int = @intCast(std.os.linux.getgid()) };
}

fn whichImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .string) return Value{ .nil = {} };
    const path_env = "/usr/bin:/bin:/usr/local/bin";
    var it = std.mem.splitSequence(u8, path_env, ":");
    while (it.next()) |dir| {
        const full = std.fs.path.join(env.allocator, &.{ dir, args[0].string }) catch continue;
        defer env.allocator.free(full);
        const full_z = allocSentinel(env.allocator, full) catch continue;
        defer env.allocator.free(full_z);
        if (std.os.linux.access(full_z, std.os.linux.X_OK) == 0) {
            return Value{ .path = full };
        }
    }
    return Value{ .nil = {} };
}

fn printImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len > 0 and args[0] == .string) {
        _ = std.os.linux.write(1, args[0].string.ptr, args[0].string.len);
    }
    return Value{ .unit = {} };
}

fn eprintImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len > 0 and args[0] == .string) {
        _ = std.os.linux.write(2, args[0].string.ptr, args[0].string.len);
    }
    return Value{ .unit = {} };
}

fn eprintlnImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len > 0 and args[0] == .string) {
        const msg = std.fmt.allocPrint(env.allocator, "{s}\n", .{args[0].string}) catch return Value{ .unit = {} };
        defer env.allocator.free(msg);
        _ = std.os.linux.write(2, msg.ptr, msg.len);
    }
    return Value{ .unit = {} };
}

fn readBytesImpl(env: *RuntimeEnv, args: []const Value) Value {
    const max: usize = if (args.len > 0 and args[0] == .int) @intCast(@max(args[0].int, 0)) else 4096;
    const buf = env.allocator.alloc(u8, max) catch return value_mod.makeErr(4, Value{ .string = "oom" }, env.allocator) catch return Value{ .nil = {} };
    const n = std.os.linux.read(0, buf.ptr, buf.len);
    if (n <= 0) return value_mod.makeErr(4, Value{ .string = "read error" }, env.allocator) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .bytes = buf[0..n] }, env.allocator) catch return Value{ .nil = {} };
}

fn readAllImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = std.os.linux.read(0, &tmp, tmp.len);
        if (n <= 0) break;
        buf.appendSlice(env.allocator, tmp[0..n]) catch break;
    }
    const s = buf.toOwnedSlice(env.allocator) catch return Value{ .string = "" };
    return Value{ .string = s };
}

fn readAllBytesImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = std.os.linux.read(0, &tmp, tmp.len);
        if (n <= 0) break;
        buf.appendSlice(env.allocator, tmp[0..n]) catch break;
    }
    const b = buf.toOwnedSlice(env.allocator) catch return Value{ .bytes = &.{} };
    return Value{ .bytes = b };
}

fn isTerminalImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .bool = true };
}

fn flushImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .unit = {} };
}

fn killImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    if (args[0] != .int or args[1] != .int) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    _ = std.os.linux.kill(@intCast(args[0].int), @enumFromInt(@as(u32, @intCast(args[1].int))));
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

fn waitImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    var status: i32 = 0;
    const pid = std.os.linux.waitpid(-1, &status, 0);
    return if (pid > 0) Value{ .int = status } else Value{ .nil = {} };
}

fn sleepImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    const s: u64 = if (args.len > 0 and args[0] == .int) @intCast(@max(args[0].int, 0)) else 0;
    var ts: std.os.linux.timespec = .{ .sec = @intCast(s), .nsec = 0 };
    _ = std.os.linux.nanosleep(&ts, null);
    return Value{ .unit = {} };
}

fn mkdirImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "invalid arg" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
    if (std.os.linux.mkdir(path_z, 0o755) != 0) {
        return value_mod.makeErr(1, Value{ .string = "mkdir error" }, env.allocator) catch return Value{ .nil = {} };
    }
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

fn mkdirAllImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "invalid arg" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
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

fn writeStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .path or args[1] != .string)
        return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
    const fd = std.os.linux.open(path_z, .{ .CREAT = true, .TRUNC = true }, 0o644);
    if (fd < 0) return value_mod.makeErr(1, Value{ .string = "open error" }, env.allocator) catch return Value{ .nil = {} };
    defer _ = std.os.linux.close(@intCast(fd));
    _ = std.os.linux.write(@intCast(fd), args[1].string.ptr, args[1].string.len);
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

fn touchImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
    const fd = std.os.linux.open(path_z, .{ .CREAT = true }, 0o644);
    if (fd >= 0) _ = std.os.linux.close(@intCast(fd));
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

fn removeImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
    if (std.os.linux.unlink(path_z) != 0) {
        return value_mod.makeErr(1, Value{ .string = "remove error" }, env.allocator) catch return Value{ .nil = {} };
    }
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

fn removeDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
    if (std.os.linux.rmdir(path_z) != 0) {
        return value_mod.makeErr(1, Value{ .string = "rmdir error" }, env.allocator) catch return Value{ .nil = {} };
    }
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

fn currentDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    return Value{ .path = env.allocator.dupe(u8, "/") catch return Value{ .nil = {} } };
}

fn homeDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    return Value{ .path = env.allocator.dupe(u8, "/root") catch return Value{ .nil = {} } };
}

fn tempDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    return Value{ .path = env.allocator.dupe(u8, "/tmp") catch return Value{ .nil = {} } };
}

fn mapFileError(err: anyerror) u8 {
    return switch (err) {
        error.FileNotFound => 0,
        error.AccessDenied => 1,
        error.PathAlreadyExists => 2,
        error.NameTooLong => 3,
        error.FileTooBig => 3,
        error.FileSystem => 3,
        else => 4,
    };
}

fn mapKindTag(mode: std.os.linux.mode_t) i64 {
    const masked = mode & std.os.linux.S.IFMT;
    return switch (masked) {
        std.os.linux.S.IFREG => 0,
        std.os.linux.S.IFDIR => 1,
        std.os.linux.S.IFLNK => 2,
        std.os.linux.S.IFSOCK => 3,
        std.os.linux.S.IFIFO => 4,
        std.os.linux.S.IFCHR => 5,
        std.os.linux.S.IFBLK => 6,
        else => 7,
    };
}

fn streamLinesImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .stream) return Value{ .nil = {} };
    const node = value_mod.streamLines(env.allocator, args[0].stream, 65536) catch return Value{ .nil = {} };
    return Value{ .stream = node };
}

fn streamIterImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .unit = {} };
}

fn streamFoldImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .unit = {} };
}

fn streamToListImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .stream) return Value{ .nil = {} };
    var list: std.ArrayListUnmanaged(Value) = .empty;
    while (stream_consumer.consumeNext(args[0].stream, env.allocator, null) catch null) |val| {
        list.append(env.allocator, val) catch return Value{ .nil = {} };
    }
    const items = list.toOwnedSlice(env.allocator) catch return Value{ .nil = {} };
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

fn streamStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .stream) return Value{ .string = "" };
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    while (stream_consumer.consumeNext(args[0].stream, env.allocator, null) catch null) |val| {
        if (val != .string) continue;
        buf.appendSlice(env.allocator, val.string) catch break;
    }
    const s = buf.toOwnedSlice(env.allocator) catch return Value{ .string = "" };
    return Value{ .string = s };
}

fn streamBytesImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .stream) return Value{ .bytes = &.{} };
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    while (stream_consumer.consumeNext(args[0].stream, env.allocator, null) catch null) |val| {
        if (val != .bytes) {
            const s = switch (val) {
                .string => |s| s,
                .int => |i| blk: {
                    var b: [32]u8 = undefined;
                    break :blk std.fmt.bufPrint(&b, "{d}", .{i}) catch continue;
                },
                else => continue,
            };
            buf.appendSlice(env.allocator, s) catch break;
        } else {
            buf.appendSlice(env.allocator, val.bytes) catch break;
        }
    }
    const b = buf.toOwnedSlice(env.allocator) catch return Value{ .bytes = &.{} };
    return Value{ .bytes = b };
}

pub fn buildPrimitiveTable(comptime int_t: TypeId, comptime string_t: TypeId, comptime unit_t: TypeId, comptime stream_string_t: TypeId, comptime bool_t: TypeId, comptime bytes_t: TypeId) PrimitiveTable {
    const P = true;
    const bindings = [_]PrimitiveBinding{
        .{ .module = "IO", .name = "println", .fn_ptr = printlnImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "readln", .fn_ptr = readlnImpl, .arg_count = 0, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "readString", .fn_ptr = readStringImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "list", .fn_ptr = listDirImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "stat", .fn_ptr = statImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Env", .name = "getenv", .fn_ptr = getenvImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Env", .name = "contains", .fn_ptr = containsEnvImpl, .arg_count = 1, .return_type = bool_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "exit", .fn_ptr = exitImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "pid", .fn_ptr = pidImpl, .arg_count = 0, .return_type = int_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "uid", .fn_ptr = uidImpl, .arg_count = 0, .return_type = int_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "gid", .fn_ptr = gidImpl, .arg_count = 0, .return_type = int_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Cmd", .name = "which", .fn_ptr = whichImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Stream", .name = "lines", .fn_ptr = streamLinesImpl, .arg_count = 1, .return_type = stream_string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Stream", .name = "iter", .fn_ptr = streamIterImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = true },
        .{ .module = "Stream", .name = "fold", .fn_ptr = streamFoldImpl, .arg_count = 3, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Stream", .name = "toList", .fn_ptr = streamToListImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Stream", .name = "string", .fn_ptr = streamStringImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Stream", .name = "bytes", .fn_ptr = streamBytesImpl, .arg_count = 1, .return_type = bytes_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "IO", .name = "print", .fn_ptr = printImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "eprint", .fn_ptr = eprintImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "eprintln", .fn_ptr = eprintlnImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "readBytes", .fn_ptr = readBytesImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "readAll", .fn_ptr = readAllImpl, .arg_count = 0, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "readAllBytes", .fn_ptr = readAllBytesImpl, .arg_count = 0, .return_type = bytes_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "isTerminal", .fn_ptr = isTerminalImpl, .arg_count = 0, .return_type = bool_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "flush", .fn_ptr = flushImpl, .arg_count = 0, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "kill", .fn_ptr = killImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "wait", .fn_ptr = waitImpl, .arg_count = 0, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "sleep", .fn_ptr = sleepImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "mkdir", .fn_ptr = mkdirImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "mkdirAll", .fn_ptr = mkdirAllImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "writeString", .fn_ptr = writeStringImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "touch", .fn_ptr = touchImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "remove", .fn_ptr = removeImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "removeDir", .fn_ptr = removeDirImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "currentDir", .fn_ptr = currentDirImpl, .arg_count = 0, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "homeDir", .fn_ptr = homeDirImpl, .arg_count = 0, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "tempDir", .fn_ptr = tempDirImpl, .arg_count = 0, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
    };
    _ = .{ int_t, string_t, unit_t, stream_string_t, bool_t, bytes_t };
    return .{ .bindings = &bindings };
}

const EffectNamespacePattern = struct {
    module: []const u8,
    is_effect: bool,
};

const effect_namespaces = [_]EffectNamespacePattern{
    .{ .module = "IO", .is_effect = true },
    .{ .module = "File", .is_effect = true },
    .{ .module = "Env", .is_effect = true },
    .{ .module = "Process", .is_effect = true },
    .{ .module = "Task", .is_effect = true },
    .{ .module = "Random", .is_effect = true },
    .{ .module = "Stream.iter", .is_effect = true },
};

pub fn isEffectBinding(name: []const u8) bool {
    if (std.mem.eql(u8, name, "Signal.on")) return true;
    if (std.mem.startsWith(u8, name, "Cmd.")) {
        const rest = name["Cmd.".len..];
        if (std.mem.containsAtLeast(u8, rest, 1, "?")) return true;
        if (std.mem.containsAtLeast(u8, rest, 1, "!")) return true;
        if (std.mem.eql(u8, rest, "exec")) return true;
        if (std.mem.eql(u8, rest, "pipe?")) return true;
        if (std.mem.eql(u8, rest, "pipe!")) return true;
        if (std.mem.eql(u8, rest, "timeout")) return true;
        if (std.mem.eql(u8, rest, "retry")) return true;
        if (std.mem.eql(u8, rest, "execSafe")) return true;
        if (std.mem.eql(u8, rest, "which")) return true;
        return false;
    }
    for (effect_namespaces) |ns| {
        if (std.mem.startsWith(u8, name, ns.module) and ns.is_effect) {
            if (name.len == ns.module.len) return true;
            if (name.len > ns.module.len and name[ns.module.len] == '.') return true;
        }
    }
    return false;
}
