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
- 效应跟踪：AST 标记 + `(a -> b)!` 效应回调标注

### 标准库模块（全部）

Kun v0.1 包含以下全部标准库模块（设计完整，逐模块实现）：

- 基础操作：`Int`、`Float`、`String`、`Bytes`、`Char`、`Regex`、`Function`、`Decimal`
- 哈希与编码：`Hash`、`Base64`
- 数据结构：`List`、`Map`、`Set`、`Result`、`Nil`
- 系统类型：`Signal`、`IOError`、`CommandError`、`DateTime`、`Duration`、`Path`、`Uid`、`Gid`（`Pid`/`ExitCode` 在 `Process` 模块，`File.Type`/`File.Mode`/`File.Stat` 在 `File` 模块）
- IO 与文件：`IO`、`Env`、`File`
- 命令调用：`Cmd`
- 流处理：`Stream`
- 进程与系统：`Process`、`Random`
- 工具：`Cli`（v0.1 仅声明器，parse 推迟 v0.3）、`Validator`、`Parser.JSON`、`Parser.Record`（v0.3）
- 并发：`Task`（v0.4）

### 命令系统

- `Cmd.<bin>` 语法（Record 选项 → camelCase → kebab-case 映射）
- `Cmd.<bin>?` 立即执行 + 返回 `Result`
- `Cmd.exec` 显式执行
- `Cmd.pipe` / `Cmd.pipe?` OS 管道链
- `|>` 管道触发 Command 执行

### 模块系统

- `import` 语法 + 完整搜索路径解析（`~/kun/lib/`、`$KUN_PATH/lib/` 等）

### 运行时

- fork-exec 命令执行 + pipe 捕获 stdout/stderr
- `do` 块顺序执行 + `defer` LIFO 逆序清理
- Stream tagged union 惰性序列

### 工具

- `kun` 脚本执行器


## MVP 不包含（推迟特性）

- CLI 沙箱：`--allow-path` / `--allow-net` / Landlock / seccomp-BPF / mount namespace / network namespace / 环境变量过滤（v0.2）
- `Cli.parse` / `Cli.show`（编译期代码展开 v0.3）
- `Parser.Record.fromJson` / `Parser.Record.toJson`（编译期代码展开 v0.3）
- `Random.*`（需 CSPRNG 系统调用，实现推迟 v0.3；模块签名已在 v0.1 中定义）
- `Hash.md5` / `Hash.md5Hex`（v0.3）
- 类型化命令模块自动发现（`~/.kun/cmd/` — v0.3）
- `Task.spawn` / `Task.all`（并发 v0.4）
- `kun doc` 文档生成（v0.5）
- `Cmd.timeout` / `Cmd.retry` / `Cmd.withRunAs`（v1.0）
- `Signal.on`（需 signalfd 基础设施，v1.0）
- `Test` 模块及 `kun test` 子命令——纯断言函数签名已在标准库中定义但不实现；脚本验证通过直接运行并检查退出码完成（v1.2）
- `Sys.ps` / `Sys.free` / `Sys.df` 已移除——可通过 `Cmd.ps` / `Cmd.free` / `Cmd.df` 替代，故不纳入语言标准库
- `kun-shell` 交互式环境（Kun Shell）——设计已定型，实现在 v2.0 前不启动

## MVP 后优先级（v0.2 → v0.3 → v0.4 → v0.5 → v1.0 → v1.2 → v2.0）

| 版本 | 特性 |
|------|------|
| 0.2.0 | CLI 沙箱（Landlock/seccomp/namespace/--allow-path/--allow-net/环境变量过滤） |
| 0.3.0 | Cli.parse/Cli.show + Parser.Record + Random.* + 类型化命令模块 + Hash.md5 |
| 0.4.0 | Task.spawn/Task.all |
| 0.5.0 | kun doc 文档生成 |
| 1.0.0 | Cmd.timeout/retry/withRunAs + Signal.on + 性能优化 |
| 1.2.0 | Test 模块 + kun test 子命令 |
| 2.0.0 | Kun Shell 交互式环境（表达式求值、类型查询、SQLite/DuckDB 日志存储、函数收藏、AST 哈希） |

## 验证标准

- 能够编写简单的 Kun 脚本替代等价的 Shell 脚本（文件操作 + 命令调用 + 错误处理）
- 类型检查器能捕获类型错误（含效应泄露错误）


## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.23 | 版本路线图重构：模块系统搜索路径提升至 v0.1；CLI 沙箱推迟至 v0.2；Cli.parse/show + Parser.Record + Random.* + 类型化命令模块 + Hash.md5 提升至 v0.3；Task.spawn/all 提升至 v0.4；kun doc 推迟至 v0.5；Test 模块推迟至 v1.2 |
| 2026.06.18 | Kun Shell 从 MVP v0.1 移除，推迟至 v2.0；验证标准同步移除 Kun Shell 条目；v2.0 加入路线图 |
| 2026.06.15 | 跨文档一致性修复：模块系统从"排除"改为"语法启用 + 搜索推迟"（消除与 standard-library.md/system-baseline.md 的设计矛盾）；rlimit 从"不包含"改为"硬编码默认值可用 + CLI 覆盖推迟 0.5.0"；等递归类型描述精确化（别名和泛型 ADT 可用，不求解等递归约束） |
| 2026.06.14 | v3：架构重设计后全面重写——移除 `Nat`/`IO T`/CDF 残留，新增 `!` 效应标记/`Cmd.exec`/`EffectFn`/安全加固/测试框架/分版本路线图 |
| 2026.05.27 | v1：MVP 基础定义（架构重设计前） |
