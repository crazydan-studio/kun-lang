# 应用开发工作流

## 概述

Kun 项目的开发遵循吸引子引导工程（Attractor-Guided Engineering）方法论。仓库是持久化的真理源，Chat 仅是临时工作面。所有持久化的结论必须落盘到文件中。

## 任务启动检查清单

> **每次接手新任务时，AI Agent 必须按顺序执行以下检查。完成第 0 步后运行验证命令确认。**

### 第 0 步：启动验证命令

```bash
# 在开始任何修改前运行。输出应显示 AGENTS.md 已读
echo "AGENTS.md read: $(date -r /workspace/AGENTS.md '+%Y-%m-%d %H:%M')" && \
echo "---" && \
echo "步骤 0/7 待确认"
```

### 第 1 步：识别变更类型

| 类型 | 示例 | 需警惕的流程 |
|------|------|------------|
| 新功能 | 语法特性、标准库类型 | `input→discussion→requirements→plan` |
| 重构 | 能力系统重设计 | `plan-first` + 审计 |
| 修复 | bug、语法错误 | `conventions.md` 错误模式升级 |
| 文档 | 新增/更新文档 | `skills/writing-conventions` |
| 配置 | VitePress、Git 配置 | `implement` 可直接执行 |

**检查**：任务是否触及 `ai-autonomy-policy.md:19-25` 中的受保护区域（类型系统核心、运行时安全模型、命令签名系统）？若触及，确认对应的自治级别要求。

### 第 2 步：阅读 Owner Docs

```bash
# 每次接手新任务时必须阅读以下文件
grep -c '^#' /workspace/AGENTS.md  # 确认 AGENTS.md 已读
grep -c 'ai-autonomy-policy' /workspace/docs/ai-agent/context/ai-autonomy-policy.md
```

按任务类型锁定目标文件：

| 任务类型 | 必须阅读的文件 |
|---------|--------------|
| 语法设计 | `syntax.md`、`code-formatting.md`、`design/index.md` |
| 类型系统 | `type-system.md`、`syntax.md`、`design/index.md` |
| 安全模型 | `roles-and-permissions.md`、`system-baseline.md`、`ai-autonomy-policy.md` |
| 运行时 | `system-baseline.md`、`module-boundaries.md` |
| 示例/文档 | `code-formatting.md`、`writing-conventions.md`（skills/） |

### 第 3 步：检查 Skills

检查 `docs/ai-agent/skills/` 中是否有适用于当前任务的提示词模板：

```bash
ls /workspace/docs/ai-agent/skills/*.md | grep -v index.md
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

### 第 4 步：检查计划触发条件

满足以下任一条件必须在 `docs/ai-agent/plans/` 中编写执行计划：

- [ ] 类型系统、命令签名、运行时等核心模块变更
- [ ] 涉及多个子系统
- [ ] 变更超过 5 个文件或约 200 行代码
- [ ] 需要分阶段执行
- [ ] 存在未解决的风险

**若触发**：先写计划 → 审计计划 → 再实施。

### 第 5 步：确认流程顺序

```bash
# 检查 input → discussion → requirements 链是否完整
# 新功能必须经过：input/ → discussions/ → requirements/ → plans/ → 实施
# 非新功能可跳过 input→discussion→requirements，但 plan 不可跳过
```

### 第 6 步：记录路由决策

在 `docs/ai-agent/context/project-context.md` 的"最近任务路由"表中添加一行：

```markdown
| <日期> | <任务描述> | <分类> | ✅ owner docs 已读 | ✅ skills 检查: <适用/不适用> | <路由决策> |
```

### 第 7 步：实施前自检

```bash
echo "=== 实施前自检 ==="
echo "变更类型: " && echo "触发 plan? " && echo "Owner docs 已读? " && echo "Skills 已检查? " && echo "路由已记录? " && echo "=== 确认 ==="
```

---

## 工作流阶段

### 阶段 0：读取上下文

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
