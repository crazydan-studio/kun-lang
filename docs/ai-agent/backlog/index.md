# 待办事项

## 工作项

| 优先级 | 事项 | 需求文档 | Owner Doc | 计划 | 状态 | AI 自治 | 阻塞项 | 最后检查 |
|---|---|---|---|---|---|---|---|---|
| P0 | 项目初始化与文档体系搭建 | — | `docs/ai-agent/context/project-context.md` | — | `done` | `implement` | 无 | 2026-05-30 |
| P0 | 类型系统核心设计 | — | `docs/ai-agent/design/type-system.md` | — | `done` | `plan-first` | 无 | 2026-05-30 |
| P0 | 语法全面调整（21 项） | — | `docs/ai-agent/design/syntax.md` | `docs/ai-agent/plans/plan-syntax-overhaul.md` | `done` | `implement` | 无 | 2026-05-30 |
| P0 | 运行时架构设计 | — | `docs/ai-agent/architecture/system-baseline.md` | `docs/ai-agent/plans/plan-runtime-architecture.md` | `done` | `plan-first` | 无 | 2026-05-31 |
| P0 | 首阶段 Zig 代码实现（build.zig + Lexer + Parser + AST + CLI） | — | `docs/ai-agent/design/syntax.md` | `docs/ai-agent/plans/plan-implementation-phase-1.md` | `done` | `implement` | 无 | 2026-06-20 |
| P1 | 命令函数系统设计 | — | `docs/ai-agent/design/command-system.md` | — | `done` | `plan-first` | 无 | 2026-06-04 |
| P1 | 安全模型设计 | — | `docs/ai-agent/design/command-system.md`（安全模型已并入命令系统设计） | — | `done` | `plan-first` | 无 | 2026-05-31 |
| P1 | 标准库类型设计 | — | `docs/ai-agent/design/standard-library.md` | — | `done` | `implement` | 无 | 2026-05-30 |
| **P1** | **Kun Shell 设计** | — | [`docs/ai-agent/design/kun-shell.md`](/ai-agent/design/kun-shell) | — | `done` | `plan-first` | 实现推迟 v2.0，设计已完成 | 2026-06-18 |


## 状态流转

`idea` → `needs-requirement` → `needs-design` → `ready` → `in-progress` → `done`

## 注意事项

- AI 不得将工作项升级为 `ready`，除非人工确认
- `blocked` 状态的工作项必须在阻塞项解决后才能推进
- 优先级 P0 为阻塞项，必须优先处理
- 标记为 `done` 的工作项在版本归档时迁移到 `docs/ai-agent/archive/<version>/`
