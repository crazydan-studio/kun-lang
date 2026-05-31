# AGENTS.md — Kun 项目 AI 协作操作规范

> 本文件定义了 AI Agent 在 Kun 项目中的操作契约。所有参与本项目的 AI Agent 在开始工作前必须阅读并遵守本规范。

## 核心原则

### 仓库即真理源（Repo = Source of Truth）

仓库是持久化的制度基础设施，AI 可以持续地与之协作。Chat（对话）仅是临时工作面。所有持久化的结论必须落盘到文件中。

### 文档优于对话

- 任何需求理解、设计决策、架构变更都必须以文件形式记录到 `docs/ai-agent/` 对应目录
- 对话中产生的结论如果没有写入文件，视为不存在
- AI 不得仅凭对话记忆做出影响仓库状态的决策

### 任务路由优先

在编写代码之前，AI 必须：
1. 分类任务类型（新功能、修复、重构、文档、配置等）
2. 阅读相关的 owner docs（`docs/ai-agent/context/`、`docs/ai-agent/design/`、`docs/ai-agent/architecture/`）
3. 检查 `docs/ai-agent/skills/` 中是否有适用的技能
4. 记录任务路由决策

## 操作规则

1. **文档先行**：修改代码前先更新对应的设计/架构文档
2. **输入→讨论→需求流程**：所有新功能遵循 `docs/ai-agent/input/` → `docs/ai-agent/discussions/` → `docs/ai-agent/requirements/` 流程
3. **先计划后实现**：涉及多模块或超过 5 个文件的变更必须先写计划（`docs/ai-agent/plans/`）
4. **最小代码注释**：代码应自文档化，注释仅用于解释"为什么"而非"是什么"
5. **归档意识**：版本迭代前，将当前版本文档迁移到 `docs/ai-agent/archive/<version>/`
6. **技能约束**：使用 `docs/ai-agent/skills/` 中的提示词模板，但必须结合 owner docs 使用
7. **错误模式升级**：连续出现同类错误时必须记录到 `docs/ai-agent/bugs/` 并升级处理

## 计划触发条件

以下情况必须编写执行计划：
- 类型系统、命令签名、运行时等核心模块变更
- 涉及多个子系统（如类型检查器 + 解释器 + 运行时）
- 跨多个会话的长期任务
- 变更超过 5 个文件或约 200 行代码
- 需要分阶段执行
- 存在未解决的风险

## 强制审计

- 所有计划在实施前必须经过独立审计（独立子代理/审查者）
- 完成后必须进行闭合审计（closure audit）

## 自治级别

AI 自治策略定义在 `docs/ai-agent/context/ai-autonomy-policy.md`，包含以下级别：
- `implement`：AI 可在阅读需求 + owner doc + 验证命令后自主实施
- `plan-first`：AI 可起草计划，但实施需等待计划审计通过
- `ask-first`：AI 必须在代码/行为变更前询问
- `research-only`：仅检查/总结，不做行为变更
- `blocked`：必须等待阻塞项解决

## 文件操作规范

- 文档使用 Markdown 格式，遵循 `docs/ai-agent/skills/writing-conventions.md`
- PlantUML 图表文件放置在 `docs/ai-agent/diagrams/` 目录
- VitePress 路由使用 `index.md` 而非 `README.md`
