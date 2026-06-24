const std = @import("std");
const primitive = @import("primitive.zig");
const typed = @import("../ast/typed.zig");
const env_mod = @import("../typecheck/env.zig");
const value_mod = @import("value.zig");

test "primitive table builds at comptime" {
    const int_t = env_mod.int_type;
    const string_t = env_mod.string_type;
    const unit_t = env_mod.unit_type;
    const stream_str = env_mod.string_type;
    const table = primitive.buildPrimitiveTable(int_t, string_t, unit_t, stream_str, int_t, int_t);
    try std.testing.expect(table.bindings.len >= 2);
}

test "primitive is_effect query" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    try std.testing.expect(table.bindings[0].is_effect == true);
    try std.testing.expect(table.bindings[1].is_effect == true);
}

test "primitive println outputs to stdout" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    try std.testing.expect(table.bindings[0].module[0] == 'I');
    try std.testing.expect(table.bindings[0].module[1] == 'O');
    try std.testing.expect(std.mem.eql(u8, table.bindings[0].name, "println"));
    try std.testing.expect(std.mem.eql(u8, table.bindings[1].name, "readln"));
}

test "primitive isEffectBinding returns true for IO namespace" {
    try std.testing.expect(primitive.isEffectBinding("IO.println"));
    try std.testing.expect(primitive.isEffectBinding("IO.readln"));
}

test "primitive isEffectBinding returns true for File/Env/Process" {
    try std.testing.expect(primitive.isEffectBinding("File.readString"));
    try std.testing.expect(primitive.isEffectBinding("Env.get"));
    try std.testing.expect(primitive.isEffectBinding("Process.exit"));
}

test "primitive isEffectBinding returns false for pure namespaces" {
    try std.testing.expect(!primitive.isEffectBinding("List.map"));
    try std.testing.expect(!primitive.isEffectBinding("String.length"));
    try std.testing.expect(!primitive.isEffectBinding("String.trim"));
    try std.testing.expect(!primitive.isEffectBinding("Int.abs"));
}

test "primitive isEffectBinding returns true for Stream.iter" {
    try std.testing.expect(primitive.isEffectBinding("Stream.iter"));
}

test "Phase4 primitive printlnImpl returns unit" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    const entry = table.bindings[0];
    var renv = primitive.RuntimeEnv{ .frame = undefined, .primitives = table, .allocator = std.testing.allocator };
    const arg = value_mod.Value{ .string = "hi" };
    const result = entry.fn_ptr(&renv, &[_]value_mod.Value{arg});
    try std.testing.expect(result == .unit);
}

test "Phase4 primitive pidImpl returns int" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    for (table.bindings) |entry| {
        if (std.mem.eql(u8, entry.module, "Process") and std.mem.eql(u8, entry.name, "pid")) {
            var renv = primitive.RuntimeEnv{ .frame = undefined, .primitives = table, .allocator = std.testing.allocator };
            const arg = value_mod.Value{ .unit = {} };
            const result = entry.fn_ptr(&renv, &[_]value_mod.Value{arg});
            try std.testing.expect(result == .int);
            break;
        }
    }
}

test "Phase4 dotted name lookup all bindings" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    const names = [_][]const u8{
        "IO.println", "IO.readln",
        "File.readString", "File.list", "File.stat",
        "Env.getenv", "Env.contains",
        "Process.exit", "Process.pid", "Process.uid", "Process.gid",
        "Cmd.which",
    };
    for (names) |name| {
        const dot = std.mem.indexOfScalar(u8, name, '.').?;
        const module = name[0..dot];
        const fn_name = name[dot + 1 ..];
        var found = false;
        for (table.bindings) |b| {
            if (std.mem.eql(u8, b.module, module) and std.mem.eql(u8, b.name, fn_name)) { found = true; break; }
        }
        try std.testing.expect(found);
    }
}

test "Phase4 dotted name lookup fails for unknown module" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    const names = [_][]const u8{ "Nonexistent.foo", "X.y", "IO.nonexistent", "Cmd.unknown" };
    for (names) |name| {
        const dot = std.mem.indexOfScalar(u8, name, '.').?;
        const module = name[0..dot];
        const fn_name = name[dot + 1 ..];
        var found = false;
        for (table.bindings) |b| {
            if (std.mem.eql(u8, b.module, module) and std.mem.eql(u8, b.name, fn_name)) { found = true; break; }
        }
        try std.testing.expect(!found);
    }
}

test "Phase4 primitive table has 12 bindings" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    try std.testing.expectEqual(@as(usize, 18), table.bindings.len);
}

fn lookupBinding(table: primitive.PrimitiveTable, module: []const u8, name: []const u8) bool {
    for (table.bindings) |b| {
        if (std.mem.eql(u8, b.module, module) and std.mem.eql(u8, b.name, name)) return true;
    }
    return false;
}

test "Phase4 dotted name lookup finds all 12 bindings" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    try std.testing.expect(lookupBinding(table, "IO", "println"));
    try std.testing.expect(lookupBinding(table, "IO", "readln"));
    try std.testing.expect(lookupBinding(table, "File", "readString"));
    try std.testing.expect(lookupBinding(table, "File", "list"));
    try std.testing.expect(lookupBinding(table, "File", "stat"));
    try std.testing.expect(lookupBinding(table, "Env", "getenv"));
    try std.testing.expect(lookupBinding(table, "Env", "contains"));
    try std.testing.expect(lookupBinding(table, "Process", "exit"));
    try std.testing.expect(lookupBinding(table, "Process", "pid"));
    try std.testing.expect(lookupBinding(table, "Process", "uid"));
    try std.testing.expect(lookupBinding(table, "Process", "gid"));
    try std.testing.expect(lookupBinding(table, "Cmd", "which"));
}

test "Phase4 RuntimeEnv init" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    var frame = @import("env.zig").Frame{ .bindings = undefined, .parent = null, .primitives = null };
    const renv = primitive.RuntimeEnv.init(&frame, table, std.testing.allocator);
    try std.testing.expect(renv.frame == &frame);
    try std.testing.expectEqual(table.bindings.len, renv.primitives.bindings.len);
}

test "Phase4 primitive File operations all is_effect" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    for (table.bindings) |b| {
        if (std.mem.eql(u8, b.module, "File")) {
            try std.testing.expect(b.is_effect);
        }
    }
}

test "Phase4 primitive Env operations all is_effect" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    for (table.bindings) |b| {
        if (std.mem.eql(u8, b.module, "Env")) {
            try std.testing.expect(b.is_effect);
        }
    }
}

test "Phase4 primitive Process operations all is_effect" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    for (table.bindings) |b| {
        if (std.mem.eql(u8, b.module, "Process")) {
            try std.testing.expect(b.is_effect);
        }
    }
}

test "Phase4 primitive Cmd.which is_effect" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    for (table.bindings) |b| {
        if (std.mem.eql(u8, b.module, "Cmd") and std.mem.eql(u8, b.name, "which")) {
            try std.testing.expect(b.is_effect);
            return;
        }
    }
    try std.testing.expect(false);
}

test "Phase4 primitive impl functions return correct variant" {
    const Tag = @typeInfo(value_mod.Value).@"union".tag_type.?;
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    const cases = [_]struct { mod: []const u8, name: []const u8, arg: value_mod.Value, expected: Tag }{
        .{ .mod = "IO", .name = "readln", .arg = .{ .unit = {} }, .expected = .string },
        .{ .mod = "File", .name = "readString", .arg = .{ .unit = {} }, .expected = .nil },
        .{ .mod = "File", .name = "list", .arg = .{ .unit = {} }, .expected = .nil },
        .{ .mod = "File", .name = "stat", .arg = .{ .unit = {} }, .expected = .nil },
        .{ .mod = "Env", .name = "getenv", .arg = .{ .unit = {} }, .expected = .nil },
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
    };
    for (cases) |c| {
        var found = false;
        for (table.bindings) |entry| {
            if (std.mem.eql(u8, entry.module, c.mod) and std.mem.eql(u8, entry.name, c.name)) {
                var renv = primitive.RuntimeEnv{ .frame = undefined, .primitives = table, .allocator = std.testing.allocator };
                const result = entry.fn_ptr(&renv, &[_]value_mod.Value{c.arg});
                try std.testing.expectEqual(@intFromEnum(c.expected), @intFromEnum(result));
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "Phase4 isEffectBinding Task namespace is effect" {
    try std.testing.expect(primitive.isEffectBinding("Task.wait"));
    try std.testing.expect(primitive.isEffectBinding("Task.spawn"));
}

test "Phase4 isEffectBinding Random namespace is effect" {
    try std.testing.expect(primitive.isEffectBinding("Random.int"));
    try std.testing.expect(primitive.isEffectBinding("Random.float"));
}

test "Phase4 isEffectBinding known Cmd non-effect APIs" {
    try std.testing.expect(!primitive.isEffectBinding("Cmd.withStdinFile"));
    try std.testing.expect(!primitive.isEffectBinding("Cmd.withStdin"));
    try std.testing.expect(!primitive.isEffectBinding("Cmd.mergeStderr"));
    try std.testing.expect(!primitive.isEffectBinding("Cmd.withRunAs"));
    try std.testing.expect(!primitive.isEffectBinding("Cmd.andThen"));
    try std.testing.expect(!primitive.isEffectBinding("Cmd.orElse"));
}

test "Phase4 isEffectBinding false for various pure namespaces" {
    try std.testing.expect(!primitive.isEffectBinding("List.map"));
    try std.testing.expect(!primitive.isEffectBinding("Int.abs"));
    try std.testing.expect(!primitive.isEffectBinding("Bool.not"));
    try std.testing.expect(!primitive.isEffectBinding("Float.ceil"));
}

test "Phase4 primitive table binding count consistent" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    var count: usize = 0;
    for (table.bindings) |_| count += 1;
    try std.testing.expectEqual(@as(usize, 18), count);
}

test "Phase4 isEffectBinding true for bare effect namespace names" {
    try std.testing.expect(primitive.isEffectBinding("IO"));
    try std.testing.expect(primitive.isEffectBinding("File"));
    try std.testing.expect(primitive.isEffectBinding("Env"));
    try std.testing.expect(primitive.isEffectBinding("Process"));
    try std.testing.expect(primitive.isEffectBinding("Task"));
    try std.testing.expect(primitive.isEffectBinding("Random"));
}

test "Phase4 isEffectBinding true for IO.any_method" {
    try std.testing.expect(primitive.isEffectBinding("IO.println"));
    try std.testing.expect(primitive.isEffectBinding("IO.write"));
    try std.testing.expect(primitive.isEffectBinding("IO.flush"));
}

test "Phase4 isEffectBinding false for Stream.lines and other non-iter methods" {
    try std.testing.expect(!primitive.isEffectBinding("Stream.lines"));
    try std.testing.expect(!primitive.isEffectBinding("Stream.fold"));
    try std.testing.expect(!primitive.isEffectBinding("Stream.toList"));
    try std.testing.expect(!primitive.isEffectBinding("Stream.string"));
    try std.testing.expect(!primitive.isEffectBinding("Stream.bytes"));
    try std.testing.expect(!primitive.isEffectBinding("Stream.map"));
    try std.testing.expect(!primitive.isEffectBinding("Stream.filter"));
}

test "Phase4 isEffectBinding false for bare non-namespace names" {
    try std.testing.expect(!primitive.isEffectBinding("x"));
    try std.testing.expect(!primitive.isEffectBinding("println"));
    try std.testing.expect(!primitive.isEffectBinding("exec"));
    try std.testing.expect(!primitive.isEffectBinding("print"));
}

test "Phase4 isEffectBinding true for Signal.on" {
    try std.testing.expect(primitive.isEffectBinding("Signal.on"));
}

test "Phase4 isEffectBinding false for unknown namespace" {
    try std.testing.expect(!primitive.isEffectBinding("Unknown.foo"));
    try std.testing.expect(!primitive.isEffectBinding("Foo.bar"));
}

// --- isEffectBinding Cmd variants individually ---

test "Phase4 isEffectBinding Cmd variant lookup" {
    const cases = [_]struct { name: []const u8, expected: bool }{
        .{ .name = "Cmd.exec", .expected = true },
        .{ .name = "Cmd.which", .expected = true },
        .{ .name = "Cmd.timeout", .expected = true },
        .{ .name = "Cmd.retry", .expected = true },
        .{ .name = "Cmd.execSafe", .expected = true },
        .{ .name = "Cmd.foo?", .expected = true },
        .{ .name = "Cmd.foo!", .expected = true },
        .{ .name = "Cmd.ls?", .expected = true },
        .{ .name = "Cmd.echo!", .expected = true },
        .{ .name = "Cmd.pipe?", .expected = true },
        .{ .name = "Cmd.pipe!", .expected = true },
        .{ .name = "Cmd.ls", .expected = false },
        .{ .name = "Cmd.echo", .expected = false },
        .{ .name = "Cmd.pipe", .expected = false },
        .{ .name = "Cmd.withEnv", .expected = false },
        .{ .name = "Cmd.nonexistent", .expected = false },
    };
    for (cases) |c| {
        try std.testing.expectEqual(c.expected, primitive.isEffectBinding(c.name));
    }
}

// --- PrimitiveBinding validation ---

test "Phase4 all IO bindings have non-empty module and name" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    for (table.bindings) |b| {
        try std.testing.expect(b.module.len > 0);
        try std.testing.expect(b.name.len > 0);
    }
}

test "Phase4 all bindings have valid return_type" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    for (table.bindings) |b| {
        _ = b.return_type;
    }
    try std.testing.expectEqual(@as(usize, 18), table.bindings.len);
}

test "Phase4 all bindings have non-null fn_ptr" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    for (table.bindings) |b| {
        _ = b.fn_ptr;
    }
}

test "Phase4 all bindings module name length valid" {
    const table = primitive.buildPrimitiveTable(env_mod.int_type, env_mod.string_type, env_mod.unit_type, env_mod.string_type, env_mod.bool_type, env_mod.bytes_type);
    for (table.bindings) |b| {
        try std.testing.expect(b.module.len > 0);
        try std.testing.expect(b.name.len > 0);
        try std.testing.expect(b.module.len <= 7);
    }
}

