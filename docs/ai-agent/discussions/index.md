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
| [命令函数设计](discussion-command-function-design.md) | 结构化输出、exec 移除、runAs 隐式参数、Record 参数、process.exec 完全移除 | 2026-06-02 |
| [CDF→Kun 代码生成设计](discussion-cdf-code-generation.md) | CDF 编译期代码生成、validator/pure/parser 设计、param 语义、option type 直接命名 | 2026-06-03 |
| [行多态与扩展积类型](discussion-row-polymorphism.md) | 行变量与行合一、`{ a \| name : String }` 统一语法、编译期字段展开、无子类型兼容性 | 2026-06-04 |
| [`.cmd.kun` + Builder API 替代 CDF](discussion-cmdkun-replacement.md) | 废弃 CDF，`.cmd.kun` 完全替代方案——全 Kun 语法、Builder API、Landlock 安全、版本化注册中心 | 2026-06-04 |
| [设计审计第二轮确认](discussion-design-review-round2.md) | 12 个审计跟进项（R1-R3 高严重度漏洞确认修复、TOCTOU 缓解方案、subprocess 权限建议） | 2026-06-04 |
