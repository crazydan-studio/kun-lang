const std = @import("std");
const ast = @import("../ast/ast.zig");
const parser = @import("../parser/parser.zig");
const typed = @import("../ast/typed.zig");
const env_mod = @import("env.zig");
const constraint_mod = @import("constraint.zig");
const error_mod = @import("error.zig");
const primitive_mod = @import("../runtime/primitive.zig");

const TypeEnv = env_mod.TypeEnv;
const TypedDecl = typed.TypedDecl;
const ErrorList = error_mod.ErrorList;
const PrimitiveTable = primitive_mod.PrimitiveTable;

pub fn infer(
    allocator: std.mem.Allocator,
    decls: []const parser.Decl,
    env: *TypeEnv,
    primitives: PrimitiveTable,
) (error{TypeCheckFailed, Unimplemented, OutOfMemory})![]const TypedDecl {
    var errors = try ErrorList.init(allocator);
    defer errors.deinit(allocator);

    const result = constraint_mod.inferModule(allocator, decls, env, &errors, primitives) catch |err| {
        for (decls) |decl| {
            switch (decl) {
                .function_def => |f| ast.destroyExprSub(allocator, f.body),
                else => {},
            }
        }
        return err;
    };

    for (decls) |decl| {
        switch (decl) {
            .function_def => |f| ast.destroyExprSub(allocator, f.body),
            else => {},
        }
    }

    return result;
}
