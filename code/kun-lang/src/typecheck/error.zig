const typed = @import("../ast/typed.zig");
const ast = @import("../ast/ast.zig");
const TypeId = typed.TypeId;

pub const TypeError = union(enum) {
    mismatch: struct { expected: TypeId, found: TypeId, span: ast.Span },
    not_a_function: struct { found: TypeId, span: ast.Span },
    effect_in_pure: struct { span: ast.Span },
    non_exhaustive: struct { missing: []const []const u8, span: ast.Span },
    unknown_field: struct { name: []const u8, span: ast.Span },
    missing_field: struct { name: []const u8, span: ast.Span },
    nil_to_non_nilable: ast.Span,
    unbound_variable: []const u8,
    unbound_type: []const u8,
    infinite_type: ast.Span,
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

const std = @import("std");
