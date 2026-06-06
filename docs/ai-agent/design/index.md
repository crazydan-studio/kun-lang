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
| [feature-inventory.md](feature-inventory.md) | 功能清单与实现状态 |
| [roles-and-permissions.md](roles-and-permissions.md) | 安全角色与权限模型（含容器化对比） |
| [supply-chain-security.md](supply-chain-security.md) | 供应链安全防御方案 |
| [command-function-system.md](command-function-system.md) | 命令函数系统（`.cmd.kun` + Builder API）设计 |
| [command-signature-system.md](command-signature-system.md) | ~~命令签名系统（CDF）设计~~ **已废弃** |
| [capability-mapping-guide.md](capability-mapping-guide.md) | 能力映射指南——将 Linux 命令能力抽象为类型安全函数的方法论 |

## 设计原则

- **类型安全**：所有操作在编译期进行类型检查，消除运行时类型错误
- **表达式导向**：所有语句均为表达式，具有返回值
- **不可变优先**：数据默认不可变，需要变更时通过显式机制
- **错误显式化**：通过和类型（如 `Result`、`?T`）显式表达所有可能的失败
- **严格求值**：管道和高阶函数默认严格求值，`let` 绑定和 `Stream` 惰性
