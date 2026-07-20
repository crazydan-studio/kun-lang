# 语法使用综合示例

本目录包含 Kun 语言的语法使用综合示例，覆盖类型系统、标准库、命令系统等核心特性。

> **说明**：以下示例展示完整设计愿景，**非 MVP 可运行形态**——其中可能涉及 `Cli.parse`、`Parser.Record.fromJson` 等编译器 Primitive 函数（依赖前端编译 pass 的类型检查后 TypeEnv 内省），以及 `Decimal`/`Validator`/`Task`/`Log`/`Signal`/`Hash`/`Base64`/`Regex` 等推迟到 v0.2+ 的标准库模块（详见 [MVP 定义](../requirements/mvp.md)）。示例旨在演示语言设计的最终形态与典型用法，待对应模块/Primitive 实现后即可运行。

## 文件说明

| 文件 | 用途 |
|------|------|
| [basic.kun](basic.kun) | 基础语法、类型系统、标准库、命令系统综合示例（库模块） |
| [log-analyzer.kun](log-analyzer.kun) | 可执行脚本示例：日志分析器，展示 `main` 入口、Cmd 管道、Stream 处理、模式匹配 |
