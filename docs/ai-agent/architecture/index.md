# 技术架构

本目录包含 Kun 语言的技术架构文档，定义系统的技术结构和模块边界。

## 文件说明

| 文件 | 用途 |
|---|---|
| [project-vision.md](project-vision.md) | 项目愿景与核心理念 |
| [system-baseline.md](system-baseline.md) | 系统技术基线与运行时架构设计（含生命周期、执行模型、命令调用、错误诊断、安全隔离、类型表示、内存管理、模块解析、标准库集成） |
| [module-boundaries.md](module-boundaries.md) | 模块边界与职责划分 |

## 设计原则

- **仓库即真理源**：文档是设计意图的持久化载体
- **类型驱动**：`Cmd.<bin>` 构造 Command 值，选项通过 Record 类型表达，位置参数直接传递；Command 延迟执行，触发后输出为 Stream String；组合是类型安全的管道
- **安全默认**：最小权限通过 CLI 参数和沙箱隔离实现
- **简单可靠**：采用 Zig 作为宿主语言，构建单体、无库依赖的轻量级运行时
