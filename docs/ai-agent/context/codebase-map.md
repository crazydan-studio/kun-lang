# 代码库地图

## 入口点

| 组件 | 路径 | 说明 |
|---|---|---|
| 项目根目录 | `/` | 仓库根目录，包含 README.md、LICENSE |
| 源代码 | `code/` | Kun 语言实现源代码（待开发） |
| 文档 | `docs/` | VitePress 项目文档 |
| 构建脚本 | `tools/` | 构建、预览等辅助脚本 |

## 关键目录

| 目录 | 用途 |
|---|---|
| `docs/ai-agent/context/` | 项目上下文与 AI 协作规范（最高优先级） |
| `docs/ai-agent/architecture/` | 技术架构与系统设计 |
| `docs/ai-agent/design/` | 应用层行为与功能设计（type-system / standard-library / syntax） |
| `docs/ai-agent/requirements/` | 需求文档 |
| `docs/ai-agent/backlog/` | 待办事项 |
| `docs/ai-agent/plans/` | 执行计划 |
| `docs/ai-agent/skills/` | AI 技能提示词库 |
| `docs/ai-agent/diagrams/` | PlantUML 图表文件 |
| `docs/ai-agent/archive/` | 历史版本文档归档 |
| `code/` | 源代码（待开发） |
| `tools/` | 构建脚本 |

## 脆弱文件

当前项目处于初始阶段，暂无已识别的脆弱文件。

## 文档构建

| 操作 | 命令 |
|---|---|
| 文档目录 | `docs/` |
| 依赖管理 | `pnpm`（在 `docs/` 下） |
| 构建 | `cd docs && pnpm build` |
| 预览 | `cd docs && pnpm dev` |
| Markdown 检查 | `cd docs && pnpm lint` |
