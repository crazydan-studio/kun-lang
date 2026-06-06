# Zig 模式指南

> 本文件记录 Kun 项目实现中 Zig 语言的惯用模式、注意事项和最佳实践，供 LLM 代码生成时参考。

## 版本

- **Zig 版本**：0.13.0
- **构建系统**：`build.zig`

## 内存管理

### Arena 分配器（首选策略）

Kun 项目以 Arena 分配器为主要内存管理策略。Arena 在阶段开始时创建，阶段结束时整体释放。

```zig
const std = @import("std");

fn processPhase(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const arena_allocator = arena.allocator();
    // 所有临时分配使用 arena_allocator
    const result = try arena_allocator.alloc(u8, 1024);
    // arena.deinit() 整体释放
}
```

**规则**：
- 临时分配优先使用 Arena
- 长期存活的对象使用传入的 `allocator` 参数
- 不在 Arena 中分配有独立生命周期的对象

### 分配器传递

所有可能分配内存的函数通过参数接收分配器，而非使用全局或隐式分配器：

```zig
// ✅ 正确：分配器参数
fn parse(allocator: std.mem.Allocator, input: []const u8) !Ast {
    // ...
}

// ❌ 错误：不应使用堆分配或全局分配器
```

### 字符串处理

```zig
// 字符串拼接（需要分配器）
const result = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ name, version });

// 字符串比较
const eq = std.mem.eql(u8, "hello", "world");

// 子串
const sub = slice[start..end];
```

## C ABI 兼容性

### 导出 C 兼容函数

```zig
// 导出给 dlopen 使用的入口函数
export fn command_entry(args: [*c]const CommandArgs, result: [*c]CommandResult) i32 {
    // ...
}
```

### C 兼容结构体

```zig
const CommandArgs = extern struct {
    count: u64,
    fields: [*]CommandArg,
};

const CommandResult = extern struct {
    exit_code: i32,
    stdout_data: Slice,
    stderr_data: Slice,
    error_tag: ErrorTag,
};
```

### dlopen/dlsym 调用

```zig
const handle = try std.DynLib.open("libexample.so");
defer handle.close();

const func = handle.lookup(@TypeOf(entry_point), "entry_point") orelse return error.SymbolNotFound;
const result = func(args);
```

## 系统调用

### 直接系统调用（无 libc）

```zig
// Linux x86_64 系统调用示例
fn getdents(fd: i32, buf: [*]u8, count: u32) !usize {
    const rc = asm volatile (
        \\syscall
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (78),  // SYS_getdents
          [fd] "{rdi}" (@as(u64, @intCast(fd))),
          [buf] "{rsi}" (@as(u64, @intCast(@intFromPtr(buf)))),
          [count] "{rdx}" (@as(u64, count)),
        : "rcx", "r11", "memory"
    );
    // ...
}
```

### libc 调用（当更方便时）

```zig
const c = @cImport({
    @cInclude("unistd.h");
});

const result = c.read(fd, buf, len);
```

## Comptime 编译期代码

### 编译期类型注册

```zig
const BuiltinCommands = struct {
    const commands = comptime blk: {
        // 编译期展开命令表
        break :blk .{ "ls", "stat", "grep" };
    };
};
```

### 编译期函数

```zig
fn FieldType(comptime T: type, comptime name: []const u8) type {
    for (@typeInfo(T).Struct.fields) |field| {
        if (std.mem.eql(u8, field.name, name)) {
            return field.type;
        }
    }
    @compileError("field " ++ name ++ " not found");
}
```

## AST 和类型检查器

### 标记联合体（Tagged Union）

```zig
const AstNode = union(enum) {
    int_literal: i64,
    string_literal: []const u8,
    binary_op: struct { op: Op, left: *AstNode, right: *AstNode },
    lambda: struct { params: []const Param, body: *AstNode },
    // ...
};
```

### 递归类型（通过指针）

```zig
const Type = union(enum) {
    int,
    string,
    list: *Type,
    function: struct { params: []const Type, ret: *Type },
    // ...
};
```

## 错误处理

### Zig 错误联合类型

```zig
fn parse(input: []const u8) !Ast {
    if (input.len == 0) return error.EmptyInput;
    // ...
}

// 调用方
const ast = parse(input) catch |err| {
    std.log.err("parse failed: {}", .{err});
    return err;
};
```

### 错误集合定义

```zig
const ParseError = error{
    UnexpectedToken,
    UnterminatedString,
    InvalidNumber,
};
```

## 常见陷阱

### 切片是 `[]const T` 而非 `[*]T`

```zig
// ✅ 正确
fn process(data: []const u8) void {}

// ❌ 避免：除非确需 C 兼容
fn process(data: [*]const u8, len: usize) void {}
```

### `defer` 执行顺序（后进先出）

```zig
{
    const a = try allocator.alloc(u8, 10);
    defer allocator.free(a); // 第二个执行

    const b = try allocator.alloc(u8, 20);
    defer allocator.free(b); // 第一个执行
}
```

### 联合体的默认内存布局

```zig
// 明确指定 extern 或 packed 以控制布局
const Value = extern union {
    int: i64,
    float: f64,
    ptr: ?*anyopaque,
};
```
