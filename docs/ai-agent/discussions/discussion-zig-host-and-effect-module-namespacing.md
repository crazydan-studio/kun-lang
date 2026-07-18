# Zig 0.16.0 宿主语言与效应/模块同名消歧

> **日期**：2026-07-16
> **状态**：已定稿
> **相关文档**：[Zig 模式指南](../context/zig-patterns.md)、[语法设计 - 效应与模块同名](../design/syntax.md#效应与模块同名)、[类型系统 - 内置效应](../design/type-system.md#内置效应)

## 背景

两个设计问题需要定稿：

1. **Zig 0.16.0（https://ziglang.org/documentation/0.16.0/）作为 Kun 宿主语言是否可行？** 仓库现有 `zig-patterns.md` 基于 Zig 0.17.0-dev（开发版），需评估锁定稳定版 0.16.0 的可行性。
2. **模块与效应同名时（如 `Cmd`），在保持同名的前提下，如何区分效应接口和模块接口？** 当前设计中 `Cmd` 既是效应（`effect Cmd = { exec, ... }`）又是模块（`Cmd.kun` 提供 `withEnv`/`withoutDash` 等纯函数），需明确消歧规则。

## 讨论一：Zig 0.16.0 作为宿主语言

### 结论：可行，推荐锁定稳定版 0.16.0

Zig 0.16.0 已发布的稳定版对 Kun 所需核心能力全覆盖：

| Kun 需求 | Zig 0.16.0 支持情况 |
|---|---|
| Arena 内存管理（Kun 全程 Arena 策略） | ✅ `ArenaAllocator` 线程安全、无锁 |
| dlopen/dlsym + C ABI（FFI 仅 Linux） | ✅ `std.c.dlopen`/`dlsym`，C ABI 稳定 |
| fork-exec + 子进程管理（Cmd 执行） | ✅ `std.process.Child`，poll/非阻塞 I/O |
| Landlock / seccomp 沙箱 | ✅ `std.os.linux.landlock_*`/`seccomp` 封装 |
| I/O Interface（0.16 引入 `std.Io`） | ✅ 0.16 标志性特性，`std.Io.File`/`stream`/`Event` |
| Juicy Main（`pub fn main(init: std.process.Init) !void`） | ✅ 0.16+ 推荐，环境变量非全局，符合 Kun 沙箱模型 |
| comptime 元编程（内置 handler 注册表编译期生成） | ✅ `std.ComptimeStringMap` 等 |
| tagged union（Kun ADT 运行时表示） | ✅ Zig 原生核心特性 |
| 显式错误集（对应 Kun `Result`/`IOError`） | ✅ error set + `!` 语法 |

### 需注意的约束

1. **`@cImport` 已废弃**：0.16 起 C 头文件导入迁移到构建系统 `b.addTranslateC(.{...})`。Kun 的 FFI 不依赖 C 头文件（用 `extern` 块手写签名 + `dlopen` 动态绑定），不受影响。
2. **类型反射 API 变更**：0.16 中 `@Type` 已移除，改用 `@Int`/`@Struct`/`@Union`/`@Fn` 等独立内置函数。Kun 若需编译期反射生成类型（如 FFI 签名校验），需用新 API。
3. **stdlib API 命名调整**：`std.fs.path.cwd` → `process.Cwd` 等。这是 0.16 主动推进的 API 规范化，Kun 实现跟随即可。

### 版本选择理由

- **稳定版优于 dev 版**：0.16.0 是已发布稳定版，API 冻结；0.17.0-dev 仍处于 API 变动期，锁定 dev 版会带来持续适配成本。
- **核心能力齐备**：Kun 所需的 Arena、FFI/dlopen、fork-exec、沙箱、tagged union、comptime、I/O Interface、Juicy Main 在 0.16.0 均已落地并稳定。
- **决策**：锁定 **0.16.0**，更新 `zig-patterns.md` 版本声明从 0.17.0-dev → 0.16.0，补充官方文档链接与版本包路径，代码注释中 0.17 特性引用统一为 0.16（这些特性在 0.16.0 已落地）。

## 讨论二：效应与模块同名的消歧

### 结论：类型命名空间与值命名空间分离 + 效应操作必须全名调用，无需额外语法

`Cmd` 同时是效应名（类型层）与模块名（值层），二者语法位置天然不重叠，编译器按上下文自动消歧。

### 现状

- **效应名 `Cmd`**（类型层）：`effect Cmd = { exec, execSafe, stream, which }`，出现在函数效应集 `! {Cmd}`、`Handler {Cmd} a`、`handle ... with h`。
- **模块名 `Cmd`**（值层）：`<runtime>/lib/kun/Cmd.kun`，`export (Cmd, pipe, cmd, withEnv, withStdin, withStdinFile, mergeStderr, withWorkDir, withRunAs, withoutDash, andThen, orElse, timeout, retry)`，模块内提供纯函数 `Cmd.withEnv`/`Cmd.withoutDash`/`Cmd.andThen` 等（均已导出，可选择性导入裸名）。
- 调用 `Cmd.exec`（效应操作，产生 `! {Cmd}`）与 `Cmd.withEnv`（模块纯函数，无效应）都挂同一 `Cmd.` 前缀。

### 三层消歧机制

#### 1. 类型层 vs 值层（最根本）

效应名只出现在类型标注的效应集位置（类型上下文），模块名只出现在表达式/导入位置（值上下文），二者**语法位置不重叠**，同名不冲突——这是 Elm/Haskell 等"类型与值分离命名空间"语言的成熟做法。

| 标识符 `Cmd` 的角色 | 出现位置 | 命名空间 |
|---|---|---|
| 效应名 | `! {Cmd}`、`Handler {Cmd} a`、`effect Cmd = {...}` | 类型命名空间 |
| 模块名 | `import Cmd (...)`、`Cmd.exec`、`Cmd/` 目录 | 值命名空间 |

#### 2. 操作签名区分效应操作 vs 模块函数

同一 `Cmd.` 前缀下，编译器按签名归属区分：效应操作（来自 `effect Cmd` 声明）查**效应操作表**；模块函数（来自模块绑定）查**模块符号表**。效应操作调用产生 `! {Cmd}`，模块纯函数无效应——效应集检查进一步区分（效应操作在纯函数体内调用 → 编译错误）。

#### 3. 效应操作必须全名调用（关键规则）

为彻底消除歧义，效应操作**不支持选择性导入裸名**，必须以 `EffectName.op` 全名调用：

- `import Cmd (exec)` ❌ 编译错误（效应操作不可裸名导入）
- `Cmd.exec c` ✅（效应操作全名调用）
- `import Cmd (withEnv)` ✅（模块纯函数可选择性导入裸名，直接用 `withEnv env c`）

这样**视觉上**也能区分：带 `EffectName.` 前缀且名为该效应声明的操作（如 `Cmd.exec`/`Cmd.execSafe`/`Cmd.stream`/`Cmd.which`）的是效应操作；其余 `EffectName.<xxx>` 或裸名的是模块函数。

### 消歧规则定稿

1. **效应名与模块名共享标识符，分属类型命名空间与值命名空间**，语法位置不重叠，同名合法。
2. **`EffectName.<op>` 解析**：先查效应操作表，再查模块符号表。
3. **效应操作必须全名调用**：`import EffectName (op)` ❌，必须 `EffectName.op`。
4. **模块纯函数可选择性导入裸名**：`import Module (func)` ✅。
5. **效应操作不可被模块函数遮蔽**：`effect Cmd` 声明后，同模块内不可再定义同名 `exec`/`execSafe`/`stream`/`which` 绑定（编译错误）。
6. **handler 内 `continue`/`abort`**：`continue (Cmd.exec c)` 委托的永远是效应操作（查效应表），模块函数不参与 handler 委托。
7. **7 个内置效应名为保留名**，用户不可定义同名 `effect`；内置效应名与对应标准库模块同名，遵循上述规则。用户自定义效应若与用户模块同名，同样适用。

### 示例

```kun
// Cmd 既是效应又是模块，同名合法
import Cmd (Cmd, pipe, cmd, withEnv, withoutDash)   // 模块函数可选择性导入

fetchUser : UserId -> Result User ! {Cmd, IO}        // Cmd 作为效应名（类型层）

main : List String -> Unit ! {Cmd, IO} =
  \args ->
    let
      c = cmd docker run { d = true } [ "nginx" ]
        |> withEnv (Map.fromList [ ("TZ", "UTC") ])   // withEnv 模块函数（裸名）
        |> withoutDash                                // withoutDash 模块函数（裸名）
      result = Cmd.execSafe c                         // Cmd.execSafe 效应操作（全名，产生 ! {Cmd}）
    in
      case result of
        Ok stream -> Stream.iter IO.println stream
        Err e     -> IO.println "failed"
```

## 落盘清单

| 文件 | 变更 |
|---|---|
| `docs/ai-agent/context/zig-patterns.md` | 版本声明 0.17.0-dev → 0.16.0；补充官方文档链接与版本包路径；代码注释 0.17 → 0.16；新增 2026.07.16 版本历史 |
| `docs/ai-agent/design/syntax.md` | 新增「效应与模块同名」章节（命名空间分离、`Cmd.<name>` 解析、5 条消歧规则、示例、保留名说明）；Cmd 模块导出声明补全修饰函数；新增版本历史条目 |
| `docs/ai-agent/design/type-system.md` | 内置效应章节补充「效应名与模块名同名」说明（交叉引用语法设计）；Cmd 模块导出声明补全；新增版本历史条目 |
| `docs/ai-agent/design/standard-library.md` | Cmd 模块导出声明补全修饰函数（withEnv/withStdin 等） |
| `docs/ai-agent/design/command-system.md` | Cmd 模块导出声明补全修饰函数（withEnv/withStdin 等） |
| `docs/ai-agent/discussions/discussion-zig-host-and-effect-module-namespacing.md` | 新建本讨论记录 |
| `docs/ai-agent/discussions/index.md` | 新增本讨论记录的索引行（日期 2026-07-16） |

## 参考链接

- Zig 0.16.0 官方文档：https://ziglang.org/documentation/0.16.0/
