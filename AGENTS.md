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

在编写代码之前，AI 必须按顺序执行以下检查：

0. **执行任务启动检查清单**（详见 `docs/ai-agent/process/application-development-workflow.md`）
   - 评估变更范围（文件数、模块数、受保护区域）
   - 检查依赖项与前提条件
   - 识别待确认项
   - 匹配执行流程档位
   - 向用户呈现分析结果，获得确认后再执行

1. 分类任务类型（新功能、修复、重构、文档、配置等）
2. 阅读相关的 owner docs（`docs/ai-agent/context/`、`docs/ai-agent/design/`、`docs/ai-agent/architecture/`）
3. 检查 `docs/ai-agent/skills/` 中是否有适用的技能（见「技能决策指引」）
4. 记录任务路由决策到 `docs/ai-agent/context/project-context.md`

## 操作规则

1. **文档先行**：修改代码前先更新对应的设计/架构文档
2. **输入→讨论→需求流程**：所有新功能遵循 `docs/ai-agent/input/` → `docs/ai-agent/discussions/` → `docs/ai-agent/requirements/` 流程
3. **先计划后实现**：涉及多模块或超过 5 个文件的变更必须先写计划（`docs/ai-agent/plans/`）
4. **最小代码注释**：代码应自文档化，注释仅用于解释"为什么"而非"是什么"
5. **归档意识**：版本迭代前，将当前版本文档迁移到 `docs/ai-agent/archive/<version>/`
6. **技能约束**：使用 `docs/ai-agent/skills/` 中的提示词模板，但必须结合 owner docs 使用
7. **错误模式升级**：连续出现同类错误时必须记录到 `docs/ai-agent/bugs/` 并升级处理
   - 历史违规记录见 `docs/ai-agent/lessons/agents-md-compliance.md`
   - 任务启动检查清单（`process/application-development-workflow.md`）是防止已知违规的首要防线

## 文档目录总览

下表列出了 `docs/ai-agent/` 下全部文档目录及其使用时机。所有路径均为相对于仓库根目录的相对路径。

| 目录 | 内容说明 | 使用时机 |
|------|---------|---------|
| `docs/ai-agent/context/` | 项目上下文、自治策略、代码库地图、约定、真理源与优先级、Zig 模式指南（**最高优先级**） | 每次任务开始时优先阅读 |
| `docs/ai-agent/process/` | 任务启动检查清单、应用开发工作流 | **接手新任务的第一步** |
| `docs/ai-agent/architecture/` | 系统基线、模块边界、项目愿景 | 涉及系统架构、模块间交互时 |
| `docs/ai-agent/design/` | 类型系统、语法、标准库、安全模型等应用层设计 | 涉及语言行为规范变更时 |
| `docs/ai-agent/requirements/` | MVP、产品范围、需求定义 | 新功能开发前 |
| `docs/ai-agent/input/` | 原始需求输入记录 | 新功能需求溯源时 |
| `docs/ai-agent/discussions/` | 设计讨论记录 | 决策过程需要回顾时 |
| `docs/ai-agent/plans/` | 执行计划与编写指南 | 计划触发条件满足时 |
| `docs/ai-agent/skills/` | 可复用技能提示词（审计/写作） | 特定任务前按需加载（见「技能决策指引」） |
| `docs/ai-agent/audits/` | 审计记录、审计执行指南 | 实施前/实施后的审计环节 |
| `docs/ai-agent/lessons/` | 经验教训与违规记录 | 遇到已记录过的错误模式时 |
| `docs/ai-agent/examples/` | 语法使用综合示例 | 理解语法设计意图、验证一致性时 |
| `docs/ai-agent/logs/` | 开发日志 | 追溯近期工作时 |
| `docs/ai-agent/backlog/` | 待办事项与状态流转 | 了解未完成工作项时 |
| `docs/ai-agent/testing/` | 测试记录与基线值 | 测试实施前后 |
| `docs/ai-agent/bugs/` | Bug 修复笔记 | 遇到已知 Bug 模式时 |
| `docs/ai-agent/references/` | 实现指南、维护检查清单、文档命名规范 | 需要开发指南或维护检查时 |
| `docs/ai-agent/retrospectives/` | 回顾总结 | 项目持续改进阶段 |
| `docs/ai-agent/analysis/` | 技术分析报告（如语言选型评估） | 技术选型、方案评估时 |
| `docs/ai-agent/articles/` | 技术文章 | 扩展学习时 |
| `docs/ai-agent/archive/` | 版本归档规则 | 文档版本迭代前 |
| `docs/ai-agent/diagrams/` | PlantUML 图表 | 需要生成或更新可视化图表时 |

**文档状态追踪**：每份文档的设计状态见 [`design/feature-inventory.md`](docs/ai-agent/design/feature-inventory.md)（功能级）和各个 `index.md`（文件级）。例如 `Kun Shell` 设计已定型（未来版本实现），路由时仍应阅读其设计文档。

**文档优先级链**（引用 `docs/ai-agent/context/source-of-truth-and-precedence.md`）：
> `context/` > `architecture/` > `design/` > `requirements/` > `plans/` > 其他文档

## 计划触发条件

以下情况必须编写执行计划：
- 类型系统、命令系统、运行时等核心模块变更
- 涉及多个子系统（如类型检查器 + 解释器 + 运行时）
- 跨多个会话的长期任务
- 变更超过 5 个文件或约 200 行代码
- 需要分阶段执行
- 存在未解决的风险

如何判断是否满足上述条件 → 执行任务启动检查清单的 0a 步骤（`process/application-development-workflow.md` 的变更范围评估表）

## 强制审计

- 所有计划在实施前必须经过独立审计（独立子代理/审查者）
  - 审计类型与执行要求见 `docs/ai-agent/audits/00-audit-execution-guide.md`
  - 可用审计技能模板见 `docs/ai-agent/skills/`（plan-audit-prompt、document-audit-prompt 等）
- 完成后必须进行闭合审计（closure audit）
  - 使用 `docs/ai-agent/skills/closure-audit-prompt.md`
- 审计结论必须记录到 `docs/ai-agent/audits/` 目录
- 发现的问题必须跟踪到解决

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

## 技能决策指引

使用 `docs/ai-agent/skills/` 中的提示词模板时，按以下场景选择：

| 当前任务场景 | 应加载的技能 |
|-------------|------------|
| 编写/修改文档 | `skills/writing-conventions.md` |
| 审计设计文档质量 | `skills/document-audit-prompt.md` |
| 审计计划可行性 | `skills/plan-audit-prompt.md` |
| 实施后完成度审查 | `skills/closure-audit-prompt.md` |
| 跨维度风险评估 | `skills/multi-dimensional-audit-prompt.md` |
| 发现隐藏风险 | `skills/open-ended-audit-prompt.md` |
| 需求偏差诊断 | `skills/requirement-gap-retrospective-prompt.md` |

技能是方法选择器，必须结合 owner docs 使用，不能替代 owner docs。

## Git 规范

参见 `docs/ai-agent/context/conventions.md` 中的 Git 章节。核心原则：

- **按需提交**：AI 仅在用户明确要求时执行 git commit
- 提交前必须通过 `git status` 和 `git diff` 确认变更内容
- 提交信息格式：`<类型>: <描述>`（类型：新增/修复/重构/文档/配置/测试）
