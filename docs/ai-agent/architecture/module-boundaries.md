# 模块边界

## 模块划分

```
kun-lang/
├── 解释器核心
│   ├── 词法分析器（Lexer）
│   ├── 语法分析器（Parser）
│   ├── 类型检查器（Type Checker）
│   ├── 效应检查器（Effect Checker）— 函数效应集推导
│   ├── AST（抽象语法树）
│   └── i18n（locale 检测 + 消息翻译）
├── CLI 参数解析引擎
│   ├── Spec 数据模型（CliSpec / CliArg / CliMeta / CliError）
│   ├── token 分片与选项匹配
│   ├── 子命令调度
│   ├── 帮助与版本信息生成
│   └── 错误报告
├── 运行时（Runtime）
│   ├── Command 构造器（`cmd` 字面量）
│   ├── Command 执行器（fork-exec + pipe 捕获）
│   └── Stream 状态机（tagged union）
├── 命令调用系统
│   ├── `cmd` 字面量入口（四段式）
│   ├── camelCase → kebab-case 自动映射
│   ├── 类型化模块自动发现（~/.kun/cmd/）
│   ├── Cmd.withEnv / Cmd.withStdinStr / Cmd.withStdinBytes / Cmd.withStdinFile / Cmd.mergeStderr
│   ├── Cmd.withWorkDir / Cmd.withRunAs
│   ├── Cmd.andThen / Cmd.orElse（短路条件组合）
│   ├── Cmd.timeout / Cmd.retry（修饰函数，需配合 Cmd.exec/execSafe/stream 执行）
│   ├── pipe 纯函数（OS 管道链组合）
│   └── Cmd.which（PATH 查找）
├── 安全子系统
│   ├── 安全参数定义（--allow-path、--allow-net、--allow-ffi、--no-sandbox、--force、--env=、--cpu-limit、--mem-limit、--audit）—— 解析由 CLI 参数解析引擎完成
│   ├── Landlock 文件控制（5.13+）/ 网络控制（6.7+）首选
│   ├── Mount namespace 兜底隔离（内核 3.8+）
│   ├── seccomp-BPF 系统调用过滤（最低降级，per 子进程 fork 后安装）
│   ├── rlimit 资源限制
│   └── 环境变量安全过滤
├── 标准库
│   ├── 数据类型（Int、Float、String、Bytes、Char、Decimal、List、Map、Set、Stream 等）
│   ├── 管道与高阶函数（Function、Nil、Result 等）
│   ├── 模式匹配
│   ├── IO 操作（IO、File、Env、Cmd、Process 等）
│   ├── CLI 工具（Cli、Validator、Path 等）
│   ├── 类型安全解析（Parser.JSON、Parser.Record）
│   ├── 系统与安全（Random、Signal、DateTime、IOError、CommandError、Uid、Gid 等）
│   └── Primitive 函数表（运行时与标准库之间的 Rust 级绑定接口）
└── Kun Shell
    ├── 交互式环境
    ├── SQLite/DuckDB 日志存储
    ├── 函数收藏与复用（AST 哈希）
    ├── 历史回放
    └── 编辑器集成
```

## 模块职责

### 解释器核心

负责将 Kun 源代码解析为 AST 并进行类型检查。包含词法分析、语法分析、类型推断和类型检查。效应检查器推导函数效应集（体内所有效应调用的并集），标注于函数类型 `a -> b ! {E}`。这是编译器的前端部分，不涉及任何 IO 或系统调用。

### 运行时

负责执行编译后的代码。通过 fork-exec 机制执行外部命令，以 pipe 捕获 stdout/stderr。`cmd` 字面量构造 `Command` 值不立即执行；必须显式调用 `Cmd.exec`/`Cmd.execSafe`/`Cmd.stream` 才触发 fork-exec。`|>` 退化为纯管道，不再隐式触发执行。

### 命令调用系统

负责将 Linux 命令的能力抽象为类型安全调用。`cmd` 字面量构造 `Command` 值（四段式：命令 / 子命令* / 选项? / 位置参数?），camelCase 字段名自动映射为 kebab-case CLI flag，字符串键原样使用。类型化模块自动发现机制在编译时检查选项类型一致性。`Cmd.withEnv` / `Cmd.withStdinStr` / `Cmd.withStdinBytes` / `Cmd.withStdinFile` / `Cmd.mergeStderr` / `Cmd.withWorkDir` / `Cmd.withRunAs` 修饰 Command 值（纯函数），`Cmd.andThen` / `Cmd.orElse` 提供短路条件组合。工具函数：`Cmd.timeout` 提供超时控制，`Cmd.retry` 提供重试机制（两者为修饰函数，需配合 `Cmd.exec`/`Cmd.execSafe`/`Cmd.streamLines`/`Cmd.streamBytes` 执行）。`pipe` 纯函数将多个 Command 组合为 OS 管道链。`Cmd.which` 在 PATH 中查找可执行文件。

### 安全子系统

实现多层安全模型。从 CLI 参数解析安全策略（`--allow-path`、`--allow-net` 等），初始化阶段在父进程安装 Landlock（首选）/ mount namespace（兜底）主沙箱层；fork 子进程后安装 seccomp-BPF（per 子进程降级）。rlimit 限制 CPU、内存、文件描述符和子进程数。环境变量白名单过滤 + 始终剔除列表。

### 标准库

提供内置的数据类型和函数。实现分为两类：Primitive 实现（Rust 原生函数，通过 Primitive 函数表绑定到模块导出，适用于需要系统调用、编译期类型内省或直接操作运行时数据结构的函数）和纯 Kun 实现（`.kun` 文件，用语言自身编写，适用于纯数据变换和组合子）。逐函数分类详见 `design/standard-library.md` 中的 `[Primitive]` / `[PureKun]` 标注。模块加载时的绑定规则（受保护模块名防护、同名覆盖检测）见 `system-baseline.md` 标准库集成章节。

### Kun Shell

Kun 的交互式环境，以独立可执行文件 `kun-shell` 提供。通过动态链接库 `libkunlang.so` 与 `kun` 共享解释器核心代码。包含 SQLite/DuckDB 日志存储、函数收藏（AST 哈希唯一引用）、历史回放、编辑器集成等功能。完整设计见 [Kun Shell](../design/kun-shell.md)。

> **未来版本**。设计已定型，当前不构建 `kun-shell` 二进制。

## 模块依赖关系

```
Kun Shell ───→ 解释器核心 ───→ 运行时（含 Primitive 函数表）
                                     ↓
                     CLI 参数解析引擎 ───→ 标准库（Cli 模块编译期展开）
                                     ↓
                     解释器核心 ───→ 命令调用系统
                                     ↓
                           运行时 → 安全子系统
                                     ↓
                           运行时 → 标准库（Primitive 绑定接口）

libkunlang.so（解释器核心 + CLI 参数解析引擎 + 运行时 + Primitive 函数表，kun 与 kun-shell 共享）
```

解释器核心依赖命令调用系统的类型化模块进行类型检查；CLI 参数解析引擎为 `kun`、`kun-shell`、`Cli` 模块提供共享的 spec 模型与解析算法；运行时通过 Primitive 函数表将 Rust 原生实现绑定到标准库的受保护模块导出，并通过安全子系统进行沙箱管理；标准库由运行时加载并提供给用户代码使用（其中 `Cli` 模块在编译期展开为对 CLI 参数解析引擎的调用）；Kun Shell 通过 `libkunlang.so` 共享解释器核心、CLI 参数解析引擎、运行时及 Primitive 函数表，是解释器核心的交互式包装。

i18n 子系统位于解释器核心内部——locale 检测在初始化阶段先于任何错误输出执行，确保错误消息按正确语言格式化。

## 源代码映射

> **注**：`code/kun-lang/` 实现已撤销（commit `559180a`，2026-07-17），以下映射为重新实现时的目录规划，待设计完全稳定后基于新设计落地。

重新实现时各模块在 `code/kun-lang/src/` 中的物理路径与模块划分的对应关系（基于 Rust 重新实现，源文件后缀 `.rs`）：

| 架构模块 | 源代码目录 |
|---------|-----------|
| 解释器核心 — Lexer | `lexer/` |
| 解释器核心 — Parser | `parser/` |
| 解释器核心 — Type Checker | `typecheck/` |
| 解释器核心 — Effect Checker | `typecheck/effect.rs` |
| 解释器核心 — AST | `ast/` |
| 解释器核心 — i18n | `i18n/` |
| 运行时 | `runtime/` |
| 命令调用系统 | `command/` |
| 标准库 | `stdlib/` |
| CLI 参数解析引擎 | `cli/` |
| 安全子系统 | `security/` |
| Kun Shell | 未来版本 |

完整源代码树见 `context/codebase-map.md`。

