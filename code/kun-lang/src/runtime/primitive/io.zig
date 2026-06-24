const std = @import("std");
const value_mod = @import("../value.zig");
const RuntimeEnv = @import("../primitive.zig").RuntimeEnv;
const hash_map = @import("../hash_map.zig");

const Value = value_mod.Value;

pub fn allocSentinel(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
    const buf = try allocator.allocSentinel(u8, s.len, 0);
    @memcpy(buf[0..s.len], s);
    return buf;
}

pub fn printlnImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len > 0 and args[0] == .string) {
        const msg = std.fmt.allocPrint(env.allocator, "{s}\n", .{args[0].string}) catch return Value{ .unit = {} };
        defer env.allocator.free(msg);
        _ = std.os.linux.write(1, msg.ptr, msg.len);
    }
    return Value{ .unit = {} };
}

pub fn printImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len > 0 and args[0] == .string) {
        _ = std.os.linux.write(1, args[0].string.ptr, args[0].string.len);
    }
    return Value{ .unit = {} };
}

pub fn readlnImpl(env: *RuntimeEnv, args: []const Value) Value {
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

pub fn eprintImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    if (args.len > 0 and args[0] == .string) {
        _ = std.os.linux.write(2, args[0].string.ptr, args[0].string.len);
    }
    return Value{ .unit = {} };
}

pub fn eprintlnImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len > 0 and args[0] == .string) {
        const msg = std.fmt.allocPrint(env.allocator, "{s}\n", .{args[0].string}) catch return Value{ .unit = {} };
        defer env.allocator.free(msg);
        _ = std.os.linux.write(2, msg.ptr, msg.len);
    }
    return Value{ .unit = {} };
}

pub fn readBytesImpl(env: *RuntimeEnv, args: []const Value) Value {
    const max: usize = if (args.len > 0 and args[0] == .int) @intCast(@max(args[0].int, 0)) else 4096;
    const buf = env.allocator.alloc(u8, max) catch return value_mod.makeErr(4, Value{ .string = "oom" }, env.allocator) catch return Value{ .nil = {} };
    const n = std.os.linux.read(0, buf.ptr, buf.len);
    if (n <= 0) return value_mod.makeErr(4, Value{ .string = "read error" }, env.allocator) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .bytes = buf[0..n] }, env.allocator) catch return Value{ .nil = {} };
}

pub fn readAllImpl(env: *RuntimeEnv, args: []const Value) Value {
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

pub fn readAllBytesImpl(env: *RuntimeEnv, args: []const Value) Value {
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

pub fn isTerminalImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    const TCGETS = 0x5401;
    var termios: std.os.linux.termios = undefined;
    const result = std.os.linux.ioctl(1, TCGETS, @intFromPtr(&termios));
    return Value{ .bool = result == 0 };
}

pub fn flushImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .unit = {} };
}

pub fn getenvImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .string) return Value{ .nil = {} };
    const key = args[0].string;
    const fd = std.os.linux.open("/proc/self/environ", .{}, 0);
    if (fd < 0) return Value{ .nil = {} };
    defer _ = std.os.linux.close(@intCast(fd));
    var buf: [8192]u8 = undefined;
    const n = std.os.linux.read(@intCast(fd), &buf, buf.len);
    if (n <= 0) return Value{ .nil = {} };
    var start: usize = 0;
    var i: usize = 0;
    const data = buf[0..@intCast(n)];
    while (i < data.len) : (i += 1) {
        if (data[i] == 0) {
            if (i > start) {
                const entry = data[start..i];
                if (std.mem.indexOfScalar(u8, entry, '=')) |eq_pos| {
                    if (std.mem.eql(u8, entry[0..eq_pos], key)) {
                        return Value{ .string = env.allocator.dupe(u8, entry[eq_pos + 1 ..]) catch return Value{ .nil = {} } };
                    }
                }
            }
            start = i + 1;
        }
    }
    return Value{ .nil = {} };
}

pub fn containsEnvImpl(env: *RuntimeEnv, args: []const Value) Value {
    const result = getenvImpl(env, args);
    return Value{ .bool = result != .nil };
}

pub fn envListImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    var map_repr = value_mod.MapRepr{ .entries = @constCast(&[0]u8{}), .len = 0, .cap = 0 };
    const fd = std.os.linux.open("/proc/self/environ", .{}, 0);
    if (fd < 0) return Value{ .map = map_repr };
    defer _ = std.os.linux.close(@intCast(fd));

    var buf: [8192]u8 = undefined;
    const n = std.os.linux.read(@intCast(fd), &buf, buf.len);
    if (n <= 0) return Value{ .map = map_repr };

    var start: usize = 0;
    var pos: usize = 0;
    while (pos < @as(usize, @intCast(n))) : (pos += 1) {
        if (buf[pos] == 0) {
            if (pos > start) {
                const entry_str = buf[start..pos];
                if (std.mem.indexOfScalar(u8, entry_str, '=')) |eq_pos| {
                    const key = env.allocator.dupe(u8, entry_str[0..eq_pos]) catch {
                        start = pos + 1;
                        continue;
                    };
                    const val_str = env.allocator.dupe(u8, entry_str[eq_pos + 1 ..]) catch {
                        start = pos + 1;
                        continue;
                    };
                    map_repr = hash_map.mapInsert(env.allocator, map_repr.entries, map_repr.len, map_repr.cap, Value{ .string = key }, Value{ .string = val_str }) catch continue;
                }
            }
            start = pos + 1;
        }
    }
    return Value{ .map = map_repr };
}

pub fn exitImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    const code: u8 = if (args.len > 0 and args[0] == .int) @intCast(@min(args[0].int, 255)) else 0;
    std.process.exit(code);
}

pub fn pidImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .int = @intCast(std.os.linux.getpid()) };
}

pub fn uidImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .int = @intCast(std.os.linux.getuid()) };
}

pub fn gidImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .int = @intCast(std.os.linux.getgid()) };
}

pub fn killImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    if (args[0] != .int or args[1] != .int) return value_mod.makeErr(1, Value{ .string = "args" }, env.allocator) catch return Value{ .nil = {} };
    _ = std.os.linux.kill(@intCast(args[0].int), @enumFromInt(@as(u32, @intCast(args[1].int))));
    return value_mod.makeOk(Value{ .unit = {} }, env.allocator) catch return Value{ .nil = {} };
}

pub fn waitImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    var status: i32 = 0;
    const pid = std.os.linux.waitpid(-1, &status, 0);
    return if (pid > 0) Value{ .int = status } else Value{ .nil = {} };
}

pub fn sleepImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    const s: u64 = if (args.len > 0 and args[0] == .int) @intCast(@max(args[0].int, 0)) else 0;
    var ts: std.os.linux.timespec = .{ .sec = @intCast(s), .nsec = 0 };
    _ = std.os.linux.nanosleep(&ts, null);
    return Value{ .unit = {} };
}

pub fn whichImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 1 or args[0] != .string) return Value{ .nil = {} };
    const path_env = getEnvValue(env.allocator, "PATH") orelse "/usr/bin:/bin";
    var it = std.mem.splitSequence(u8, path_env, ":");
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
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

fn getEnvValue(allocator: std.mem.Allocator, key: []const u8) ?[]const u8 {
    const fd = std.os.linux.open("/proc/self/environ", .{}, 0);
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
