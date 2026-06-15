# Zig 模式指南

> 本文件记录 Kun 项目实现中 Zig 语言的惯用模式、注意事项和最佳实践，供 LLM 代码生成时参考。
>
> **最后更新**：2026.06.15，基于 Zig 0.17.0-dev。

## 版本

- **Zig 版本**：0.17.0-dev（版本包位于 `/opt/ai-agent/tools/zig-x86_64-linux-0.17.0-dev.387+31f157d80.tar.xz`）
- **构建系统**：`build.zig`

### 0.13 → 0.17 关键变更摘要

| 类别 | 变更 |
|------|------|
| 类型反射 | `std.builtin.Type` 字段全小写（`.int`、`.@"struct"`）；`@Type` 移除，改用独立内置函数（`@Int`、`@Struct`、`@Union`、`@Fn`、`@Pointer`、`@Tuple`、`@EnumLiteral`） |
| C 互通 | `@cImport` 废弃，迁移到构建系统 `b.addTranslateC(.{...})` |
| 分配器 | `GeneralPurposeAllocator` 初始化用 `.init` decl literal；`ArrayListUnmanaged` 用 `.empty`；`ArenaAllocator` 线程安全且无锁 |
| 控制流 | 标记 switch 支持 `continue :label`（适合解释器分发循环）；`@branchHint(.cold/.likely/.unlikely)` 替代 `@setCold` |
| I/O | 0.16 引入 I/O as an Interface：`std.Io` 替代旧 `std.io`，`std.Io.File`/`stream`/`Event` 等新 API |
| 入口点 | "Juicy Main"：`pub fn main(init: std.process.Init) !void`；环境变量非全局，通过 `init` 参数传入 |
| 文件系统 | `std.fs.path` API 重命名（如 `cwd` → `process.Cwd`）；`Dir.readFileAlloc` / `File.readToEndAlloc` 新增便利方法 |
| 数组初始化 | `@splat` 支持数组（0.14）；注意：后续版本中 `@splat` 正被数组乘法语法 `[_]T{x} ** n` 替代 |
| 类型系统 | `@FieldType` 新增；匿名结构体类型移除，元组统一为结构等价；packed struct/union 支持等值比较和原子操作 |
| 构建系统 | 包哈希格式变更；新增 `WriteFile`/`RemoveDir` 步骤；`addLibrary` 函数用于创建共享库 |

## 内存管理

### Arena 分配器（首选策略）

Kun 项目以 Arena 分配器为主要内存管理策略。Arena 在阶段开始时创建，阶段结束时整体释放。Zig 0.17 中 `ArenaAllocator` 为线程安全且无锁（lock-free）。

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

### 通用分配器初始化

```zig
// 0.17 使用 decl literal 初始化
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();
```

### Unmanaged 容器初始化

```zig
// ❌ 旧方式
var list: std.ArrayListUnmanaged(u32) = .{};

// ✅ 0.17 使用 .empty decl literal
var list: std.ArrayListUnmanaged(u32) = .empty;
defer list.deinit(allocator);
```

### 分配器传递

所有可能分配内存的函数通过参数接收分配器，而非使用全局或隐式分配器：

```zig
// ✅ 正确：分配器参数
fn parse(allocator: std.mem.Allocator, input: []const u8) !Ast {
    // ...
}

// ❌ 错误：不应使用堆分配或全局分配器
```

### 分配器接口（remap）

Zig 0.14+ 的分配器接口包含 `remap` 方法，用于原地扩缩容（类似 C 的 `realloc`）。部分场景下 `remap` 可替代 `free` + `alloc` 组合以提升性能：

```zig
// 使用 remap 扩展现有分配
const new_mem = try allocator.remap(old_mem, new_len);
```

### 字符串处理

```zig
// 字符串拼接（需要分配器）
const result = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ name, version });

// 字符串比较
const eq = std.mem.eql(u8, "hello", "world");

// 子串
const sub = slice[start..end];

// 子串查找（0.16 重命名：indexOf → find）
const pos = std.mem.find(u8, haystack, needle);
```

## 子进程管理

### fork-exec + pipe 捕获（0.16+ I/O 接口）

Kun 通过 fork-exec 执行外部命令，stdout/stderr 通过 pipe 捕获：

```zig
const std = @import("std");

fn execCommand(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    return child;
}
```

### pipe 读取与 Stream 消费

```zig
fn readStdout(allocator: std.mem.Allocator, child: *std.process.Child) ![]u8 {
    const stdout = child.stdout.?;
    const result = try stdout.reader().readAllAlloc(allocator, 1024 * 1024); // 1 MiB max
    _ = try child.wait();
    return result;
}
```

### 入口点（Juicy Main）

Zig 0.16+ 推荐的 main 签名：

```zig
pub fn main(init: std.process.Init) !void {
    // 环境变量通过 init.env 访问，非全局
    const home = init.env.get("HOME") orelse "/";

    // 标准输出使用 std.Io
    const stdout = init.io.stdout_writer();
    try stdout.writeAll("Hello, World!\n");
}
```

## Landlock / seccomp 安装

在 fork 后、exec 前安装安全策略：

```zig
fn installSeccomp() !void {
    const linux = std.os.linux;

    // seccomp-BPF 过滤规则
    const filter = try buildSeccompFilter(allocator, allows);
    const rc = linux.seccomp(
        linux.SECCOMP.SET_MODE_FILTER,
        linux.SECCOMP.FILTER.FLAG.TSYNC,
        @intFromPtr(&filter),
    );
    if (rc != 0) return error.SeccompInstallFailed;
}

fn installLandlock(rules: []const LandlockRule) !void {
    // Landlock LSM 规则安装
    // 使用 std.os.linux.landlock_create_ruleset / landlock_add_rule / landlock_restrict_self
}
```

## 系统调用

### 直接系统调用（无 libc）

Zig 0.17 继续支持通过 `syscall` 函数直接调用 Linux 系统调用，无需内联汇编：

```zig
const linux = std.os.linux;

// 使用 std.os.linux.syscall 系列函数
const rc = linux.syscall3(
    linux.SYS.read,
    @as(usize, @bitCast(@as(isize, fd))),
    @intFromPtr(buf),
    count,
);
```

### C 头文件翻译（0.16+ 构建系统方式）

`@cImport` 已废弃，C 翻译通过构建系统执行：

```zig
// build.zig
const translate_c = b.addTranslateC(.{
    .root_source_file = b.path("src/c_headers.h"),
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("c", translate_c.createModule());
```

## Comptime 编译期代码

### 类型反射（0.17 字段名）

`std.builtin.Type` 字段在 0.14 起全部为小写：

```zig
fn FieldType(comptime T: type, comptime name: []const u8) type {
    for (@typeInfo(T).@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, name)) {
            return field.type;
        }
    }
    @compileError("field " ++ name ++ " not found");
}
```

### 类型构造（0.16 独立内置函数替代 @Type）

```zig
// ❌ 0.13 方式
const U8 = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = 8 } });

// ✅ 0.17 方式
const U8 = @Int(.unsigned, 8);

// 结构体类型构造
const MyStruct = @Struct(.{
    .layout = .auto,
    .backing_integer = null,
    .fields = &.{
        .{ .name = "x", .type = i32, .default_value_ptr = null, .is_comptime = false, .alignment = 0 },
        .{ .name = "y", .type = f64, .default_value_ptr = null, .is_comptime = false, .alignment = 0 },
    },
    .decls = &.{},
    .is_tuple = false,
});

// 函数类型构造
const MyFn = @Fn(.{
    .params = &.{ i32, bool },
    .return_type = void,
    .cc = .C,
});
```

### @FieldType 内置函数

```zig
const S = struct { x: i32, y: []const u8 };
comptime {
    const field_ty = @FieldType(S, "x"); // i32
}
```

### 标记 switch（0.14+ 适合解释器分发）

```zig
fn evalExpr(expr: *Expr) Value {
    // 标记 switch 配合 continue 实现高效分发
    return switch (expr) {
        .int_literal => |e| Value{ .int = e.val },
        .add => |e| {
            const lhs = evalExpr(e.lhs);
            const rhs = evalExpr(e.rhs);
            return Value{ .int = lhs.int + rhs.int };
        },
        .call => |e| {
            // ... 函数调用
        },
        else => unreachable,
    };
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

### 分支预测提示（0.14+ @branchHint）

```zig
fn coldPath() void {
    @branchHint(.cold); // 告知优化器此路径不太可能到达
    // 处理罕见的错误恢复逻辑
}

fn hotLoop() void {
    if (condition) {
        @branchHint(.likely); // 常见路径
        // ...
    }
}
```

### 测试检测

```zig
const builtin = @import("builtin");

fn isTestBuild() bool {
    return builtin.is_test;
}
```

### 入口点注意事项

```zig
// kun 脚本执行器
pub fn main(init: std.process.Init) !void {
    // init.io: I/O 接口
    // init.env: 环境变量（非全局）
    // init.args: 命令行参数
    _ = init;
}
```

### @src 包含模块字段

```zig
// @src() 现在包含 .module 字段，可用于诊断
const src = @src();
std.log.debug("in {s}:{d}", .{ src.file, src.line });
```

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.15 | 全面更新至 Zig 0.17.0-dev：类型反射字段小写、@Type 移除使用独立内置函数、@cImport 废弃、I/O as Interface、标记 switch/@branchHint、构建系统变更、Unmanaged 容器 .empty 初始化、文件系统 API 更新 |
| 2026.06.10 | 初始版本，基于 Zig 0.13.0 |
