# MVP 定义（v3 — 架构重设计后）

## 最小可行产品范围

Kun 0.1.0 的 MVP 目标是验证架构重设计后的核心语言设计可行性。本文件已从架构重设计前（2026.05.27）更新，反映当前设计定型状态。

## MVP 包含

### 类型系统

- 基础类型：`Int`(i64)、`Float`(f64)、`Bool`、`String`(UTF-8)、`Bytes`、`Char`、`Unit`、`Path`、`Duration`
- 复合类型：Record（积类型）、Tuple、`?T`（Nilable 内置类型构造器）
- 和类型：`Result`、用户自定义 ADT（`type` 声明）
- 穷举检查：对 ADT 和 `Bool` 强制
- 基础类型推断：HM（Hindley-Milner）推断核心
- 效应跟踪：函数类型效应集 `a -> b ! {E}`（效应委派系统，7 个内置效应 `IO`/`File`/`Cmd`/`Random`/`DateTime`/`Signal`/`FFI`，单效应变量 `e`）

### 标准库模块（核心，~20 个）

Kun v0.1 收窄至约 20 个核心标准库模块，聚焦"能替代 Shell 脚本"的最小可行集合。模块的类型签名与纯函数实现均在 v0.1 中提供；部分需系统调用或编译期代码展开的函数推迟实现（见下方「MVP 不包含」）。**收窄原则**：只保留验证核心语言设计（类型系统、效应系统、命令系统、模块系统）所必需的模块；可推迟到 v0.2+ 的非核心模块（如 `Decimal`/`Validator`/`Parser.Record`/`Cli`/`Task`/`Lazy`/`Log`/`Env`/`Process`/`Test`/`Signal`/`Hash`/`Base64`/`Regex`）一律移出 MVP，避免范围蔓延。

- 基础操作：`Int`、`Float`、`String`、`Bytes`、`Char`、`Function`
- 数据结构：`List`、`Map`、`Set`、`Result`、`Nil`
- 系统类型：`IOError`、`CommandError`、`DateTime`、`Duration`、`Path`、`Uid`、`Gid`（`File.Type`/`File.Mode`/`File.Stat` 在 `File` 模块）
- IO 与文件：`IO`、`File`
- 命令调用：`Cmd`
- 流处理：`Stream`
- 随机数：`Random`（模块签名在 v0.1 中定义，实现见「MVP 不包含」）
- JSON 解析：`Parser.JSON`

### 命令系统

- `cmd` 字面量（四段式：命令 / 子命令* / 选项? / 位置参数?，Record 选项 → camelCase → kebab-case 自动映射，字符串键原样）
- `Cmd.exec` eager 执行丢弃 stdout，失败 panic
- `Cmd.execSafe` eager 执行返回 `Result String CommandError`（缓冲 stdout 为 String）
- `Cmd.streamLines` lazy 执行返回 `Stream String`，不报告退出码
- `Cmd.streamBytes` lazy 执行返回 `Stream Bytes`，不报告退出码
- `pipe` 纯函数组合 OS 管道链（需配合 `Cmd.exec`/`Cmd.execSafe`/`Cmd.streamLines`/`Cmd.streamBytes` 执行）
- `|>` 纯管道（不再隐式触发 Command 执行）

### 模块系统

- `import` 语法 + 完整搜索路径解析（`~/kun/lib/`、`$KUN_PATH/lib/` 等）

### 运行时

- fork-exec 命令执行 + pipe 捕获 stdout/stderr
- `let in` / `do` 单表达式统一多语句（立即求值，按声明顺序） + `defer` LIFO 逆序清理
- Stream tagged union 惰性序列

### 工具

- `kun` 脚本执行器


## MVP 不包含

### 推迟到 v0.2+ 的标准库模块

以下标准库模块**整体推迟到 v0.2+**，v0.1 不提供（既不提供签名也不提供实现）：

| 模块 | 推迟理由 |
|---|---|
| `Decimal` | 精确十进制浮点非 MVP 核心，`Float` 已覆盖多数场景；v0.2+ 配合金融/配置场景引入 |
| `Validator` | 依赖 `Parser.Record` 编译期内省；v0.2+ 与 `Parser.Record` 同步引入 |
| `Parser.Record` | 需编译期 Primitive 展开（TypeEnv 内省）；v0.2+ 与 `Cli.parse` 同步引入 |
| `Cli` | `Cli.parse`/`Cli.show` 需编译期 Primitive；v0.2+ 引入完整 `Cli` 模块 |
| `Task` | 并发需运行时调度器（协程/线程池）；v0.2+ 引入 `Task.spawn`/`Task.all` |
| `Lazy` | 显式惰性特区可由 `Stream` 暂时覆盖；v0.2+ 引入独立 `Lazy` 模块 |
| `Log` | 用户效应示例可由用户自行定义；v0.2+ 提供标准 `Log` 模块与 `Log.Mock` |
| `Env` | 环境变量读写非 MVP 核心，可用 `cmd env` 替代；v0.2+ 引入 `Env` 模块 |
| `Process` | 进程管理（pid/exitcode/wait）非 MVP 核心；v0.2+ 引入 `Process` 模块 |
| `Test` | `Test` 效应、`testHandler`、`kun test` 子命令需运行器基础设施；v0.2+ 引入 |
| `Signal` | `Signal.on` 需 signalfd 基础设施；v0.2+ 引入 |
| `Hash` | 哈希函数（md5/sha256 等）非 MVP 核心；v0.2+ 引入（`Hash.md5` 进一步推迟到 v0.3+，因专利考量） |
| `Base64` | 编解码非 MVP 核心；v0.2+ 引入 |
| `Regex` | 正则表达式引擎复杂，非 MVP 核心；v0.2+ 引入（基于 Rust `regex` crate） |

> **类型系统层面保留 `Regex`/`Duration`/`Path` 等基础类型**：上表中 `Regex` 推迟的是**模块**（`Regex.fromString`/`Regex.match` 等函数），但 `Regex` 作为类型在 v0.1 中仍可声明（用于 `cmd` 选项参数类型标注等场景），仅无可调用函数。`Duration`/`Path`/`DateTime` 既是类型也是模块，v0.1 保留完整实现。

### 其他不包含项

- CLI 沙箱：`--allow-path` / `--allow-net` / Landlock / seccomp-BPF / mount namespace / network namespace / 环境变量过滤
- `Cli.parse` / `Cli.show`（需编译期代码展开设施）——`Cli` 模块整体推迟到 v0.2+
- `Parser.Record.fromJson` / `Parser.Record.toJson`（需编译期代码展开设施）——`Parser.Record` 模块整体推迟到 v0.2+
- `Random.*`（需 CSPRNG 系统调用；模块签名已在 v0.1 中定义，但函数实现推迟）
- `Hash.md5` / `Hash.md5Hex`（`Hash` 模块整体推迟到 v0.2+，`md5` 进一步推迟到 v0.3+）
- 类型化命令模块自动发现（`~/.kun/cmd/`）
- `Task.spawn` / `Task.all`（并发）——`Task` 模块整体推迟到 v0.2+
- `kun doc` 文档生成
- `Cmd.timeout` / `Cmd.retry` / `Cmd.withRunAs`
- `Signal.on`（需 signalfd 基础设施）——`Signal` 模块整体推迟到 v0.2+
- `Test` 模块及 `kun test` 子命令——`Test` 模块整体推迟到 v0.2+；脚本验证通过直接运行并检查退出码完成
- `Sys.ps` / `Sys.free` / `Sys.df` 已移除——可通过 `cmd ps {} []` / `cmd free {} []` / `cmd df {} []` 替代，故不纳入语言标准库
- `kun-shell` 交互式环境（Kun Shell）——设计已定型，实现在未来版本中不启动

## 后续优先级

| 特性 |
|------|
| CLI 沙箱（Landlock/seccomp/namespace/--allow-path/--allow-net/环境变量过滤） |
| Cli.parse/Cli.show + Parser.Record + Random.* + 类型化命令模块 + Hash.md5 |
| Task.spawn/Task.all |
| kun doc 文档生成 |
| Cmd.timeout/retry/withRunAs + Signal.on + 性能优化 |
| Test 模块 + kun test 子命令 |
| Kun Shell 交互式环境（表达式求值、类型查询、SQLite/DuckDB 日志存储、函数收藏、AST 哈希） |

## 验证标准

- 能够编写简单的 Kun 脚本替代等价的 Shell 脚本（文件操作 + 命令调用 + 错误处理）
- 类型检查器能捕获类型错误（含效应泄露错误）
