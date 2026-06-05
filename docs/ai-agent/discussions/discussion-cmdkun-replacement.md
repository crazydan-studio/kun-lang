# 讨论记录：`.cmd.kun` + Builder API 替代 CDF

## 背景

现行 CDF（Command Description File）方案通过独立 DSL 定义命令签名，存在两套语言、声明式局限、seccomp 伪精确等问题。项目维护者提出用 `.cmd.kun` + Builder API 完全替代。

## 决策

**废弃 CDF 方案**。采用 `.cmd.kun` + Builder API 方案完全替代。

## 关键差异

| 维度 | CDF 方案（已废弃） | `.cmd.kun` + Builder 方案（新） |
|------|---------|------------------------|
| 定义语言 | CDF DSL（独立 EBNF 语法） | 纯 Kun 语法 + Builder API |
| 表达能力 | 声明式，有限 `case` | 全 Kun（if/else、case、递归） |
| 工具链 | 需 CDF 编译器 | 复用 Kun 编译器 |
| 安全来源 | 参数类型 → seccomp 推导（伪精确） | capability_check + namespace + seccomp + Landlock |
| 路径级控制 | seccomp 做不到 | Landlock（内核 5.13+） |
| 用户输入保护 | Validator（值级） | `withUnsafeArg`（调用级标记） |
| 学习成本 | 两套语言 | 一套语言 |
| 退出码 | CDF `exitcode` DSL | Builder 链式 `exitcode` 调用 |
| 自动推导 | 运行时 T3 升级通路 | `kun cmd init` 开发辅助工具 |
| 分发 | CDF 文件分发 | `.cmd.kun` 版本化注册中心 |
| 内建命令 | 独立 T1 层 | 与 `.cmd.kun` 调用方式一致 |

## 设计文档

完整设计见 `design/command-function-system.md`。
