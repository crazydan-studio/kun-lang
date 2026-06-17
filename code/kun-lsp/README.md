# kun-lsp — Language Server Protocol 实现

产出 `kun-lsp` 可执行文件，依赖 `libkunlang.so`。

## 职责

实现 [Language Server Protocol (LSP) 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/) 规范。编辑器（VSCode / Neovim / Helix / Emacs）通过标准输入/输出 JSON-RPC 2.0 与本服务器通信，获得实时类型检查、自动补全、跳转定义等 IDE 功能。

## 与 kun-lang 的关系

`kun-lsp` 链接 `libkunlang.so` 共享解释器核心。不重新实现语言前端。LSP 服务器维护工作区中的文件索引，在每个文件变更时调用 `libkunlang.so` 的词法分析 + 语法分析 + 类型检查管线，将结果转换为 LSP 诊断消息。

## 内部组织

```
src/
├── main.zig                  # 入口：命令行参数 → 启动 LSP 服务器
├── server.zig                # LSP 服务器生命周期：initialize / shutdown / exit
├── transport.zig             # JSON-RPC 2.0 传输层：stdio / TCP socket
├── handler.zig               # 请求与通知分发（switch dispatch）
├── diagnostics.zig           # 诊断推送：类型错误 → textDocument/publishDiagnostics
├── completion.zig            # 自动补全：textDocument/completion
├── hover.zig                 # 类型悬停：textDocument/hover（显示类型签名与文档）
├── goto_def.zig              # 跳转定义：textDocument/definition
├── symbols.zig               # 文档符号：textDocument/documentSymbol + workspace/symbol
├── formatting.zig            # 格式化：textDocument/formatting（调用 kun fmt）
└── workspace.zig             # 工作区管理：文件索引、增量更新、import 依赖图
```

## 支持的功能

| LSP 方法 | 实现状态 |
|----------|:--:|
| `initialize` / `shutdown` / `exit` | 设计 |
| `textDocument/didOpen` / `didChange` / `didClose` | 设计 |
| `textDocument/publishDiagnostics` | 设计（类型错误 + 效应违规） |
| `textDocument/completion` | 设计（作用域变量 / 模块函数 / 关键字 / ADT 变体） |
| `textDocument/hover` | 设计（类型签名 + doc 注释） |
| `textDocument/definition` | 设计（变量定义 / 函数定义 / 模块导入） |
| `textDocument/formatting` | 设计（委托 `kun fmt`） |
| `textDocument/documentSymbol` | 设计 |
| `workspace/didChangeWatchedFiles` | 设计 |
| semantic tokens | 未计划 |

## 关键约束

- 工作区文件索引增量更新（不重解析未变更文件）
- 诊断推送去抖（debounce），默认 300ms 延迟
- 类型检查失败时仍提供部分结果（已成功的绑定仍可补全/悬停）
- 通过 `libkunlang.so` 调用 `kun fmt` 的格式化引擎（非进程 fork）
- 支持多工作区文件夹（multi-root workspace）
