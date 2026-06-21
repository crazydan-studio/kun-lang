# 开发计划

本目录包含项目的执行计划文档。

## 计划编写指南

在编写计划前，请阅读 [计划编写与执行指南](00-plan-authoring-and-execution-guide.md)。

## 计划模板

每个计划应包含：
- **变更范围**：涉及哪些模块和文件
- **实施步骤**：具体的执行步骤
- **验证方法**：如何验证变更正确
- **风险评估**：可能的风险和缓解措施

## 执行计划

| 文件 | 主题 | 状态 |
|------|------|------|
| [类型系统核心设计](plan-type-system-core-design.md) | 类型系统设计 + 标准库 + 语法设计 + 文档同步 | 已完成 |
| [能力安全系统重新设计](plan-capability-redesign.md) | 能力声明语法、零默认能力、二级粒度、CDF 移除能力 | 已完成（事后补写） |
| [CDF 能力导向重构](plan-cdf-capability-refactor.md) | CDF 格式重构、能力参数建模、安全层对齐 | 已完成 |
| [CDF 类型层与架构层修复](plan-cdf-type-and-arch-fixes.md) | CmdResult 定义、错误类型一致、process.exec 移除 | 已完成 |
| [运行时架构设计](plan-runtime-architecture.md) | 运行时生命周期、执行模型、模块边界 | 已完成 |
| [语法全面调整](plan-syntax-overhaul.md) | 20 项语法变更、15 个文件同步 | 已完成 |
| [标准库内置函数绑定机制设计](plan-stdlib-builtin-binding.md) | Primitive 函数表、模块绑定规则、安全防护、逐函数实现类别标注 | 已完成 |
| [错误消息国际化（i18n）子系统设计](plan-i18n.md) | msgid 体系、.po 管理、构建时代码生成、locale 检测、消息格式化 API | 进行中 |
| [首阶段实现 — 骨架 + Lexer + Parser + AST](plan-implementation-phase-1.md) | build.zig + 词法分析器 + AST + 语法分析器 + CLI dump-ast | 已完成 |
| [Phase 2 — 类型检查器 + 运行时求值器 MVP](plan-implementation-phase-2.md) | HM 类型推断 + 效应检查 + 模式穷举 + 标记 switch 求值器 | 未审计 |
