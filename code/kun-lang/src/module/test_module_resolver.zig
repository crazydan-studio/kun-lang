const std = @import("std");
const module_resolver = @import("module_resolver.zig");
const parser = @import("../parser/parser.zig");
const lexer = @import("../lexer/lexer.zig");

test "isBuiltinType recognizes all builtins" {
    const cases = [_][]const u8{
        "CommandError", "Result", "Duration", "Path",
        "Int", "Float", "Bool", "String", "Bytes", "Char",
        "DateTime", "Decimal", "List", "Map", "Set", "Stream",
        "Unit", "Regex", "Signal", "IOError", "Uid", "Gid",
    };
    for (cases) |name| {
        try std.testing.expect(module_resolver.isBuiltinType(name));
    }
    try std.testing.expect(!module_resolver.isBuiltinType("NotAType"));
    try std.testing.expect(!module_resolver.isBuiltinType(""));
}

test "isBuiltinType edge cases" {
    try std.testing.expect(!module_resolver.isBuiltinType("IntExtra"));
    try std.testing.expect(!module_resolver.isBuiltinType("float"));
    try std.testing.expect(!module_resolver.isBuiltinType("CMDERror"));
    try std.testing.expect(!module_resolver.isBuiltinType(" "));
    try std.testing.expect(!module_resolver.isBuiltinType("Int."));
}

test "hasPrimitiveBinding recognizes all modules" {
    const cases = [_][]const u8{
        "IO", "File", "Env", "Process", "Cmd",
        "Stream", "List", "Map", "Set",
        "Bytes", "String", "Hash", "Base64",
        "DateTime", "Parser.JSON", "Regex", "Validator",
        "Nilable", "Duration", "Int", "Float", "Char",
    };
    for (cases) |name| {
        try std.testing.expect(module_resolver.hasPrimitiveBinding(name));
    }
    try std.testing.expect(!module_resolver.hasPrimitiveBinding("Cli"));
    try std.testing.expect(!module_resolver.hasPrimitiveBinding("Task"));
    try std.testing.expect(!module_resolver.hasPrimitiveBinding("Random"));
}

test "hasPrimitiveBinding edge cases" {
    try std.testing.expect(!module_resolver.hasPrimitiveBinding("IOExtra"));
    try std.testing.expect(!module_resolver.hasPrimitiveBinding("I O"));
    try std.testing.expect(!module_resolver.hasPrimitiveBinding(""));
    try std.testing.expect(!module_resolver.hasPrimitiveBinding("NOT_A_MODULE"));
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

test "LoadedModule with exports" {
    const module = module_resolver.LoadedModule{
        .name = "Math",
        .path = "/tmp/Math.kun",
        .decls = &.{},
        .exports = &.{ "add", "sub" },
    };
    try std.testing.expectEqualStrings("Math", module.name);
    try std.testing.expect(module.exports != null);
    try std.testing.expectEqualStrings("add", module.exports.?[0]);
    try std.testing.expectEqualStrings("sub", module.exports.?[1]);
}

test "ModuleResolver init with no script dir" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const resolver = try module_resolver.ModuleResolver.init(arena.allocator(), null);
    try std.testing.expect(resolver.project_lib == null);
}

test "ModuleResolver init with script dir" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const resolver = try module_resolver.ModuleResolver.init(arena.allocator(), "/my/project");
    try std.testing.expect(resolver.project_lib != null);
    try std.testing.expectEqualStrings("/my/project/lib", resolver.project_lib.?);
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

test "ModuleResolver resolve nonexistent returns error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var resolver = try module_resolver.ModuleResolver.init(arena.allocator(), null);
    try std.testing.expectError(error.ModuleNotFound, resolver.resolve(arena.allocator(), "NonExistentModule"));
}

test "ModuleResolver search path init priority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Verify init configures correct path strings
    const resolver = try module_resolver.ModuleResolver.init(alloc, "/app");
    try std.testing.expectEqualStrings("/app/lib", resolver.project_lib.?);
    // runtime_lib should be non-empty default
    try std.testing.expect(resolver.runtime_lib.len > 0);
    // cmd_path should be non-empty default
    try std.testing.expect(resolver.cmd_path.len > 0);
}

test "ModuleResolver parse export lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Parse a module with exports (single line, no newlines)
    const source = "export (add, sub)";
    const tokens = try lexer.tokenize(alloc, source);
    const decls = try parser.parseModule(alloc, tokens);

    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expect(decls[0] == .export_);
    try std.testing.expectEqualStrings("add", decls[0].export_.names[0]);
    try std.testing.expectEqualStrings("sub", decls[0].export_.names[1]);

    // Parse a module without exports
    const source2 = "add = \\x -> x";
    const tokens2 = try lexer.tokenize(alloc, source2);
    const decls2 = try parser.parseModule(alloc, tokens2);

    try std.testing.expectEqual(@as(usize, 1), decls2.len);
    try std.testing.expect(decls2[0] == .function_def);
}

test "ModuleResolver script without export" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Single function def, no export — script-like
    const source = "answer = 42";
    const tokens = try lexer.tokenize(alloc, source);
    const decls = try parser.parseModule(alloc, tokens);

    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expect(decls[0] == .function_def);
    try std.testing.expectEqualStrings("answer", decls[0].function_def.name);
}

test "ModuleResolver decl classifies correctly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test that a module with export and function_def is classified as lib
    const src_lib = "export (add)";
    const tokens = try lexer.tokenize(alloc, src_lib);
    const decls = try parser.parseModule(alloc, tokens);
    try std.testing.expect(decls[0] == .export_);

    // Test that a script with just a function def and no export
    const src_script = "answer = 42";
    const tokens2 = try lexer.tokenize(alloc, src_script);
    const decls2 = try parser.parseModule(alloc, tokens2);
    try std.testing.expect(decls2[0] == .function_def);
}
