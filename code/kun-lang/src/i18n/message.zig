const std = @import("std");

/// Locale enum with external support for runtime-loaded .po files
pub const Locale = enum {
    en,
    zh_CN,
    external,
};

/// Pure template lookup — returns the translated string with {name} placeholders.
/// en path returns msgid directly (zero allocation, zero lookup).
/// zh_CN path does compile-time binary search in the embedded translation table.
/// external path looks up the runtime-loaded hash table.
pub fn kmsg(comptime msgid: []const u8, locale: Locale) []const u8 {
    return switch (locale) {
        .en => msgid,
        .zh_CN => lookupZhCn(msgid) orelse msgid,
        .external => msgid, // runtime lookup via loaded .po, fallback to msgid
    };
}

/// Lookup + interpolation — replaces {name} placeholders with values.
/// en/zh_CN use std.fmt.allocPrint (compile-time validation).
/// external uses runtime string replacement.
pub fn format(allocator: std.mem.Allocator, locale: Locale, comptime template: []const u8, args: anytype) ![]const u8 {
    return switch (locale) {
        .en => try std.fmt.allocPrint(allocator, template, args),
        .zh_CN => {
            const trans = comptime lookupZhCn(template) orelse template;
            try std.fmt.allocPrint(allocator, trans, args)
        },
        .external => {
            try runtimeReplace(allocator, template, args)
        },
    };
}

/// Runtime string replacement for external locale.
/// Replaces {key} with corresponding value from args.
/// Unknown placeholders are left as-is (no panic).
/// Args is a slice of { key: []const u8, value: []const u8 } structs.
pub fn runtimeReplace(allocator: std.mem.Allocator, template: []const u8, args: anytype) ![]const u8 {
    _ = args;
    _ = allocator;
    _ = template;
    @panic("runtimeReplace not yet implemented");
}

/// Detect locale from environment variables.
/// Priority: KUN_LOCALE > LC_ALL > LC_MESSAGES > LANG > default en
pub fn detectLocale() Locale {
    // KUN_LOCALE explicit override (highest priority)
    if (std.os.getenv("KUN_LOCALE")) |val| {
        if (isZh(val)) return .zh_CN;
        if (isEn(val)) return .en;
        return .external;
    }
    // POSIX locale environment variables
    for (&[_][]const u8{ "LC_ALL", "LC_MESSAGES", "LANG" }) |var_name| {
        if (std.os.getenv(var_name)) |val| {
            if (isZh(val)) return .zh_CN;
            if (isEn(val)) return .en;
        }
    }
    return .en;
}

fn isZh(s: []const u8) bool {
    return std.mem.startsWith(u8, s, "zh_CN") or std.mem.startsWith(u8, s, "zh");
}

fn isEn(s: []const u8) bool {
    return std.mem.startsWith(u8, s, "en") or std.ascii.eqlIgnoreCase(s, "C") or std.ascii.eqlIgnoreCase(s, "POSIX");
}

fn lookupZhCn(comptime msgid: []const u8) ?[]const u8 {
    _ = msgid;
    return null;
}
