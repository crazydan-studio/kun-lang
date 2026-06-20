# Audit Round 13 — 边缘区域专项审计

- **日期**：2026-06-20
- **审计范围**：README.md、AGENTS.md 目录索引、docs/index.md、config.mts sidebar、archive/、backlog/、discussions/、input/、全 docs/ Markdown 链接有效性
- **审计方法**：交叉对照目录内容与索引文件、检查文件存在性、验证 sidebar 完整性

## 发现汇总

| 严重度 | 数量 |
|--------|------|
| P0（必须修复） | 3 |
| P1（应修复） | 3 |
| P2（建议修复） | 2 |
| **合计** | **8** |

---

## P0 — 必须修复

### 1. examples/ sidebar 指向全部不存在的 .md 文件

**位置**：`docs/.vitepress/config.mts:402-408`

**问题**：sidebar 中 examples 子项指向的 `.md` 文件全部不存在：

| Sidebar 项 | 链接路径 | 实际文件 |
|------------|---------|---------|
| 日志文件处理器 | `/ai-agent/examples/file-processor` | ✗ 不存在 |
| 类型系统聚焦 | `/ai-agent/examples/type-showcase` | ✗ 不存在 |
| IO 与效应系统 | `/ai-agent/examples/networking` | ✗ 不存在 |
| 模式匹配专题 | `/ai-agent/examples/pattern-matching` | ✗ 不存在 |

**实际情况**：`examples/` 目录实际包含 `basic.kun` 和 `log-analyzer.kun` 两个 `.kun` 文件，`examples/index.md` 也已正确引用这两个文件。sidebar 与其完全脱节，用户点击 sidebar 导航会跳转至 404 页面。

**修复方式**：更新 sidebar 项使其与 `examples/index.md` 一致，或补充缺失的 `.md` 示例文件。

---

### 2. backlog/index.md 引用的两个设计文件已不存在

**位置**：`docs/ai-agent/backlog/index.md:11-12`

**问题**：

1. **第 11 行** P1 命令函数系统设计 Owner Doc 列为 `docs/ai-agent/design/command-function-system.md`，但该文件**已不存在**（已被合并/重命名为 `docs/ai-agent/design/command-system.md`）
2. **第 12 行** P1 安全模型设计 Owner Doc 列为 `docs/ai-agent/design/roles-and-permissions.md`，但该文件**已归档至** `archive/deprecated/roles-and-permissions.md`

**修复方式**：
- `command-function-system.md` → 更新为 `docs/ai-agent/design/command-system.md`
- `roles-and-permissions.md` → 更新为 `docs/ai-agent/design/command-system.md`（安全模型已并入命令系统设计）或指向当前安全设计对应文档

---

### 3. audits/ sidebar 缺失 7 份已存在的审计文档

**位置**：`docs/.vitepress/config.mts:327-340`

**问题**：`audits/` 目录实际有 17 个 `.md` 文件（不含 `index.md`），但 sidebar 仅列出 10 个。以下 7 个已存在的审计文件在 sidebar 中**完全缺失**：

- `audit-round9-documentation-timeliness`
- `audit-round10-comprehensive`
- `audit-round11-deep`
- `audit-round12-focused`
- `audit-agents-md-revision-closure`
- `audit-syntax-usability`
- `audit-type-system-design-v2`

`docs/ai-agent/audits/index.md` 也同样缺失上述 7 个文件的条目，sidebar 与 index 均未覆盖。

**修复方式**：在 `config.mts` 的 `sidebarWorking()` 审计节和 `audits/index.md` 中补充全部 7 个文件。

---

## P1 — 应修复

### 4. input/index.md 引用了不存在的文件

**位置**：`docs/ai-agent/input/index.md:22`

**问题**：表格末行引用 `input-architecture-redesign-evaluation.md`，但该文件在 `input/` 目录中**不存在**。目录中实际有 11 个文件（含 `index.md` 和 `00-input-processing-guide.md`），表格应仅列出 9 个内容文件，但实际列出 10 个，多出的 `架构重设计方案评估` 行指向不存在文件。

**修复方式**：删除该行或补充对应的 `.md` 文件。

---

### 5. discussion sidebar 缺失 `discussion-string-path-typing`

**位置**：`docs/.vitepress/config.mts:300-315`

**问题**：`discussion-string-path-typing.md` 存在于 `discussions/` 目录且在 `discussions/index.md` 中有条目，但 `config.mts` sidebar 的讨论记录节**未包含**该文件。用户点击 "讨论记录" 展开后无法导航至此文档。

**修复方式**：在 sidebar 讨论记录 items 中添加 `{ text: 'String 操作与 Path 模块函数归属', link: '/ai-agent/discussions/discussion-string-path-typing' }`。

---

### 6. README.md 引用不存在的 `lsp-dev.sh`

**位置**：`/kun-lang/README.md:36`

**问题**：`[tools/lsp-dev.sh](tools/lsp-dev.sh)` 指向的文件**不存在**。`tools/` 目录仅包含 `docs-build.sh` 和 `docs-dev.sh`，无 `lsp-dev.sh`。

**修复方式**：删除该链接或创建对应的脚本文件。

---

## P2 — 建议修复

### 7. AGENTS.md 目录表 `context/` 描述不完整

**位置**：`/kun-lang/AGENTS.md:51`

**问题**：AGENTS.md 文档目录总览表中 `context/` 的 "内容说明" 列为 "项目上下文、自治策略、代码库地图、约定"，但 `context/` 目录实际还包含：
- `source-of-truth-and-precedence.md`（真理源与优先级）
- `zig-patterns.md`（Zig 模式指南）

这两个文件未被描述覆盖。

**修复方式**：补充描述为 "项目上下文、自治策略、代码库地图、约定、真理源与优先级、Zig 模式指南"。

---

### 8. docs/index.md 文档组织树缺少多个子目录

**位置**：`docs/index.md:31-46`

**问题**：`docs/` 的目录树仅列出 `ai-agent/` 下的 5 个子目录（context/、architecture/、design/、requirements/、backlog/、plans/、skills/、archive/、diagrams/），但实际 `ai-agent/` 有 16 个一级子目录，缺失以下目录：
- `audits/`、`bugs/`、`discussions/`、`input/`、`lessons/`、`logs/`、`references/`、`retrospectives/`、`analysis/`、`articles/`、`examples/`、`testing/`

虽然树末有 `... 其他开发相关文档` 占位，但直接列出所有目录对读者更方便。

**修复方式**：在树中补充所有实际存在的子目录，或将占位说明更新为列出关键目录。

---

## 复验记录

| 检查项 | 结果 |
|--------|------|
| archive/index.md 中 5 个废弃文档引用 | 全部有效 |
| archive/deprecated/ 下 5 个文件 | 全部存在 |
| backlog/ 其他文件引用（kun-shell、plans） | 有效 |
| discussions/index.md 与目录对照 | 一致 |
| input/ sidebar 与目录对照 | 全部覆盖 |
| requirements/ sidebar 与目录对照 | 全部覆盖 |
| plans/ sidebar 与目录对照 | 全部覆盖 |
| bugs/ sidebar 与目录对照 | 全部覆盖 |
| logs/ sidebar 与目录对照 | 全部覆盖 |
| testing/ sidebar 与目录对照 | 全部覆盖 |
| references/ sidebar 与目录对照 | 全部覆盖 |
| lessons/ sidebar 与目录对照 | 全部覆盖 |
| retrospectives/ sidebar 与目录对照 | 全部覆盖 |
| AGENTS.md 中 `conventions.md` Git 章节引用 | 有效（conventions.md 存在 Git 规范节） |
| AGENTS.md 中 `process/application-development-workflow.md` 引用 | 需在之前审计中验证 |
| 已确认禁止模式（注释/泛型/箭头函数等） | 未扫描（已在之前轮次完成） |
