const std = @import("std");
const typed = @import("../ast/typed.zig");
const ast = @import("../ast/ast.zig");
const TypeId = typed.TypeId;

pub const TypeError = union(enum) {
    mismatch: struct { expected: TypeId, found: TypeId, span: ast.Span },
    not_a_function: struct { found: TypeId, span: ast.Span },
    effect_in_pure: struct { called_func: []const u8, span: ast.Span },
    non_exhaustive: struct { missing: []const []const u8, span: ast.Span },
    unknown_field: struct { name: []const u8, span: ast.Span },
    missing_field: struct { name: []const u8, span: ast.Span },
    nil_to_non_nilable: ast.Span,
    unbound_variable: struct { name: []const u8, span: ast.Span },
    unbound_type: struct { name: []const u8, span: ast.Span },
    infinite_type: ast.Span,
    function_apply_arg: struct { func_name: []const u8, expected: TypeId, found: TypeId, span: ast.Span },
    if_branch_mismatch: struct { then_type: TypeId, else_type: TypeId, span: ast.Span },
    too_many_args: struct { func_type: TypeId, span: ast.Span },
    effect_callback_mismatch: struct { func_name: []const u8, param: TypeId, result: TypeId, span: ast.Span },
    nilable_used_as_t: struct { expected: TypeId, inner_type: TypeId, span: ast.Span },
    redundant_pattern: struct { pattern: []const u8, span: ast.Span },
    tuple_index_out_of_range: struct { len: usize, index: usize, span: ast.Span },
    command_not_consumed: struct { cmd_name: []const u8, span: ast.Span },
    stream_not_consumed: ast.Span,
    recursive_alias_depth: struct { path: []const u8, span: ast.Span },
    pure_unit_return: struct { func_name: []const u8, span: ast.Span },
    effect_in_let: struct { called_func: []const u8, span: ast.Span },
    empty_body: struct { context: []const u8, span: ast.Span },
    duplicate_binding: struct { name: []const u8, span: ast.Span },
    unused_binding: struct { name: []const u8, span: ast.Span },
    unused_result: ast.Span,
    pure_expr_last: ast.Span,
};

pub const ErrorList = struct {
    items: std.ArrayListUnmanaged(TypeError),
    gpa: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !ErrorList {
        return ErrorList{ .items = .empty, .gpa = allocator };
    }

    pub fn deinit(self: *ErrorList, _: std.mem.Allocator) void {
        self.items.deinit(self.gpa);
    }

    pub fn add(self: *ErrorList, _: std.mem.Allocator, err: TypeError) !void {
        try self.items.append(self.gpa, err);
    }

    pub fn hasErrors(self: *const ErrorList) bool {
        return self.items.items.len > 0;
    }
};


