const std = @import("std");
const hash_map = @import("hash_map.zig");
const value_mod = @import("value.zig");

const Value = value_mod.Value;
const MapRepr = value_mod.MapRepr;
const SetRepr = value_mod.SetRepr;

test "hash_map insert and get" {
    const allocator = std.testing.allocator;
    var repr = MapRepr{ .entries = @constCast(&[0]u8{}), .len = 0, .cap = 0 };

    repr = try hash_map.mapInsert(allocator, repr.entries, repr.len, repr.cap, Value{ .string = "key1" }, Value{ .int = 42 });
    defer allocator.free(repr.entries[0 .. @sizeOf(MapBucket) * repr.cap]);

    repr = try hash_map.mapInsert(allocator, repr.entries, repr.len, repr.cap, Value{ .string = "key2" }, Value{ .int = 99 });

    const v1 = hash_map.mapGet(repr.entries, repr.len, repr.cap, Value{ .string = "key1" });
    try std.testing.expect(v1 != null);
    try std.testing.expectEqual(@as(i64, 42), v1.?.int);

    const v3 = hash_map.mapGet(repr.entries, repr.len, repr.cap, Value{ .string = "key3" });
    try std.testing.expect(v3 == null);
}

test "hash_map remove" {
    const allocator = std.testing.allocator;
    var repr = MapRepr{ .entries = @constCast(&[0]u8{}), .len = 0, .cap = 0 };

    repr = try hash_map.mapInsert(allocator, repr.entries, repr.len, repr.cap, Value{ .string = "a" }, Value{ .int = 1 });
    defer allocator.free(repr.entries[0 .. @sizeOf(MapBucket) * repr.cap]);
    repr = try hash_map.mapInsert(allocator, repr.entries, repr.len, repr.cap, Value{ .string = "b" }, Value{ .int = 2 });

    var removed = try hash_map.mapRemove(allocator, repr.entries, repr.len, repr.cap, Value{ .string = "a" });
    defer if (removed.cap > 0) allocator.free(removed.entries[0 .. @sizeOf(MapBucket) * removed.cap]);

    try std.testing.expectEqual(@as(u64, 1), removed.len);
    try std.testing.expect(hash_map.mapGet(removed.entries, removed.len, removed.cap, Value{ .string = "a" }) == null);
    try std.testing.expect(hash_map.mapGet(removed.entries, removed.len, removed.cap, Value{ .string = "b" }) != null);
}

test "hash_map keys and values" {
    const allocator = std.testing.allocator;
    var repr = MapRepr{ .entries = @constCast(&[0]u8{}), .len = 0, .cap = 0 };

    repr = try hash_map.mapInsert(allocator, repr.entries, repr.len, repr.cap, Value{ .string = "x" }, Value{ .int = 10 });
    defer allocator.free(repr.entries[0 .. @sizeOf(MapBucket) * repr.cap]);
    repr = try hash_map.mapInsert(allocator, repr.entries, repr.len, repr.cap, Value{ .string = "y" }, Value{ .int = 20 });

    const keys = try hash_map.mapKeys(allocator, repr.entries, repr.len, repr.cap);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = try hash_map.mapValues(allocator, repr.entries, repr.len, repr.cap);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "hash_map set insert and contains" {
    const allocator = std.testing.allocator;
    var repr = SetRepr{ .entries = @constCast(&[0]u8{}), .len = 0, .cap = 0 };

    repr = try hash_map.setInsert(allocator, repr.entries, repr.len, repr.cap, Value{ .int = 1 });
    defer allocator.free(repr.entries[0 .. @sizeOf(SetBucket) * repr.cap]);
    repr = try hash_map.setInsert(allocator, repr.entries, repr.len, repr.cap, Value{ .int = 2 });

    try std.testing.expect(hash_map.setContains(repr.entries, repr.len, repr.cap, Value{ .int = 1 }));
    try std.testing.expect(hash_map.setContains(repr.entries, repr.len, repr.cap, Value{ .int = 2 }));
    try std.testing.expect(!hash_map.setContains(repr.entries, repr.len, repr.cap, Value{ .int = 3 }));
}

test "hash_map resize triggers" {
    const allocator = std.testing.allocator;
    var repr = MapRepr{ .entries = @constCast(&[0]u8{}), .len = 0, .cap = 0 };

    var i: i64 = 0;
    while (i < 20) : (i += 1) {
        const key_s = try std.fmt.allocPrint(allocator, "key{d}", .{i});
        repr = try hash_map.mapInsert(allocator, repr.entries, repr.len, repr.cap, Value{ .string = key_s }, Value{ .int = i });
    }
    defer allocator.free(repr.entries[0 .. @sizeOf(MapBucket) * repr.cap]);

    try std.testing.expect(repr.cap >= 8);
    try std.testing.expectEqual(@as(u64, 20), repr.len);

    const v = hash_map.mapGet(repr.entries, repr.len, repr.cap, Value{ .string = "key0" });
    try std.testing.expect(v != null);
    try std.testing.expectEqual(@as(i64, 0), v.?.int);
}

const MapBucket = struct {
    hash: u64,
    key: Value,
    value: Value,
    occupied: bool,
};

const SetBucket = struct {
    hash: u64,
    key: Value,
    occupied: bool,
};
