const std = @import("std");
const error_mod = @import("error.zig");

const TypeError = error_mod.TypeError;
const TypeEnv = @import("env.zig").TypeEnv;

pub const Locale = enum { en, zh_CN };

inline fn formatLoc(
    allocator: std.mem.Allocator,
    comptime en_fmt: []const u8,
    comptime zh_fmt: []const u8,
    locale: Locale,
    args: anytype,
) ![]const u8 {
    return switch (locale) {
        .en => try std.fmt.allocPrint(allocator, en_fmt, args),
        .zh_CN => try std.fmt.allocPrint(allocator, zh_fmt, args),
    };
}

pub fn formatError(allocator: std.mem.Allocator, err: TypeError, locale: Locale, env: *TypeEnv) ![]const u8 {
    const span_str = switch (err) {
        .mismatch => |m| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ m.span.start.line, m.span.start.col }),
        .not_a_function => |n| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ n.span.start.line, n.span.start.col }),
        .effect_in_pure => |e| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ e.span.start.line, e.span.start.col }),
        .non_exhaustive => |ne| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ ne.span.start.line, ne.span.start.col }),
        .unknown_field => |uf| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ uf.span.start.line, uf.span.start.col }),
        .missing_field => |mf| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ mf.span.start.line, mf.span.start.col }),
        .nil_to_non_nilable => |nn| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ nn.start.line, nn.start.col }),
        .unbound_variable => try std.fmt.allocPrint(allocator, "{d}:{d}", .{ @as(u32, 0), @as(u32, 0) }),
        .unbound_type => try std.fmt.allocPrint(allocator, "{d}:{d}", .{ @as(u32, 0), @as(u32, 0) }),
        .infinite_type => |it| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ it.start.line, it.start.col }),
        .function_apply_arg => |fa| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ fa.span.start.line, fa.span.start.col }),
        .if_branch_mismatch => |ib| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ ib.span.start.line, ib.span.start.col }),
        .too_many_args => |tm| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ tm.span.start.line, tm.span.start.col }),
        .effect_callback_mismatch => |ec| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ ec.span.start.line, ec.span.start.col }),
        .nilable_used_as_t => |nu| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ nu.span.start.line, nu.span.start.col }),
        .redundant_pattern => |rp| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ rp.span.start.line, rp.span.start.col }),
        .tuple_index_out_of_range => |to| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ to.span.start.line, to.span.start.col }),
        .command_not_consumed => |cn| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ cn.span.start.line, cn.span.start.col }),
        .stream_not_consumed => |sn| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ sn.start.line, sn.start.col }),
        .recursive_alias_depth => |ra| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ ra.span.start.line, ra.span.start.col }),
        .pure_unit_return => |pu| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ pu.span.start.line, pu.span.start.col }),
        .effect_in_let => |el| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ el.span.start.line, el.span.start.col }),
        .empty_body => |eb| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ eb.span.start.line, eb.span.start.col }),
        .duplicate_binding => |db| try std.fmt.allocPrint(allocator, "{d}:{d}", .{ db.span.start.line, db.span.start.col }),
    };
    defer allocator.free(span_str);

    return switch (err) {
        .mismatch => |m| {
            const expected = try env.typeName(allocator, m.expected);
            const found = try env.typeName(allocator, m.found);
            return formatLoc(allocator,
                "Type Mismatch: expected {s}, found {s}\n  at {s}",
                "类型不匹配：期望 {s}，实际为 {s}\n  位于 {s}",
                locale, .{ expected, found, span_str });
        },
        .not_a_function => |n| {
            const found = try env.typeName(allocator, n.found);
            return formatLoc(allocator,
                "Not A Function: value has type {s}\n  at {s}",
                "非函数调用：值的类型为 {s}\n  位于 {s}",
                locale, .{ found, span_str });
        },
        .effect_in_pure => |e| {
            return formatLoc(allocator,
                "Effect In Pure Function: {s}\n  at {s}",
                "纯函数中的效应调用：{s}\n  位于 {s}",
                locale, .{ e.called_func, span_str });
        },
        .non_exhaustive => |ne| {
            const missing_str = if (ne.missing.len > 0) ne.missing[0] else "_";
            return formatLoc(allocator,
                "Non-Exhaustive Pattern: missing {s}\n  at {s}",
                "模式匹配非穷举：缺少 {s}\n  位于 {s}",
                locale, .{ missing_str, span_str });
        },
        .unknown_field => |uf| {
            return formatLoc(allocator,
                "Unknown Field: {s}\n  at {s}",
                "未知字段：{s}\n  位于 {s}",
                locale, .{ uf.name, span_str });
        },
        .missing_field => |mf| {
            return formatLoc(allocator,
                "Missing Field: {s}\n  at {s}",
                "缺少字段：{s}\n  位于 {s}",
                locale, .{ mf.name, span_str });
        },
        .nil_to_non_nilable => return formatLoc(allocator,
            "Nil assigned to non-nilable type\n  at {s}",
            "Nil 赋值给非 Nilable 类型\n  位于 {s}",
            locale, .{span_str}),
        .unbound_variable => |uv| {
            return formatLoc(allocator,
                "Unbound Variable: {s}",
                "未定义变量：{s}",
                locale, .{uv});
        },
        .unbound_type => |ut| {
            return formatLoc(allocator,
                "Unbound Type: {s}",
                "未定义类型：{s}",
                locale, .{ut});
        },
        .infinite_type => return formatLoc(allocator,
            "Infinite Type\n  at {s}",
            "无限类型\n  位于 {s}",
            locale, .{span_str}),
        .function_apply_arg => |fa| {
            const expected = try env.typeName(allocator, fa.expected);
            const found = try env.typeName(allocator, fa.found);
            return formatLoc(allocator,
                "Argument Type Mismatch: expected {s}, got {s} for {s}\n  at {s}",
                "函数参数类型不匹配：{s} 期望 {s}，传入 {s}\n  位于 {s}",
                locale, .{ expected, found, fa.func_name, span_str });
        },
        .if_branch_mismatch => |ib| {
            const then_t = try env.typeName(allocator, ib.then_type);
            const else_t = try env.typeName(allocator, ib.else_type);
            return formatLoc(allocator,
                "Branch Type Mismatch: then={s} else={s}\n  at {s}",
                "分支类型不一致：then={s} else={s}\n  位于 {s}",
                locale, .{ then_t, else_t, span_str });
        },
        .too_many_args => |tm| {
            const ftype = try env.typeName(allocator, tm.func_type);
            return formatLoc(allocator,
                "Too Many Arguments for function type {s}\n  at {s}",
                "函数 {s} 参数过多\n  位于 {s}",
                locale, .{ ftype, span_str });
        },
        .effect_callback_mismatch => |ec| {
            return formatLoc(allocator,
                "Effect Callback Required: {s} must be an effect function\n  at {s}",
                "需要效应回调：{s} 必须是效应函数\n  位于 {s}",
                locale, .{ ec.func_name, span_str });
        },
        .nilable_used_as_t => |nu| {
            const expected = try env.typeName(allocator, nu.expected);
            const inner = try env.typeName(allocator, nu.inner_type);
            return formatLoc(allocator,
                "Nilable type {s} used where {s} is expected\n  at {s}",
                "可空类型 {s} 用于期望 {s} 的位置\n  位于 {s}",
                locale, .{ inner, expected, span_str });
        },
        .redundant_pattern => |rp| {
            return formatLoc(allocator,
                "Redundant Pattern: {s}\n  at {s}",
                "冗余模式：{s}\n  位于 {s}",
                locale, .{ rp.pattern, span_str });
        },
        .tuple_index_out_of_range => |to| {
            return formatLoc(allocator,
                "Tuple Index Out Of Range: index={d}, length={d}\n  at {s}",
                "元组索引越界：索引={d}，长度={d}\n  位于 {s}",
                locale, .{ to.index, to.len, span_str });
        },
        .command_not_consumed => |cn| {
            return formatLoc(allocator,
                "Command Not Consumed: {s}\n  at {s}",
                "Command 未消费：{s}\n  位于 {s}",
                locale, .{ cn.cmd_name, span_str });
        },
        .stream_not_consumed => return formatLoc(allocator,
            "Stream Not Consumed\n  at {s}",
            "Stream 未消费\n  位于 {s}",
            locale, .{span_str}),
        .recursive_alias_depth => |ra| {
            return formatLoc(allocator,
                "Recursive Type Expansion Limit: {s}\n  at {s}",
                "递归类型展开超限：{s}\n  位于 {s}",
                locale, .{ ra.path, span_str });
        },
        .pure_unit_return => |pu| {
            return formatLoc(allocator,
                "Pure Function Returns Unit: {s}\n  at {s}",
                "纯函数返回 Unit：{s}\n  位于 {s}",
                locale, .{ pu.func_name, span_str });
        },
        .effect_in_let => |el| {
            return formatLoc(allocator,
                "Effect In Pure Function: {s}\n  at {s}",
                "纯函数中的效应调用：{s}\n  位于 {s}",
                locale, .{ el.called_func, span_str });
        },
        .empty_body => |eb| {
            return formatLoc(allocator,
                "Empty Body: {s}\n  at {s}",
                "空函数体：{s}\n  位于 {s}",
                locale, .{ eb.context, span_str });
        },
        .duplicate_binding => |db| {
            return formatLoc(allocator,
                "Duplicate Binding: {s}\n  at {s}",
                "重复绑定：{s}\n  位于 {s}",
                locale, .{ db.name, span_str });
        },
    };
}
