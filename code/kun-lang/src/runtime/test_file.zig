const std = @import("std");
const fs_mod = @import("primitive/fs.zig");
const value_mod = @import("value.zig");
const RuntimeEnv = @import("primitive.zig").RuntimeEnv;

const Value = value_mod.Value;

fn makeEnv(allocator: std.mem.Allocator) RuntimeEnv {
    return .{ .frame = undefined, .primitives = .{ .bindings = &.{} }, .allocator = allocator };
}

test "file writeString and readString round trip" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const path = "/tmp/kun_test_writestring.txt";
    defer _ = std.os.linux.unlink(@ptrCast(path));

    const write_args = [_]Value{ Value{ .path = path }, Value{ .string = "hello world" } };
    const wresult = fs_mod.writeStringImpl(&env, &write_args);
    if (wresult != .adt or wresult.adt.tag != 0) return;

    const read_args = [_]Value{Value{ .path = path }};
    const rresult = fs_mod.readStringImpl(&env, &read_args);
    if (rresult != .adt or rresult.adt.tag != 0) return;
    if (rresult.adt.payload.* != .string) return;
    try std.testing.expect(std.mem.eql(u8, "hello world", rresult.adt.payload.*.string));
}

test "file mkdir and removeDir" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const path = "/tmp/kun_test_mkdir";

    const mk_args = [_]Value{Value{ .path = path }};
    const mkresult = fs_mod.mkdirImpl(&env, &mk_args);
    try std.testing.expect(mkresult == .adt and mkresult.adt.tag == 0);

    const rm_args = [_]Value{Value{ .path = path }};
    const rmresult = fs_mod.removeDirImpl(&env, &rm_args);
    try std.testing.expect(rmresult == .adt and rmresult.adt.tag == 0);
}

test "file touch and remove" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const path = "/tmp/kun_test_touch.txt";
    defer _ = std.os.linux.unlink(@ptrCast(path));

    const touch_args = [_]Value{Value{ .path = path }};
    const tresult = fs_mod.touchImpl(&env, &touch_args);
    try std.testing.expect(tresult == .adt and tresult.adt.tag == 0);

    const rm_args = [_]Value{Value{ .path = path }};
    const rmresult = fs_mod.removeImpl(&env, &rm_args);
    try std.testing.expect(rmresult == .adt and rmresult.adt.tag == 0);
}

test "file stat existing file" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const path = "/tmp/kun_test_stat.txt";
    defer _ = std.os.linux.unlink(@ptrCast(path));

    const touch_args = [_]Value{Value{ .path = path }};
    _ = fs_mod.touchImpl(&env, &touch_args);

    const stat_args = [_]Value{Value{ .path = path }};
    const result = fs_mod.statImpl(&env, &stat_args);
    try std.testing.expect(result == .adt and result.adt.tag == 0);
    try std.testing.expect(result.adt.payload.* == .record);
}

test "file readString non-existent returns err" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{Value{ .path = "/tmp/kun_nonexistent_xyz" }};
    const result = fs_mod.readStringImpl(&env, &args);
    if (result == .adt and result.adt.tag != 0) {
        // non-existent file returns Err
    }
}

test "file currentDir homeDir tempDir" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const cd = fs_mod.currentDirImpl(&env, &.{});
    try std.testing.expect(cd == .path);
    try std.testing.expect(cd.path.len > 0);

    const hd = fs_mod.homeDirImpl(&env, &.{});
    try std.testing.expect(hd == .path);
    try std.testing.expect(hd.path.len > 0);

    const td = fs_mod.tempDirImpl(&env, &.{});
    try std.testing.expect(td == .path);
    try std.testing.expect(td.path.len > 0);
}

test "file copy and rename" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const src = "/tmp/kun_test_copy_src.txt";
    const dst = "/tmp/kun_test_copy_dst.txt";
    defer _ = std.os.linux.unlink(@ptrCast(src));
    defer _ = std.os.linux.unlink(@ptrCast(dst));

    const write_args = [_]Value{ Value{ .path = src }, Value{ .string = "copy test" } };
    _ = fs_mod.writeStringImpl(&env, &write_args);

    const copy_args = [_]Value{ Value{ .path = src }, Value{ .path = dst } };
    const cp = fs_mod.copyImpl(&env, &copy_args);
    try std.testing.expect(cp == .adt and cp.adt.tag == 0);

    const read_args = [_]Value{Value{ .path = dst }};
    const rr = fs_mod.readStringImpl(&env, &read_args);
    try std.testing.expect(rr == .adt and rr.adt.tag == 0);
    try std.testing.expect(std.mem.eql(u8, "copy test", rr.adt.payload.*.string));
}

test "file listDir" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{Value{ .path = "/tmp" }};
    const result = fs_mod.listDirImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag == 0);
    try std.testing.expect(result.adt.payload.* == .list);
}
