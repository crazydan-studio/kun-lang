# 版本归档

本目录存放历史版本的文档，作为回顾供 AI Agent 参考架构迁移、功能演进等历史过程。

## 归档规则

在开发新版本之前，需要将与当前版本相关的文档和图表按原始组织结构迁移到 `docs/ai-agent/archive/<version>/` 子目录中，从而为活跃文档腾出空间。

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

- **活跃版本**：2026.06（文档在 `docs/ai-agent/architecture/`、`docs/ai-agent/design/` 中）
- **归档版本**：暂无

## 已废弃文档

[`deprecated/`](deprecated/) 目录存放已废弃的历史设计文档，仅供回顾参考：

| 文件 | 原用途 | 废弃原因 |
|------|--------|---------|
| `roles-and-permissions.md` | 安全角色与权限模型 | `with caps` 方案被 CLI 参数（`--allow-path`/`--allow-net`/`--no-sandbox`）替代 |
| `supply-chain-security.md` | 供应链安全防御方案 | Ed25519 签名验证、二进制完整性校验等已移除 |
| `command-function-system.md` | 命令函数系统（`.cmd.kun` + Builder API） | 被 `Cmd.<bin>` 语法替代 |
| `command-signature-system.md` | 命令签名系统（CDF） | 不涉及注册中心，设计废弃 |
| `capability-mapping-guide.md` | 能力映射指南 | `.cmd.kun` 命令函数系统被 `Cmd.<bin>` 替代 |
| `req-capability-design.md` | 能力安全系统重新设计（需求综合，`with caps` 语法方案） | `with caps` 方案被 CLI 参数替代，运行时沙箱通过 Landlock + mount namespace + seccomp + rlimit 实现 |
