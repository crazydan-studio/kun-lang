# 执行计划：Phase 8 — Nilable ADT + 标准库扩展（v0.2）

## 背景

v0.1（Phase 1-7）完成了解释器核心、运行时、命令系统和标准库 Primitive 表。Phase 7 实现了模块系统和 `--run` 端到端。

Phase 8 是 v0.2 的第一个实施阶段，核心变更来自今日的设计调整：

1. **Nilable 公开 ADT**：`type Nilable a = Some a | Nil`——当前实现中 `nilable` 是一元类型构造器，需要改为公开 ADT，新增 `Some` 变体支持、`Nilable` 模块
2. **Regex 引擎**：改用 `zig-regex` 替代自研 NFA，实现 `Regex` Primitive 绑定
3. **Validator 模块**：依赖 zig-regex，实现常用校验函数
4. **`Duration`/`Int`/`Float`/`Char` 模块**：Primitive 绑定 + PureKun 函数补齐
5. **Nil 模块重命名**：`Nil` → `Nilable`（模块代码文件改名）

## 基线数据

| 维度 | 值 |
|------|-----|
| 当前测试 | 679（全通过） |
| 源码文件 | ~55 个 Zig 文件 |
| 推迟项 v0.2 | Regex 引擎 + Validator、DateTime 格式化、Duration/Int/Float/Char Primitive |

## Step 1：Nilable ADT 公开化（Parser + TypeChecker + Module）

### 1.1 概述

当前实现中 `nilable` 是一个一元类型构造器（`Type.nilable: TypeId`），无用户可见的 `Some` 变体。改为公开 ADT 意味着：

- `Some` 成为 `Nilable` ADT 的已知变体，在 `case` 模式中可用
- `?T` 在类型标注中脱糖为 `Nilable T`（类型环境内部仍可用 `nilable` 快捷表示）
- `Nilable` 模块提供组合子函数

**注意**：不改变运行时 `nilable` 的内部类型表示和存储——`Type.nilable: TypeId` 仍作为编译器内部的快捷表示存在，等价于 `adt{ Some(T), Nil }`。

### 1.2 具体实现

#### 1.2a 类型标注解析：`?T` → `Nilable T`

**修改文件**：`src/parser/parser.zig`

当前 `skipTypeAnn` 是 stub，遇到 `?T` 时直接跳过 token。改为：

```zig
// 在 parseTypeAnn 中处理 '?' token
if (kind == .question) {
    return TypeAnn{ .nilable = .{ .inner = try parseTypeAnn(...) } };
}
```

`TypeAnn.nilable` 在约束生成阶段（`constraint.zig`）脱糖为 `Type.nilable`（内部快捷表示）或构造 ADT 类型。

#### 1.2b 添加 `Some` 变体支持

**修改文件**：

| 文件 | 变更 |
|------|------|
| `src/typecheck/env.zig` | 预注册 `Nilable` ADT 类型（`nilable_adt`）及其 `Some` / `Nil` 变体 |
| `src/typecheck/constraint.zig` | `TypeAnn.nilable` 脱糖为 `Type.nilable`（复用现有逻辑）；`Some` 作为变体构造器解析为 `nilable` 的 `Some` 变体 |
| `src/typecheck/pattern.zig` | 添加 `Some v` 模式处理——`Some` 模式匹配时提取内层值 |
| `src/lexer/lexer.zig` | `Some` **不**作为关键字。`Some` 作为 ADT 变体名已经可通过标识符机制处理（大写开头 → 类型/变体） |
| `src/typecheck/error.zig` | 新增 `Some` 相关错误的消息（可选——若 `Some` 在作用域外使用，现有"未定义变体"错误已覆盖） |

**预注册 ADT**：

```zig
// env.zig init
const nilable_adt_variants = [_]AdtVariant{
    .{ .name = "Some", .fields = &.{some_inner_id} },  // Some : T -> Nilable T
    .{ .name = "Nil", .fields = &.{} },                  // Nil : Nilable T
};
const nilable_adt_id = registerType(.{ .adt = .{
    .name = "Nilable",
    .variants = &nilable_adt_variants,
}});
```

对 `Type.nilable` 的引用映射到该 ADT 的 `Some` 变体包含内层类型——类型检查器在合一 Nilable ADT 时与 `Type.nilable` 快捷表示双向兼容。

#### 1.2c `Nilable` 模块

**新建文件**：`code/kun-lang/src/runtime/nilable_module.zig`

```zig
// PureKun 风格的组合子函数，注册为 Primitive（因 ?a 类型签名需要编译器支持）

pub const withDefault : fn (env, args) Value {
    // args[0] = default value, args[1] = ?value
    // if args[1] is nil, return args[0]; else return args[1] unwrapped
}

pub const map : fn (env, args) Value { ... }
pub const orElse : fn (env, args) Value { ... }
pub const toResult : fn (env, args) Value { ... }
pub const andThen : fn (env, args) Value { ... }
pub const isNil : fn (env, args) Value { ... }
pub const isSome : fn (env, args) Value { ... }
pub const filter : fn (env, args) Value { ... }
```

**stdlib/kun/Nilable.kun**（推迟到有 .kun 标准库支持时）：暂不创建 .kun 文件。函数通过 Primitive 表注册。

**注册到 Primitive 表**：`src/runtime/primitive.zig` 添加 `Nilable` 模块条目，`is_effect = false`（纯函数）。

#### 1.2d 模式匹配更新

**修改文件**：`src/typecheck/pattern.zig`

`Some v` 模式匹配的 `narrowType` 行为：
- 匹配 `Nil` 模式 → scrutinee 类型保持 `?T`（不变）
- 匹配 `Some v` 模式 → `v` 收窄为内层 `T`
- `checkExhaustive`：Nilable 的穷举需要覆盖 `Some` 和 `Nil` 两个变体

当前 `narrowType` 已有对 `Nil` 和裸变量（`name[0] >= 'a'`）的特殊处理。新增 `Some` 变体模式的处理：

```zig
// pattern.zig — narrowType
if (resolved == .nilable) {
    if (std.mem.eql(u8, name, "Nil")) return scrutinee_ty;  // Nil 分支
    if (std.mem.eql(u8, name, "Some")) {
        // Some v 模式 → v 收窄为内层 T
        return inner_type;
    }
    if (name[0] >= 'a' && name[0] <= 'z') {
        return inner_type;  // 兼容：裸变量 v → Some v（旧代码过渡）
    }
}
```

**向后兼容**：保留裸变量 `v ->` 模式到 `Some v ->` 的自动映射（当前 `pattern.zig` 已有此逻辑）。设计文档说"不做糖化"，但现有测试依赖此行为。采用**温和过渡**：裸变量模式产生告警，建议改为显式 `Some v`。

#### 1.2e `Nilable` 模块名替换 `Nil` 引用

当前源码中的内置类型列表、模块引用使用 `Nil` 作为内置类型名。`Nilable` 模块独立注册。

### 1.3 测试

| 范围 | 测试内容 |
|------|---------|
| 类型标注 | `?T` 解析、`Nilable T` 等价 |
| `Some` 模式 | `case x of Some v -> v; Nil -> 0` 穷举检查 |
| `Nilable` 模块函数 | `withDefault`/`map`/`orElse`/`toResult`/`andThen`/`isNil`/`isSome`/`filter` |
| 向后兼容 | 裸变量模式 → 告警 |
| Nilable 合一 | `nilable` 内部表示 ↔ ADT 表示的双向兼容 |

## Step 2：Regex 引擎（zig-regex）

### 2.1 添加 zig-regex 依赖

**修改文件**：`build.zig.zon`、`build.zig`

```zig
// build.zig.zon
.dependencies = .{
    .regex = .{
        .url = "https://github.com/zig-utils/zig-regex/archive/main.tar.gz",
        .hash = "...",
    },
},

// build.zig
const regex = b.dependency("regex", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("regex", regex.module("regex"));
```

### 2.2 实现 RegexHandle / Regex 运行时

**新建文件**：`src/runtime/regex_engine.zig`

```zig
const std = @import("std");
const regex = @import("regex");

pub const RegexHandle = regex.Regex;

pub fn compile(allocator: std.mem.Allocator, pattern: []const u8) !RegexHandle {
    return try RegexHandle.compile(allocator, pattern);
}

pub fn isMatch(re: *const RegexHandle, input: []const u8) !bool {
    return (try re.find(input)) != null;
}

pub fn firstMatch(re: *const RegexHandle, allocator: std.mem.Allocator, input: []const u8) !?struct { matched: []const u8, groups: []const []const u8 } {
    // 使用 zig-regex API 查找第一个匹配
}

pub fn replace(re: *const RegexHandle, allocator: std.mem.Allocator, input: []const u8, replacement: []const u8) ![]const u8 {
    return try re.replace(allocator, input, replacement);
}

pub fn replaceAll(re: *const RegexHandle, allocator: std.mem.Allocator, input: []const u8, replacement: []const u8) ![]const u8 {
    return try re.replaceAll(allocator, input, replacement);
}

pub fn split(re: *const RegexHandle, allocator: std.mem.Allocator, input: []const u8) ![][]const u8 {
    // 使用 zig-regex split 功能
}
```

### 2.3 替换 eval.zig 中的 regex stub

**修改文件**：`src/runtime/eval.zig`

当前 `regex_literal` 处的 `@panic("regex engine not yet implemented")` 改为真实调用：

```zig
.regex_literal => |v| {
    // v.value 是模式字符串，编译期为 regex handle
    // 编译时由 zig-regex 编译
},
```

### 2.4 注册 Regex Primitive 函数

**修改文件**：`src/runtime/primitive.zig`

| 函数 | 签名 | is_effect |
|------|------|-----------|
| `isMatch` | `Regex -> String -> Bool` | false |
| `firstMatch` | `Regex -> String -> ?{ matched: String, groups: List String }` | false |
| `allMatches` | `Regex -> String -> List { matched: String, groups: List String }` | false |
| `replace` | `Regex -> String -> String -> String` | false |
| `replaceAll` | `Regex -> String -> String -> String` | false |
| `split` | `Regex -> String -> List String` | false |
| `fromString` | `String -> Result Regex String` | false |

### 2.5 验证

```bash
cd code/kun-lang && zig build test
# 新增 runtime/test_regex.zig（~15 测试）
```

## Step 3：Validator 模块

### 3.1 实现 Validator 函数

**新建文件**：`src/stdlib/validator.zig`

`Validator.regex` 委托 `Regex.fromString`，其余为 PureKun 纯函数：

| 函数 | 签名 | 实现方式 |
|------|------|---------|
| `oneOf` | `List String -> String -> Result String String` | PureKun |
| `range` | `Int -> Int -> Int -> Result Int String` | PureKun |
| `nonEmpty` | `String -> Result String String` | PureKun |
| `regex` | `String -> String -> Result String String` | Primitive（委托 Regex.fromString） |

注册到 `primitive.zig`，`Validator` 模块标记为 `is_effect = false`。

### 3.2 验证

```bash
cd code/kun-lang && zig build test
# 新增 stdlib/test_validator.zig（~8 测试）
```

## Step 4：DateTime 格式化引擎

### 4.1 实现

**新建文件**：`src/runtime/datetime_fmt.zig`

`DateTime.format` 和 `DateTime.parse` 的 Primitive 实现：

```zig
pub fn format(template: []const u8, dt: i64, allocator: std.mem.Allocator) ![]const u8 {
    // 支持格式字段：yyyy/yy/MM/dd/HH/mm/ss/SSS/Z
    // 按 template 展开为字符串
}

pub fn parse(template: []const u8, input: []const u8, allocator: std.mem.Allocator) !i64 {
    // 解析按 template 格式的字符串为 Unix 纳秒
}
```

### 4.2 注册 Primitive

| 函数 | 签名 | is_effect |
|------|------|-----------|
| `format` | `String -> DateTime -> Result String String` | false |
| `parse` | `String -> String -> Result DateTime String` | false |
| `now` | `-> DateTime` | true |

**修改文件**：`src/runtime/primitive.zig`、`src/runtime/eval.zig`

### 4.3 验证

```bash
cd code/kun-lang && zig build test
# 新增 runtime/test_datetime.zig（~10 测试）
```

## Step 5：Duration/Int/Float/Char 模块 Primitive 绑定 + PureKun 函数

### 5.1 Duration 模块

当前 `Duration` 已有编译器内置类型和字面量支持，缺少模块函数。

**新建文件**：`src/stdlib/duration.zig`

| 函数 | 签名 | 实现方式 |
|------|------|---------|
| `toNanos` | `Duration -> Int` | Primitive |
| `toMicros` | `Duration -> Int` | Primitive |
| `toMillis` | `Duration -> Int` | Primitive |
| `toSeconds` | `Duration -> Int` | Primitive |
| `toMinutes` | `Duration -> Int` | Primitive |
| `toHours` | `Duration -> Int` | Primitive |
| `toDays` | `Duration -> Int` | Primitive |
| `fromString` | `String -> Result Duration String` | Primitive |
| `fromMillis` | `Int -> Duration` | PureKun |
| `toString` | `Duration -> String` | Primitive |
| `format` | `String -> Duration -> Result String String` | Primitive |
| `negate` | `Duration -> Duration` | PureKun |
| `isNegative` | `Duration -> Bool` | PureKun |
| `abs` | `Duration -> Duration` | PureKun |

### 5.2 Int 模块

当前 `Int` 的 `fromString`/`toFloat`/`toString` 已作为 Primitive 存在，补齐剩余函数。

| 函数 | 签名 | 实现方式 |
|------|------|---------|
| `abs` | `Int -> Int` | PureKun |
| `min` | `Int -> Int -> Int` | PureKun |
| `max` | `Int -> Int -> Int` | PureKun |
| `pow` | `Int -> Int -> Int` | PureKun |
| `clamp` | `Int -> Int -> Int -> Int` | PureKun |

**修改文件**：注册到 `src/runtime/primitive.zig`

### 5.3 Float 模块

当前 `Float` `fromString`/`toInt`/`toString` 已作为 Primitive 存在。

| 函数 | 签名 | 实现方式 |
|------|------|---------|
| `pi` / `e` | `Float` | PureKun（常量） |
| `abs` / `floor` / `ceil` / `round` | `Float -> Float` | PureKun |
| `sin` / `cos` / `tan` | `Float -> Float` | PureKun |
| `exp` / `log` / `log2` / `log10` | `Float -> Float` | PureKun |
| `pow` / `sqrt` | `Float -> Float -> Float` / `Float -> Float` | PureKun |
| `approxEqual` | `Float -> Float -> Float -> Bool` | PureKun |
| `min` / `max` | `Float -> Float -> Float` | PureKun |
| `clamp` | `Float -> Float -> Float -> Float` | PureKun |

**修改文件**：注册到 `src/runtime/primitive.zig`

### 5.4 Char 模块

| 函数 | 签名 | 实现方式 |
|------|------|---------|
| `of` | `Int -> Char` | Primitive（of 约定：调用者自保证，非法 panic） |
| `fromInt` | `Int -> Result Char String` | Primitive |
| `isDigit` / `isAlpha` / `isUpper` / `isLower` / `isWhitespace` / `isControl` | `Char -> Bool` | PureKun |
| `toUpper` / `toLower` | `Char -> Char` | PureKun |
| `toInt` | `Char -> Int` | PureKun |

**新建文件**：`src/stdlib/char.zig`

### 5.5 验证

```bash
cd code/kun-lang && zig build test
# 新增 stdlib/test_duration.zig、stdlib/test_float.zig、stdlib/test_char.zig（各 ~8 测试）
```

## 变更范围总表

| Step | 新建文件 | 修改文件 | 新增代码行 | 新增测试 |
|------|---------|---------|-----------|---------|
| 1 — Nilable ADT | `src/runtime/nilable_module.zig` | `src/parser/parser.zig`, `src/typecheck/env.zig`, `src/typecheck/constraint.zig`, `src/typecheck/pattern.zig`, `src/runtime/primitive.zig` | ~300 | ~25 |
| 2 — Regex | `src/runtime/regex_engine.zig` | `build.zig.zon`, `build.zig`, `src/runtime/eval.zig`, `src/runtime/primitive.zig` | ~200 | ~15 |
| 3 — Validator | `src/stdlib/validator.zig` | `src/runtime/primitive.zig` | ~80 | ~8 |
| 4 — DateTime | `src/runtime/datetime_fmt.zig` | `src/runtime/eval.zig`, `src/runtime/primitive.zig` | ~250 | ~10 |
| 5 — Duration/Int/Float/Char | `src/stdlib/duration.zig`, `src/stdlib/char.zig` | `src/runtime/primitive.zig` | ~350 | ~30 |
| **合计** | **6 个新文件** | **9 个修改文件** | **~1180** | **~88** |

目标：**679 → ~767 测试**。

## 依赖关系

```
Step 3 (Validator) ──依赖── Step 2 (Regex)
                                      ├── 无其他依赖
Step 4 (DateTime) ── 独立
Step 5 (Duration/Int/Float/Char) ── 独立，可并行
```

Step 1 影响类型检查器和模式匹配，与 Step 2-5 无代码冲突（修改不同模块），可并行实施。

## 推迟项（不在本计划范围）

| 项 | 原因 | 目标版本 |
|----|------|---------|
| 沙箱（Landlock/seccomp/rlimit） | 安全子系统 | v0.5 |
| Kun Shell | 交互环境 | v2.0 |
| Cli 模块 + Parser.Record | 编译期代码展开 | v0.3 |
| 等递归类型 | TypeEnv 别名集合 | v0.3 |
| String/List/Map/Set PureKun 函数（.kun 文件） | 标准库文件体系 | v0.2（后续 phase） |
| 预索引优化 | 模块系统性能优化 | v0.2（后续 phase） |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.26 | 初始版本 |

