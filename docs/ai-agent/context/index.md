# 项目上下文

本目录包含 AI Agent 协作所需的核心上下文信息，是理解项目当前状态的入口。

## 文件说明

| 文件 | 用途 |
|---|---|
| [project-context.md](project-context.md) | 项目快照：身份、活跃工作、验证命令 |
| [ai-autonomy-policy.md](ai-autonomy-policy.md) | AI 自治策略与受保护区域定义 |
| [codebase-map.md](codebase-map.md) | 代码库地图：入口点与脆弱文件 |
| [conventions.md](conventions.md) | 项目约定：命名、格式、工作流规范 |
| [source-of-truth-and-precedence.md](source-of-truth-and-precedence.md) | 真理源定义与文档优先级 |
| [rust-patterns.md](rust-patterns.md) | Rust 模式指南：Arena（bumpalo）、AST enum/match、HM 类型推断、syscall（nix）、Landlock/seccomp 沙箱、错误处理、构建配置（Rust 1.97） |
| [zig-patterns.md](zig-patterns.md) | ⚠️ **已归档（2026-07-20）** — Zig 时期的模式指南，保留作为历史参考 |

## 优先级

**本目录的文件优先级最高**。当其他文档与本目录的文件冲突时，以本目录为准。
