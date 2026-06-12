# 模块边界

## 模块划分

```
kun-lang/
├── 解释器核心
│   ├── 词法分析器（Lexer）
│   ├── 语法分析器（Parser）
│   ├── 类型检查器（Type Checker）
│   ├── 效应检查器（Effect Checker）— AST 标记
│   └── AST（抽象语法树）
├── 运行时（Runtime）
│   ├── Command 构造器（Cmd.<bin>）
│   ├── Command 执行器（fork-exec + pipe 捕获）
│   └── Stream 状态机（tagged union）
├── 命令调用系统
│   ├── Cmd.<bin> 语法入口
│   ├── camelCase → kebab-case 自动映射
│   ├── 类型化模块自动发现（~/.kun/cmd/）
│   ├── Cmd.withEnv / Cmd.withStdin / Cmd.withRawOpt / Cmd.mergeStderr
│   ├── Cmd.withCwd / Cmd.withRunAs
│   ├── Cmd.andThen / Cmd.orElse（短路条件组合）
│   ├── Cmd.timeout / Cmd.retry（超时与重试）
│   └── Cmd.pipe OS 管道链
├── 安全子系统
│   ├── CLI 安全参数解析（--allow-path、--allow-net、--no-sandbox、--force、--env=、--cpu-limit、--mem-limit）
│   ├── Landlock 文件控制（5.13+）/ 网络控制（6.7+）首选
│   ├── Mount namespace 兜底隔离（内核 3.8+）
│   ├── seccomp-BPF 系统调用过滤（最低降级，per 子进程 fork 后安装）
│   ├── rlimit 资源限制
│   └── 环境变量安全过滤
├── 标准库
│   ├── 数据类型（List、Map、Set、Stream 等）
│   ├── 管道与高阶函数
│   ├── 模式匹配
│   ├── IO 操作
│   └── 文件操作（File.* — 进程内 syscall）
└── REPL
    ├── 交互式环境
    ├── 语法高亮
    └── 错误报告
```

## 模块职责

### 解释器核心

负责将 Kun 源代码解析为 AST 并进行类型检查。包含词法分析、语法分析、类型推断和类型检查。效应检查器扫描 `do` 块，将含 `do` 块的函数标记为效应函数。这是编译器的前端部分，不涉及任何 IO 或系统调用。

### 运行时

负责执行编译后的代码。通过 fork-exec 机制执行外部命令，以 pipe 捕获 stdout/stderr。Command 值延迟执行，在 `|>` 隐式触发或 `do` 块语句边界自动 fork-exec。

### 命令调用系统

负责将 Linux 命令的能力抽象为类型安全调用。`Cmd.<bin>` 语法构造 Command 值，camelCase 字段名自动映射为 kebab-case CLI flag。类型化模块自动发现机制在编译时检查选项类型一致性。`Cmd.withEnv` / `Cmd.withStdin` / `Cmd.withRawOpt` / `Cmd.mergeStderr` / `Cmd.withCwd` / `Cmd.withRunAs` 修饰 Command 值，`Cmd.andThen` / `Cmd.orElse` 提供短路条件组合，`Cmd.timeout` / `Cmd.retry` 提供超时与重试。`Cmd.pipe` 将多个 Command 组合为 OS 管道链。

### 安全子系统

实现多层安全模型。从 CLI 参数解析安全策略（`--allow-path`、`--allow-net` 等），初始化阶段在父进程安装 Landlock（首选）/ mount namespace（兜底）主沙箱层；fork 子进程后安装 seccomp-BPF（per 子进程降级）。rlimit 限制 CPU、内存、文件描述符和子进程数。环境变量白名单过滤 + 始终剔除列表。

### 标准库

提供内置的数据类型和函数。包括列表、映射、集合、流等数据结构，管道和高阶函数组合工具，模式匹配机制，以及结构化的 IO 和文件操作。

### REPL

提供交互式的开发和调试环境，支持语法高亮、自动补全和结构化的错误报告。

## 模块依赖关系

```
REPL → 解释器核心 → 运行时
                      ↓
解释器核心 → 命令调用系统
                      ↓
           安全子系统 ← 运行时
                      ↓
                 标准库 ← 运行时
```

解释器核心依赖命令调用系统的类型化模块进行类型检查；运行时依赖安全子系统进行沙箱管理；标准库由运行时加载并提供给用户代码使用；REPL 是解释器核心的交互式包装。
