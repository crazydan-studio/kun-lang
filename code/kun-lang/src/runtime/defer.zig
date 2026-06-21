const std = @import("std");
const typed = @import("../ast/typed.zig");

pub const DeferStack = struct {
    items: std.ArrayListUnmanaged(*const typed.TypedExpr),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DeferStack {
        return .{ .items = .empty, .allocator = allocator };
    }

    pub fn deinit(self: *DeferStack) void {
        self.items.clearAndFree(self.allocator);
    }

    pub fn push(self: *DeferStack, expr: *const typed.TypedExpr) !void {
        try self.items.append(self.allocator, expr);
    }

    pub fn pop(self: *DeferStack) ?*const typed.TypedExpr {
        if (self.items.items.len == 0) return null;
        const last = self.items.items[self.items.items.len - 1];
        self.items.items.len -= 1;
        return last;
    }

    pub fn isEmpty(self: *const DeferStack) bool {
        return self.items.items.len == 0;
    }
};
