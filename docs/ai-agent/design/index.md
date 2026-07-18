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
| [command-system.md](command-system.md) | OS 命令调用机制（`cmd` 字面量四段式、显式执行三入口、管道、修饰函数） |
| [kun-cli-tool.md](kun-cli-tool.md) | `kun` CLI 工具（子命令、安全控制参数、脚本入口、Kun Shell [推迟 v2.0]） |
| [kun-shell.md](kun-shell.md) | Kun Shell 交互式环境（SQLite 日志存储、函数收藏、AST 哈希） [推迟 v2.0] |
| [testing.md](testing.md) | 单元测试设计（`TestCase` 类型、`Test` 模块（`test`/`Test.with`/`Test.timeout`/`Test.describe`）、`_test.kun` 约定、`kun test` 命令、handler 隔离） |

> 已废弃的历史设计文档已归档至 [`archive/deprecated/`](../archive/deprecated/) 目录。包括：安全角色与权限模型（`with caps`）、供应链安全、命令函数系统（`.cmd.kun` + Builder API）、命令签名系统（CDF）、能力映射指南。

## 设计原则

- **类型安全**：所有操作在编译期进行类型检查，消除运行时类型错误
- **表达式导向**：所有语句均为表达式，具有返回值（块表达式范式）
- **不可变优先**：数据默认不可变，需要变更时通过显式机制
- **错误显式化**：通过和类型（如 `Result`、`?T`）显式表达所有可能的失败；`Cmd.execSafe` 返回 `Result`，`Cmd.exec`/`Cmd.stream` 失败 panic
- **求值策略**：`let in` 立即求值；`Lazy`/`Stream` 显式惰性特区；`Cmd.exec`/`Cmd.execSafe`/`Cmd.stream` 显式执行，无 Command 的 `?`/`!` 后缀（零参函数执行的 `!` 另见[类型系统 - 零参效应函数类型](type-system.md#零参效应函数类型-t-e)）

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.07.16 | 测试类型重命名与 `Test` 模块化：`type Test = Test {...}` Record 重命名为 `type TestCase = TestCase {...}`（消除「类型与效应同名」歧义）；`Test` 名专用于效应（`! {Test, e}`）与模块（`Test.with`/`Test.timeout`/`Test.describe`，同名消歧）；新增 `test` 构造器与 `Test.with`/`Test.timeout`/`Test.describe` 链式 `|>` 调用；文件列表 `testing.md` 描述更新为「`TestCase` 类型、`Test` 模块（`test`/`Test.with`/`Test.timeout`/`Test.describe`）、`_test.kun` 约定、`kun test` 命令、handler 隔离」；详见 [单元测试设计](testing.md) |
| 2026.07.16 | 单元测试系统重设计：文件列表新增 `testing.md`（单元测试设计——`Test` 类型值、`_test.kun` 约定、`kun test` 命令、`Test` 效应、handler 隔离）；详见 [单元测试设计](testing.md) |
| 2026.07.16 | 三项设计调整：（1）零参效应函数约定——签名 `T ! {E}`（无 `->`），调用 `Name!`，"无 `?`/`!` 后缀"措辞澄清为"无 Command 的 `?`/`!` 后缀（零参函数执行的 `!` 后缀是独立特性）"（2）守卫子句改用 `if`（移除 `when` 关键字）（3）类型标注与值绑定支持同行形式 `name : Type = expr` |
| 2026.07.15 | 代数效应与命令系统设计配套更新：`cmd` 字面量四段式、显式执行三入口（`Cmd.exec`/`Cmd.execSafe`/`Cmd.stream`）；`let in` 立即求值、`Lazy`/`Stream` 显式惰性特区；`effect`/`handler`/`handle with` 代数效应系统；`extern` 块 FFI 与 `--allow-ffi` 安全控制 |
| 2026.06.13 | 求值策略措辞修正；示例代码语法合规审计与修复 |
| 2026.06.10 | 架构重设计：应用层设计文档定型 |
