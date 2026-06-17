# Kun — 代码仓库

## 模块组织

```
code/
├── README.md          # 本文件
├── kun-lang/          # 核心语言：编译器 + 运行时 + CLI（产出 kun + libkunlang.so）
├── kun-shell/         # 交互式环境（产出 kun-shell，依赖 libkunlang.so）
└── kun-lsp/           # Language Server Protocol 实现（产出 kun-lsp，依赖 libkunlang.so）
```

## 模块关系

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

## 技术栈

| 维度 | 选择 |
|------|------|
| 宿主语言 | Zig 0.17.0-dev |
| 构建系统 | Zig Build System（`build.zig`） |
| 目标平台 | Linux (x86_64) |
| 产物格式 | ELF 可执行文件 + ELF 共享库 |

## 构建

```bash
cd code/kun-lang && zig build          # 构建 kun + libkunlang.so
cd code/kun-shell && zig build         # 构建 kun-shell
cd code/kun-lsp && zig build           # 构建 kun-lsp
```

## 测试

```bash
cd code/kun-lang && zig build test     # 运行核心库单元测试
cd code/kun-shell && zig build test
cd code/kun-lsp && zig build test
```

## 相关文档

- 架构基线：`docs/ai-agent/architecture/system-baseline.md`
- 模块边界：`docs/ai-agent/architecture/module-boundaries.md`
- 类型系统：`docs/ai-agent/design/type-system.md`
- 语法设计：`docs/ai-agent/design/syntax.md`
- 标准库：`docs/ai-agent/design/standard-library.md`
- 命令系统：`docs/ai-agent/design/command-system.md`
