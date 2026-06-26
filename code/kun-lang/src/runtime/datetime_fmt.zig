const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const RuntimeEnv = @import("../runtime/primitive.zig").RuntimeEnv;

/// DateTime.now : -> DateTime
pub fn nowImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    // Return Unix timestamp in nanoseconds via clock_gettime
    var tp: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.REALTIME, &tp);
    const nanos = @as(i64, tp.sec) * 1_000_000_000 + @as(i64, tp.nsec);
    return Value{ .int = nanos };
}

/// DateTime.format : String -> DateTime -> Result String String
pub fn formatImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2) return Value{ .nil = {} };
    const template = args[0];
    const dt_val = args[1];
    if (template != .string or dt_val != .int) return Value{ .nil = {} };

    const nanos = dt_val.int;
    const ts: i64 = @intCast(@divTrunc(nanos, 1_000_000_000));
    const result = formatTimestamp(env.allocator, template.string, ts) catch return Value{ .nil = {} };
    return value_mod.makeOk(Value{ .string = result }, env.allocator) catch Value{ .nil = {} };
}

/// DateTime.parse : String -> String -> Result DateTime String
pub fn parseImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = env;
    _ = args;
    return Value{ .nil = {} };
}

fn formatTimestamp(allocator: std.mem.Allocator, template: []const u8, ts: i64) ![]const u8 {
    // Convert Unix timestamp to broken-down time
    const seconds: u64 = @intCast(ts);
    const days = seconds / 86400;
    const remaining = seconds % 86400;
    const hours = remaining / 3600;
    const mins = (remaining % 3600) / 60;
    const secs = remaining % 60;

    // Calculate year/month/day from days since epoch
    const y = daysToYear(days);
    const doy = days - yearToDays(y);
    const month = dayOfYearToMonth(doy, isLeap(y));
    const day = doy - monthStartDay(month, isLeap(y)) + 1;

    // Apply format template
    // Support: yyyy, yy, MM, dd, HH, mm, ss, SSS, Z
    var result = std.ArrayListUnmanaged(u8).empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < template.len) {
        if (template[i] == '%' and i + 1 < template.len) {
            i += 1;
            // Simple format specifiers
            switch (template[i]) {
                'Y' => {
                    const y_str = try std.fmt.allocPrint(allocator, "{d:0>4}", .{y});
                    defer allocator.free(y_str);
                    try result.appendSlice(allocator, y_str);
                },
                'm' => {
                    const m_str = try std.fmt.allocPrint(allocator, "{d:0>2}", .{month});
                    defer allocator.free(m_str);
                    try result.appendSlice(allocator, m_str);
                },
                'd' => {
                    const d_str = try std.fmt.allocPrint(allocator, "{d:0>2}", .{day});
                    defer allocator.free(d_str);
                    try result.appendSlice(allocator, d_str);
                },
                'H' => {
                    const h_str = try std.fmt.allocPrint(allocator, "{d:0>2}", .{hours});
                    defer allocator.free(h_str);
                    try result.appendSlice(allocator, h_str);
                },
                'M' => {
                    const m_str = try std.fmt.allocPrint(allocator, "{d:0>2}", .{mins});
                    defer allocator.free(m_str);
                    try result.appendSlice(allocator, m_str);
                },
                'S' => {
                    const s_str = try std.fmt.allocPrint(allocator, "{d:0>2}", .{secs});
                    defer allocator.free(s_str);
                    try result.appendSlice(allocator, s_str);
                },
                else => try result.append(allocator, template[i]),
            }
        } else {
            try result.append(allocator, template[i]);
        }
        i += 1;
    }

    return result.toOwnedSlice(allocator);
}

fn isLeap(year: i64) bool {
    return @rem(year, 4) == 0 and (@rem(year, 100) != 0 or @rem(year, 400) == 0);
}

fn daysToYear(days: u64) i64 {
    var y: i64 = 1970;
    var d = days;
    while (true) {
        const yd: u64 = if (isLeap(y)) @as(u64, 366) else @as(u64, 365);
        if (d < yd) return y;
        d -= yd;
        y += 1;
    }
}

fn yearToDays(year: i64) u64 {
    var d: u64 = 0;
    var y: i64 = 1970;
    while (y < year) {
        d += if (isLeap(y)) 366 else 365;
        y += 1;
    }
    return d;
}

fn dayOfYearToMonth(doy: u64, leap: bool) u64 {
    const days: [12]u64 = if (leap)
        .{ 0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335 }
    else
        .{ 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 };

    for (days, 1..) |md, m| {
        if (doy < md) return m - 1;
    }
    return 12;
}

fn monthStartDay(month: u64, leap: bool) u64 {
    const days: [12]u64 = if (leap)
        .{ 0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335 }
    else
        .{ 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 };
    if (month < 1 or month > 12) return 0;
    return days[month - 1];
}
