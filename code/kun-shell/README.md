# kun-shell — 交互式 REPL 环境

产出 `kun-shell` 可执行文件，依赖 `libkunlang.so`。

## 职责

提供 Kun 语言的交互式 REPL 环境。用户在终端中直接输入 Kun 表达式、定义函数、导入模块、执行 do 块。支持持久化历史记录、函数收藏、外部编辑器集成。

## 与 kun-lang 的关系

`kun-shell` 链接 `libkunlang.so` 共享解释器核心（词法分析、语法分析、类型检查、效应检查、求值引擎）。自身 CLI 参数解析与 `Cli` 模块共享同一 spec 模型。不重复实现任何语言前端逻辑。

## 内部组织

```
src/
├── main.zig                  # 入口：参数解析 + REPL 启动
├── repl.zig                  # REPL 主循环：读取 → 求值 → 打印
├── line_edit.zig             # 行编辑：光标移动、删除、多行输入
├── completion.zig            # 自动补全：作用域内变量名 / 模块函数名 / 类型
├── highlight.zig             # 语法高亮：关键字、字面量、类型、注释
├── history.zig               # 持久化命令历史（SQLite/DuckDB 存储）
├── favorites.zig             # 函数收藏：AST 哈希 → 收藏库（跨会话复用）
└── editor.zig                # 编辑器集成：:edit / :run 子命令
```

## 核心交互

```
kun-shell> 1 + 2
3 : Int

kun-shell> add = \x y -> x + y
add : Int -> Int -> Int

kun-shell> :type add
Int -> Int -> Int

kun-shell> import List
kun-shell> List.map (\x -> x * 2) [1, 2, 3]
[2, 4, 6] : List Int
```

## 子命令

| 命令 | 用途 |
|------|------|
| `:type <expr>` | 查询表达式类型 |
| `:edit <file>` | 在外部编辑器中编辑 `.kun` 文件 |
| `:run <file>` | 执行 `.kun` 脚本 |
| `:load <module>` | 加载模块（导入到当前环境） |
| `:favorites` | 列出收藏函数 |
| `:save <name>` | 将上一条表达式收藏为命名函数 |

## 持久化存储

- 历史记录：`~/.kun/history.db`（SQLite）
- 函数收藏：`~/.kun/favorites/`（AST 哈希索引）

## 关键约束

- 默认运行在 `--no-sandbox` 模式（交互式环境）
- REPL 每行独立求值，作用域跨行累积
- 多行输入通过缩进或未闭合括号检测
- `defer` 在每条顶层表达式求值后立即执行
