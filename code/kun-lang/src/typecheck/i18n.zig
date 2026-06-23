const std = @import("std");
const ast = @import("../ast/ast.zig");
const typed = @import("../ast/typed.zig");
const error_mod = @import("error.zig");

const TypeError = error_mod.TypeError;
const TypeEnv = @import("env.zig").TypeEnv;

pub const Locale = enum { en, zh_CN };

const MsgEntry = struct { msgid: []const u8, zh_CN: []const u8 };

const translations = [_]MsgEntry{
    .{ .msgid = "Type Mismatch", .zh_CN = "类型不匹配" },
    .{ .msgid = "Not A Function", .zh_CN = "非函数调用" },
    .{ .msgid = "Effect In Pure Function", .zh_CN = "纯函数中的效应调用" },
    .{ .msgid = "Non-Exhaustive Pattern", .zh_CN = "模式匹配非穷举" },
    .{ .msgid = "Unknown Field", .zh_CN = "未知字段" },
    .{ .msgid = "Missing Field", .zh_CN = "缺少字段" },
    .{ .msgid = "Nil For Non-Nilable", .zh_CN = "Nil赋值给非Nilable类型" },
    .{ .msgid = "Unbound Variable", .zh_CN = "未定义变量" },
    .{ .msgid = "Unbound Type", .zh_CN = "未定义类型" },
    .{ .msgid = "Infinite Type", .zh_CN = "无限类型" },
    .{ .msgid = "Argument Type Mismatch", .zh_CN = "函数参数类型不匹配" },
    .{ .msgid = "Branch Type Mismatch", .zh_CN = "分支类型不一致" },
    .{ .msgid = "Too Many Arguments", .zh_CN = "参数过多" },
    .{ .msgid = "Effect Callback Required", .zh_CN = "需要效应回调" },
    .{ .msgid = "Nilable Used As Non-Nilable", .zh_CN = "可空类型用于非空位置" },
    .{ .msgid = "Redundant Pattern", .zh_CN = "冗余模式" },
    .{ .msgid = "Tuple Index Out Of Range", .zh_CN = "元组索引越界" },
    .{ .msgid = "Command Not Consumed", .zh_CN = "Command未消费" },
    .{ .msgid = "Stream Not Consumed", .zh_CN = "Stream未消费" },
    .{ .msgid = "Recursive Type Expansion Limit", .zh_CN = "递归类型展开超限" },
    .{ .msgid = "Pure Function Returns Unit", .zh_CN = "纯函数返回Unit" },
    .{ .msgid = "Empty Body", .zh_CN = "空函数体" },
    .{ .msgid = "Duplicate Binding", .zh_CN = "重复绑定" },
    .{ .msgid = "Expected", .zh_CN = "期望" },
    .{ .msgid = "Found", .zh_CN = "发现" },
    .{ .msgid = "Hint", .zh_CN = "提示" },
    .{ .msgid = "Reason", .zh_CN = "原因" },
};

fn translate(msgid: []const u8, locale: Locale) []const u8 {
    if (locale == .en) return msgid;
    for (translations) |entry| {
        if (std.mem.eql(u8, entry.msgid, msgid)) return entry.zh_CN;
    }
    return msgid;
}

pub fn formatError(allocator: std.mem.Allocator, err: TypeError, locale: Locale, env: *TypeEnv) ![]const u8 {
    return switch (err) {
        .mismatch => |m| {
            const expected = try env.typeName(allocator, m.expected);
            const found = try env.typeName(allocator, m.found);
            return std.fmt.allocPrint(allocator, "{s}: {s} {s}\n  {s}: {s}\n  {s}: {s}", .{
                translate("Type Mismatch", locale),
                translate("Expected", locale), expected,
                translate("Found", locale), found,
                "at", try formatSpan(allocator, m.span),
            });
        },
        .not_a_function => |n| {
            const found = try env.typeName(allocator, n.found);
            return std.fmt.allocPrint(allocator, "{s}: {s}\n  {s}: {s}", .{
                translate("Not A Function", locale),
                translate("Found", locale), found,
                "at", try formatSpan(allocator, n.span),
            });
        },
        .effect_in_pure => |e| {
            return std.fmt.allocPrint(allocator, "{s}: {s}\n  at {s}", .{
                translate("Effect In Pure Function", locale),
                e.called_func,
                try formatSpan(allocator, e.span),
            });
        },
        .non_exhaustive => |ne| {
            return std.fmt.allocPrint(allocator, "{s}: missing variants\n  at {s}", .{
                translate("Non-Exhaustive Pattern", locale),
                try formatSpan(allocator, ne.span),
            });
        },
        .unknown_field => |uf| {
            return std.fmt.allocPrint(allocator, "{s}: {s}\n  at {s}", .{
                translate("Unknown Field", locale),
                uf.name,
                try formatSpan(allocator, uf.span),
            });
        },
        .missing_field => |mf| {
            return std.fmt.allocPrint(allocator, "{s}: {s}\n  at {s}", .{
                translate("Missing Field", locale),
                mf.name,
                try formatSpan(allocator, mf.span),
            });
        },
        .nil_to_non_nilable => |nn| {
            return std.fmt.allocPrint(allocator, "{s}\n  at {s}", .{
                translate("Nil For Non-Nilable", locale),
                try formatSpan(allocator, nn),
            });
        },
        .unbound_variable => |uv| {
            return std.fmt.allocPrint(allocator, "{s}: {s}", .{
                translate("Unbound Variable", locale),
                uv,
            });
        },
        .unbound_type => |ut| {
            return std.fmt.allocPrint(allocator, "{s}: {s}", .{
                translate("Unbound Type", locale),
                ut,
            });
        },
        .infinite_type => |it| {
            return std.fmt.allocPrint(allocator, "{s}\n  at {s}", .{
                translate("Infinite Type", locale),
                try formatSpan(allocator, it),
            });
        },
        .function_apply_arg => |fa| {
            const expected = try env.typeName(allocator, fa.expected);
            const found = try env.typeName(allocator, fa.found);
            return std.fmt.allocPrint(allocator, "{s}: {s} {s} -> {s}\n  at {s}", .{
                translate("Argument Type Mismatch", locale),
                translate("Expected", locale), expected,
                translate("Found", locale), found,
                try formatSpan(allocator, fa.span),
            });
        },
        .if_branch_mismatch => |ib| {
            const then_t = try env.typeName(allocator, ib.then_type);
            const else_t = try env.typeName(allocator, ib.else_type);
            return std.fmt.allocPrint(allocator, "{s}: then={s} else={s}\n  at {s}", .{
                translate("Branch Type Mismatch", locale),
                then_t, else_t,
                try formatSpan(allocator, ib.span),
            });
        },
        .too_many_args => |tm| {
            const ftype = try env.typeName(allocator, tm.func_type);
            return std.fmt.allocPrint(allocator, "{s}: {s}\n  at {s}", .{
                translate("Too Many Arguments", locale),
                ftype,
                try formatSpan(allocator, tm.span),
            });
        },
        .effect_callback_mismatch => |ec| {
            return std.fmt.allocPrint(allocator, "{s}: {s}\n  at {s}", .{
                translate("Effect Callback Required", locale),
                ec.func_name,
                try formatSpan(allocator, ec.span),
            });
        },
        .nilable_used_as_t => |nu| {
            const expected = try env.typeName(allocator, nu.expected);
            const inner = try env.typeName(allocator, nu.inner_type);
            return std.fmt.allocPrint(allocator, "{s}: {s} vs {s}\n  at {s}", .{
                translate("Nilable Used As Non-Nilable", locale),
                expected, inner,
                try formatSpan(allocator, nu.span),
            });
        },
        .redundant_pattern => |rp| {
            return std.fmt.allocPrint(allocator, "{s}: {s}\n  at {s}", .{
                translate("Redundant Pattern", locale),
                rp.pattern,
                try formatSpan(allocator, rp.span),
            });
        },
        .tuple_index_out_of_range => |to| {
            return std.fmt.allocPrint(allocator, "{s}: index={d} len={d}\n  at {s}", .{
                translate("Tuple Index Out Of Range", locale),
                to.index, to.len,
                try formatSpan(allocator, to.span),
            });
        },
        .command_not_consumed => |cn| {
            return std.fmt.allocPrint(allocator, "{s}: {s}\n  at {s}", .{
                translate("Command Not Consumed", locale),
                cn.cmd_name,
                try formatSpan(allocator, cn.span),
            });
        },
        .stream_not_consumed => |sn| {
            return std.fmt.allocPrint(allocator, "{s}\n  at {s}", .{
                translate("Stream Not Consumed", locale),
                try formatSpan(allocator, sn),
            });
        },
        .recursive_alias_depth => |ra| {
            return std.fmt.allocPrint(allocator, "{s}: {s}\n  at {s}", .{
                translate("Recursive Type Expansion Limit", locale),
                ra.path,
                try formatSpan(allocator, ra.span),
            });
        },
        .pure_unit_return => |pu| {
            return std.fmt.allocPrint(allocator, "{s}: {s}\n  at {s}", .{
                translate("Pure Function Returns Unit", locale),
                pu.func_name,
                try formatSpan(allocator, pu.span),
            });
        },
        .effect_in_let => |el| {
            return std.fmt.allocPrint(allocator, "{s}: {s}\n  at {s}", .{
                translate("Effect In Pure Function", locale),
                el.called_func,
                try formatSpan(allocator, el.span),
            });
        },
        .empty_body => |eb| {
            return std.fmt.allocPrint(allocator, "{s}: {s}\n  at {s}", .{
                translate("Empty Body", locale),
                eb.context,
                try formatSpan(allocator, eb.span),
            });
        },
        .duplicate_binding => |db| {
            return std.fmt.allocPrint(allocator, "{s}: {s}\n  at {s}", .{
                translate("Duplicate Binding", locale),
                db.name,
                try formatSpan(allocator, db.span),
            });
        },
    };
}

fn formatSpan(allocator: std.mem.Allocator, span: ast.Span) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{d}:{d}", .{ span.start.line, span.start.col });
}
