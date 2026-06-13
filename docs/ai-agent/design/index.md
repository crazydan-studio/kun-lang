# 应用层设计

本目录包含 Kun 语言当前版本的应用层行为设计文档，定义语言的功能和行为规范。

## 文件说明

| 文件 | 用途 |
|---|---|
| [app-overview.md](app-overview.md) | Kun 语言功能概览 |
| [type-system.md](type-system.md) | 类型系统核心设计 |
| [standard-library.md](standard-library.md) | 标准库类型设计 |
| [syntax.md](syntax.md) | 语法设计 |
| [code-formatting.md](code-formatting.md) | 代码格式化规范 |
| [cli.md](cli.md) | `Cli` 模块详细设计（命令行参数解析） |
| [feature-inventory.md](feature-inventory.md) | 功能清单与实现状态 |
| [command-system.md](command-system.md) | OS 命令调用机制（Cmd.&lt;bin&gt; 语法、camelCase 映射、执行模型、管道、修饰函数） |
| [kun-cli-tool.md](kun-cli-tool.md) | `kun` CLI 工具（子命令、安全控制参数、脚本入口、Kun Shell） |
| [kun-shell.md](kun-shell.md) | Kun Shell 交互式环境（SQLite 日志存储、函数收藏、AST 哈希） |

> 已废弃的历史设计文档已归档至 [`archive/deprecated/`](../archive/deprecated/) 目录。包括：安全角色与权限模型（`with caps`）、供应链安全、命令函数系统（`.cmd.kun` + Builder API）、命令签名系统（CDF）、能力映射指南。

## 设计原则

- **类型安全**：所有操作在编译期进行类型检查，消除运行时类型错误
- **表达式导向**：所有语句均为表达式，具有返回值
- **不可变优先**：数据默认不可变，需要变更时通过显式机制
- **错误显式化**：通过和类型（如 `Result`、`?T`）显式表达所有可能的失败；`Cmd.<bin>?` 返回 `Result`，默认 panic
- **求值策略**：管道和高阶函数默认严格求值；`let` 绑定延迟求值；`Stream` 惰性

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.13 | 求值策略措辞修正；示例代码语法合规审计与修复 |
| 2026.06.10 | 架构重设计：应用层设计文档定型 |
