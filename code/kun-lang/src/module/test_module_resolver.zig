const std = @import("std");
const module_resolver = @import("module_resolver.zig");

test "isBuiltinType recognizes all builtins" {
    const cases = [_][]const u8{
        "CommandError", "Result", "Duration", "Path",
        "Int", "Float", "Bool", "String", "Bytes", "Char",
        "DateTime", "Decimal", "List", "Map", "Set", "Stream",
        "Nil", "Unit", "Regex", "Signal", "IOError", "Uid", "Gid",
    };
    for (cases) |name| {
        try std.testing.expect(module_resolver.isBuiltinType(name));
    }
    try std.testing.expect(!module_resolver.isBuiltinType("NotAType"));
    try std.testing.expect(!module_resolver.isBuiltinType(""));
}

test "hasPrimitiveBinding recognizes all modules" {
    const cases = [_][]const u8{
        "IO", "File", "Env", "Process", "Cmd",
        "Stream", "List", "Map", "Set",
        "Bytes", "String", "Hash", "Base64",
        "DateTime", "Parser.JSON", "Regex", "Validator",
    };
    for (cases) |name| {
        try std.testing.expect(module_resolver.hasPrimitiveBinding(name));
    }
    try std.testing.expect(!module_resolver.hasPrimitiveBinding("Cli"));
    try std.testing.expect(!module_resolver.hasPrimitiveBinding("Task"));
}

test "LoadedModule struct fields" {
    const module = module_resolver.LoadedModule{
        .name = "Test",
        .path = "/tmp/Test.kun",
        .decls = &.{},
        .exports = null,
    };
    try std.testing.expectEqualStrings("Test", module.name);
    try std.testing.expect(module.exports == null);
}

test "ModuleResolver init with no script dir" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const resolver = try module_resolver.ModuleResolver.init(arena.allocator(), null);
    try std.testing.expect(resolver.project_lib == null);
}

test "ModuleResolver circular import detection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var resolver = try module_resolver.ModuleResolver.init(arena.allocator(), null);
    try resolver.loading.put(arena.allocator(), "Foo", {});
    defer _ = resolver.loading.remove("Foo");
    try std.testing.expectError(error.CircularImport, resolver.load(arena.allocator(), "Foo"));
}

test "ModuleResolver resolve cached module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var resolver = try module_resolver.ModuleResolver.init(arena.allocator(), null);
    const module = try arena.allocator().create(module_resolver.LoadedModule);
    module.* = .{ .name = "Cached", .path = "/tmp/Cached.kun", .decls = &.{}, .exports = null };
    try resolver.loaded.put(arena.allocator(), "Cached", module);
    const result = try resolver.load(arena.allocator(), "Cached");
    try std.testing.expectEqualStrings("Cached", result.name);
}
