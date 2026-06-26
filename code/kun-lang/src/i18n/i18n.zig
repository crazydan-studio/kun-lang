const std = @import("std");
const error_mod = @import("../typecheck/error.zig");
const msg = @import("message.zig");

const TypeError = error_mod.TypeError;
const TypeEnv = @import("../typecheck/env.zig").TypeEnv;

pub const Locale = msg.Locale;
pub const kmsg = msg.kmsg;
pub const format = msg.format;
pub const detectLocale = msg.detectLocale;
pub const runtimeReplace = msg.runtimeReplace;

/// Format a single location-based error message using kmsg/format API.
/// Uses kmsg for template lookup and format for named interpolation.
pub fn formatError(allocator: std.mem.Allocator, err: TypeError, locale: Locale, env: *TypeEnv) ![]const u8 {
    return switch (err) {
        .mismatch => |m| {
            const expected = try env.typeName(allocator, m.expected);
            const found = try env.typeName(allocator, m.found);
            return try format(allocator, locale,
                "Type Mismatch: expected {s}, found {s}\n  at {f}",
                .{ expected, found, m.span });
        },
        .not_a_function => |n| {
            const found = try env.typeName(allocator, n.found);
            return try format(allocator, locale,
                "Not A Function: value has type {s}\n  at {f}",
                .{ found, n.span });
        },
        .effect_in_pure => |e| {
            return try format(allocator, locale,
                "Effect In Pure Function: {s}\n  at {f}",
                .{ e.called_func, e.span });
        },
        .non_exhaustive => |ne| {
            const missing_str = if (ne.missing.len > 0) ne.missing[0] else "_";
            return try format(allocator, locale,
                "Non-Exhaustive Pattern: missing {s}\n  at {f}",
                .{ missing_str, ne.span });
        },
        .unknown_field => |uf| {
            return try format(allocator, locale,
                "Unknown Field: {s}\n  at {f}",
                .{ uf.name, uf.span });
        },
        .missing_field => |mf| {
            return try format(allocator, locale,
                "Missing Field: {s}\n  at {f}",
                .{ mf.name, mf.span });
        },
        .unbound_variable => |uv| {
            return try format(allocator, locale,
                "Unbound Variable: {s}\n  at {f}",
                .{ uv.name, uv.span });
        },
        .unbound_type => |ut| {
            return try format(allocator, locale,
                "Unbound Type: {s}\n  at {f}",
                .{ ut.name, ut.span });
        },
        .infinite_type => |it| {
            return try format(allocator, locale,
                "Infinite Type\n  at {f}",
                .{it.start});
        },
        .function_apply_arg => |fa| {
            const expected = try env.typeName(allocator, fa.expected);
            const found = try env.typeName(allocator, fa.found);
            return try format(allocator, locale,
                "Argument Type Mismatch: expected {s}, got {s} for {s}\n  at {f}",
                .{ expected, found, fa.func_name, fa.span });
        },
        .if_branch_mismatch => |ib| {
            const then_t = try env.typeName(allocator, ib.then_type);
            const else_t = try env.typeName(allocator, ib.else_type);
            return try format(allocator, locale,
                "Branch Type Mismatch: then={s} else={s}\n  at {f}",
                .{ then_t, else_t, ib.span });
        },
        .too_many_args => |tm| {
            const ftype = try env.typeName(allocator, tm.func_type);
            return try format(allocator, locale,
                "Too Many Arguments for function type {s}\n  at {f}",
                .{ ftype, tm.span });
        },
        .effect_callback_mismatch => |ec| {
            return try format(allocator, locale,
                "Effect Callback Required: {s} must be an effect function\n  at {f}",
                .{ ec.func_name, ec.span });
        },
        .nilable_used_as_t => |nu| {
            const expected = try env.typeName(allocator, nu.expected);
            const inner = try env.typeName(allocator, nu.inner_type);
            return try format(allocator, locale,
                "Nilable type {s} used where {s} is expected\n  at {f}",
                .{ inner, expected, nu.span });
        },
        .redundant_pattern => |rp| {
            return try format(allocator, locale,
                "Redundant Pattern: {s}\n  at {f}",
                .{ rp.pattern, rp.span });
        },
        .tuple_index_out_of_range => |to| {
            return try format(allocator, locale,
                "Tuple Index Out Of Range: index={d}, length={d}\n  at {f}",
                .{ to.index, to.len, to.span });
        },
        .command_not_consumed => |cn| {
            return try format(allocator, locale,
                "Command Not Consumed: {s}\n  at {f}",
                .{ cn.cmd_name, cn.span });
        },
        .stream_not_consumed => |sn| {
            return try format(allocator, locale,
                "Stream Not Consumed\n  at {f}",
                .{sn.start});
        },
        .recursive_alias_depth => |ra| {
            return try format(allocator, locale,
                "Recursive Type Expansion Limit: {s}\n  at {f}",
                .{ ra.path, ra.span });
        },
        .pure_unit_return => |pu| {
            return try format(allocator, locale,
                "Pure Function Returns Unit: {s}\n  at {f}",
                .{ pu.func_name, pu.span });
        },
        .effect_in_let => |el| {
            return try format(allocator, locale,
                "Effect In Pure Function: {s}\n  at {f}",
                .{ el.called_func, el.span });
        },
        .empty_body => |eb| {
            return try format(allocator, locale,
                "Empty Body: {s}\n  at {f}",
                .{ eb.context, eb.span });
        },
        .duplicate_binding => |db| {
            return try format(allocator, locale,
                "Duplicate Binding: {s}\n  at {f}",
                .{ db.name, db.span });
        },
        .unused_binding => |ub| {
            return try format(allocator, locale,
                "Unused Binding: {s}\n  at {f}",
                .{ ub.name, ub.span });
        },
        .unused_result => |ur| {
            return try format(allocator, locale,
                "Unused Result\n  at {f}",
                .{ur.start});
        },
        .pure_expr_last => |pe| {
            return try format(allocator, locale,
                "Pure Expression as Last Statement\n  at {f}",
                .{pe.start});
        },
    };
}
