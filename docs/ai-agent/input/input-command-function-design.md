# 输入记录：命令函数系统设计——.cmd.kun 与 Builder API（完整方案）

## 来源

项目维护者

## 日期

2026-06-04

## 状态

✅ 已定型。详见 `design/command-function-system.md`。废弃 CDF 方案（`design/command-signature-system.md`）

## 原始问题

### 1. 现行 CDF 方案的问题

当前命令函数设计通过 CDF（Command Description File）定义命令签名，存在以下问题：

- **两套语言**：Kun + CDF DSL，用户需同时学习
- **声明式局限**：条件逻辑、循环、参数计算等需专用语法（`case` 表达式），表达能力受限
- **安全推导不可靠**：seccomp 规则从参数类型推导，但 seccomp 无法做路径级过滤，推导的"精确性"是伪精确
- **CDF 编译器**：额外的工具链复杂度

### 2. 核心决策：用 Kun 代码 + Builder API 替代 CDF

决定引入 `.cmd.kun` 文件作为命令函数的定义源，用纯 Kun 代码构造命令行，编译器自动封装安全层。

## 设计概要

### 2.1 文件格式

`.cmd.kun` 文件是以 `command` 声明开头、使用 Kun 语法编写命令定义的专用文件。每个文件对应一个主命令（如 `git`、`docker`、`kubectl`），其中所有命令函数共享同一个 `bin`。

### 2.2 文件结构与声明顺序

```kun-cmd
// ① command 声明（文件第一个非注释行）
// with 后紧跟命令名，其需要在 PATH 路径中可被搜索到
command Git with "git" export
  ( git, status, remote_add
  , StatusEntry, CommitEntry )

// ② import（可导入任意非 IO 函数，不可导入其他 .cmd.kun）
import Command with
  ( Command, OutputMode(..)
  , withPath, withOutput, withArg
  , withArgs, withUnsafeArg )
import Stream with (..)
import Parser with (rawText, parseStatusLine, parseLogLine)

// ④ type 定义（可选）
type StatusEntry = { file : Path, status : String }
type CommitEntry = { hash : String, author : String, message : String }

// ⑤ 辅助函数（可选，不导出）
makeBase = \args ->
  withArgs args

// ⑥ 命令函数（导出，以 end 结尾）
status : {} -> Command (Stream StatusEntry)
status = \{} ->
  withOutput (LineStream parseStatusLine)
    |> withPath Path.cwd
    |> makeBase ["status"]

log : { maxCount : ?Int, branch : ?String } -> Command (Stream CommitEntry)
log = \{ maxCount, branch } ->
  withOutput (LineStream parseLogLine)
    |> withPath Path.cwd
    |> withArg "log"
    |> ( case maxCount of
           n -> withFlag "-n" n
           Nil -> identity
       )
    |> ( case branch of
           b -> withArg b
           Nil -> identity
       )

remote : { } -> Command String
remote = \{ } ->
  withOutput rawText
    |> withPath Path.cwd
    |> withArgs ["remote"]

remote_add : { name : String, url : String } -> Command String
remote_add = \{ name, url } ->
  withOutput rawText
    |> withPath Path.cwd
    |> withArgs ["remote", "add", name, url]
    |> withUnsafeArg name
    |> withUnsafeArg url
```

### 2.3 调用方使用

```kun
import Cmd.Git as Git

with caps
  process.run = ["git"]
  fs.read = [Path.cwd]

main =
  do
    entries <-! Git.status {}
    // entries : Stream Git.StatusEntry
    // 编译器已为 Git.status 包裹 run，其实际签名为：
    //   Git.status : {} -> IO (Result (Stream Git.StatusEntry) IOError)
```

### 2.4 Builder API 签名

```kun
module Command export
  ( withArg, withArgs, withFlag, withPath, withUnsafeArg
  , withOutput, withEnv, withRunAs )

// 构造 Command 并确定输出的数据类型
withOutput    : OutputMode a -> Command a
withArg       : Command a -> String -> Command a
withUnsafeArg : Command a -> String -> Command a
withArgs      : Command a -> List String -> Command a
withPath      : Path -> AccessMode -> Command a -> Command a

type Command a =
  { bin : ?String
  , output : OutputMode a
  , runAs : ?RunAs
  , envs : ?Map String String
  }

type OutputMode a
  = LineStream (Stream String -> Result a String)
  | Document (String -> Result a String)

type AccessMode = Read | Write | ReadWrite
```

### 2.5 编译器封装

编译器处理 `.cmd.kun` 时，对每个导出命令函数：

1. 验证返回类型为 `Command (Stream T)` 或 `Command (T)`：即命令组装只能从 `withOutput` 开始
2. 将命令函数重新封装，以通过 `InternalCommand.run` 做安全检查和执行
3. 封装后的命令函数返回类型从 `Command (Stream T)` 提升为 `IO (Result (Stream T) IOError)`
4. 收集所有 `withPath` 调用 → 路径摘要（用于 Landlock）

`InternalCommand` 为 Kun 内部模块，不能被外部调用：

```kun
run : String -> {runAs: ?RunAs, envs: Map String String} -> Command a -> IO (Result a IOError)
run = \bin opts cmd ->
  // 检查 cmd 配置：告警 runAs/envs 被提前赋值，但为了安全将被强制重置
  // 向 cmd 补充 runAs/envs 等字段值（强制覆盖）
  // 对 cmd 做安全控制
  // 拼装 cmd 并执行以得到输出（在审计或调试时，可打印输出拼装的 cmd 字符串）
  // 解析输出，返回解析后的数据
```

> 注意，若有在命令内预配置 env 的情况，则可以放松对 `envs` 的处理，支持合并预置环境变量和用户指定的环境变量，但系统敏感的环境变量需始终排除。
> 
> 完整设计见 `design/command-function-system.md`，包括：Builder API 完整签名、退出码链式设置、审计日志、seccomp 推导、Landlock 路径级安全、自动推导（`kun cmd init`）、签名与注册中心版本化管理、内建 Primitive 覆盖范围、编译期验证规则。

编译后的命令函数等同于：

```kun
// 用户写的
type StatusOptions_ =
  { ...
  }
status_ : StatusOptions_ -> Command (Stream StatusEntry)
status_ = \{} ->
  withOutput (LineStream parseStatusLine)
    |> withArg "status"

// 编译器封装后的等价物
// 在解析 command 模块时从 `command Git with "<bin>"` 中解析 `<bin>` 得到
cmd_bin = "git"

type StatusOptions =
  { StatusOptions_
  | runAs : ?RunAs
  , envs : ?Map String String
  , ...
  }
status : StatusOptions -> IO (Result (Stream StatusEntry) IOError)
status = \{runAs, envs, ..opts} ->
  status_ opts
    |> InternalCommand.run cmd_bin {runAs = runAs, envs = envs}
```

### 2.6 安全栈（run 内部）

```
run(cmd)
  │
  ├─ ① process.run 白名单检查
  │     bin 在 process.run 中？
  │
  ├─ ② capability_check（withPath 收集的路径）
  │     当前 with caps 是否覆盖所有路径？
  │
  ├─ ③ Namespace 配置
  │     PID + Network（按需）
  │
  ├─ ④ seccomp 通用 profile + conditional
  │     从 Builder 链推导：是否写文件？是否网络？是否子进程？
  │
  ├─ ⑤ Landlock（内核 5.13+）
  │     withPath 收集的路径 → 路径级白名单
  │
  └─ ⑥ fork-exec + 输出解析
        → Result (Stream T) IOError
```

## 编译期验证规则（14 条）

| # | 规则 | 违规 |
|---|------|------|
| 1 | `command` 在文件第一个非注释行 | 编译期错误 |
| 2 | `import` 在 `command` 之后 | 编译期错误 |
| 4 | `command Xxx with "<bin>"` 中 `<bin>` 为 basename（不含 `"/"`） | 编译期错误 |
| 7 | 导出命令函数返回 `Command (Stream T)` 或 `Command (T)` | 编译期错误 |
| 8 | 无逃逸 IO（禁止 IO 函数导入和调用，非 IO 函数不做限制） | 编译期错误 |
| 9 | 函数参数透传 `withArg`/`withArgs` 需 `withUnsafeArg` | 编译期警告 |
| 10 | 不可导入其他 `.cmd.kun` | 编译期错误 |
| 11 | `export` 无重复符号 | 编译期错误 |
| 12 | `export` 中的 type 必须在文件内有定义或从外部导入 | 编译期错误 |
| 13 | 隐式字段名不冲突（`runAs`/`envs`/`stdin`/`stdout`/`stderr`/`fd`） | 编译期错误 |

## 与 CDF 方案的关键差异

| 维度 | CDF 方案 | .cmd.kun + Builder 方案 |
|------|---------|------------------------|
| 定义语言 | CDF DSL（独立语法） | Kun 语法 + Builder API |
| 表达能力 | 声明式，有限条件逻辑 | 全 Kun（if/else、case、递归） |
| 工具链 | 需 CDF 编译器 | 复用 Kun 编译器 |
| 安全来源 | 参数类型 → seccomp 推导（伪精确） | capability_check + namespace + 通用 seccomp + Landlock |
| 路径级控制 | seccomp 做不到 | Landlock（内核 5.13+） |
| argv 构造 | 编译期固定 | 编译期已知片段 + 运行时条件片段 |
| 用户输入保护 | validator（值级） | withUnsafeArg 标记（调用级） |
| 学习成本 | 两套语言 | 一套语言 |
| 注册中心 | CDF 文件分发 | .cmd.kun 文件分发 |
