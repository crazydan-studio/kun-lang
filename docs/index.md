# Kun 项目文档中心

> Kun（鲲）—— 面向 Linux 的函数式脚本语言

## 文档导航

| 如果你需要... | 首先阅读 | 其次阅读 |
|---|---|---|
| 了解项目全貌 | [项目上下文](/ai-agent/context/project-context) | [代码库地图](/ai-agent/context/codebase-map) |
| 理解项目愿景 | [项目愿景](/ai-agent/architecture/project-vision) | [系统基线](/ai-agent/architecture/system-baseline) |
| 了解当前设计 | [应用概览](/ai-agent/design/app-overview) | [功能清单](/ai-agent/design/feature-inventory) |
| 理解技术架构 | [系统基线](/ai-agent/architecture/system-baseline) | [模块边界](/ai-agent/architecture/module-boundaries) |
| 确定下一步工作 | [待办事项](/ai-agent/backlog/) | [需求文档](/ai-agent/requirements/) |
| 提交新功能需求 | [输入处理指南](/ai-agent/input/00-input-processing-guide) | [需求综合指南](/ai-agent/requirements/00-requirement-synthesis-guide) |
| 编写执行计划 | [计划编写指南](/ai-agent/plans/00-plan-authoring-and-execution-guide) | [需求文档](/ai-agent/requirements/) |
| 查看历史版本 | [版本归档](/ai-agent/archive/) | — |
| 了解编写规范 | [约定规范](/ai-agent/context/conventions) | [文档编写规范](/ai-agent/skills/writing-conventions) |
| AI 协作规则 | [AI 自治策略](/ai-agent/context/ai-autonomy-policy) | [真理源与优先级](/ai-agent/context/source-of-truth-and-precedence) |

## 项目概况

- **项目名称**：Kun（鲲）
- **当前版本**：0.1.0
- **项目类型**：编程语言设计与实现
- **宿主语言**：Zig
- **目标平台**：Linux
- **许可证**：Apache 2.0

## 文档组织

```
docs/
├── ai-agent/       ← AI Agent 专属的设计、开发文档
│   ├── context/       项目上下文与 AI 协作规范
│   ├── architecture/  技术架构与系统设计
│   ├── design/        应用层行为与功能设计
│   ├── requirements/  需求文档
│   ├── backlog/       待办事项与工作项
│   ├── plans/         执行计划
│   ├── skills/        可复用的技能提示词
│   ├── archive/       历史版本归档
│   ├── diagrams/      PlantUML 图表文件
│   └── ...            其他开发相关文档
├── v0/             ← 版本发布与使用文档（占位，尚未发布）
├── public/         静态资源
└── .vitepress/     VitePress 配置
```
