const std = @import("std");
const value_mod = @import("value.zig");
const typed = @import("../ast/typed.zig");

const io = @import("primitive/io.zig");
const fs = @import("primitive/fs.zig");
const data = @import("primitive/data.zig");
const stream = @import("primitive/stream.zig");
const crypto = @import("primitive/crypto.zig");

const TypeId = typed.TypeId;
const Frame = @import("env.zig").Frame;
const Value = value_mod.Value;

pub const RuntimeEnv = struct {
    frame: *Frame,
    primitives: PrimitiveTable,
    allocator: std.mem.Allocator,
    eval_fn: ?*anyopaque = null,

    pub fn init(frame: *Frame, primitives: PrimitiveTable, allocator: std.mem.Allocator) RuntimeEnv {
        return .{ .frame = frame, .primitives = primitives, .allocator = allocator, .eval_fn = null };
    }
};

pub const EvalFn = *const fn (expr: *const typed.TypedExpr, frame: *Frame, allocator: std.mem.Allocator) anyerror!Value;

pub fn callEval(env: *RuntimeEnv, expr: *const typed.TypedExpr, frame: *Frame) anyerror!Value {
    const eval = env.eval_fn orelse return error.EvalUnavailable;
    const fn_ptr: EvalFn = @ptrCast(@alignCast(eval));
    return fn_ptr(expr, frame, env.allocator);
}

pub const PrimitiveFn = *const fn (env: *RuntimeEnv, args: []const Value) Value;

pub const PrimitiveBinding = struct {
    module: []const u8,
    name: []const u8,
    fn_ptr: PrimitiveFn,
    arg_count: u8,
    return_type: TypeId,
    is_polymorphic: bool,
    is_effect: bool,
};

pub const PrimitiveTable = struct {
    bindings: []const PrimitiveBinding,
};

pub fn buildPrimitiveTable(comptime int_t: TypeId, comptime string_t: TypeId, comptime unit_t: TypeId, comptime stream_string_t: TypeId, comptime bool_t: TypeId, comptime bytes_t: TypeId) PrimitiveTable {
    const P = true;
    const bindings = [_]PrimitiveBinding{
        .{ .module = "IO", .name = "println", .fn_ptr = io.printlnImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "readln", .fn_ptr = io.readlnImpl, .arg_count = 0, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "print", .fn_ptr = io.printImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "eprint", .fn_ptr = io.eprintImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "eprintln", .fn_ptr = io.eprintlnImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "readBytes", .fn_ptr = io.readBytesImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "readAll", .fn_ptr = io.readAllImpl, .arg_count = 0, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "readAllBytes", .fn_ptr = io.readAllBytesImpl, .arg_count = 0, .return_type = bytes_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "isTerminal", .fn_ptr = io.isTerminalImpl, .arg_count = 0, .return_type = bool_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "IO", .name = "flush", .fn_ptr = io.flushImpl, .arg_count = 0, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },

        .{ .module = "File", .name = "readString", .fn_ptr = fs.readStringImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "list", .fn_ptr = fs.listDirImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "stat", .fn_ptr = fs.statImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "mkdir", .fn_ptr = fs.mkdirImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "mkdirAll", .fn_ptr = fs.mkdirAllImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "writeString", .fn_ptr = fs.writeStringImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "touch", .fn_ptr = fs.touchImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "remove", .fn_ptr = fs.removeImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "removeDir", .fn_ptr = fs.removeDirImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "currentDir", .fn_ptr = fs.currentDirImpl, .arg_count = 0, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "homeDir", .fn_ptr = fs.homeDirImpl, .arg_count = 0, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "tempDir", .fn_ptr = fs.tempDirImpl, .arg_count = 0, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "readBytes", .fn_ptr = fs.readBytesImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "writeBytes", .fn_ptr = fs.writeBytesImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "appendString", .fn_ptr = fs.appendStringImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "appendBytes", .fn_ptr = fs.appendBytesImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "readLines", .fn_ptr = fs.readLinesImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "walkDir", .fn_ptr = fs.walkDirImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "glob", .fn_ptr = fs.globImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "createTempFile", .fn_ptr = fs.createTempFileImpl, .arg_count = 0, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "createTempDir", .fn_ptr = fs.createTempDirImpl, .arg_count = 0, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "copy", .fn_ptr = fs.copyImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "rename", .fn_ptr = fs.renameImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "removeAll", .fn_ptr = fs.removeAllImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "File", .name = "atomicWriteString", .fn_ptr = fs.atomicWriteImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },

        .{ .module = "Env", .name = "getenv", .fn_ptr = io.getenvImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Env", .name = "contains", .fn_ptr = io.containsEnvImpl, .arg_count = 1, .return_type = bool_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Env", .name = "list", .fn_ptr = io.envListImpl, .arg_count = 0, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },

        .{ .module = "Process", .name = "exit", .fn_ptr = io.exitImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "pid", .fn_ptr = io.pidImpl, .arg_count = 0, .return_type = int_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "uid", .fn_ptr = io.uidImpl, .arg_count = 0, .return_type = int_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "gid", .fn_ptr = io.gidImpl, .arg_count = 0, .return_type = int_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "kill", .fn_ptr = io.killImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "wait", .fn_ptr = io.waitImpl, .arg_count = 0, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Process", .name = "sleep", .fn_ptr = io.sleepImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },

        .{ .module = "Cmd", .name = "which", .fn_ptr = io.whichImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Cmd", .name = "exec", .fn_ptr = stream.cmdExecImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Cmd", .name = "execSafe", .fn_ptr = stream.cmdExecSafeImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Cmd", .name = "pipe?", .fn_ptr = stream.cmdPipeImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },
        .{ .module = "Cmd", .name = "pipe!", .fn_ptr = stream.cmdPipeBangImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = true },

        .{ .module = "Stream", .name = "lines", .fn_ptr = stream.streamLinesImpl, .arg_count = 1, .return_type = stream_string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Stream", .name = "iter", .fn_ptr = stream.streamIterImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = true },
        .{ .module = "Stream", .name = "fold", .fn_ptr = stream.streamFoldImpl, .arg_count = 3, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Stream", .name = "toList", .fn_ptr = stream.streamToListImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Stream", .name = "string", .fn_ptr = stream.streamStringImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Stream", .name = "bytes", .fn_ptr = stream.streamBytesImpl, .arg_count = 1, .return_type = bytes_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Stream", .name = "fromList", .fn_ptr = stream.streamFromListImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Stream", .name = "range", .fn_ptr = stream.streamRangeImpl, .arg_count = 3, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Stream", .name = "iterate", .fn_ptr = stream.streamIterateImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Stream", .name = "linesMax", .fn_ptr = stream.streamLinesMaxImpl, .arg_count = 2, .return_type = stream_string_t, .is_polymorphic = false, .is_effect = false },

        .{ .module = "List", .name = "length", .fn_ptr = data.listLengthImpl, .arg_count = 1, .return_type = int_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "isEmpty", .fn_ptr = data.listIsEmptyImpl, .arg_count = 1, .return_type = bool_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "head", .fn_ptr = data.listHeadImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "last", .fn_ptr = data.listLastImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "get", .fn_ptr = data.listGetImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "append", .fn_ptr = data.listAppendImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "reverse", .fn_ptr = data.listReverseImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "sort", .fn_ptr = data.listSortImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "slice", .fn_ptr = data.listSliceImpl, .arg_count = 3, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "take", .fn_ptr = data.listTakeImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "List", .name = "drop", .fn_ptr = data.listDropImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },

        .{ .module = "Map", .name = "get", .fn_ptr = data.mapGetImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Map", .name = "keys", .fn_ptr = data.mapKeysImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Map", .name = "values", .fn_ptr = data.mapValuesImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Map", .name = "size", .fn_ptr = data.mapSizeImpl, .arg_count = 1, .return_type = int_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Map", .name = "isEmpty", .fn_ptr = data.mapIsEmptyImpl, .arg_count = 1, .return_type = bool_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Map", .name = "insert", .fn_ptr = data.mapInsertImpl, .arg_count = 3, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Map", .name = "remove", .fn_ptr = data.mapRemoveImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },

        .{ .module = "Set", .name = "size", .fn_ptr = data.setSizeImpl, .arg_count = 1, .return_type = int_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Set", .name = "isEmpty", .fn_ptr = data.setIsEmptyImpl, .arg_count = 1, .return_type = bool_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Set", .name = "contains", .fn_ptr = data.setContainsImpl, .arg_count = 2, .return_type = bool_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Set", .name = "insert", .fn_ptr = data.setInsertImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },
        .{ .module = "Set", .name = "remove", .fn_ptr = data.setRemoveImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = P, .is_effect = false },

        .{ .module = "Bytes", .name = "length", .fn_ptr = data.bytesLengthImpl, .arg_count = 1, .return_type = int_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Bytes", .name = "slice", .fn_ptr = data.bytesSliceImpl, .arg_count = 3, .return_type = bytes_t, .is_polymorphic = false, .is_effect = false },

        .{ .module = "String", .name = "length", .fn_ptr = data.stringLengthImpl, .arg_count = 1, .return_type = int_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "String", .name = "slice", .fn_ptr = data.stringSliceImpl, .arg_count = 3, .return_type = string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "String", .name = "toString", .fn_ptr = data.stringToStringImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = false },

        .{ .module = "Hash", .name = "sha256", .fn_ptr = crypto.sha256Impl, .arg_count = 1, .return_type = bytes_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Hash", .name = "sha256Hex", .fn_ptr = crypto.sha256HexImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Hash", .name = "sha256Stream", .fn_ptr = crypto.sha256StreamImpl, .arg_count = 1, .return_type = bytes_t, .is_polymorphic = P, .is_effect = false },

        .{ .module = "Base64", .name = "encode", .fn_ptr = crypto.base64EncodeImpl, .arg_count = 1, .return_type = string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Base64", .name = "decode", .fn_ptr = crypto.base64DecodeImpl, .arg_count = 1, .return_type = bytes_t, .is_polymorphic = false, .is_effect = false },

        .{ .module = "DateTime", .name = "now", .fn_ptr = crypto.dateTimeNowImpl, .arg_count = 0, .return_type = int_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "DateTime", .name = "format", .fn_ptr = crypto.dateTimeFormatImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "DateTime", .name = "parse", .fn_ptr = crypto.dateTimeParseImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },

        .{ .module = "Parser.JSON", .name = "fromString", .fn_ptr = crypto.jsonFromStringImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Parser.JSON", .name = "toString", .fn_ptr = crypto.jsonToStringImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },

        .{ .module = "Regex", .name = "isMatch", .fn_ptr = crypto.regexIsMatchImpl, .arg_count = 2, .return_type = bool_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Regex", .name = "fromString", .fn_ptr = crypto.regexFromStringImpl, .arg_count = 1, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Regex", .name = "firstMatch", .fn_ptr = crypto.regexFirstMatchImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Regex", .name = "allMatches", .fn_ptr = crypto.regexAllMatchesImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Regex", .name = "replace", .fn_ptr = crypto.regexReplaceImpl, .arg_count = 3, .return_type = string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Regex", .name = "replaceAll", .fn_ptr = crypto.regexReplaceAllImpl, .arg_count = 3, .return_type = string_t, .is_polymorphic = false, .is_effect = false },
        .{ .module = "Regex", .name = "split", .fn_ptr = crypto.regexSplitImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },

        .{ .module = "Validator", .name = "regex", .fn_ptr = crypto.validatorRegexImpl, .arg_count = 2, .return_type = unit_t, .is_polymorphic = false, .is_effect = false },
    };
    _ = .{ int_t, string_t, unit_t, stream_string_t, bool_t, bytes_t };
    return .{ .bindings = &bindings };
}

const EffectNamespacePattern = struct {
    module: []const u8,
    is_effect: bool,
};

const effect_namespaces = [_]EffectNamespacePattern{
    .{ .module = "IO", .is_effect = true },
    .{ .module = "File", .is_effect = true },
    .{ .module = "Env", .is_effect = true },
    .{ .module = "Process", .is_effect = true },
    .{ .module = "Task", .is_effect = true },
    .{ .module = "Random", .is_effect = true },
    .{ .module = "Stream.iter", .is_effect = true },
};

pub fn isEffectBinding(name: []const u8) bool {
    if (std.mem.eql(u8, name, "Signal.on")) return true;
    if (std.mem.startsWith(u8, name, "Cmd.")) {
        const rest = name["Cmd.".len..];
        if (std.mem.containsAtLeast(u8, rest, 1, "?")) return true;
        if (std.mem.containsAtLeast(u8, rest, 1, "!")) return true;
        if (std.mem.eql(u8, rest, "exec")) return true;
        if (std.mem.eql(u8, rest, "pipe?")) return true;
        if (std.mem.eql(u8, rest, "pipe!")) return true;
        if (std.mem.eql(u8, rest, "timeout")) return true;
        if (std.mem.eql(u8, rest, "retry")) return true;
        if (std.mem.eql(u8, rest, "execSafe")) return true;
        if (std.mem.eql(u8, rest, "which")) return true;
        return false;
    }
    for (effect_namespaces) |ns| {
        if (std.mem.startsWith(u8, name, ns.module) and ns.is_effect) {
            if (name.len == ns.module.len) return true;
            if (name.len > ns.module.len and name[ns.module.len] == '.') return true;
        }
    }
    return false;
}
