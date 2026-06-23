const std = @import("std");
const i18n = @import("i18n.zig");
const error_mod = @import("error.zig");
const env_mod = @import("env.zig");

const Locale = i18n.Locale;

fn createTypeEnv() !env_mod.TypeEnv {
    return env_mod.TypeEnv.init(std.testing.allocator);
}

test "i18n formatError not_a_function en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .not_a_function = .{ .found = env_mod.int_type, .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Not A Function"));
}

test "i18n formatError not_a_function zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .not_a_function = .{ .found = env_mod.int_type, .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "非函数调用"));
}

test "i18n formatError effect_in_pure en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .effect_in_pure = .{ .called_func = "IO.println", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Effect In Pure Function"));
}

test "i18n formatError effect_in_pure zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .effect_in_pure = .{ .called_func = "IO.println", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "纯函数中的效应调用"));
}

test "i18n formatError unbound_variable en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .unbound_variable = "x" };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Unbound Variable"));
}

test "i18n formatError unbound_variable zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .unbound_variable = "x" };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "未定义变量"));
}

test "i18n formatError unbound_type en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .unbound_type = "Foo" };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Unbound Type"));
}

test "i18n formatError unbound_type zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .unbound_type = "Foo" };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "未定义类型"));
}

test "i18n formatError empty_body en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .empty_body = .{ .context = "do", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Empty Body"));
}

test "i18n formatError empty_body zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .empty_body = .{ .context = "do", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "空函数体"));
}

test "i18n formatError duplicate_binding en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .duplicate_binding = .{ .name = "x", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Duplicate Binding"));
}

test "i18n formatError duplicate_binding zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .duplicate_binding = .{ .name = "x", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "重复绑定"));
}

test "i18n formatError pure_unit_return en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .pure_unit_return = .{ .func_name = "compute", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Pure Function Returns Unit"));
}

test "i18n formatError pure_unit_return zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .pure_unit_return = .{ .func_name = "compute", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "纯函数返回 Unit"));
}

test "i18n formatError effect_in_let en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .effect_in_let = .{ .called_func = "IO.println", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Effect In Pure Function"));
}

test "i18n formatError effect_in_let zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .effect_in_let = .{ .called_func = "IO.println", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "纯函数中的效应调用"));
}

test "i18n formatError command_not_consumed en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .command_not_consumed = .{ .cmd_name = "ls", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Command Not Consumed"));
}

test "i18n formatError command_not_consumed zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .command_not_consumed = .{ .cmd_name = "ls", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Command 未消费"));
}

test "i18n formatError if_branch_mismatch en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .if_branch_mismatch = .{ .then_type = env_mod.int_type, .else_type = env_mod.string_type, .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Branch Type Mismatch"));
}

test "i18n formatError if_branch_mismatch zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .if_branch_mismatch = .{ .then_type = env_mod.int_type, .else_type = env_mod.string_type, .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "分支类型不一致"));
}

test "i18n formatError unknown_field en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .unknown_field = .{ .name = "z", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Unknown Field"));
}

test "i18n formatError unknown_field zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .unknown_field = .{ .name = "z", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "未知字段"));
}

test "i18n formatError nil_to_non_nilable en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .nil_to_non_nilable = undefined };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Nil assigned"));
}

test "i18n formatError nil_to_non_nilable zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .nil_to_non_nilable = undefined };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Nil 赋值"));
}

test "i18n formatError infinite_type en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .infinite_type = undefined };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Infinite Type"));
}

test "i18n formatError infinite_type zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .infinite_type = undefined };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "无限类型"));
}

test "i18n formatError effect_callback_mismatch en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .effect_callback_mismatch = .{ .func_name = "iter", .param = 0, .result = 0, .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Effect Callback Required"));
}

test "i18n formatError effect_callback_mismatch zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .effect_callback_mismatch = .{ .func_name = "iter", .param = 0, .result = 0, .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "需要效应回调"));
}

test "i18n formatError stream_not_consumed en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .stream_not_consumed = undefined };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Stream Not Consumed"));
}

test "i18n formatError stream_not_consumed zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .stream_not_consumed = undefined };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Stream 未消费"));
}

test "i18n formatError recursive_alias_depth en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .recursive_alias_depth = .{ .path = "A -> B -> A", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Recursive Type Expansion Limit"));
}

test "i18n formatError recursive_alias_depth zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .recursive_alias_depth = .{ .path = "A -> B -> A", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "递归类型展开超限"));
}

test "i18n formatError nilable_used_as_t en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .nilable_used_as_t = .{ .expected = env_mod.int_type, .inner_type = env_mod.string_type, .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Nilable type"));
}

test "i18n formatError nilable_used_as_t zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .nilable_used_as_t = .{ .expected = env_mod.int_type, .inner_type = env_mod.string_type, .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "可空类型"));
}

test "i18n formatError missing_field en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .missing_field = .{ .name = "x", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Missing Field"));
}

test "i18n formatError missing_field zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .missing_field = .{ .name = "x", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "缺少字段"));
}

test "i18n formatError too_many_args en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .too_many_args = .{ .func_type = env_mod.int_type, .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Too Many Arguments"));
}

test "i18n formatError too_many_args zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .too_many_args = .{ .func_type = env_mod.int_type, .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "函数"));
}

test "i18n formatError non_exhaustive en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const missing = [_][]const u8{"False"};
    const err = error_mod.TypeError{ .non_exhaustive = .{ .missing = &missing, .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Non-Exhaustive Pattern"));
}

test "i18n formatError non_exhaustive zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const missing = [_][]const u8{"False"};
    const err = error_mod.TypeError{ .non_exhaustive = .{ .missing = &missing, .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "模式匹配非穷举"));
}

test "i18n formatError redundant_pattern en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .redundant_pattern = .{ .pattern = "_", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Redundant Pattern"));
}

test "i18n formatError redundant_pattern zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .redundant_pattern = .{ .pattern = "_", .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "冗余模式"));
}

test "i18n formatError tuple_index_out_of_range en" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .tuple_index_out_of_range = .{ .len = 2, .index = 5, .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .en, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Tuple Index Out Of Range"));
}

test "i18n formatError tuple_index_out_of_range zh_CN" {
    var env = try createTypeEnv();
    defer env.deinit(std.testing.allocator);
    const err = error_mod.TypeError{ .tuple_index_out_of_range = .{ .len = 2, .index = 5, .span = undefined } };
    const msg = try i18n.formatError(std.testing.allocator, err, .zh_CN, &env);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.startsWith(u8, msg, "元组索引越界"));
}
