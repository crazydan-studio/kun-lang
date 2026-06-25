const std = @import("std");
const primitive = @import("primitive.zig");
const typed = @import("../ast/typed.zig");
const env_mod = @import("../typecheck/env.zig");
const value_mod = @import("value.zig");

fn buildTable() primitive.PrimitiveTable {
    return primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
}

test "table builds at comptime" {
    const int_t = env_mod.int_type;
    const table = primitive.buildPrimitiveTable(int_t, env_mod.string_type, env_mod.unit_type, env_mod.string_type, int_t, int_t);
    try std.testing.expect(table.bindings.len >= 2);
}

test "all bindings have required fields" {
    const table = buildTable();
    for (table.bindings) |b| {
        _ = b.module;
        _ = b.name;
        _ = b.fn_ptr;
        _ = b.return_type;
        try std.testing.expect(b.module.len > 0);
        try std.testing.expect(b.name.len > 0);
        try std.testing.expect(b.module.len <= 12);
    }
    try std.testing.expect(table.bindings.len > 18);
}

test "dotted name lookup" {
    const table = buildTable();
    {
        const present = [_][]const u8{
            "IO.println", "IO.readln", "File.readString", "File.list", "File.stat",
            "Env.getenv", "Env.contains", "Process.exit", "Process.pid", "Process.uid", "Process.gid",
            "Cmd.which", "Stream.lines", "Stream.iter", "Stream.toList",
            "List.length", "String.length", "Hash.sha256", "Base64.encode",
        };
        for (present) |name| {
            const dot = std.mem.indexOfScalar(u8, name, '.').?;
            try std.testing.expect(lookupBinding(table, name[0..dot], name[dot + 1 ..]));
        }
    }
    {
        const absent = [_][]const u8{ "Nonexistent.foo", "X.y", "IO.nonexistent", "Cmd.unknown" };
        for (absent) |name| {
            const dot = std.mem.indexOfScalar(u8, name, '.').?;
            try std.testing.expect(!lookupBinding(table, name[0..dot], name[dot + 1 ..]));
        }
    }
}

fn lookupBinding(table: primitive.PrimitiveTable, module: []const u8, name: []const u8) bool {
    for (table.bindings) |b| {
        if (std.mem.eql(u8, b.module, module) and std.mem.eql(u8, b.name, name)) return true;
    }
    return false;
}

test "RuntimeEnv init" {
    const table = buildTable();
    var frame = @import("env.zig").Frame{ .bindings = undefined, .parent = null, .primitives = null };
    const renv = primitive.RuntimeEnv.init(&frame, table, std.testing.allocator);
    try std.testing.expect(renv.frame == &frame);
    try std.testing.expectEqual(table.bindings.len, renv.primitives.bindings.len);
}

test "effect module check: all bindings in effect namespaces have is_effect=true" {
    const table = buildTable();
    const effect_modules = [_][]const u8{ "IO", "File", "Env", "Process", "Cmd", "Stream.iter" };
    for (table.bindings) |b| {
        for (effect_modules) |m| {
            if (std.mem.eql(u8, b.module, m) or std.mem.eql(u8, b.name, "exit") or
                (std.mem.eql(u8, b.module, "Stream") and std.mem.eql(u8, b.name, "iter")))
            {
                try std.testing.expect(b.is_effect);
            }
        }
    }
}

test "primitive impl functions return correct variant" {
    const Tag = @typeInfo(value_mod.Value).@"union".tag_type.?;
    const table = buildTable();
    const cases = [_]struct { mod: []const u8, name: []const u8, arg: value_mod.Value, expected: Tag }{
        .{ .mod = "IO", .name = "println", .arg = .{ .string = "hi" }, .expected = .unit },
        .{ .mod = "Env", .name = "getenv", .arg = .{ .string = "HOME" }, .expected = .string },
        .{ .mod = "Env", .name = "contains", .arg = .{ .unit = {} }, .expected = .bool },
        .{ .mod = "Process", .name = "uid", .arg = .{ .unit = {} }, .expected = .int },
        .{ .mod = "Process", .name = "gid", .arg = .{ .unit = {} }, .expected = .int },
        .{ .mod = "Cmd", .name = "which", .arg = .{ .unit = {} }, .expected = .nil },
        .{ .mod = "Stream", .name = "lines", .arg = .{ .unit = {} }, .expected = .nil },
        .{ .mod = "Stream", .name = "iter", .arg = .{ .unit = {} }, .expected = .unit },
        .{ .mod = "Stream", .name = "fold", .arg = .{ .unit = {} }, .expected = .unit },
        .{ .mod = "Stream", .name = "toList", .arg = .{ .unit = {} }, .expected = .nil },
        .{ .mod = "Stream", .name = "string", .arg = .{ .unit = {} }, .expected = .string },
        .{ .mod = "Stream", .name = "bytes", .arg = .{ .unit = {} }, .expected = .bytes },
        .{ .mod = "List", .name = "length", .arg = .{ .list = .{ .items = &.{}, .cap = 0 } }, .expected = .int },
        .{ .mod = "List", .name = "isEmpty", .arg = .{ .list = .{ .items = &.{}, .cap = 0 } }, .expected = .bool },
        .{ .mod = "List", .name = "head", .arg = .{ .list = .{ .items = &.{}, .cap = 0 } }, .expected = .nil },
        .{ .mod = "String", .name = "length", .arg = .{ .string = "x" }, .expected = .int },
        .{ .mod = "Bytes", .name = "length", .arg = .{ .bytes = &.{} }, .expected = .int },
        .{ .mod = "Hash", .name = "sha256", .arg = .{ .bytes = "test" }, .expected = .bytes },
        .{ .mod = "Hash", .name = "sha256Hex", .arg = .{ .bytes = "test" }, .expected = .string },
        .{ .mod = "Base64", .name = "encode", .arg = .{ .bytes = "test" }, .expected = .string },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for (cases) |c| {
        var found = false;
        for (table.bindings) |entry| {
            if (std.mem.eql(u8, entry.module, c.mod) and std.mem.eql(u8, entry.name, c.name)) {
                var renv = primitive.RuntimeEnv{ .frame = undefined, .primitives = table, .allocator = arena.allocator() };
                const result = entry.fn_ptr(&renv, &[_]value_mod.Value{c.arg});
                try std.testing.expectEqual(@intFromEnum(c.expected), @intFromEnum(result));
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "isEffectBinding covers all known patterns" {
    const cases = [_]struct { name: []const u8, expected: bool }{
        .{ .name = "IO.println", .expected = true },
        .{ .name = "IO.readln", .expected = true },
        .{ .name = "IO.flush", .expected = true },
        .{ .name = "IO", .expected = true },
        .{ .name = "File.readString", .expected = true },
        .{ .name = "File", .expected = true },
        .{ .name = "Env.get", .expected = true },
        .{ .name = "Env", .expected = true },
        .{ .name = "Process.exit", .expected = true },
        .{ .name = "Process", .expected = true },
        .{ .name = "Task.wait", .expected = true },
        .{ .name = "Task", .expected = true },
        .{ .name = "Random.int", .expected = true },
        .{ .name = "Random", .expected = true },
        .{ .name = "Stream.iter", .expected = true },
        .{ .name = "Signal.on", .expected = true },
        .{ .name = "Cmd.exec", .expected = true },
        .{ .name = "Cmd.which", .expected = true },
        .{ .name = "Cmd.timeout", .expected = true },
        .{ .name = "Cmd.retry", .expected = true },
        .{ .name = "Cmd.execSafe", .expected = true },
        .{ .name = "Cmd.foo?", .expected = true },
        .{ .name = "Cmd.foo!", .expected = true },
        .{ .name = "Cmd.pipe?", .expected = true },
        .{ .name = "Cmd.pipe!", .expected = true },
        .{ .name = "List.map", .expected = false },
        .{ .name = "String.length", .expected = false },
        .{ .name = "String.trim", .expected = false },
        .{ .name = "Int.abs", .expected = false },
        .{ .name = "Bool.not", .expected = false },
        .{ .name = "Float.ceil", .expected = false },
        .{ .name = "Stream.lines", .expected = false },
        .{ .name = "Stream.fold", .expected = false },
        .{ .name = "Stream.toList", .expected = false },
        .{ .name = "Stream.string", .expected = false },
        .{ .name = "Stream.bytes", .expected = false },
        .{ .name = "Stream.map", .expected = false },
        .{ .name = "Stream.filter", .expected = false },
        .{ .name = "Cmd.ls", .expected = false },
        .{ .name = "Cmd.echo", .expected = false },
        .{ .name = "Cmd.pipe", .expected = false },
        .{ .name = "Cmd.withEnv", .expected = false },
        .{ .name = "Cmd.withStdinFile", .expected = false },
        .{ .name = "Cmd.withStdin", .expected = false },
        .{ .name = "Cmd.mergeStderr", .expected = false },
        .{ .name = "Cmd.withRunAs", .expected = false },
        .{ .name = "Cmd.andThen", .expected = false },
        .{ .name = "Cmd.orElse", .expected = false },
        .{ .name = "x", .expected = false },
        .{ .name = "println", .expected = false },
        .{ .name = "exec", .expected = false },
        .{ .name = "Unknown.foo", .expected = false },
        .{ .name = "Foo.bar", .expected = false },
    };
    for (cases) |c| {
        try std.testing.expectEqual(c.expected, primitive.isEffectBinding(c.name));
    }
}
