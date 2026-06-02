# 讨论记录

本目录存放需求讨论、设计讨论、技术方案讨论的记录。

## 讨论指南

在发起讨论前，请阅读 [讨论编写指南](00-discussion-writing-guide.md)。

## 讨论记录

| 文件 | 主题 | 日期 |
|------|------|------|
| [类型系统设计决策](discussion-type-system-design-decisions.md) | 6 项核心设计决策（推断/整数/Nat/泛型/效应/子类型）+ Path/Regex 讨论 | 2026-05-28 |
| [语法演进与设计决策](discussion-syntax-evolution.md) | 16 项语法变更的讨论：注释/字面量/泛型/函数/Stream/无参函数/模块等 | 2026-05-30 |
| [异步支持必要性分析](discussion-async-support.md) | MVP 不做异步支持，通过标准库 Task 模块提供组合子式并发 | 2026-05-31 |
| [能力安全系统设计](discussion-capability-design.md) | `with caps` 语法、零默认能力、编译器内置能力对象、二级粒度声明、审查机制 | 2026-06-01 |
| [命令函数设计](discussion-command-function-design.md) | 结构化输出、exec 移除、runAs 隐式参数、Record 参数、process.exec 自动推断 | 2026-06-02 |
