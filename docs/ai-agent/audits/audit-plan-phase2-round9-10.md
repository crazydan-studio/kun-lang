# 审计记录：Plan Phase 2 第 9–10 轮

## 基本信息

| 字段 | 值 |
|------|-----|
| 审计对象 | `docs/ai-agent/plans/plan-implementation-phase-2.md`（第 1–8 轮修复后） |
| 审计类型 | 计划审计（第 9–10 轮） |
| 审计日期 | 2026-06-21 |
| 审计者 | AI Agent |
| 对照基线 | `system-baseline.md`, `type-system.md`, `syntax.md`, `standard-library.md`, `command-system.md`, `kun-cli-tool.md`, 当前源码 |
| 审计技能 | `skills/plan-audit-prompt.md` |

## 第 9 轮发现（5 项）

| ID | 严重度 | 问题 | 修复 |
|----|--------|------|------|
| R9-1 | P1 | typed.zig 的 `Stmt.kind` 缺 `defer_` 变体，但 eval 代码已引用 `.defer_ => \|d\|`。AST 有 defer 但 TypedStmt 未同步 | typed.zig 修改表添加 Stmt.kind 补 `defer_` 变体 |
| R9-2 | P1 | 多参 Lambda（`\x y -> body`）在柯里化类型系统下的脱糖完全未描述。约束生成器和 eval 都假设单参，但 parser 可能产生多参 lambda | 约束表 lambda 条目添加多参脱糖说明 |
| R9-3 | P1 | 合一规则表缺 `nilable(a) ~ base` 规则。`nil_to_non_nilable` 错误模板在 MVP 中实现，但无合一规则触发该错误 | 添加 `nilable(a) \| base → nil_to_non_nilable` 规则 |
| R9-4 | P2 | `Subst` 映射定义为 `TypeId → Type` 而非 `TypeId → TypeId`，与 Arena 索引方案不一致 | 改为 `TypeId → TypeId` |
| R9-5 | P2 | `Branch.type_` 和 `Stmt.type_` 从 Type → TypeId 迁移未体现在关键变更列表中 | 扩展关键变更列表涵盖全部 Type→TypeId 迁移点 |

## 第 10 轮发现（1 项）

| ID | 严重度 | 问题 | 修复 |
|----|--------|------|------|
| R10-1 | P2 | `char_literal.value` 类型 u21→u32 迁移未在关键变更中提及。当前 typed.zig 用 u21（Unicode scalar），system-baseline 和 Value 均要求 u32 | 关键变更列表添加 char_literal.value 迁移说明 |

## 结论

第 9–10 轮发现 6 项（P1×3, P2×3），全部已修复。第 10 轮仅发现 1 个 P2 遗漏。累计 8 轮审计共修复 51 项问题。计划可进入实施阶段。
