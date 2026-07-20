# 代码库地图

## 入口点

| 组件 | 路径 | 说明 |
|---|---|---|
| 项目根目录 | `/` | 仓库根目录，包含 README.md、LICENSE、AGENTS.md |
| 源代码 | `code/` | Kun 语言实现源代码（待开发，基于 Rust 重新实现） |
| 文档 | `docs/` | VitePress 项目文档 |
| 构建脚本 | `tools/` | 构建、预览等辅助脚本 |

## 源代码结构

> **注**：`code/kun-lang/`（核心语言实现）的源码已撤销（commit `559180a`，2026-07-17），相关代码已移除。设计文档仍保留在 `docs/ai-agent/design/` 与 `docs/ai-agent/architecture/` 中，作为重新实现的依据。

`code/` 当前组织如下：

```
code/
├── README.md          # 本文件
├── examples/          # Kun 语言示例脚本
│   ├── k8s-deploy/    # K8s 部署示例
│   └── monorepo-ci/   # Monorepo CI 示例
├── kun-shell/         # 交互式环境（规划中，依赖 libkunlang.so）
└── kun-lsp/           # Language Server Protocol 实现（规划中，依赖 libkunlang.so）
```

`kun-lang/`（核心语言：编译器 + 运行时 + CLI）的实现已撤销，待设计完全稳定后基于新设计（效应委派系统、命令系统重设计等）与 Rust 宿主语言重新实现（详见 [语言评估](../analysis/language-evaluation.md)）。

## 关键目录

| 目录 | 用途 |
|---|---|
| `docs/ai-agent/context/` | 项目上下文与 AI 协作规范（最高优先级） |
| `docs/ai-agent/architecture/` | 技术架构与系统设计 |
| `docs/ai-agent/design/` | 应用层行为与功能设计（type-system / standard-library / syntax / kun-shell；roles-and-permissions / supply-chain-security / command-function-system / capability-mapping-guide 已废弃） |
| `docs/ai-agent/requirements/` | 需求文档 |
| `docs/ai-agent/process/` | 任务启动检查清单、应用开发工作流 |
| `docs/ai-agent/backlog/` | 待办事项 |
| `docs/ai-agent/plans/` | 执行计划 |
| `docs/ai-agent/skills/` | AI 技能提示词库 |
| `docs/ai-agent/audits/` | 审计记录与审计执行指南 |
| `docs/ai-agent/examples/` | 语法使用综合示例 |
| `docs/ai-agent/diagrams/` | PlantUML 图表文件 |
| `docs/ai-agent/archive/` | 历史版本文档归档 |
| `docs/ai-agent/input/` | 原始需求输入记录 |
| `docs/ai-agent/discussions/` | 设计讨论记录 |
| `docs/ai-agent/lessons/` | 经验教训与违规记录 |
| `docs/ai-agent/logs/` | 开发日志 |
| `docs/ai-agent/testing/` | 测试记录与基线值 |
| `docs/ai-agent/bugs/` | Bug 修复笔记 |
| `docs/ai-agent/references/` | 实现指南、维护检查清单、文档命名规范 |
| `docs/ai-agent/retrospectives/` | 回顾总结 |
| `docs/ai-agent/articles/` | 技术文章 |
| `docs/ai-agent/analysis/` | 技术分析报告（如语言选型评估） |
| `code/` | 源代码 |
| `tools/` | 构建脚本 |

## 脆弱文件

当前项目处于初始阶段，暂无已识别的脆弱文件。
