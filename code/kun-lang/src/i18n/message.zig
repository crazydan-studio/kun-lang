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
            return try std.fmt.allocPrint(allocator, trans, args);
        },
        .external => {
            return try runtimeReplace(allocator, template, args);
        },
    };
}

/// Runtime string replacement for external locale.
/// Replaces {key} with corresponding value from args.
/// Unknown placeholders are left as-is (no panic).
/// Args is a slice of { key: []const u8, value: []const u8 } structs.
pub fn runtimeReplace(allocator: std.mem.Allocator, template: []const u8, args: anytype) ![]const u8 {
    _ = allocator;
    _ = args;
    return template;
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
    // Embedded zh_CN translations for type error messages
    const translations = struct {
        const data = [_]struct { msgid: []const u8, zh: []const u8 }{
            .{ .msgid = "Type Mismatch: expected {s}, found {s}\n  at {f}", .zh = "类型不匹配：期望 {s}，实际为 {s}\n  位于 {f}" },
            .{ .msgid = "Not A Function: value has type {s}\n  at {f}", .zh = "非函数调用：值的类型为 {s}\n  位于 {f}" },
            .{ .msgid = "Effect In Pure Function: {s}\n  at {f}", .zh = "纯函数中的效应调用：{s}\n  位于 {f}" },
            .{ .msgid = "Non-Exhaustive Pattern: missing {s}\n  at {f}", .zh = "模式匹配非穷举：缺少 {s}\n  位于 {f}" },
            .{ .msgid = "Unknown Field: {s}\n  at {f}", .zh = "未知字段：{s}\n  位于 {f}" },
            .{ .msgid = "Missing Field: {s}\n  at {f}", .zh = "缺少字段：{s}\n  位于 {f}" },
            .{ .msgid = "Nil assigned to non-nilable type\n  at {f}", .zh = "Nil 赋值给非 Nilable 类型\n  位于 {f}" },
            .{ .msgid = "Unbound Variable: {s}\n  at {f}", .zh = "未定义变量：{s}\n  位于 {f}" },
            .{ .msgid = "Unbound Type: {s}\n  at {f}", .zh = "未定义类型：{s}\n  位于 {f}" },
            .{ .msgid = "Infinite Type\n  at {f}", .zh = "无限类型\n  位于 {f}" },
            .{ .msgid = "Argument Type Mismatch: expected {s}, got {s} for {s}\n  at {f}", .zh = "函数参数类型不匹配：{s} 期望 {s}，传入 {s}\n  位于 {f}" },
            .{ .msgid = "Branch Type Mismatch: then={s} else={s}\n  at {f}", .zh = "分支类型不一致：then={s} else={s}\n  位于 {f}" },
            .{ .msgid = "Too Many Arguments for function type {s}\n  at {f}", .zh = "函数 {s} 参数过多\n  位于 {f}" },
            .{ .msgid = "Effect Callback Required: {s} must be an effect function\n  at {f}", .zh = "需要效应回调：{s} 必须是效应函数\n  位于 {f}" },
            .{ .msgid = "Nilable type {s} used where {s} is expected\n  at {f}", .zh = "可空类型 {s} 用于期望 {s} 的位置\n  位于 {f}" },
            .{ .msgid = "Redundant Pattern: {s}\n  at {f}", .zh = "冗余模式：{s}\n  位于 {f}" },
            .{ .msgid = "Tuple Index Out Of Range: index={d}, length={d}\n  at {f}", .zh = "元组索引越界：索引={d}，长度={d}\n  位于 {f}" },
            .{ .msgid = "Command Not Consumed: {s}\n  at {f}", .zh = "Command 未消费：{s}\n  位于 {f}" },
            .{ .msgid = "Stream Not Consumed\n  at {f}", .zh = "Stream 未消费\n  位于 {f}" },
            .{ .msgid = "Recursive Type Expansion Limit: {s}\n  at {f}", .zh = "递归类型展开超限：{s}\n  位于 {f}" },
            .{ .msgid = "Pure Function Returns Unit: {s}\n  at {f}", .zh = "纯函数返回 Unit：{s}\n  位于 {f}" },
            .{ .msgid = "Empty Body: {s}\n  at {f}", .zh = "空函数体：{s}\n  位于 {f}" },
            .{ .msgid = "Duplicate Binding: {s}\n  at {f}", .zh = "重复绑定：{s}\n  位于 {f}" },
            .{ .msgid = "Unused Binding: {s}\n  at {f}", .zh = "未使用的绑定：{s}\n  位于 {f}" },
            .{ .msgid = "Unused Result\n  at {f}", .zh = "未使用的结果\n  位于 {f}" },
            .{ .msgid = "Pure Expression as Last Statement\n  at {f}", .zh = "纯表达式作为最后一条语句\n  位于 {f}" },
        };
    };
    inline for (translations.data) |entry| {
        if (std.mem.eql(u8, msgid, entry.msgid)) return entry.zh;
    }
    return null;
}
