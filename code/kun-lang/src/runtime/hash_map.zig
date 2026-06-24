const std = @import("std");
const value_mod = @import("value.zig");

const Value = value_mod.Value;
const MapRepr = value_mod.MapRepr;
const SetRepr = value_mod.SetRepr;

const MIN_CAP: u64 = 8;
const LOAD_FACTOR_NUM: u64 = 7;
const LOAD_FACTOR_DEN: u64 = 10;

const MapBucket = struct {
    hash: u64,
    key: Value,
    value: Value,
    occupied: bool,

    comptime {
        if (@sizeOf(@This()) % @alignOf(Value) != 0) {
            @compileError("MapBucket alignment mismatch with Value");
        }
    }
};

const SetBucket = struct {
    hash: u64,
    key: Value,
    occupied: bool,

    comptime {
        if (@sizeOf(@This()) % @alignOf(Value) != 0) {
            @compileError("SetBucket alignment mismatch with Value");
        }
    }
};

pub fn hashKey(key: Value) u64 {
    return switch (key) {
        .int => |i| @bitCast(@as(u64, @intCast(i))),
        .string => |s| std.hash.Wyhash.hash(0, s),
        .bool => |b| @intFromBool(b),
        .char => |c| @as(u64, c),
        .path => |p| std.hash.Wyhash.hash(0, p),
        .duration => |d| @bitCast(@as(u64, @intCast(d))),
        else => 0,
    };
}

pub fn keyEqual(a: Value, b: Value) bool {
    if (@intFromEnum(a) != @intFromEnum(b)) return false;
    return switch (a) {
        .int => |ai| b.int == ai,
        .string => |as| std.mem.eql(u8, as, b.string),
        .bool => |ab| b.bool == ab,
        .char => |ac| b.char == ac,
        .path => |ap| std.mem.eql(u8, ap, b.path),
        .duration => |ad| b.duration == ad,
        else => false,
    };
}

fn findMapSlot(buckets: []MapBucket, cap: u64, key: Value, key_hash: u64) ?usize {
    var idx: usize = @intCast(key_hash % cap);
    var i: u64 = 0;
    while (i < cap) : (i += 1) {
        if (!buckets[idx].occupied) return idx;
        if (buckets[idx].hash == key_hash and keyEqual(buckets[idx].key, key)) return idx;
        idx = (idx + 1) % @as(usize, @intCast(cap));
    }
    return null;
}

fn findSetSlot(buckets: []SetBucket, cap: u64, key: Value, key_hash: u64) ?usize {
    var idx: usize = @intCast(key_hash % cap);
    var i: u64 = 0;
    while (i < cap) : (i += 1) {
        if (!buckets[idx].occupied) return idx;
        if (buckets[idx].hash == key_hash and keyEqual(buckets[idx].key, key)) return idx;
        idx = (idx + 1) % @as(usize, @intCast(cap));
    }
    return null;
}

fn findMapSlotForGet(buckets: []MapBucket, cap: u64, key: Value, key_hash: u64) ?usize {
    var idx: usize = @intCast(key_hash % cap);
    var i: u64 = 0;
    while (i < cap) : (i += 1) {
        if (!buckets[idx].occupied) return null;
        if (buckets[idx].hash == key_hash and keyEqual(buckets[idx].key, key)) return idx;
        idx = (idx + 1) % @as(usize, @intCast(cap));
    }
    return null;
}

fn findSetSlotForGet(buckets: []SetBucket, cap: u64, key: Value, key_hash: u64) ?usize {
    var idx: usize = @intCast(key_hash % cap);
    var i: u64 = 0;
    while (i < cap) : (i += 1) {
        if (!buckets[idx].occupied) return null;
        if (buckets[idx].hash == key_hash and keyEqual(buckets[idx].key, key)) return idx;
        idx = (idx + 1) % @as(usize, @intCast(cap));
    }
    return null;
}

fn needsResize(len: u64, cap: u64) bool {
    return len * LOAD_FACTOR_DEN >= cap * LOAD_FACTOR_NUM;
}

fn resizeMap(allocator: std.mem.Allocator, old_entries: [*]u8, old_len: u64, old_cap: u64) !MapRepr {
    const new_cap = if (old_cap == 0) MIN_CAP else old_cap * 2;
    const new_bytes = try allocator.alloc(u8, @sizeOf(MapBucket) * new_cap);
    @memset(new_bytes, 0);
    const new_buckets: []MapBucket = @alignCast(std.mem.bytesAsSlice(MapBucket, new_bytes));

    const old_buckets: []MapBucket = if (old_cap > 0)
        @alignCast(std.mem.bytesAsSlice(MapBucket, old_entries[0 .. @sizeOf(MapBucket) * old_cap]))
    else
        &[_]MapBucket{};

    for (old_buckets) |b| {
        if (!b.occupied) continue;
        if (findMapSlot(new_buckets, new_cap, b.key, b.hash)) |slot| {
            new_buckets[slot] = b;
        }
    }

    return MapRepr{ .entries = new_bytes.ptr, .len = old_len, .cap = new_cap };
}

fn resizeSet(allocator: std.mem.Allocator, old_entries: [*]u8, old_len: u64, old_cap: u64) !SetRepr {
    const new_cap = if (old_cap == 0) MIN_CAP else old_cap * 2;
    const new_bytes = try allocator.alloc(u8, @sizeOf(SetBucket) * new_cap);
    @memset(new_bytes, 0);
    const new_buckets: []SetBucket = @alignCast(std.mem.bytesAsSlice(SetBucket, new_bytes));

    const old_buckets: []SetBucket = if (old_cap > 0)
        @alignCast(std.mem.bytesAsSlice(SetBucket, old_entries[0 .. @sizeOf(SetBucket) * old_cap]))
    else
        &[_]SetBucket{};

    for (old_buckets) |b| {
        if (!b.occupied) continue;
        if (findSetSlot(new_buckets, new_cap, b.key, b.hash)) |slot| {
            new_buckets[slot] = b;
        }
    }

    return SetRepr{ .entries = new_bytes.ptr, .len = old_len, .cap = new_cap };
}

pub fn mapGet(entries: [*]u8, len: u64, cap: u64, key: Value) ?Value {
    _ = len;
    if (cap == 0) return null;
    const kh = hashKey(key);
    const buckets: []MapBucket = @alignCast(std.mem.bytesAsSlice(MapBucket, entries[0 .. @sizeOf(MapBucket) * cap]));
    if (findMapSlotForGet(buckets, cap, key, kh)) |slot| {
        return buckets[slot].value;
    }
    return null;
}

pub fn mapInsert(allocator: std.mem.Allocator, entries: [*]u8, len: u64, cap: u64, key: Value, value: Value) !MapRepr {
    const kh = hashKey(key);
    var repr = MapRepr{ .entries = entries, .len = len, .cap = cap };

    if (needsResize(repr.len, repr.cap)) {
        repr = try resizeMap(allocator, repr.entries, repr.len, repr.cap);
    }

    const buckets: []MapBucket = @alignCast(std.mem.bytesAsSlice(MapBucket, repr.entries[0 .. @sizeOf(MapBucket) * repr.cap]));
    if (findMapSlot(buckets, repr.cap, key, kh)) |slot| {
        const is_new = !buckets[slot].occupied;
        buckets[slot] = MapBucket{ .hash = kh, .key = key, .value = value, .occupied = true };
        if (is_new) repr.len += 1;
    }

    return repr;
}

pub fn mapRemove(allocator: std.mem.Allocator, entries: [*]u8, len: u64, cap: u64, key: Value) !MapRepr {
    if (cap == 0 or len == 0) return MapRepr{ .entries = entries, .len = len, .cap = cap };

    const new_bytes = try allocator.alloc(u8, @sizeOf(MapBucket) * cap);
    @memset(new_bytes, 0);
    const new_buckets: []MapBucket = @alignCast(std.mem.bytesAsSlice(MapBucket, new_bytes));

    const old_buckets: []MapBucket = @alignCast(std.mem.bytesAsSlice(MapBucket, entries[0 .. @sizeOf(MapBucket) * cap]));
    const kh = hashKey(key);
    var new_len: u64 = 0;

    for (old_buckets) |b| {
        if (!b.occupied) continue;
        if (b.hash == kh and keyEqual(b.key, key)) continue;
        if (findMapSlot(new_buckets, cap, b.key, b.hash)) |slot| {
            new_buckets[slot] = b;
            new_len += 1;
        }
    }

    return MapRepr{ .entries = new_bytes.ptr, .len = new_len, .cap = cap };
}

pub fn mapKeys(allocator: std.mem.Allocator, entries: [*]u8, len: u64, cap: u64) ![]Value {
    if (cap == 0) return &[_]Value{};
    const buckets: []MapBucket = @alignCast(std.mem.bytesAsSlice(MapBucket, entries[0 .. @sizeOf(MapBucket) * cap]));
    const items = try allocator.alloc(Value, len);
    var idx: usize = 0;
    for (buckets) |b| {
        if (b.occupied) {
            items[idx] = b.key;
            idx += 1;
        }
    }
    return items[0..idx];
}

pub fn mapValues(allocator: std.mem.Allocator, entries: [*]u8, len: u64, cap: u64) ![]Value {
    if (cap == 0) return &[_]Value{};
    const buckets: []MapBucket = @alignCast(std.mem.bytesAsSlice(MapBucket, entries[0 .. @sizeOf(MapBucket) * cap]));
    const items = try allocator.alloc(Value, len);
    var idx: usize = 0;
    for (buckets) |b| {
        if (b.occupied) {
            items[idx] = b.value;
            idx += 1;
        }
    }
    return items[0..idx];
}

pub fn setContains(entries: [*]u8, len: u64, cap: u64, key: Value) bool {
    _ = len;
    if (cap == 0) return false;
    const kh = hashKey(key);
    const buckets: []SetBucket = @alignCast(std.mem.bytesAsSlice(SetBucket, entries[0 .. @sizeOf(SetBucket) * cap]));
    return findSetSlotForGet(buckets, cap, key, kh) != null;
}

pub fn setInsert(allocator: std.mem.Allocator, entries: [*]u8, len: u64, cap: u64, key: Value) !SetRepr {
    const kh = hashKey(key);
    var repr = SetRepr{ .entries = entries, .len = len, .cap = cap };

    if (needsResize(repr.len, repr.cap)) {
        repr = try resizeSet(allocator, repr.entries, repr.len, repr.cap);
    }

    const buckets: []SetBucket = @alignCast(std.mem.bytesAsSlice(SetBucket, repr.entries[0 .. @sizeOf(SetBucket) * repr.cap]));
    if (findSetSlot(buckets, repr.cap, key, kh)) |slot| {
        const is_new = !buckets[slot].occupied;
        buckets[slot] = SetBucket{ .hash = kh, .key = key, .occupied = true };
        if (is_new) repr.len += 1;
    }

    return repr;
}

pub fn setRemove(allocator: std.mem.Allocator, entries: [*]u8, len: u64, cap: u64, key: Value) !SetRepr {
    if (cap == 0 or len == 0) return SetRepr{ .entries = entries, .len = len, .cap = cap };

    const new_bytes = try allocator.alloc(u8, @sizeOf(SetBucket) * cap);
    @memset(new_bytes, 0);
    const new_buckets: []SetBucket = @alignCast(std.mem.bytesAsSlice(SetBucket, new_bytes));

    const old_buckets: []SetBucket = @alignCast(std.mem.bytesAsSlice(SetBucket, entries[0 .. @sizeOf(SetBucket) * cap]));
    const kh = hashKey(key);
    var new_len: u64 = 0;

    for (old_buckets) |b| {
        if (!b.occupied) continue;
        if (b.hash == kh and keyEqual(b.key, key)) continue;
        if (findSetSlot(new_buckets, cap, b.key, b.hash)) |slot| {
            new_buckets[slot] = b;
            new_len += 1;
        }
    }

    return SetRepr{ .entries = new_bytes.ptr, .len = new_len, .cap = cap };
}
