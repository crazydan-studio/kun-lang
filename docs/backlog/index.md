# 待办事项

## 工作项

| 优先级 | 事项 | 需求文档 | Owner Doc | 计划 | 状态 | AI 自治 | 阻塞项 | 最后检查 |
|---|---|---|---|---|---|---|---|---|
| P0 | 项目初始化与文档体系搭建 | — | `docs/context/project-context.md` | — | `done` | `implement` | 无 | 2026-05-30 |
| P0 | 类型系统核心设计 | — | `docs/design/type-system.md` | — | `done` | `plan-first` | 无 | 2026-05-30 |
| P0 | 语法全面调整（21 项） | — | `docs/design/syntax.md` | `docs/plans/plan-syntax-overhaul.md` | `done` | `implement` | 无 | 2026-05-30 |
| P0 | 运行时架构设计 | — | `docs/architecture/system-baseline.md` | — | `idea` | `plan-first` | 无 | — |
| P1 | 命令签名系统设计 | — | `docs/design/app-overview.md` | — | `idea` | `plan-first` | 无 | — |
| P1 | 安全模型设计 | — | `docs/design/roles-and-permissions.md` | — | `needs-design` | `plan-first` | 无 | — |
| P1 | 标准库类型设计 | — | `docs/design/standard-library.md` | — | `done` | `implement` | 无 | 2026-05-30 |
| P2 | 语法设计 | — | `docs/design/syntax.md` | — | `done` | `plan-first` | 无 | 2026-05-30 |
| P2 | REPL 设计 | — | — | — | `idea` | `plan-first` | 运行时设计 | — |

## 状态流转

`idea` → `needs-requirement` → `needs-design` → `ready` → `in-progress` → `done`

## 注意事项

- AI 不得将工作项升级为 `ready`，除非人工确认
- `blocked` 状态的工作项必须在阻塞项解决后才能推进
- 优先级 P0 为阻塞项，必须优先处理
- 标记为 `done` 的工作项在版本归档时迁移到 `docs/archive/<version>/`
