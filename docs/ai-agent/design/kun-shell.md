# Kun Shell

## 定位

Kun Shell 是 Kun 的交互式环境。`kun-shell` 为独立可执行文件，与 `kun` CLI 工具通过动态链接库 `libkun_core.so` 共享解释器核心代码（词法分析、语法分析、类型检查、效应检查、求值引擎）。

启动命令：

```bash
kun-shell
```

Kun Shell 默认运行在 `--no-sandbox` 模式。

## 核心能力

### 表达式与函数

在 Shell 中可直接求值表达式、定义函数和导入模块：

```kun
// 表达式求值
>>> 1 + 2
3 : Int

// 定义函数
>>> add = \x y -> x + y
add : Int -> Int -> Int

>>> add 3 5
8 : Int

// 导入模块
>>> import List

>>> List.map (\x -> x * 2) [1, 2, 3]
[2, 4, 6] : List Int

// 类型查询
>>> :type add
Int -> Int -> Int
```

### 脚本与模块

在 Shell 中可直接编写和运行 `.kun` 脚本及库模块：

```kun
// 编写并运行脚本
>>> :edit /tmp/hello.kun
// 打开编辑器，编写内容后保存：

main : List String -> Unit
main = \_ ->
  do
    IO.println "Hello Kun Shell"

>>> :run /tmp/hello.kun
Hello Kun Shell

// 加载库模块
>>> :load lib/Math.kun
module Math loaded
```

### 交互命令

| 命令 | 说明 |
|------|------|
| `<expr>` | 求值表达式，打印结果与类型 |
| `:type <expr>` | 显示表达式类型 |
| `:edit <path>` | 在编辑器中打开/创建 `.kun` 文件 |
| `:run <path>` | 运行 `.kun` 脚本 |
| `:load <path>` | 加载库模块 |
| `:cmds` | 列出可用的类型化命令模块 |
| `:modules` | 列出已加载的模块 |
| `:funcs` | 列出已定义和收藏的函数 |
| `:history` | 查看命令历史 |
| `:replay <id>` | 回放指定历史记录 |
| `:save <name>` | 收藏当前函数定义 |
| `:exit` / `:quit` | 退出 Shell |
| `Ctrl+D` | 发送 EOF，退出 Shell |

## 日志存储

### SQLite 缺省引擎

Kun Shell 以 SQLite 作为缺省日志存储引擎，结构化记录所有输入和执行结果。

数据库文件路径：`~/.kun/shell/history.db`

表结构：

```sql
-- 命令历史表
CREATE TABLE shell_history (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  TEXT NOT NULL,           -- 会话标识（UUID）
    input       TEXT NOT NULL,           -- 原始输入
    input_hash  TEXT NOT NULL,           -- 输入内容的 SHA-256
    output      TEXT,                    -- 执行结果或错误信息
    output_type TEXT,                    -- ok / error / unit
    duration_ms INTEGER,                 -- 执行耗时（毫秒）
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 收藏函数表
CREATE TABLE shell_funcs (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,           -- 函数名
    signature   TEXT NOT NULL,           -- 类型签名
    source      TEXT NOT NULL,           -- 函数源码
    ast_hash    TEXT NOT NULL UNIQUE,    -- AST 哈希（SHA-256）
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 会话表
CREATE TABLE shell_sessions (
    id          TEXT PRIMARY KEY,        -- UUID
    started_at  TEXT NOT NULL DEFAULT (datetime('now')),
    ended_at    TEXT
);
```

### 历史查看与回放

```bash
# 查看最近 20 条历史
>>> :history

# 回放指定记录
>>> :replay 128

# 搜索历史
>>> :history --search "List.map"
```

每次 Shell 启动创建新会话（`session_id`），历史记录与函数收藏跨会话持久化。

### DuckDB 可替换引擎

Kun Shell 支持以动态链接库方式接入 DuckDB 替换 SQLite：

```bash
# 编译时启用 DuckDB 支持
kun shell --engine duckdb

# 或通过运行时动态加载
>>> :engine duckdb
```

DuckDB 作为可选引擎，提供更强大的分析查询能力，适用于大规模日志分析场景。Kun 运行时通过 `libkun_duckdb.so` 动态链接库加载 DuckDB，加载失败时回退到 SQLite。

## 函数收藏与复用

### 收藏函数

在 Shell 中定义的函数可通过 `:save` 命令持久化收藏：

```kun
>>> formatHost = \host port ->
      f"{host}:{port}"
formatHost : String -> Int -> String

>>> :save formatHost
function 'formatHost' saved
```

### AST 哈希与唯一引用

每个函数的 AST 经过 SHA-256 哈希计算，作为唯一标识存储在 `shell_funcs.ast_hash` 字段中。

输入相同源码的函数产生相同 AST 哈希，Kun Shell 据此实现：

- **去重**：同名函数若 AST 哈希未变，不触发重新保存
- **复用**：多会话中定义相同逻辑的函数共享同一 AST 引用
- **引用完整性**：通过哈希唯一引用避免因函数重命名或源码位置变化导致的引用失效

```kun
// 首次定义 → 编译，哈希存入
>>> add = \x y -> x + y
>>> :save add
function 'add' saved  // ast_hash: a1b2c3...

// 再次定义相同逻辑 → 哈希匹配，不重新编译
>>> add = \x y -> x + y
>>> :save add
function 'add' already saved (hash unchanged)

// 定义不同逻辑 → 新哈希，重新编译
>>> add = \x y z -> x + y + z
>>> :save add
function 'add' updated  // ast_hash: d4e5f6...
```

### 函数复用

收藏的函数可在后续会话中通过函数名直接使用：

```kun
// 新会话中
>>> :funcs
formatHost : String -> Int -> String

>>> formatHost "localhost" 8080
"localhost:8080" : String
```

收藏函数在 Shell 启动时自动从 SQLite 加载，编译后的 AST 缓存到内存中，通过 AST 哈希判断是否需要重新编译。

## 架构

Kun Shell 由以下组件构成，通过 `libkun_core.so` 动态链接库与 `kun` 共享解释器核心：

```
kun-shell 可执行文件
├── 输入处理层    —— 读取用户输入、命令解析、历史补全
├── 求值引擎      —— 通过 libkun_core.so 调用解释器核心
├── 存储层        —— SQLite（缺省）/ DuckDB（可选）日志与收藏
├── 编辑器集成    —— 调用 $EDITOR 进行文件编辑
├── 历史回放      —— 结构化日志查询与重放
└── 函数收藏      —— AST 哈希、唯一引用、跨会话复用

解释器核心（libkun_core.so）
├── 词法分析器
├── 语法分析器
├── 类型检查器
├── 效应检查器
└── 求值引擎
```

`kun-shell` 和 `kun` 均链接 `libkun_core.so`，解释器核心代码编译为单一共享库，避免两份二进制重复内建解释器逻辑。Kun Shell 在解释器核心之上构建交互式界面和持久化能力。

## 与相关文档的关系

| 文档 | 内容 |
|------|------|
| [`kun` CLI 工具](kun-cli-tool.md) | `kun` 与 `kun-shell` 通过 `libkun_core.so` 共享解释器核心 |
| [系统基线](../architecture/system-baseline.md) | 求值引擎与解释器核心的实现 |
| [模块边界](../architecture/module-boundaries.md) | Shell 在架构中的位置与依赖 |
| [语法设计](syntax.md) | Shell 中使用的 Kun 语法 |
| [Standard Library](standard-library.md) | Shell 中可用的标准库模块 |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.13 | Kun Shell 初始设计：替代 REPL，SQLite 日志存储、DuckDB 可替换引擎、函数收藏、AST 哈希唯一引用 |
