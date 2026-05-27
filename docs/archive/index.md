# 版本归档

本目录存放历史版本的文档，作为回顾供 AI Agent 参考架构迁移、功能演进等历史过程。

## 归档规则

在开发新版本之前，需要将与当前版本相关的文档和图表按原始组织结构迁移到 `docs/archive/<version>/` 子目录中，从而为活跃文档腾出空间。

## 归档结构

每个版本目录下的文件结构与活跃文档目录保持一致：

```
archive/
└── <version>/
    ├── architecture/
    │   ├── index.md
    │   ├── project-vision.md
    │   ├── system-baseline.md
    │   └── module-boundaries.md
    ├── design/
    │   ├── index.md
    │   ├── app-overview.md
    │   └── feature-inventory.md
    └── diagrams/
        └── (相关图表文件)
```

## 当前版本

- **活跃版本**：0.1.0（文档在 `docs/architecture/`、`docs/design/` 中）
- **归档版本**：暂无
