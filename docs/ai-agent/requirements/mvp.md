# MVP 定义（v3 — 架构重设计后）

## 最小可行产品范围

Kun 0.1.0 的 MVP 目标是验证架构重设计后的核心语言设计可行性。本文件已从架构重设计前（2026.05.27）更新，反映当前设计定型状态。

## MVP 包含

### 类型系统

- 基础类型：`Int`(i64)、`Float`(f64)、`Bool`、`String`(UTF-8)、`Bytes`、`Char`、`Unit`、`Path`
- 复合类型：Record（积类型）、Tuple、`?T`（Nilable 内置类型构造器）
- 和类型：`Result`、用户自定义 ADT（`type` 声明）
- 穷举检查：对 ADT 和 `Bool` 强制
- 基础类型推断：HM（Hindley-Milner）推断核心
- 效应跟踪：AST 标记 + `(a -> b)!` 效应回调标注

### 标准库模块（首批）

- `Int`、`Float`、`String`、`Bytes`、`Regex`、`Math`、`Function`
- `List`、`Map`、`Set`、`Result`、`Nil`
- `IO`、`Env`、`File`（含 `mkdir`/`mkdirAll`/`exists`/`readString`/`writeString`/`stat`/`list`/`remove`）
- `Path`、`Duration`、`Stream`
- `Cmd`（含 `Cmd.exec`、`Cmd.<bin>`、`Cmd.<bin>?`、`Cmd.pipe`、`Cmd.pipe?`、`Cmd.which`）
- `Process`（含 `exit`/`pid`/`sleep`）
- `Test`（断言模块：`Test.equal`、`Test.ok`、`Test.panics`）

### 命令系统

- `Cmd.<bin>` 语法（Record 选项 → camelCase → kebab-case 映射）
- `Cmd.<bin>?` 立即执行 + 返回 `Result`
- `Cmd.exec` 显式执行
- `Cmd.pipe` / `Cmd.pipe?` OS 管道链
- `|>` 管道触发 Command 执行

### 运行时

- fork-exec 命令执行 + pipe 捕获 stdout/stderr
- `do` 块顺序执行 + `defer` LIFO 逆序清理
- Stream tagged union 惰性序列

### 安全（基础）

- CLI `--allow-path` 文件系统访问控制
- CLI `--allow-net` 网络访问控制
- Landlock（内核 5.13+）+ network namespace 网络隔离（内核 3.0+）
- `prctl(PR_SET_NO_NEW_PRIVS)` 特权提升防御
- seccomp-BPF 系统调用过滤（含 bpf/perf_event_open/userfaultfd/memfd_create 防御）
- 环境变量安全过滤（含 BASH_FUNC_* 等注入防御）

### 工具

- `kun` 脚本执行器
- `kun-shell` 交互式环境（表达式求值 + `:type`）
- `kun doc` 文档生成
- `kun test` 测试运行器

## MVP 不包含

- 泛型（参数化多态 — 类型构造器 `List a`、`Map k v` 等仍可用）
- 等递归类型（等递归 `type` 别名）— 类型别名和泛型 ADT 仍可用（如 `type Result t e = Ok t | Err e`），但编译器不求解等递归约束
- 模块系统（`import`/`export`）— 语法在 v0.1 中定义并正常解析，标准库模块名在 MVP 中自动可用无需显式 `import`（用户代码中的 `import M` 语句被接受但不触发文件搜索）。User-defined 模块的搜索路径解析、循环依赖检测、缓存失效等完整模块加载机制推迟到 v0.2
- 安全沙箱完整配置 — CLI 参数和 seccomp/Landlock/mount ns 基础层在 v0.1 中运作；`--cpu-limit`/`--mem-limit` rlimit 细粒度 CLI 覆盖推迟到 v0.3（v0.1 使用硬编码默认值：CPU 60s / 内存 512MB / NOFILE 256 / NPROC 32）
- 类型化命令模块自动发现（`~/.kun/cmd/`）
- `kun cmd init` 命令骨架生成
- 预置命令模块
- `Task.spawn` 并发
- `Parser.JSON` / `Parser.Record`
- `Cli` 模块
- `Cmd.withRunAs` / `Cmd.timeout` / `Cmd.retry`
- `Signal.on`/`Sys`/`Random`/`Validator`/`Decimal`

## MVP 后优先级（v0.2 → v0.5 → v1.0）

| 版本 | 特性 |
|------|------|
| v0.2 | 模块系统（`import`/`export`）+ 泛型 + 完整 Stream 组合子（zip/concat/flatMap） |
| v0.3 | rlimit CLI 覆盖（`--cpu-limit`/`--mem-limit`）+ 类型化命令模块 + 完整模块系统激活 |
| v0.5 | `Cli` 模块 + `Parser.*` + `Task.spawn` + 预置命令模块 |
| v1.0 | 完整标准库 + `Cmd.timeout`/`retry`/`withRunAs` + 性能优化 |

## 验证标准

- 能够编写简单的 Kun 脚本替代等价的 Shell 脚本（文件操作 + 命令调用 + 错误处理）
- 类型检查器能捕获类型错误（含效应泄露错误）
- Kun Shell 能交互式执行 Kun 表达式
- `kun test` 能执行测试脚本并报告结果

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.15 | 跨文档一致性修复：模块系统从"排除"改为"语法启用 + 搜索推迟"（消除与 standard-library.md/system-baseline.md 的设计矛盾）；rlimit 从"不包含"改为"硬编码默认值可用 + CLI 覆盖推迟 v0.3"；等递归类型描述精确化（别名和泛型 ADT 可用，不求解等递归约束） |
| 2026.06.14 | v3：架构重设计后全面重写——移除 `Nat`/`IO T`/CDF 残留，新增 `!` 效应标记/`Cmd.exec`/`EffectFn`/安全加固/测试框架/分版本路线图 |
| 2026.05.27 | v1：MVP 基础定义（架构重设计前） |
