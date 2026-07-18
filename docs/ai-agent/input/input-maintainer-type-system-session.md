# 输入：类型系统设计会话 — 维护者指令记录

来源：项目维护者（会话 2026-05-28）

## 输入 1：启动类型系统核心设计

推进类型系统核心设计，从 `idea` 状态进入设计阶段。

**处理**：已创建 `docs/ai-agent/design/type-system.md`，包含 14 个设计维度。

---

## 输入 2：设计决策裁定

| 决策 | 输入 | 裁定结果 |
|------|------|---------|
| Nat/Int 关系 | 独立类型，不支持子类型 | 覆写了 AI 推荐的 Nat<:Int 方案 |
| 正则修饰符 | 仅支持内联（PCRE），不支持后缀标志 | 覆写了 AI 推荐的后缀标志方案 |
| 类型推断 | Hindley-Milner | 确认 AI 推荐 |
| 整数语义 | 固定宽度 i64 | 确认 AI 推荐 |
| 泛型约束 | 无约束 | 确认 AI 推荐 |
| 效应深度 | 仅标记 IO 边界 | 确认 AI 推荐 |
| 子类型 | 无 | 由 Nat/Int 独立决策自然导出 |
| Path/文件类型 | 保持单一 Path，不嵌入文件类型 | 确认 AI 推荐 |

**处理**：已写入 `docs/ai-agent/design/type-system.md` 及各相关章节。

---

## 输入 3：需要补充的类型

经 AI 审计后，要求补充：

| 类型 | 批次 |
|------|------|
| Port、Pid、Signal、Errno | P1 立即 |
| IOError、FileType | P1 立即（修复悬空引用） |
| DateTime、ExitCode、User/Group、IpAddress | P1 后续 |

**处理**：已写入 `docs/ai-agent/design/standard-library.md`。

---

## 输入 4：Array 合并到 List

List 与 Array 不单独定义，List 支持索引访问。

**处理**：已合并，新增 List/Array 合并设计决策小节。

---

## 输入 5：类型系统与标准库拆分

Port/Pid/Signal/Errno/FileType/IOError 等从 `type-system.md` 迁出，以标准库形式定义。

**处理**：已创建 `docs/ai-agent/design/standard-library.md`。

---

## 输入 6：启动语法设计

完成类型系统后要求启动语法设计。

**处理**：已创建 `docs/ai-agent/design/syntax.md`，覆盖全部语法模式，统一 9 处文档不一致。

---

## 输入 7：提交人信息

要求提交作者为 `AI 码农 <coder@ai.crazydan.io>`。

**处理**：已完成 git rebase 变更。

---

## 输入 8：文档流程记录补齐

指出 discussions/plans/audits/input 等目录缺少记录，要求补齐。

**处理**：已创建讨论记录、执行计划、审计记录和本输入文档。

---

## 输入 9：上下文文档同步

指出 project-context.md、codebase-map.md 等落后于实际工作状态。

**处理**：已同步更新。

---

## 后续建议

- 运行时架构设计、命令签名系统设计为下一优先级
- 建议在启动实现前完成命令签名系统设计文档
