# 项目愿景

## 核心问题

Shell 脚本是 Linux 系统管理自动化的重要工具，但存在以下根本性问题：

1. **缺乏类型安全**：变量无类型约束，参数传递全凭字符串拼接，运行时才能发现错误
2. **错误处理薄弱**：错误码与异常信号混杂，缺乏结构化的错误处理机制
3. **数据结构原始**：只有字符串和数组，无法表达复杂的数据关系
4. **组合能力有限**：管道仅传递文本流，无法传递结构化数据
5. **安全风险高**：脚本拥有与用户相同的权限，缺乏细粒度的访问控制

## 愿景

设计一款函数式、强静态类型、代数数据类型、结构化 + 不可变数据、表达式导向语法、高性能的 Linux 脚本语言——Kun（鲲），从根本上消除 Shell 脚本所存在的各种问题，同时保持 Unix 哲学中"小程序组合完成复杂任务"的核心理念。

## 核心理念

### 命令即函数

每一个 Linux 命令通过 `cmd` 字面量调用，构造 `Command` 值（延迟执行），选项通过 Record 类型表达（`cmd ls { long = true } []`），camelCase 字段名自动映射为 kebab-case CLI flag。执行（`Cmd.exec`/`Cmd.execSafe`/`Cmd.stream`）后输出通过 `Stream String` 捕获，可进一步类型化处理。

### 类型驱动组合

通过 `cmd` 字面量的自动模块发现机制（`~/.kun/cmd/`），为命令提供类型化选项检查。`kun cmd init` 从 `man`/`--help` 生成类型化模块骨架。`pipe` 纯函数组合多个命令为 OS 管道链，`|>` 组合类型化进程内管道。

### 安全即默认

脚本默认仅 CWD 可读写，无网络访问。通过 CLI 参数 `--allow-path` / `--allow-net` 在运行时声明安全边界。采用 Landlock + mount namespace 兜底 + rlimit + seccomp 多层沙箱隔离，子进程 fork-exec 前自动安装安全策略。

### 表达式导向

语法设计借鉴 Elm、Haskell 和 Rust（以 Elm 语法结构为主），确保简洁、统一、一致。所有数据均必须赋初值，消除 null，支持自动类型推断。

## 实现策略

采用 Rust 作为宿主语言构建轻量级的二进制脚本执行器（`kun`）与共享解释器核心（`libkunlang.so`）。Rust 通过 `bumpalo`（Arena 分配）、`nix`（syscall 包装）、`regex`（正则引擎）等成熟 crate 满足 Kun 的核心需求；详见 [语言评估](../analysis/language-evaluation.md)。交互式环境 `kun-shell` 设计已定型，未来版本实现（详见 [Kun Shell](../design/kun-shell.md)）。

运行时使用 Linux 的 fork-exec 机制执行外部命令，通过 pipe 捕获 stdout/stderr。`cmd` 字面量参数通过 Record 类型表达，运行时自动序列化为 argv 数组——shell 元字符（`;`、`|`、`$(...)` 等）在 exec 层面为普通字符，无注入风险。

