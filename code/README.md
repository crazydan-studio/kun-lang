# Kun — 代码仓库

## 模块组织

```
code/
├── README.md          # 本文件
├── examples/          # Kun 语言示例脚本
├── kun-shell/         # 交互式环境（规划中，依赖 libkunlang.so）
└── kun-lsp/           # Language Server Protocol 实现（规划中，依赖 libkunlang.so）
```

> 注：`kun-lang/`（核心语言：编译器 + 运行时 + CLI）的实现已撤销，相关代码已移除。
> 其设计文档仍保留在 `docs/ai-agent/design/` 与 `docs/ai-agent/architecture/` 中。

## 模块关系（设计）

```
┌─────────────┐
│  kun-lsp    │  ← LSP 服务器（编辑器集成）
└──────┬──────┘
┌──────┴──────┐
│  kun-shell  │  ← 交互式 REPL 环境
└──────┬──────┘
┌──────┴──────┐
│  kun-lang   │  ← 核心：libkunlang.so（解释器） + kun（脚本执行器 / fmt / lint / check / doc / cmd init）
└─────────────┘
```

`kun-lang` 产出动态链接库 `libkunlang.so`，供 `kun-shell` 和 `kun-lsp` 链接使用。三者共享同一解释器核心——词法分析、语法分析、类型检查、效应检查、求值引擎不重复实现。

## 相关文档

- 架构基线：`docs/ai-agent/architecture/system-baseline.md`
- 模块边界：`docs/ai-agent/architecture/module-boundaries.md`
- 类型系统：`docs/ai-agent/design/type-system.md`
- 语法设计：`docs/ai-agent/design/syntax.md`
- 标准库：`docs/ai-agent/design/standard-library.md`
- 命令系统：`docs/ai-agent/design/command-system.md`
