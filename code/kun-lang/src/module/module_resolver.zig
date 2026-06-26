const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const parser = @import("../parser/parser.zig");
const io = @import("../stdlib/io.zig");

pub const LoadedModule = struct {
    name: []const u8,
    path: []const u8,
    decls: []const parser.Decl,
    exports: ?[]const []const u8,
};

pub const ModuleError = error{
    ModuleNotFound,
    CircularImport,
    OutOfMemory,
};

pub const ModuleResolver = struct {
    project_lib: ?[]const u8,
    kun_path: [][]const u8,
    runtime_lib: []const u8,
    cmd_path: []const u8,
    loaded: std.StringHashMapUnmanaged(*LoadedModule),
    loading: std.StringHashMapUnmanaged(void),

    pub fn init(allocator: std.mem.Allocator, script_dir: ?[]const u8) !ModuleResolver {
        var kun_path_list: std.ArrayListUnmanaged([]const u8) = .empty;
        if (io.getEnvValue(allocator, "KUN_PATH")) |kp| {
            var it = std.mem.splitSequence(u8, kp, ":");
            while (it.next()) |dir| {
                if (dir.len > 0) {
                    try kun_path_list.append(allocator, dir);
                }
            }
        }

        return ModuleResolver{
            .project_lib = if (script_dir) |d| try std.fs.path.join(allocator, &.{ d, "lib" }) else null,
            .kun_path = try kun_path_list.toOwnedSlice(allocator),
            .runtime_lib = io.getEnvValue(allocator, "KUN_RUNTIME") orelse "/usr/local/lib/kun",
            .cmd_path = if (io.getEnvValue(allocator, "HOME")) |home|
                try std.fs.path.join(allocator, &.{ home, ".kun/cmd" })
            else
                "/root/.kun/cmd",
            .loaded = .empty,
            .loading = .empty,
        };
    }

    pub fn load(
        self: *ModuleResolver,
        allocator: std.mem.Allocator,
        module_name: []const u8,
    ) ModuleError!*LoadedModule {
        if (self.loaded.get(module_name)) |m| return m;
        if (self.loading.contains(module_name)) return error.CircularImport;
        try self.loading.put(allocator, module_name, {});

        const module_path = try self.resolve(allocator, module_name);
        const source = try readFileAlloc(allocator, module_path, 1024 * 1024);

        const tokens = lexer.tokenize(allocator, source) catch return error.ModuleNotFound;
        const decls = parser.parseModule(allocator, tokens) catch return error.ModuleNotFound;

        var exports: ?[]const []const u8 = null;
        for (decls) |decl| {
            if (decl == .export_) {
                exports = decl.export_.names;
                break;
            }
        }

        const module = try allocator.create(LoadedModule);
        module.* = .{
            .name = module_name,
            .path = module_path,
            .decls = decls,
            .exports = exports,
        };

        try self.loaded.put(allocator, module_name, module);

        for (decls) |decl| {
            if (decl == .import) {
                const imp = decl.import;
                _ = self.load(allocator, imp.module) catch continue;
            }
        }

        _ = self.loading.remove(module_name);
        return module;
    }

    pub fn deinit(_: *ModuleResolver, _: std.mem.Allocator) void {
        // TODO: resolver lives on the Arena, so deinit is a no-op.
        // When moving off arena allocation, free:
        //   - loaded HashMap values (*LoadedModule) and keys
        //   - loading HashMap
        //   - kun_path entries
    }

    pub fn resolve(self: *ModuleResolver, allocator: std.mem.Allocator, module_name: []const u8) ModuleError![]const u8 {
        if (self.project_lib) |base| {
            if (try findModule(allocator, base, module_name)) |p| return p;
        }
        for (self.kun_path) |base| {
            if (try findModule(allocator, base, module_name)) |p| return p;
        }
        if (try findModule(allocator, self.runtime_lib, module_name)) |p| return p;
        if (try findModule(allocator, self.cmd_path, module_name)) |p| return p;

        return error.ModuleNotFound;
    }
};

fn findModule(allocator: std.mem.Allocator, base: []const u8, module_name: []const u8) !?[]const u8 {
    const kun_path = try std.fmt.allocPrint(allocator, "{s}/{s}.kun", .{ base, module_name });
    const path_z = try allocator.allocSentinel(u8, kun_path.len, 0);
    @memcpy(path_z[0..kun_path.len], kun_path);
    defer allocator.free(path_z);
    if (std.os.linux.access(path_z, std.os.linux.F_OK) != 0) {
        allocator.free(kun_path);
        return null;
    }
    return kun_path;
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, limit: usize) ModuleError![]u8 {
    const path_z = try allocator.allocSentinel(u8, path.len, 0);
    defer allocator.free(path_z);
    @memcpy(path_z[0..path.len], path);
    const fd = std.posix.openatZ(std.os.linux.AT.FDCWD, path_z, .{}, 0) catch return error.ModuleNotFound;
    defer _ = std.os.linux.close(fd);

    var buf = try allocator.alloc(u8, limit);
    errdefer allocator.free(buf);
    const n = std.posix.read(fd, buf) catch {
        allocator.free(buf);
        return error.ModuleNotFound;
    };
    if (n == 0) return buf[0..0];
    return try allocator.realloc(buf, n);
}

pub fn isBuiltinType(name: []const u8) bool {
    const builtins = [_][]const u8{
        "CommandError", "Result", "Duration", "Path",
        "Int", "Float", "Bool", "String", "Bytes", "Char",
        "DateTime", "Decimal", "List", "Map", "Set", "Stream",
        "Unit", "Regex", "Signal", "IOError", "Uid", "Gid",
    };
    for (builtins) |b| {
        if (std.mem.eql(u8, name, b)) return true;
    }
    return false;
}

pub fn hasPrimitiveBinding(name: []const u8) bool {
    const primitive_modules = [_][]const u8{
        "IO", "File", "Env", "Process", "Cmd",
        "Stream", "List", "Map", "Set",
        "Bytes", "String", "Hash", "Base64",
        "DateTime", "Parser.JSON", "Regex",
        "Nilable", "Duration", "Int", "Float", "Char",
    };
    for (primitive_modules) |m| {
        if (std.mem.eql(u8, name, m)) return true;
    }
    return false;
}
