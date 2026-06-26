# 执行计划：Phase 8 — Nilable ADT + 标准库扩展（v0.2）

## 背景

v0.1（Phase 1-7）完成了解释器核心、运行时、命令系统和标准库 Primitive 表。Phase 7 实现了模块系统和 `--run` 端到端。

Phase 8 是 v0.2 的第一个实施阶段，核心变更来自今日的设计调整：

1. **Nilable 公开 ADT**：`type Nilable a = Some a | Nil`——当前实现中 `nilable` 是一元类型构造器，需要改为公开 ADT，新增 `Some` 变体支持、`Nilable` 模块
2. **Regex 引擎**：改用 `zig-regex` 替代自研 NFA，实现 `Regex` Primitive 绑定
3. **Validator 模块**：依赖 zig-regex，实现常用校验函数
4. **`Duration`/`Int`/`Float`/`Char` 模块**：Primitive 绑定 + PureKun 函数补齐
5. **Nil 内置模块重命名**：`Nil` → `Nilable`（模块名与类型名 `Nilable a` 统一，`isNil`/`isSome` 等函数移至 `Nilable` 模块）

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
- 源码中引用 `Nil` 内置类型名的位置更新为 `Nilable`（模块名与类型名统一）

**注意**：不改变运行时 `nilable` 的内部类型表示和存储——`Type.nilable: TypeId` 仍作为编译器内部的快捷表示存在，等价于 `adt{ Some(T), Nil }`。

### 1.2 具体实现

#### 1.2a 类型标注解析：`?T` → `Nilable T`

**修改文件**：`src/parser/parser.zig`

当前 `skipTypeAnn` 是 stub，遇到 `?T` 时直接跳过 token。改为：

```zig
// 在 parseTypeAnn 中处理 '?' token
if (kind == .question) {
    const inner = try state.heap.alloc(TypeAnn, 1);
    inner.* = try parseTypeAnn(state);
    return TypeAnn{ .nilable = inner };
}
```

`TypeAnn.nilable` 在约束生成阶段（`constraint.zig`）脱糖为 `Type.nilable`（内部快捷表示）或构造 ADT 类型。

#### 1.2b 去除 `Nil` 字面量关键字，改为缺省导入的 ADT 变体

当前 `Nil` 是特殊字面量关键字（`kw_nil` token、`Expr.nil_literal`、`Pattern.literal(.nil_literal)`、`Value.nil` 多条特殊路径）。改为将 `Nil` 和 `Some` 均作为 `Nilable` ADT 的变体缺省导入，去除 `Nil` 的特判路径——编译器内部复用已有的 ADT 变体机制。

| 组件 | 当前 | 改为 |
|------|------|------|
| 词法分析 | `kw_nil` 关键字 token | 普通大写标识符（`Nil` 和 `Some` 因编译器内置 ADT 自动缺省可用，无需 `import`；区别于 `Ok`/`Err` 需要 `import Result`） |
| 语法分析 | `nil_literal` 特殊 Expr + 特殊 Pattern | 按 ADT 变体构造器处理（大写标识符 → 尝试匹配已知 ADT 变体） |
| 类型检查 | `nil_literal` → `Type.nilable(a)` 特判分支 | 走 ADT 变体合一——`Nil` 是 `Nilable` ADT 的无 payload 变体 |
| 求值 | `nil_literal` → `Value.nil` 特判分支 | 走 ADT 变体构造路径 |

**修改文件**：

| 文件 | 变更 |
|------|------|
| `src/lexer/lexer.zig` | **删除** `kw_nil` token kind；从关键字映射表中移除 `"Nil"` |
| `src/ast/ast.zig` | **删除** `Expr` 和 `Pattern` 中的 `nil_literal` 变体（如适用） |
| `src/ast/typed.zig` | **删除** `TypedExpr` 中的 `nil_literal` 变体；`Value.nil` 可保留为 ADT Nil 变体的运行时快捷表示 |
| `src/parser/parser.zig` | **删除** `nil_literal` 表达式解析分支；`kw_nil` 在模式分支和类型检查分支中移除；`Nil` 作为大写标识符走 ADT 变体解析路径 |
| `src/typecheck/constraint.zig` | **删除** `nil_literal` 约束生成特判；删除 9 处 `error.NilToNonNilable` 捕获（该错误已被移除）；`Nil` 作为 ADT 变体由已有 ADT 模式处理 |
| `src/typecheck/effect.zig` | **删除** `nil_literal` 分支（已由 ADT 路径覆盖） |
| `src/typecheck/pattern.zig` | **删除** `nil_literal` 模式特判；`Nil` 模式走 ADT 变体匹配 |
| `src/typecheck/error.zig` | 删除 `nil_to_non_nilable` 错误变体（由 ADT 统一错误代替） |
| `src/runtime/eval.zig` | **删除** `nil_literal` 求值特判；ADT `Nil` 变体求值走已有 ADT 路径 |
| `src/runtime/value.zig` | `Value.nil` 保留为运行时快捷表示（与 `Type.nilable` 同理，是内部优化） |
| `src/module/module_resolver.zig` | `isBuiltinType` 移除 `"Nil"`（已在 1.2f 中处理） |
| `src/typecheck/unify.zig` | 删除 `nil_to_non_nilable` 合一错误；`Nil` 作为 `Nilable` ADT 变体与预期类型合一 |
| `src/i18n/i18n.zig` | 删除 `nil_to_non_nilable` 格式化分支（已由 ADT 统一错误消息代替） |
| `src/i18n/test_i18n.zig` | 删除 `nil_to_non_nilable` 测试用例 |
| `src/lexer/test_lexer.zig` | 删除 `kw_nil` 相关测试用例 |
| `src/typecheck/test_constraint.zig` | `nil_literal` 测试用例迁移为 ADT 变体测试 |
| `src/typecheck/test_unify.zig` | `NilToNonNilable` 测试用例迁移（该错误已由 ADT 统一错误代替） |
| `src/typecheck/test_pattern.zig` | `nil_literal` 测试用例迁移 |
| `src/typecheck/test_effect.zig` | `nil_literal` 测试用例迁移 |
| `src/runtime/test_eval.zig` | 6 处 `nil_literal` 测试用例迁移为 ADT `Nil` 变体构造 |

`kw_nil` 删除后，`Nil` 在表达式和模式中统一通过"大写标识符 → ADT 变体查找"路径处理。`Nil` 作为 `Nilable` ADT 的 `Nil` 变体被识别。`Some` 同理。两者均通过编译器内置 ADT 的变体作用域自动缺省可用——与 `Result` 的 `Ok`/`Err`（需 `import Result`）不同，`Nilable` 是编译器内置类型。

#### 1.2c 添加 `Some` 变体支持

`Some` 和 `Nil` 都是 `Nilable` ADT 的变体，通过缺省导入自动可用。`Some` 不是关键字——作为 ADT 变体名通过标识符机制处理（大写开头 → 类型/变体）。

**修改文件**：

| 文件 | 变更 |
|------|------|
| `src/typecheck/env.zig` | 预注册 `Nilable` ADT 类型（`nilable_adt`）及其 `Some` / `Nil` 变体；将两个变体注入缺省环境 |
| `src/typecheck/constraint.zig` | `TypeAnn.nilable` 脱糖为 `Type.nilable`（复用现有逻辑）；`Some` / `Nil` 作为变体构造器由已有 ADT 路径处理 |
| `src/typecheck/pattern.zig` | 添加 `Some v` 模式处理——`Some` 模式匹配时提取内层值；`Nil` 模式匹配时保持类型 |

**预注册 ADT**：

```zig
// env.zig init
const nilable_adt_variants = [_]AdtVariant{
    .{ .name = "Some", .payload = &.{some_inner_id} },  // Some : T -> Nilable T
    .{ .name = "Nil", .payload = &.{} },                  // Nil : Nilable T
};
const nilable_adt_id = registerType(.{ .adt = .{
    .name = "Nilable",
    .variants = &nilable_adt_variants,
}});
```

对 `Type.nilable` 的引用映射到该 ADT 的 `Some` 变体包含内层类型——类型检查器在合一 Nilable ADT 时与 `Type.nilable` 快捷表示双向兼容。

> **实现复杂度**：`Type.nilable` ↔ ADT 双向兼容需要在 `unify.zig`、`generalize`、`freshInstance`、`typeName`、`occursCheck` 等所有操作处增加分支判断——当前遇到 `adt` 时需检查其是否为预注册的 `Nilable` ADT，若是则等价于 `nilable`。`generalize` 和 `freshInstance` 的递归逻辑需要同时处理两种表示。此兼容层的代码量约 60-80 行，分散在 5-6 个函数中。

#### 1.2d `Nilable` 模块

`Nilable` 模块函数均为 PureKun（纯组合子），按标准库分类规则应使用 Kun 语言实现。但在实现 .kun 标准库文件之前，采用**过渡方案**：将 `Nilable` 模块函数以 Primitive 形式注册（Zig 实现），待后续 phase 支持 .kun 标准库文件后降级为 PureKun。此过渡在 `standard-library.md` 中标注 `[Primitive]`，并记录 PureKun 回退计划。

**新建文件**：`src/stdlib/nilable.zig`

```zig
// 过渡实现：暂以 Primitive 注册，后续降级为 PureKun

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

**注册到 Primitive 表**：`src/runtime/primitive.zig` 添加 `Nilable` 模块条目，`is_effect = false`（纯函数）。

**后续降级计划**（v0.2 后续 phase）：当 Kun 的 .kun 标准库文件系统就绪后，创建 `lib/kun/Nilable.kun`，将函数体从 Zig 迁移到 Kun，并移除 Primitive 表中的 `Nilable` 条目。

#### 1.2e 模式匹配更新

**修改文件**：`src/typecheck/pattern.zig`

`Some v` 模式匹配的 `narrowType` 行为：
- 匹配 `Nil` 模式 → scrutinee 类型保持 `Nilable T`（scrutinee 整体类型不变）
- 匹配 `Some v` 模式 → `v` 收窄为内层 `T`
- `checkExhaustive`：Nilable 的穷举需要覆盖 `Some` 和 `Nil` 两个变体

`Nil` 和 `Some` 都通过 ADT 变体模式路径处理（去除 `nil_literal` 特判）：

```zig
// pattern.zig — narrowType
if (resolved == .nilable) {
    if (std.mem.eql(u8, name, "Nil")) return scrutinee_ty;  // Nil 分支
    if (std.mem.eql(u8, name, "Some")) {
        // Some v 模式 → v 收窄为内层 T
        return inner_type;
    }
}
```

**不保留**裸变量 `v ->` 的向后兼容——设计文档明确要求"case 分支需显式 Some，不做糖化"。用户在 `case` 中必须写 `Some v ->`，编译期遇到裸变量模式在 Nilable scrutinee 上时直接报错，提示使用显式 `Some` 变体。所有现有示例已在 `docs/ai-agent/examples/` 和 `code/examples/` 中更新为显式 `Some`。

#### 1.2f `Nilable` 模块名迁移

当前源码中的内置类型列表和模块引用使用 `Nil` 作为内置类型名。`Nilable` 作为新模块名独立注册，涉及以下文件：

| 文件 | 变更 |
|------|------|
| `src/module/module_resolver.zig` | `isBuiltinType` 列表中移除 `"Nil"`（`Nil` 现在是 `Nilable` ADT 的变体，非独立类型）；`hasPrimitiveBinding` 列表新增 `"Nilable"`、`"Duration"`、`"Int"`、`"Float"`、`"Char"` |
| `src/runtime/primitive.zig` | 注册 `Nilable` 模块（而非 `Nil`），绑定 `nilable.zig` 中的函数 |

`Nil` 作为 `Nilable` ADT 的变体名始终缺省可用，无需 `import`。

### 1.3 测试

**修改文件**：`src/test_main.zig`（添加 `nilable` 测试引用）

| 范围 | 测试内容 |
|------|---------|
| 类型标注 | `?T` 解析、`Nilable T` 等价 |
| `Nil`/`Some` 变体 | `case x of Some v -> v; Nil -> 0` 穷举检查——`Nil` 和 `Some` 均通过 ADT 变体路径处理 |
| `Nilable` 模块函数 | `withDefault`/`map`/`orElse`/`toResult`/`andThen`/`isNil`/`isSome`/`filter` |
| `Nil` 非关键字 | `Nil` 不再作为字面量关键字——可用作变量名（遮蔽时警告） |
| Nilable 合一 | `nilable` 内部表示 ↔ ADT 表示的双向兼容 |

## Step 2：Regex 引擎（zig-regex）

### 2.1 添加 zig-regex 依赖并更新类型定义

**修改文件**：`build.zig`（添加 zig-regex 依赖导入）、`src/runtime/value.zig`（将 `RegexHandle` 从 `opaque {}` 改为 `regex.Regex` 的类型别名）
**新建文件**：`build.zig.zon`（声明 zig-regex 外部依赖）

**新建文件**：`build.zig.zon`

```zig
.{
    .name = "kun-lang",
    .version = "0.1.0",
    .dependencies = .{
        .regex = .{
            .url = "https://github.com/zig-utils/zig-regex/archive/main.tar.gz",
            .hash = "...",
        },
    },
}

// build.zig
const regex = b.dependency("regex", .{ .target = target, .optimize = optimize });
exe_mod.addImport("regex", regex.module("regex"));
lib_mod.addImport("regex", regex.module("regex"));
test_mod.addImport("regex", regex.module("regex"));
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

**修改文件**：`src/runtime/eval.zig`、`src/runtime/primitive.zig`（在 `RuntimeEnv` 中新增 `regex_cache` 字段）

当前 `regex_literal` 处的 `@panic("regex engine not yet implemented")` 改为真实编译。

`r"..."` 字面量的正则表达式模式采用**首次使用编译**策略：第一次执行到 `regex_literal` 时将模式字符串通过 zig-regex 编译，编译后的 `Regex` 对象缓存在 `RuntimeEnv.regex_cache`（`std.StringHashMapUnmanaged(*const regex.Regex)`）中，后续再次遇到同一字面量时直接返回缓存句柄。

```zig
.regex_literal => |v| {
    // 1. 查缓存：相同模式字符串的 Regex 句柄
    // 2. 未命中：调用 Regex.compile(allocator, v.value) 编译
    // 3. 缓存并返回句柄
},
```

`Regex.fromString` 同样在**运行时**编译：接受用户输入的模式字符串，调用 `Regex.compile(allocator, pattern)`，失败时返回 `Err`。`fromString` 编译的结果不做跨次缓存（每次调用独立编译），因为动态模式来源不可预测。

### 2.4 替换 Regex Primitive 存根 + 新增函数

当前 `primitive.zig` 中已有 `Regex.isMatch`、`Regex.fromString`、`Regex.firstMatch`、`Regex.allMatches` 的 Primitive 存根（`crypto.zig` 中的 `regexIsMatchImpl`/`regexFromStringImpl`/`regexFirstMatchImpl`/`regexAllMatchesImpl`），均返回虚假值。本步骤将这些存根替换为真实 zig-regex 实现，并新增 `replace`、`replaceAll`、`split`。

**修改文件**：`src/runtime/primitive.zig`、`src/stdlib/crypto.zig`

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

**修改文件**：`src/test_main.zig`（添加 `regex` 测试引用）

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

**修改文件**：`src/test_main.zig`（添加 `validator` 测试引用）

```bash
cd code/kun-lang && zig build test
# 新增 stdlib/test_validator.zig（~8 测试）
```

## Step 4：DateTime 格式化引擎

### 4.1 实现

当前 `DateTime.now`、`DateTime.format` 和 `DateTime.parse` 已有 Primitive 存根（`primitive.zig` 中 `crypto.dateTimeNowImpl`/`dateTimeFormatImpl`/`dateTimeParseImpl`，均在 `crypto.zig` 中返回虚假值）。本步骤将存根替换为真实实现。同时修正 `now` 的 `is_effect` 值（当前为 `false`，应为 `true`——`now` 需要系统调用获取当前时间）。

**新建文件**：`src/runtime/datetime_fmt.zig`

`DateTime.format`、`DateTime.parse` 和 `DateTime.now` 的 Zig 实现：

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

**修改文件**：`src/runtime/primitive.zig`（替换 `dateTimeNowImpl`/`dateTimeFormatImpl`/`dateTimeParseImpl` 存根，修正 `now` 的 `is_effect` 为 `true`）、`src/runtime/eval.zig`、`src/stdlib/crypto.zig`

### 4.3 验证

**修改文件**：`src/test_main.zig`（添加 `datetime` 测试引用）

```bash
cd code/kun-lang && zig build test
# 新增 runtime/test_datetime.zig（~10 测试）
```

## Step 5：Duration/Int/Float/Char 模块 Primitive 绑定 + PureKun 函数

### 5.1 Duration 模块

当前 `Duration` 已有编译器内置类型和字面量支持，但模块函数未注册。

**新建文件**：`src/stdlib/duration.zig`

Duration 模块全部函数在设计中标注 `[PureKun]`（`system-baseline.md` 分类为"全部 PureKun"）。`fromString` 和 `format` 依赖字符串解析/格式化，但可用纯 Kun 实现（字符处理 + 算术运算）。采用与 Nilable 模块相同的**过渡方案**：暂以 Primitive 注册，后续降级为 PureKun。

| 函数 | 签名 | 实现方式 |
|------|------|---------|
| `toNanos` | `Duration -> Int` | PureKun |
| `toMicros` | `Duration -> Int` | PureKun |
| `toMillis` | `Duration -> Int` | PureKun |
| `toSeconds` | `Duration -> Int` | PureKun |
| `toMinutes` | `Duration -> Int` | PureKun |
| `toHours` | `Duration -> Int` | PureKun |
| `toDays` | `Duration -> Int` | PureKun |
| `fromString` | `String -> Result Duration String` | PureKun |
| `fromMillis` | `Int -> Duration` | PureKun |
| `toString` | `Duration -> String` | PureKun |
| `format` | `String -> Duration -> Result String String` | PureKun |
| `negate` | `Duration -> Duration` | PureKun |
| `isNegative` | `Duration -> Bool` | PureKun |
| `abs` | `Duration -> Duration` | PureKun |

### 5.2 Int 模块

当前 Primitive 表中无 `Int` 模块条目。`Int` 模块函数在设计中标注 `[PureKun]`（`system-baseline.md` 分类为"少量 Primitive"）。采用**过渡方案**：暂以 Primitive 注册，后续降级为 PureKun（当 .kun 标准库文件就绪时）。

**新建文件**：`src/stdlib/int.zig`

| 函数 | 签名 | 实现方式 |
|------|------|---------|
| `abs` | `Int -> Int` | PureKun |
| `min` | `Int -> Int -> Int` | PureKun |
| `max` | `Int -> Int -> Int` | PureKun |
| `pow` | `Int -> Int -> Int` | PureKun |
| `clamp` | `Int -> Int -> Int -> Int` | PureKun |
| `fromString` | `String -> Result Int String` | PureKun |
| `toFloat` | `Int -> Float` | PureKun |
| `toString` | `Int -> String` | PureKun |

**修改文件**：注册到 `src/runtime/primitive.zig`

### 5.3 Float 模块

当前 Primitive 表中无 `Float` 模块条目。`Float` 模块大部分函数在设计中标注 `[PureKun]`，但三角函数、指数、对数等实际需要 Zig `std.math`。

**新建文件**：`src/stdlib/float.zig`

| 函数 | 签名 | 实现方式 |
|------|------|---------|
| `pi` / `e` | `Float` | PureKun（常量） |
| `abs` | `Float -> Float` | PureKun |
| `floor` / `ceil` / `round` | `Float -> Float` | **Primitive**（委托 Zig `@floor`/`@ceil`/`@round` 内建） |
| `sin` / `cos` / `tan` | `Float -> Float` | **Primitive**（委托 Zig `std.math`） |
| `exp` / `log` / `log2` / `log10` | `Float -> Float` | **Primitive**（委托 Zig `std.math`） |
| `pow` / `sqrt` | `Float -> Float -> Float` / `Float -> Float` | **Primitive**（委托 Zig `std.math`） |
| `approxEqual` | `Float -> Float -> Float -> Bool` | PureKun |
| `min` / `max` | `Float -> Float -> Float` | PureKun |
| `clamp` | `Float -> Float -> Float -> Float` | PureKun |
| `fromString` | `String -> Result Float String` | PureKun |
| `toInt` | `Float -> Int` | PureKun |
| `toString` | `Float -> String` | PureKun |

> 注：`sin`/`cos`/`tan`/`exp`/`log`/`pow`/`sqrt` 在标准库 `standard-library.md` 中标注为 `[PureKun]`，但实际需要 Zig 的 `std.math` 数值计算能力，无法用纯 Kun 实现。`floor`/`ceil`/`round` 也需要 Zig `@floor`/`@ceil`/`@round` 内建函数。本计划按实际实现需求标记为 Primitive，后续应同步更新 `standard-library.md` 的标注。

### 5.4 Char 模块

当前 Primitive 表中无 `Char` 模块条目。

**新建文件**：`src/stdlib/char.zig`

| 函数 | 签名 | 实现方式 |
|------|------|---------|
| `of` | `Int -> Char` | Primitive（of 约定：调用者自保证，非法 panic） |
| `fromInt` | `Int -> Result Char String` | Primitive |
| `isDigit` / `isAlpha` / `isUpper` / `isLower` / `isWhitespace` / `isControl` | `Char -> Bool` | **Primitive**（委托 Zig Unicode 判断） |
| `toUpper` / `toLower` | `Char -> Char` | **Primitive**（委托 Zig Unicode 转换） |
| `toInt` | `Char -> Int` | PureKun |

> 注：`isDigit`/`isAlpha`/`isUpper`/`toLower` 等函数在 `standard-library.md` 标注为 `[PureKun]`，但实际需要 Zig 标准库的 Unicode 类别判断（`std.unicode`）和大小写转换能力。本计划按实际需求标记为 Primitive，后续应同步更新 `standard-library.md`。

### 5.5 验证

**修改文件**：`src/test_main.zig`（添加 `duration`、`int`、`float`、`char` 测试引用）

```bash
cd code/kun-lang && zig build test
# 新增 stdlib/test_duration.zig、stdlib/test_int.zig、stdlib/test_float.zig、stdlib/test_char.zig（各 ~8 测试）
```

## 变更范围总表

| Step | 新建文件 | 修改文件 | 新增代码行 | 新增测试 |
|------|---------|---------|-----------|---------|
| 1 — Nilable ADT | `src/stdlib/nilable.zig`, `src/stdlib/test_nilable.zig` | `src/lexer/lexer.zig`, `src/lexer/test_lexer.zig`, `src/ast/ast.zig`, `src/ast/typed.zig`, `src/parser/parser.zig`, `src/typecheck/env.zig`, `src/typecheck/constraint.zig`, `src/typecheck/effect.zig`, `src/typecheck/pattern.zig`, `src/typecheck/error.zig`, `src/typecheck/unify.zig`, `src/typecheck/test_constraint.zig`, `src/typecheck/test_unify.zig`, `src/typecheck/test_pattern.zig`, `src/typecheck/test_effect.zig`, `src/runtime/eval.zig`, `src/runtime/value.zig`, `src/runtime/primitive.zig`, `src/runtime/test_eval.zig`, `src/module/module_resolver.zig`, `src/i18n/i18n.zig`, `src/i18n/test_i18n.zig`, `src/test_main.zig` | ~465 | ~25 |
| 2 — Regex | `build.zig.zon`, `src/runtime/regex_engine.zig`, `src/runtime/test_regex.zig` | `build.zig`, `src/runtime/eval.zig`, `src/runtime/value.zig`, `src/runtime/primitive.zig`, `src/stdlib/crypto.zig`, `src/module/module_resolver.zig`, `src/test_main.zig` | ~200 | ~15 |
| 3 — Validator | `src/stdlib/validator.zig`, `src/stdlib/test_validator.zig` | `src/runtime/primitive.zig`, `src/test_main.zig` | ~80 | ~8 |
| 4 — DateTime | `src/runtime/datetime_fmt.zig`, `src/runtime/test_datetime.zig` | `src/runtime/eval.zig`, `src/runtime/primitive.zig`, `src/stdlib/crypto.zig`, `src/test_main.zig` | ~250 | ~10 |
| 5 — Duration/Int/Float/Char | `src/stdlib/duration.zig`, `src/stdlib/int.zig`, `src/stdlib/float.zig`, `src/stdlib/char.zig`, `src/stdlib/test_duration.zig`, `src/stdlib/test_int.zig`, `src/stdlib/test_float.zig`, `src/stdlib/test_char.zig` | `src/runtime/primitive.zig`, `src/test_main.zig` | ~550 | ~40 |
| **合计** | **8 个新建 Zig 模块 + 7 个新建测试文件** | **25 个修改文件** | **~1560** | **~98** |

目标：**679 → ~777 测试**。

## 依赖关系

```
Step 1 (Nilable ADT) ── 独立，影响 Parser + TypeChecker + Runtime
                           可与其他 Step 并行
Step 2 (Regex) ──── 独立
Step 3 (Validator) ──依赖── Step 2 (Regex)
Step 4 (DateTime) ── 独立
Step 5 (Duration/Int/Float/Char) ── 独立，可并行
```

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
| 2026.06.26 | R7 审计修复：删除重复行；Step 1 摘要表补齐 1.2b/1.2f 中漏列的 8 个修改文件；Step 2 补充 module_resolver.zig；依赖关系图补充 Step 1；总计修正 |
| 2026.06.26 | R6 审计修复：module_resolver 变更修正（移除 Nil + 新增 Nilable/Duration/Int/Float/Char 到 hasPrimitiveBinding）、AdtVariant.fields → .payload、TypeAnn.nilable 构造修正、DateTime.parse 已存在（替换存根非新增）、Regex Primitive 存根已存在（替换+新增补充）、Step 4 补充 crypto.zig 修改 |
| 2026.06.26 | R5 审计修复：Float 表 sin/cos/tan 重复行删除；build.zig.zon 为新建非修改；build.zig regex import 补充 lib_mod/test_mod；RuntimeEnv regex_cache 字段补充；摘要表文件路径修正 |
| 2026.06.26 | R4 审计修复：datetime_fmt.zig 重复新建行删除；各步骤补充 test_main.zig；Float floor/ceil/round → Primitive；regex 编译策略改为首次使用缓存；Step 2 补充 value.zig RegexHandle 更新；变更范围表补充测试文件数和 test_main.zig |
| 2026.06.26 | R3 审计修复：Duration fromString/format → PureKun；Int/Float 已有条目不实修正；DateTime 存根替换说明；Float/Char 补充当前状态说明 |
| 2026.06.26 | R2 审计修复：全部 8 项修复确认通过，无新问题 |
| 2026.06.26 | R1 审计修复：裸变量糖化删除、Nilable 模块 Primitive 过渡说明、标记分类修正等 8 项 |
| 2026.06.26 | 初始版本 |

