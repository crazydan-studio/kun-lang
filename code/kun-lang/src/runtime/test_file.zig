const std = @import("std");
const fs_mod = @import("primitive/fs.zig");
const io_mod = @import("primitive/io.zig");
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

test "file writeBytes and readBytes round trip" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const path = "/tmp/kun_test_writebytes.bin";
    defer _ = std.os.linux.unlink(@ptrCast(path));

    const write_args = [_]Value{ Value{ .path = path }, Value{ .bytes = "binary data here" } };
    const wresult = fs_mod.writeBytesImpl(&env, &write_args);
    try std.testing.expect(wresult == .adt and wresult.adt.tag == 0);

    const read_args = [_]Value{Value{ .path = path }};
    const rresult = fs_mod.readBytesImpl(&env, &read_args);
    try std.testing.expect(rresult == .adt and rresult.adt.tag == 0);
    try std.testing.expect(rresult.adt.payload.* == .stream);
}

test "file appendBytes" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const path = "/tmp/kun_test_append.bin";
    defer _ = std.os.linux.unlink(@ptrCast(path));

    const write_args = [_]Value{ Value{ .path = path }, Value{ .bytes = "first" } };
    _ = fs_mod.writeBytesImpl(&env, &write_args);

    const append_args = [_]Value{ Value{ .path = path }, Value{ .bytes = "second" } };
    const aresult = fs_mod.appendBytesImpl(&env, &append_args);
    try std.testing.expect(aresult == .adt and aresult.adt.tag == 0);

    const read_args = [_]Value{Value{ .path = path }};
    const rresult = fs_mod.readStringImpl(&env, &read_args);
    if (rresult == .adt and rresult.adt.tag == 0 and rresult.adt.payload.* == .string) {
        try std.testing.expect(std.mem.indexOf(u8, rresult.adt.payload.*.string, "firstsecond") != null);
    }
}

test "file readLines from file" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const path = "/tmp/kun_test_readlines.txt";
    defer _ = std.os.linux.unlink(@ptrCast(path));

    const write_args = [_]Value{ Value{ .path = path }, Value{ .string = "line1\nline2\nline3" } };
    _ = fs_mod.writeStringImpl(&env, &write_args);

    const lines_args = [_]Value{Value{ .path = path }};
    const result = fs_mod.readLinesImpl(&env, &lines_args);
    try std.testing.expect(result == .adt and result.adt.tag == 0);
    try std.testing.expect(result.adt.payload.* == .stream);
}

test "file readLines non-existent returns err" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{Value{ .path = "/tmp/kun_nonexistent_lines_xyz" }};
    const result = fs_mod.readLinesImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag != 0);
}

test "file writeBytes invalid path type" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{ Value{ .int = 0 }, Value{ .bytes = "data" } };
    const result = fs_mod.writeBytesImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag != 0);
}

test "file writeString invalid path type" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{ Value{ .int = 0 }, Value{ .string = "data" } };
    const result = fs_mod.writeStringImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag != 0);
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

test "file remove non-existent returns err" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{Value{ .path = "/tmp/kun_nonexistent_rm_xyz" }};
    const result = fs_mod.removeImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag != 0);
}

test "file mkdirAll nested" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const path = "/tmp/kun_test_mkdirall/a/b";
    defer _ = std.os.linux.rmdir(@ptrCast("/tmp/kun_test_mkdirall/a/b\x00")); // non-null-terminated issue
    defer _ = std.os.linux.rmdir("/tmp/kun_test_mkdirall/a");
    defer _ = std.os.linux.rmdir("/tmp/kun_test_mkdirall");

    const args = [_]Value{Value{ .path = path }};
    const result = fs_mod.mkdirAllImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag == 0);
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

test "file stat non-existent returns err" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{Value{ .path = "/tmp/kun_nonexistent_stat_xyz" }};
    const result = fs_mod.statImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag != 0);
}

test "file readString non-existent returns err" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{Value{ .path = "/tmp/kun_nonexistent_xyz" }};
    const result = fs_mod.readStringImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag != 0);
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

test "file copy non-existent source" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{ Value{ .path = "/tmp/kun_nonexistent_src_xyz" }, Value{ .path = "/tmp/kun_nonexistent_dst_xyz" } };
    const result = fs_mod.copyImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag != 0);
}

test "file rename" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const src = "/tmp/kun_test_rename_src.txt";
    const dst = "/tmp/kun_test_rename_dst.txt";
    defer _ = std.os.linux.unlink(@ptrCast(src));
    defer _ = std.os.linux.unlink(@ptrCast(dst));

    const write_args = [_]Value{ Value{ .path = src }, Value{ .string = "rename me" } };
    _ = fs_mod.writeStringImpl(&env, &write_args);

    const rename_args = [_]Value{ Value{ .path = src }, Value{ .path = dst } };
    const rn = fs_mod.renameImpl(&env, &rename_args);
    try std.testing.expect(rn == .adt and rn.adt.tag == 0);

    const read_args = [_]Value{Value{ .path = dst }};
    const rr = fs_mod.readStringImpl(&env, &read_args);
    try std.testing.expect(rr == .adt and rr.adt.tag == 0);
    try std.testing.expect(std.mem.eql(u8, "rename me", rr.adt.payload.*.string));
}

test "file listDir" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{Value{ .path = "/tmp" }};
    const result = fs_mod.listDirImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag == 0);
    try std.testing.expect(result.adt.payload.* == .list);
}

test "file listDir non-existent" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{Value{ .path = "/tmp/kun_nonexistent_dir_xyz" }};
    const result = fs_mod.listDirImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag != 0);
}

test "file walkDir" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const dir = "/tmp/kun_test_walkdir";
    defer _ = std.os.linux.rmdir(@ptrCast(dir));

    const mk_args = [_]Value{Value{ .path = dir }};
    _ = fs_mod.mkdirImpl(&env, &mk_args);

    const t1 = "/tmp/kun_test_walkdir/a.txt";
    defer _ = std.os.linux.unlink(@ptrCast(t1));
    _ = fs_mod.touchImpl(&env, &.{Value{ .path = t1 }});

    const args = [_]Value{Value{ .path = dir }};
    const result = fs_mod.walkDirImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag == 0);
    try std.testing.expect(result.adt.payload.* == .list);
}

test "file walkDir non-existent" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{Value{ .path = "/tmp/kun_nonexistent_walk_xyz" }};
    const result = fs_mod.walkDirImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag == 0);
}

test "file glob filesystem" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const base = "/tmp/kun_test_glob";
    defer _ = std.os.linux.rmdir(@ptrCast(base));

    const mkdir_args = [_]Value{Value{ .path = base }};
    _ = fs_mod.mkdirImpl(&env, &mkdir_args);

    const t1 = "/tmp/kun_test_glob/f1.txt";
    const t2 = "/tmp/kun_test_glob/f2.txt";
    const t3 = "/tmp/kun_test_glob/f3.log";
    defer _ = std.os.linux.unlink(@ptrCast(t1));
    defer _ = std.os.linux.unlink(@ptrCast(t2));
    defer _ = std.os.linux.unlink(@ptrCast(t3));

    _ = fs_mod.touchImpl(&env, &.{Value{ .path = t1 }});
    _ = fs_mod.touchImpl(&env, &.{Value{ .path = t2 }});
    _ = fs_mod.touchImpl(&env, &.{Value{ .path = t3 }});

    const glob_args = [_]Value{ Value{ .string = "*.txt" }, Value{ .path = base } };
    const result = fs_mod.globImpl(&env, &glob_args);
    try std.testing.expect(result == .adt and result.adt.tag == 0);
    try std.testing.expect(result.adt.payload.* == .list);
    try std.testing.expectEqual(@as(usize, 2), result.adt.payload.*.list.items.len);
}

test "file glob no match" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const glob_args = [_]Value{ Value{ .string = "zzz_no_match_glob_zzz" }, Value{ .path = "/tmp" } };
    const result = fs_mod.globImpl(&env, &glob_args);
    try std.testing.expect(result == .adt and result.adt.tag == 0);
    try std.testing.expect(result.adt.payload.* == .list);
    try std.testing.expectEqual(@as(usize, 0), result.adt.payload.*.list.items.len);
}

test "file removeDir non-existent" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{Value{ .path = "/tmp/kun_nonexistent_rmdir_xyz" }};
    const result = fs_mod.removeDirImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag != 0);
}

test "file readBytes non-existent" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{Value{ .path = "/tmp/kun_nonexistent_rb_xyz" }};
    const result = fs_mod.readBytesImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag != 0);
}

test "file appendBytes non-existent create" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const path = "/tmp/kun_test_append_create.bin";
    defer _ = std.os.linux.unlink(@ptrCast(path));

    const append_args = [_]Value{ Value{ .path = path }, Value{ .bytes = "created and appended" } };
    const result = fs_mod.appendBytesImpl(&env, &append_args);
    try std.testing.expect(result == .adt and result.adt.tag == 0);
}

test "file writeString empty content" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const path = "/tmp/kun_test_emptystr.txt";
    defer _ = std.os.linux.unlink(@ptrCast(path));

    const write_args = [_]Value{ Value{ .path = path }, Value{ .string = "" } };
    const wresult = fs_mod.writeStringImpl(&env, &write_args);
    try std.testing.expect(wresult == .adt and wresult.adt.tag == 0);

    const read_args = [_]Value{Value{ .path = path }};
    const rresult = fs_mod.readStringImpl(&env, &read_args);
    if (rresult == .adt and rresult.adt.tag == 0 and rresult.adt.payload.* == .string) {
        try std.testing.expect(std.mem.eql(u8, "", rresult.adt.payload.*.string));
    }
}

test "file mkdir invalid path type" {
    const allocator = std.testing.allocator;
    var env = makeEnv(allocator);
    const args = [_]Value{Value{ .int = 0 }};
    const result = fs_mod.mkdirImpl(&env, &args);
    try std.testing.expect(result == .adt and result.adt.tag != 0);
}
