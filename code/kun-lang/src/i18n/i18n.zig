const std = @import("std");
const error_mod = @import("../typecheck/error.zig");

const TypeError = error_mod.TypeError;
const TypeEnv = @import("../typecheck/env.zig").TypeEnv;

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
    return switch (err) {
        .mismatch => |m| {
            const expected = try env.typeName(allocator, m.expected);
            const found = try env.typeName(allocator, m.found);
            return formatLoc(allocator,
                "Type Mismatch: expected {s}, found {s}\n  at {}",
                "类型不匹配：期望 {s}，实际为 {s}\n  位于 {}",
                locale, .{ expected, found, m.span });
        },
        .not_a_function => |n| {
            const found = try env.typeName(allocator, n.found);
            return formatLoc(allocator,
                "Not A Function: value has type {s}\n  at {}",
                "非函数调用：值的类型为 {s}\n  位于 {}",
                locale, .{ found, n.span });
        },
        .effect_in_pure => |e| {
            return formatLoc(allocator,
                "Effect In Pure Function: {s}\n  at {}",
                "纯函数中的效应调用：{s}\n  位于 {}",
                locale, .{ e.called_func, e.span });
        },
        .non_exhaustive => |ne| {
            const missing_str = if (ne.missing.len > 0) ne.missing[0] else "_";
            return formatLoc(allocator,
                "Non-Exhaustive Pattern: missing {s}\n  at {}",
                "模式匹配非穷举：缺少 {s}\n  位于 {}",
                locale, .{ missing_str, ne.span });
        },
        .unknown_field => |uf| {
            return formatLoc(allocator,
                "Unknown Field: {s}\n  at {}",
                "未知字段：{s}\n  位于 {}",
                locale, .{ uf.name, uf.span });
        },
        .missing_field => |mf| {
            return formatLoc(allocator,
                "Missing Field: {s}\n  at {}",
                "缺少字段：{s}\n  位于 {}",
                locale, .{ mf.name, mf.span });
        },
        .nil_to_non_nilable => |nn| {
            return formatLoc(allocator,
                "Nil assigned to non-nilable type\n  at {}",
                "Nil 赋值给非 Nilable 类型\n  位于 {}",
                locale, .{nn.start});
        },
        .unbound_variable => |uv| {
            return formatLoc(allocator,
                "Unbound Variable: {s}\n  at {}",
                "未定义变量：{s}\n  位于 {}",
                locale, .{ uv.name, uv.span });
        },
        .unbound_type => |ut| {
            return formatLoc(allocator,
                "Unbound Type: {s}\n  at {}",
                "未定义类型：{s}\n  位于 {}",
                locale, .{ ut.name, ut.span });
        },
        .infinite_type => |it| {
            return formatLoc(allocator,
                "Infinite Type\n  at {}",
                "无限类型\n  位于 {}",
                locale, .{it.start});
        },
        .function_apply_arg => |fa| {
            const expected = try env.typeName(allocator, fa.expected);
            const found = try env.typeName(allocator, fa.found);
            return formatLoc(allocator,
                "Argument Type Mismatch: expected {s}, got {s} for {s}\n  at {}",
                "函数参数类型不匹配：{s} 期望 {s}，传入 {s}\n  位于 {}",
                locale, .{ expected, found, fa.func_name, fa.span });
        },
        .if_branch_mismatch => |ib| {
            const then_t = try env.typeName(allocator, ib.then_type);
            const else_t = try env.typeName(allocator, ib.else_type);
            return formatLoc(allocator,
                "Branch Type Mismatch: then={s} else={s}\n  at {}",
                "分支类型不一致：then={s} else={s}\n  位于 {}",
                locale, .{ then_t, else_t, ib.span });
        },
        .too_many_args => |tm| {
            const ftype = try env.typeName(allocator, tm.func_type);
            return formatLoc(allocator,
                "Too Many Arguments for function type {s}\n  at {}",
                "函数 {s} 参数过多\n  位于 {}",
                locale, .{ ftype, tm.span });
        },
        .effect_callback_mismatch => |ec| {
            return formatLoc(allocator,
                "Effect Callback Required: {s} must be an effect function\n  at {}",
                "需要效应回调：{s} 必须是效应函数\n  位于 {}",
                locale, .{ ec.func_name, ec.span });
        },
        .nilable_used_as_t => |nu| {
            const expected = try env.typeName(allocator, nu.expected);
            const inner = try env.typeName(allocator, nu.inner_type);
            return formatLoc(allocator,
                "Nilable type {s} used where {s} is expected\n  at {}",
                "可空类型 {s} 用于期望 {s} 的位置\n  位于 {}",
                locale, .{ inner, expected, nu.span });
        },
        .redundant_pattern => |rp| {
            return formatLoc(allocator,
                "Redundant Pattern: {s}\n  at {}",
                "冗余模式：{s}\n  位于 {}",
                locale, .{ rp.pattern, rp.span });
        },
        .tuple_index_out_of_range => |to| {
            return formatLoc(allocator,
                "Tuple Index Out Of Range: index={d}, length={d}\n  at {}",
                "元组索引越界：索引={d}，长度={d}\n  位于 {}",
                locale, .{ to.index, to.len, to.span });
        },
        .command_not_consumed => |cn| {
            return formatLoc(allocator,
                "Command Not Consumed: {s}\n  at {}",
                "Command 未消费：{s}\n  位于 {}",
                locale, .{ cn.cmd_name, cn.span });
        },
        .stream_not_consumed => |sn| {
            return formatLoc(allocator,
                "Stream Not Consumed\n  at {}",
                "Stream 未消费\n  位于 {}",
                locale, .{sn.start});
        },
        .recursive_alias_depth => |ra| {
            return formatLoc(allocator,
                "Recursive Type Expansion Limit: {s}\n  at {}",
                "递归类型展开超限：{s}\n  位于 {}",
                locale, .{ ra.path, ra.span });
        },
        .pure_unit_return => |pu| {
            return formatLoc(allocator,
                "Pure Function Returns Unit: {s}\n  at {}",
                "纯函数返回 Unit：{s}\n  位于 {}",
                locale, .{ pu.func_name, pu.span });
        },
        .effect_in_let => |el| {
            return formatLoc(allocator,
                "Effect In Pure Function: {s}\n  at {}",
                "纯函数中的效应调用：{s}\n  位于 {}",
                locale, .{ el.called_func, el.span });
        },
        .empty_body => |eb| {
            return formatLoc(allocator,
                "Empty Body: {s}\n  at {}",
                "空函数体：{s}\n  位于 {}",
                locale, .{ eb.context, eb.span });
        },
        .duplicate_binding => |db| {
            return formatLoc(allocator,
                "Duplicate Binding: {s}\n  at {}",
                "重复绑定：{s}\n  位于 {}",
                locale, .{ db.name, db.span });
        },
        .unused_binding => |ub| {
            return formatLoc(allocator,
                "Unused Binding: {s}\n  at {}",
                "未使用的绑定：{s}\n  位于 {}",
                locale, .{ ub.name, ub.span });
        },
        .unused_result => |ur| {
            return formatLoc(allocator,
                "Unused Result\n  at {}",
                "未使用的结果\n  位于 {}",
                locale, .{ur.start});
        },
        .pure_expr_last => |pe| {
            return formatLoc(allocator,
                "Pure Expression as Last Statement\n  at {}",
                "纯表达式作为最后一条语句\n  位于 {}",
                locale, .{pe.start});
        },
    };
}
