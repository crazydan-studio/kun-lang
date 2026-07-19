# MVP 定义（v3 — 架构重设计后）

## 最小可行产品范围

Kun 0.1.0 的 MVP 目标是验证架构重设计后的核心语言设计可行性。本文件已从架构重设计前（2026.05.27）更新，反映当前设计定型状态。

## MVP 包含

### 类型系统

- 基础类型：`Int`(i64)、`Float`(f64)、`Bool`、`String`(UTF-8)、`Bytes`、`Char`、`Unit`、`Path`、`Regex`、`Duration`
- 复合类型：Record（积类型）、Tuple、`?T`（Nilable 内置类型构造器）
- 和类型：`Result`、用户自定义 ADT（`type` 声明）
- 穷举检查：对 ADT 和 `Bool` 强制
- 基础类型推断：HM（Hindley-Milner）推断核心
- 效应跟踪：函数类型效应集 `a -> b ! {E}`（代数效应系统，7 个内置效应 `IO`/`File`/`Cmd`/`Random`/`DateTime`/`Signal`/`FFI`，单效应变量 `e`）

### 标准库模块（核心）

Kun v0.1 包含以下标准库模块的类型签名与纯函数实现；部分需系统调用或编译期代码展开的函数推迟实现（见下方「MVP 不包含」）：

- 基础操作：`Int`、`Float`、`String`、`Bytes`、`Char`、`Regex`、`Function`、`Decimal`
- 哈希与编码：`Hash`、`Base64`
- 数据结构：`List`、`Map`、`Set`、`Result`、`Nil`
- 系统类型：`Signal`、`IOError`、`CommandError`、`DateTime`、`Duration`、`Path`、`Uid`、`Gid`（`Pid`/`ExitCode` 在 `Process` 模块，`File.Type`/`File.Mode`/`File.Stat` 在 `File` 模块）
- IO 与文件：`IO`、`Env`、`File`
- 命令调用：`Cmd`
- 流处理：`Stream`
- 进程与系统：`Process`、`Random`
- 工具：`Cli`（v0.1 仅声明器）、`Validator`、`Parser.JSON`、`Parser.Record`
- 并发：`Task`

### 命令系统

- `cmd` 字面量（四段式：命令 / 子命令* / 选项? / 位置参数?，Record 选项 → camelCase → kebab-case 自动映射，字符串键原样）
- `Cmd.exec` 执行丢弃 stdout，失败 panic
- `Cmd.execSafe` 执行返回 `Result (Stream String) CommandError`
- `Cmd.stream` 执行返回 `Stream String`，失败 panic
- `pipe` 纯函数组合 OS 管道链（需配合 `Cmd.exec`/`Cmd.execSafe`/`Cmd.stream` 执行）
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

- CLI 沙箱：`--allow-path` / `--allow-net` / Landlock / seccomp-BPF / mount namespace / network namespace / 环境变量过滤
- `Cli.parse` / `Cli.show`（需编译期代码展开设施）
- `Parser.Record.fromJson` / `Parser.Record.toJson`（需编译期代码展开设施）
- `Random.*`（需 CSPRNG 系统调用；模块签名已在 v0.1 中定义）
- `Hash.md5` / `Hash.md5Hex`
- 类型化命令模块自动发现（`~/.kun/cmd/`）
- `Task.spawn` / `Task.all`（并发）
- `kun doc` 文档生成
- `Cmd.timeout` / `Cmd.retry` / `Cmd.withRunAs`
- `Signal.on`（需 signalfd 基础设施）
- `Test` 模块及 `kun test` 子命令——纯断言函数签名已在标准库中定义但不实现；脚本验证通过直接运行并检查退出码完成
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

