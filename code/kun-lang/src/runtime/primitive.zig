const std = @import("std");
const value_mod = @import("value.zig");
const typed = @import("../ast/typed.zig");
const stream_consumer = @import("stream_consumer.zig");

const Value = value_mod.Value;
const TypeId = typed.TypeId;
const Frame = @import("env.zig").Frame;
const StreamNode = value_mod.StreamNode;
const StreamFn = value_mod.StreamFn;
const cmd_mod = @import("cmd.zig");

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

fn listLengthImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .list) return Value{ .int = 0 };
    return Value{ .int = @intCast(args[0].list.items.len) };
}

fn listIsEmptyImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .list) return Value{ .bool = true };
    return Value{ .bool = args[0].list.items.len == 0 };
}

fn listHeadImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .list or args[0].list.items.len == 0) return Value{ .nil = {} };
    return args[0].list.items[0];
}

fn listLastImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .list or args[0].list.items.len == 0) return Value{ .nil = {} };
    return args[0].list.items[args[0].list.items.len - 1];
}

fn listGetImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 2 or args[0] != .int or args[1] != .list) return Value{ .nil = {} };
    const idx: usize = @intCast(@max(args[0].int, 0));
    if (idx >= args[1].list.items.len) return Value{ .nil = {} };
    return args[1].list.items[idx];
}

fn listAppendImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .list or args[1] != .list) return Value{ .nil = {} };
    const a = args[0].list;
    const b = args[1].list;
    const items = env.allocator.alloc(Value, a.items.len + b.items.len) catch return Value{ .nil = {} };
    @memcpy(items[0..a.items.len], a.items);
    @memcpy(items[a.items.len..], b.items);
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

fn listReverseImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .list) return Value{ .nil = {} };
    const src = args[0].list.items;
    const items = env.allocator.alloc(Value, src.len) catch return Value{ .nil = {} };
    for (src, 0..) |v, i| {
        items[src.len - 1 - i] = v;
    }
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

fn listSortImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[1] != .list) return Value{ .nil = {} };
    const src = args[1].list.items;
    if (src.len == 0) return args[1];
    const items = env.allocator.alloc(Value, src.len) catch return Value{ .nil = {} };
    @memcpy(items, src);
    std.mem.sort(Value, items, {}, cmpValue);
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

fn cmpValue(_: void, a: Value, b: Value) bool {
    if (a == .int and b == .int) return a.int < b.int;
    if (a == .string and b == .string) return std.mem.lessThan(u8, a.string, b.string);
    return @intFromEnum(a) < @intFromEnum(b);
}

fn listSliceImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 3 or args[0] != .int or args[1] != .int or args[2] != .list) return Value{ .nil = {} };
    const start: usize = @intCast(@max(args[0].int, 0));
    const len: usize = @intCast(@max(args[1].int, 0));
    const src = args[2].list.items;
    const actual_start = @min(start, src.len);
    const actual_end = @min(actual_start + len, src.len);
    const items = env.allocator.alloc(Value, actual_end - actual_start) catch return Value{ .nil = {} };
    @memcpy(items, src[actual_start..actual_end]);
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

fn listTakeImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .int or args[1] != .list) return Value{ .nil = {} };
    const n: usize = @intCast(@max(args[0].int, 0));
    const src = args[1].list.items;
    const count = @min(n, src.len);
    const items = env.allocator.alloc(Value, count) catch return Value{ .nil = {} };
    @memcpy(items, src[0..count]);
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

fn listDropImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .int or args[1] != .list) return Value{ .nil = {} };
    const n: usize = @intCast(@max(args[0].int, 0));
    const src = args[1].list.items;
    if (n >= src.len) return Value{ .list = .{ .items = &.{}, .cap = 0 } };
    const items = env.allocator.alloc(Value, src.len - n) catch return Value{ .nil = {} };
    @memcpy(items, src[n..]);
    return Value{ .list = .{ .items = items, .cap = items.len } };
}

fn bytesLengthImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .bytes) return Value{ .int = 0 };
    return Value{ .int = @intCast(args[0].bytes.len) };
}

fn bytesSliceImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 3 or args[0] != .int or args[1] != .int or args[2] != .bytes) return Value{ .bytes = &.{} };
    const start: usize = @intCast(@max(args[0].int, 0));
    const len: usize = @intCast(@max(args[1].int, 0));
    const src = args[2].bytes;
    if (start >= src.len) return Value{ .bytes = &.{} };
    const end = @min(start + len, src.len);
    return Value{ .bytes = src[start..end] };
}

fn stringLengthImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .string) return Value{ .int = 0 };
    return Value{ .int = @intCast(args[0].string.len) };
}

fn stringSliceImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 3 or args[0] != .int or args[1] != .int or args[2] != .string) return Value{ .string = "" };
    const start: usize = @intCast(@max(args[0].int, 0));
    const len: usize = @intCast(@max(args[1].int, 0));
    const src = args[2].string;
    if (start >= src.len) return Value{ .string = "" };
    const end = @min(start + len, src.len);
    const result = env.allocator.dupe(u8, src[start..end]) catch return Value{ .string = "" };
    return Value{ .string = result };
}

fn stringToStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1) return Value{ .string = "" };
    return switch (args[0]) {
        .int => |i| {
            const s = std.fmt.allocPrint(env.allocator, "{d}", .{i}) catch return Value{ .string = "" };
            return Value{ .string = s };
        },
        .float => |f| {
            const s = std.fmt.allocPrint(env.allocator, "{d}", .{f}) catch return Value{ .string = "" };
            return Value{ .string = s };
        },
        .bool => |b| Value{ .string = if (b) "true" else "false" },
        .string => |s| Value{ .string = s },
        else => Value{ .string = "" },
    };
}

fn mapSizeImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .map) return Value{ .int = 0 };
    return Value{ .int = @intCast(args[0].map.len) };
}

fn mapIsEmptyImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .map) return Value{ .bool = true };
    return Value{ .bool = args[0].map.len == 0 };
}

fn mapInsertImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn mapGetImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn mapRemoveImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn mapKeysImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .list = .{ .items = &.{}, .cap = 0 } };
}

fn mapValuesImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .list = .{ .items = &.{}, .cap = 0 } };
}

fn setSizeImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .set) return Value{ .int = 0 };
    return Value{ .int = @intCast(args[0].set.len) };
}

fn setIsEmptyImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len < 1 or args[0] != .set) return Value{ .bool = true };
    return Value{ .bool = args[0].set.len == 0 };
}

fn setContainsImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .bool = false };
}

fn setInsertImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn setRemoveImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn envListImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .map = .{ .entries = @constCast(&[0]u8{}), .len = 0, .cap = 0 } };
}

fn streamFromListImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .list) return Value{ .stream = value_mod.streamFromList(env.allocator, &.{}) catch return Value{ .nil = {} } };
    const node = value_mod.streamFromList(env.allocator, args[0].list.items) catch return Value{ .nil = {} };
    return Value{ .stream = node };
}

fn streamRangeImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn streamIterateImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn streamLinesMaxImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .int or args[1] != .stream) return Value{ .nil = {} };
    const node = value_mod.streamLines(env.allocator, args[1].stream, @intCast(@max(args[0].int, 0))) catch return Value{ .nil = {} };
    return Value{ .stream = node };
}

fn cmdExecImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .command) return Value{ .unit = {} };
    const stream_node = cmd_mod.execCommand(&args[0].command, env.allocator) catch return Value{ .unit = {} };
    while (stream_consumer.consumeNext(stream_node, env.allocator, null) catch null) |_| {}
    return Value{ .unit = {} };
}

fn cmdExecSafeImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .command) return value_mod.makeErr(2, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .stream = cmd_mod.execCommand(&args[0].command, env.allocator) catch return value_mod.makeErr(2, Value{ .string = "exec error" }, env.allocator) catch return Value{ .nil = {} } }, env.allocator) catch return Value{ .nil = {} };
}

fn cmdPipeImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn cmdPipeBangImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .unit = {} };
}

fn fileReadBytesImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .path) return value_mod.makeErr(0, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
    const fd = std.os.linux.open(path_z, .{}, 0);
    if (fd < 0) return value_mod.makeErr(0, Value{ .string = "not found" }, env.allocator) catch return Value{ .nil = {} };
    const buf = env.allocator.alloc(u8, 4096) catch { _ = std.os.linux.close(@intCast(fd)); return Value{ .nil = {} }; };
    const node = env.allocator.create(StreamNode) catch return Value{ .nil = {} };
    node.* = .{ .cmd = .{ .fd = @intCast(fd), .pid = -1, .buf = buf } };
    return value_mod.makeOk(Value{ .stream = node }, env.allocator) catch return Value{ .nil = {} };
}

fn fileWriteBytesImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn fileAppendStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .path or args[1] != .string)
        return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const path_z = allocSentinel(env.allocator, args[0].path) catch return Value{ .nil = {} };
    defer env.allocator.free(path_z);
    const fd = std.os.linux.open(path_z, .{ .CREAT = true, .TRUNC = false }, 0o644);
    if (fd < 0) {
        return value_mod.makeErr(0, Value{ .string = "open" }, env.allocator) catch return Value{ .nil = {} };
    }
    defer _ = std.os.linux.close(@intCast(fd));
    _ = std.os.linux.lseek(@intCast(fd), 0, std.os.linux.SEEK.END);
    _ = std.os.linux.write(@intCast(fd), args[1].string.ptr, args[1].string.len);
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

fn fileAppendBytesImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn fileReadLinesImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn fileWalkDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn fileGlobImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn fileCreateTempFileImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    const name = std.fmt.allocPrint(env.allocator, "/tmp/kun_XXXXXX", .{}) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .path = name }, env.allocator) catch return Value{ .nil = {} };
}

fn fileCreateTempDirImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    const name = std.fmt.allocPrint(env.allocator, "/tmp/kun_XXXXXX", .{}) catch return Value{ .nil = {} };
    _ = std.os.linux.mkdir(@ptrCast(name.ptr), 0o700);
    return value_mod.makeOk(Value{ .path = name }, env.allocator) catch return Value{ .nil = {} };
}

fn fileCopyImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn fileRenameImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn fileRemoveAllImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn fileAtomicWriteImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn sha256Impl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .bytes) return Value{ .bytes = &.{} };
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(args[0].bytes, &out, .{});
    const result = env.allocator.dupe(u8, &out) catch return Value{ .nil = {} };
    return Value{ .bytes = result };
}

fn sha256HexImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .bytes) return Value{ .string = "" };
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(args[0].bytes, &out, .{});
    const hex_chars = "0123456789abcdef";
    const result = env.allocator.alloc(u8, 64) catch return Value{ .string = "" };
    for (&out, 0..) |byte, i| {
        result[i * 2] = hex_chars[byte >> 4];
        result[i * 2 + 1] = hex_chars[byte & 0xF];
    }
    return Value{ .string = result };
}

fn sha256StreamImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .bytes = &.{} };
}

fn base64EncodeImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .bytes) return Value{ .string = "" };
    const encoder = std.base64.standard.Encoder;
    const out_len = encoder.calcSize(args[0].bytes.len);
    const buf = env.allocator.alloc(u8, out_len) catch return Value{ .string = "" };
    const encoded = encoder.encode(buf, args[0].bytes);
    return Value{ .string = encoded };
}

fn base64DecodeImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .string) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    const decoder = std.base64.standard.Decoder;
    const out_len = decoder.calcSizeForSlice(args[0].string) catch return value_mod.makeErr(1, Value{ .string = "invalid" }, env.allocator) catch return Value{ .nil = {} };
    const buf = env.allocator.alloc(u8, out_len) catch return Value{ .nil = {} };
    decoder.decode(buf, args[0].string) catch return value_mod.makeErr(1, Value{ .string = "decode error" }, env.allocator) catch return Value{ .nil = {} };
    return Value{ .bytes = buf };
}

fn dateTimeNowImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .int = 0 };
}

fn dateTimeFormatImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn dateTimeParseImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn jsonFromStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn jsonToStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn regexIsMatchImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .bool = false };
}

fn regexFromStringImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn validatorRegexImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn regexAllMatchesImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env; _ = args;
    return Value{ .list = .{ .items = &.{}, .cap = 0 } };
}

fn regexFirstMatchImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env; _ = args;
    return Value{ .nil = {} };
}

fn regexReplaceImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env; _ = args;
    return Value{ .string = "" };
}

fn regexReplaceAllImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env; _ = args;
    return Value{ .string = "" };
}

fn regexSplitImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env; _ = args;
    return Value{ .list = .{ .items = &.{}, .cap = 0 } };
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
        .{ .module = "List", .name = "length", .fn_ptr = listLengthImpl, .arg_count = 1, .return_type = int_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "isEmpty", .fn_ptr = listIsEmptyImpl, .arg_count = 1, .return_type = bool_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "head", .fn_ptr = listHeadImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "last", .fn_ptr = listLastImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "get", .fn_ptr = listGetImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "append", .fn_ptr = listAppendImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "reverse", .fn_ptr = listReverseImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "sort", .fn_ptr = listSortImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "slice", .fn_ptr = listSliceImpl, .arg_count = 3, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "take", .fn_ptr = listTakeImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "drop", .fn_ptr = listDropImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Map", .name = "get", .fn_ptr = mapGetImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Map", .name = "keys", .fn_ptr = mapKeysImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Map", .name = "values", .fn_ptr = mapValuesImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Map", .name = "size", .fn_ptr = mapSizeImpl, .arg_count = 1, .return_type = int_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Map", .name = "isEmpty", .fn_ptr = mapIsEmptyImpl, .arg_count = 1, .return_type = bool_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Map", .name = "insert", .fn_ptr = mapInsertImpl, .arg_count = 3, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Map", .name = "remove", .fn_ptr = mapRemoveImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Set", .name = "size", .fn_ptr = setSizeImpl, .arg_count = 1, .return_type = int_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Set", .name = "isEmpty", .fn_ptr = setIsEmptyImpl, .arg_count = 1, .return_type = bool_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Set", .name = "contains", .fn_ptr = setContainsImpl, .arg_count = 2, .return_type = bool_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Set", .name = "insert", .fn_ptr = setInsertImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Set", .name = "remove", .fn_ptr = setRemoveImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Bytes", .name = "length", .fn_ptr = bytesLengthImpl, .arg_count = 1, .return_type = int_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Bytes", .name = "slice", .fn_ptr = bytesSliceImpl, .arg_count = 3, .return_type = bytes_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "String", .name = "length", .fn_ptr = stringLengthImpl, .arg_count = 1, .return_type = int_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "String", .name = "slice", .fn_ptr = stringSliceImpl, .arg_count = 3, .return_type = string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "String", .name = "toString", .fn_ptr = stringToStringImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Env", .name = "list", .fn_ptr = envListImpl, .arg_count = 0, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Stream", .name = "fromList", .fn_ptr = streamFromListImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Stream", .name = "range", .fn_ptr = streamRangeImpl, .arg_count = 3, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Stream", .name = "iterate", .fn_ptr = streamIterateImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Stream", .name = "linesMax", .fn_ptr = streamLinesMaxImpl, .arg_count = 2, .return_type = stream_string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Cmd", .name = "exec", .fn_ptr = cmdExecImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Cmd", .name = "execSafe", .fn_ptr = cmdExecSafeImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Cmd", .name = "pipe?", .fn_ptr = cmdPipeImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Cmd", .name = "pipe!", .fn_ptr = cmdPipeBangImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "readBytes", .fn_ptr = fileReadBytesImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "writeBytes", .fn_ptr = fileWriteBytesImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "appendString", .fn_ptr = fileAppendStringImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "appendBytes", .fn_ptr = fileAppendBytesImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "readLines", .fn_ptr = fileReadLinesImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "walkDir", .fn_ptr = fileWalkDirImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "glob", .fn_ptr = fileGlobImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "createTempFile", .fn_ptr = fileCreateTempFileImpl, .arg_count = 0, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "createTempDir", .fn_ptr = fileCreateTempDirImpl, .arg_count = 0, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "copy", .fn_ptr = fileCopyImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "rename", .fn_ptr = fileRenameImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "removeAll", .fn_ptr = fileRemoveAllImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "atomicWriteString", .fn_ptr = fileAtomicWriteImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Hash", .name = "sha256", .fn_ptr = sha256Impl, .arg_count = 1, .return_type = bytes_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Hash", .name = "sha256Hex", .fn_ptr = sha256HexImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Hash", .name = "sha256Stream", .fn_ptr = sha256StreamImpl, .arg_count = 1, .return_type = bytes_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Base64", .name = "encode", .fn_ptr = base64EncodeImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Base64", .name = "decode", .fn_ptr = base64DecodeImpl, .arg_count = 1, .return_type = bytes_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "DateTime", .name = "now", .fn_ptr = dateTimeNowImpl, .arg_count = 0, .return_type = int_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "DateTime", .name = "format", .fn_ptr = dateTimeFormatImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "DateTime", .name = "parse", .fn_ptr = dateTimeParseImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Parser.JSON", .name = "fromString", .fn_ptr = jsonFromStringImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Parser.JSON", .name = "toString", .fn_ptr = jsonToStringImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Regex", .name = "isMatch", .fn_ptr = regexIsMatchImpl, .arg_count = 2, .return_type = bool_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Regex", .name = "fromString", .fn_ptr = regexFromStringImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Regex", .name = "firstMatch", .fn_ptr = regexFirstMatchImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Regex", .name = "allMatches", .fn_ptr = regexAllMatchesImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Regex", .name = "replace", .fn_ptr = regexReplaceImpl, .arg_count = 3, .return_type = string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Regex", .name = "replaceAll", .fn_ptr = regexReplaceAllImpl, .arg_count = 3, .return_type = string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Regex", .name = "split", .fn_ptr = regexSplitImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Validator", .name = "regex", .fn_ptr = validatorRegexImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
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
