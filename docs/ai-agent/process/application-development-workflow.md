# 应用开发工作流

## 概述

Kun 项目的开发遵循吸引子引导工程（Attractor-Guided Engineering）方法论。仓库是持久化的真理源，Chat 仅是临时工作面。所有持久化的结论必须落盘到文件中。

## 任务启动检查清单

> **每次接手新任务时，AI Agent 必须按顺序执行以下检查。完成第 0 步后运行验证命令确认。**

### 第 0 步：可行性分析与待确认项识别

**这是最重要的步骤。在实施任何变更前，必须完成以下分析并向用户呈现。**

#### 0a. 变更范围评估

| 维度 | 评估结果 | 填写 |
|------|---------|------|
| 涉及文件数（预估） | <5 / 5-10 / >10 | — |
| 涉及模块数 | 1 / 2-3 / >3 | — |
| 是否触及受保护区域 | 类型系统核心 / 安全模型 / 命令签名 / dlopen ptrace 机制 / 许可证文件 | — |
| 是否为隐式重构（旧语法→新语法） | 是 / 否 | — |
| 变更行数（预估） | <100 / 100-500 / >500 | — |

#### 0b. 依赖项与前提条件检查

- [ ] 当前仓库状态是否干净？（`git status`）
- [ ] 是否有前置文档需要先更新？
- [ ] 是否有未落盘的设计决策依赖？

#### 0c. 待确认项识别

列出所有不确定的点。典型样例：

> | # | 待确认项 | 可选方案 | 建议 |
> |---|---------|---------|------|
> | 1 | 语法方向 | `with caps` vs `allow` | `with caps` |
> | 2 | 默认权限策略 | 零默认 vs 工作目录只读 | 零默认 |
> | 3 | 声明层级 | 二级 vs 三级 | 二级（移除单命令） |

#### 0d. 流程匹配

根据 0a 结果确定执行流程档位：

| 条件 | 流程 |
|------|------|
| 触及受保护区域（完整列表见 `docs/ai-agent/context/ai-autonomy-policy.md`） | 按区域级别执行（`ask-first` / `plan-first`，见自治策略） → 先向用户呈现 0a+0c，等待明确批准 |
| 满足任一计划触发条件（>5文件/200行/核心模块/多子系统） | **需要 `plan-first`** → 先写计划文档，再审计，再实施 |
| 新功能（非修复/配置） | **需要 `input→discussion→requirements→plan`** 完整链 |
| 文档/配置修改 | **`implement`** 可直接执行，但需阅读 owner docs + skills |

### 第 1 步：向用户呈现

将步骤 0 的分析结果以清晰的结构化形式呈现给用户：

```
## 可行性分析

变更范围：N 文件，N 模块
触发流程：<档位>

## 待确认项

1. <问题描述> → 建议 <方案>
...

请确认后再执行。
```

**在获得确认前，不实施任何变更。**

### 第 2 步：阅读 Owner Docs

```bash
# 每次接手新任务时必须阅读以下文件
grep -c '^#' AGENTS.md  # 确认 AGENTS.md 已读
grep -c 'ai-autonomy-policy' docs/ai-agent/context/ai-autonomy-policy.md
```

按任务类型锁定目标文件：

| 任务类型 | 必须阅读的文件 |
|---------|--------------|
| 语法设计 | `design/syntax.md`、`design/code-formatting.md`、`design/index.md` |
| 类型系统 | `design/type-system.md`、`design/syntax.md`、`design/index.md` |
| 安全模型 | `design/roles-and-permissions.md`、`architecture/system-baseline.md`、`context/ai-autonomy-policy.md` |
| 运行时 | `architecture/system-baseline.md`、`architecture/module-boundaries.md` |
| Zig 实现 | `context/zig-patterns.md`、`architecture/system-baseline.md`、`conventions.md` |
| 示例/文档 | `design/code-formatting.md`、`skills/writing-conventions.md` |

### 第 3 步：检查 Skills

检查 `docs/ai-agent/skills/` 中是否有适用于当前任务的提示词模板：

```bash
ls docs/ai-agent/skills/*.md | grep -v index.md
```

| 技能文件 | 适用场景 |
|---------|---------|
| `writing-conventions.md` | 所有文档编写 |
| `document-audit-prompt.md` | 设计文档质量审计 |
| `plan-audit-prompt.md` | 计划审计 |
| `closure-audit-prompt.md` | 实施后闭合审计 |
| `multi-dimensional-audit-prompt.md` | 跨维度风险评估 |
| `open-ended-audit-prompt.md` | 开放性问题发现 |
| `requirement-gap-retrospective-prompt.md` | 需求差距回顾 |

### 第 4 步：按档位执行（用户确认后）

根据步骤 0d 确定的流程档位执行：

| 档位 | 执行内容 |
|------|---------|
| `ask-first` | 等待批准后，按 `plan-first` 或 `implement` 执行 |
| `plan-first` | 写 `plans/` 文档 → 审计计划 → 实施 |
| `implement` | 可直接实施，但需完成第 5-7 步 |

流程链完整性：

- **新功能**：`input/` → `discussions/` → `requirements/` → `plans/` → 实施
- **非新功能**：检查是否需要 `plans/`，不可跳过计划

### 第 5 步：记录路由决策

在 `docs/ai-agent/context/project-context.md` 的"最近任务路由"表中添加一行：

```markdown
| <日期> | <任务描述> | <分类> | ✅ owner docs 已读 | ✅ skills 检查: <适用/不适用> | <路由决策> |
```

### 第 6 步：实施前自检

```bash
echo "=== 实施前自检 ==="
echo "变更类型: " && echo "触发流程档位: " && echo "用户已确认? " && echo "Owner docs 已读? " && echo "Skills 已检查? " && echo "路由已记录? " && echo "=== 确认 ==="
```

#### 附加检查项（根据 `docs/ai-agent/context/conventions.md`）

- [ ] 新建文件后是否更新 `config.mts` 导航？
- [ ] `.kun` 文件是否已通过 `tools/kun-lint.sh` 检查？
- [ ] Markdown 文件是否已通过 `markdownlint` 检查？
- [ ] Zig 代码是否已对照 `zig-patterns.md` 审计？

#### Subagent 委托约束

使用 `task` 工具委托 subagent 时，prompt 中必须包含以下约束：
- "遵循 AGENTS.md 的所有操作规范"
- "执行任务启动检查清单（`process/application-development-workflow.md`）"
- "新建文件后必須同步更新 `config.mts` 导航"

#### 实施后闭合审计

实施完成后，必须执行 **阶段 11：闭合审计**：
- 使用 `docs/ai-agent/skills/closure-audit-prompt.md`
- 由独立子代理审查（不可自审）
- 审计记录写入 `docs/ai-agent/audits/`
- 问题跟踪到解决

---

## 完整工作流生命周期

> 以下阶段 0-13 描述了完整的项目生命周期，用于理解项目全局阶段归属。
> **日常任务执行时，优先使用上方的「任务启动检查清单」(步骤 0-5) 作为会话入口。**
> 「任务启动检查清单」的步骤 1-4 对应下方阶段 0-6 的精简启动版本。

### 阶段 0：读取上下文（合并至「任务启动检查清单」第 2 步）

开始任何工作前，AI Agent 必须阅读：
- `docs/ai-agent/context/project-context.md` — 了解项目当前状态
- `docs/ai-agent/context/ai-autonomy-policy.md` — 确认自治级别
- `docs/ai-agent/context/conventions.md` — 了解项目约定

### 阶段 1：收集输入

新功能或变更请求从 `docs/ai-agent/input/` 开始。将原始需求、用户反馈、问题报告等记录到输入目录。

### 阶段 2：澄清歧义

对输入进行分析，识别模糊点和不明确的需求。如有必要，在 `docs/ai-agent/discussions/` 中发起讨论。

### 阶段 3：综合需求

在 `docs/ai-agent/requirements/` 中编写结构化的需求文档。需求必须包含：
- 功能描述
- 验收标准
- 涉及的模块
- 风险评估

### 阶段 4：更新设计基线

根据需求更新 `docs/ai-agent/design/` 和 `docs/ai-agent/architecture/` 中的相关文档。

### 阶段 5：审计文档

检查文档的一致性和完整性。确保需求、设计、架构文档之间没有矛盾。

### 阶段 6：路由任务与选择技能

- 分类任务类型
- 检查 `docs/ai-agent/skills/` 中是否有适用的技能
- 确定执行策略

### 阶段 7：编写计划

在 `docs/ai-agent/plans/` 中编写详细的执行计划。计划应包含：
- 变更范围
- 实施步骤
- 验证方法
- 风险缓解

### 阶段 8：审计计划

由独立的子代理/审查者审计计划，确保计划的可行性和完整性。

### 阶段 9：实施

按照计划分步骤实施变更。每个步骤完成后进行验证。

### 阶段 10：验证

运行验证命令，确保变更正确：
- 单元测试
- 集成测试
- 文档构建
- 手动验证

### 阶段 11：闭合审计

由独立审查者进行闭合审计，确认所有变更符合需求。

### 阶段 12：回顾

在 `docs/ai-agent/retrospectives/` 中记录经验教训。

### 阶段 13：技能提取

将可复用的经验和模式提取为 `docs/ai-agent/skills/` 中的技能提示词。

## 版本迭代流程

在开发新版本之前：

1. 将 `docs/ai-agent/architecture/`、`docs/ai-agent/design/` 中的当前版本文档按原始组织结构迁移到 `docs/ai-agent/archive/<current-version>/`
2. 清空活跃文档目录，为新版本腾出空间
3. 归档的版本作为历史回顾供 AI Agent 参考
