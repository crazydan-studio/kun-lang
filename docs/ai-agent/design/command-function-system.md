# 命令函数系统设计

## 定位

命令函数系统是 Kun 将 Linux 命令抽象为类型安全函数的桥梁。核心原则是**映射能力（Capability），而非形式（Form）**。命令函数的本质是**获取结构化结果**，而非执行特定命令。`ls p"/tmp"` 的语义是"获取 /tmp 目录下的文件列表"，而非"执行带有这些参数的 ls"。

命令函数通过 `.cmd.kun` 文件定义，使用纯 Kun 语法 + Builder API 构造命令行参数，由编译器自动封装安全层。

## 架构总览

```
.cmd.kun 文件（用户编写）
  │
  ├── Kun 编译器
  │   ├── 编译期验证（14 条规则）
  │   ├── 生成 Options Record + 隐式字段注入
  │   └── 封装 InternalCommand.run 安全层
  │
  ▼
导入方可直接调用的命令函数（IO (Result T IOError)）
  │
  ├── process.run 白名单检查
  ├── capability_check（路径级）
  ├── Namespace 配置
  ├── seccomp 通用 profile
  ├── Landlock（内核 5.13+）
  └── fork-exec + 输出解析
```

## `.cmd.kun` 文件格式

`.cmd.kun` 文件是以 `command` 声明开头、使用 Kun 语法编写命令定义的专用文件。每个文件对应一个主命令（如 `git`、`docker`、`kubectl`），其中所有命令函数共享同一个 `bin`。

`.cmd.kun` 是面向命令函数提供者的文件格式。提供者编写 `.cmd.kun` 定义命令的签名、参数和输出解析逻辑。使用者（Kun 脚本/模块开发者）导入编译后的命令函数，面对的是编译器生成的类型和签名——两者在使用层面相互独立。

### 文件结构

仅两项硬性约束：
1. `command` 在文件第一个非注释行（标识 `.cmd.kun` 文件类型）
2. `import` 在 `command` 之后、其他定义之前（导入需先解析）

其余部分（类型定义、内部函数、命令函数）可任意排列。Kun 的 HM 类型推断支持前向引用，定义顺序不影响正确性。

### 完整示例

```kun
// command 声明（文件第一个非注释行）
// for 后紧跟二进制名，需在 PATH 中可被搜索到
command Git for "git" export
  ( log, status, remote_add
  , CommitEntry, StatusEntry
  , LogOptions
  )

// import（可导入任意非 IO 函数，不可导入其他 .cmd.kun）
import Command with
  ( Command
  , createStreamCommand, createDocumentCommand
  , withArg, withArgs, withFlag
  , withPath, withUnsafeArg
  )
import Stream with (..)
import Parser with (raw, json)
import Validator with (range, regex, not)

// type 定义
type CommitEntry = { hash : String, author : String, message : String }
type StatusEntry = { file : Path, status : String }

// 内部函数：parseLogLine/parseStatusLine 未在 export 中列出，是内部函数
parseLogLine : String -> Result CommitEntry String

parseStatusLine : String -> Result StatusEntry String

// 导出命令函数：编译器自动附加隐式字段并封装安全层

// log 命令——用户定义 LogOptions 积类型
type LogOptions =
  { maxCount : ?Int
  , branch : ?String
  }

log : LogOptions -> Command Stream CommitEntry
log = \{ maxCount, branch } ->
  createStreamCommand parseLogLine
    |> withPath Path.cwd Read
    |> withArg "log"
    |> (
      case maxCount of
        Nil -> identity
        n -> withFlag "-n" (toString n)
    )
    |> (
      case branch of
        Nil -> identity
        b -> withArg b
    )

// status 命令——无额外选项，使用空 Options Record
// 编译器通过扩展积类型自动注入隐式字段
type StatusOptions =
  {}

status : StatusOptions -> Command Stream StatusEntry
status = \{} ->
  createStreamCommand parseStatusLine
    |> withPath Path.cwd Read
    |> withArgs ["status"]

// remote_add 命令——含用户输入参数（用 withUnsafeArg 标记）
type RemoteAddOptions =
  { name : String
  , url : String
  }

remote_add : RemoteAddOptions -> Command Document String
remote_add = \{ name, url } ->
  createDocumentCommand raw
    |> withPath Path.cwd Read
    |> withArgs ["remote", "add"]
    |> withUnsafeArg name
    |> withUnsafeArg url


### 调用方使用

```kun
import Cmd.Git as Git

with caps
  process.run = ["git"]
  fs.read = [Path.cwd]

main =
  do
    commits <-! Git.log { maxCount = 50, branch = "main" }
    // commits : Stream (Result Git.CommitEntry String)
    // Git.log 的实际签名由编译器封装为：
    //   log : LogOptions -> IO (Result (Stream (Result CommitEntry String)) IOError)
    // 其中 LogOptions = { LogOptions_ | runAs : ?RunAs, env : ... }
    //     LogOptions_ 是在 Git.cmd.kun 中的原始定义
```

命令函数调用与普通函数调用完全一致。导入什么名字就使用什么名字，没有内置规则或隐式转换。

## Builder API

```kun
module Command export
  ( Command            // 仅导出类型名，Record 字段对外不可见
  , Stream, Document   // 幻影类型：标记行流/文档模式
  , ExitCodeResult(..)
  , createDocumentCommand, createStreamCommand
  , withArg, withArgs, withFlag
  , withPath, withUnsafeArg
  , withExitcode
  , InternalCommand    // 编译器封装代码使用，.cmd.kun 不可导入
  )

// 幻影类型——无运行时值，仅用于类型参数标记模式
type Stream
type Document

// 构造文档输出 Command（标记为 Document 模式）
createDocumentCommand : (String -> Result a String) -> Command Document a
createDocumentCommand = \parser ->
  { bin = Nil, parser = parser, args = [], paths = [],
    runAs = Nil, env = Nil, exitCodes = #{} }

// 构造行流输出 Command（标记为 Stream 模式）
createStreamCommand : (String -> Result a String) -> Command Stream a
createStreamCommand = \parser ->
  { bin = Nil, parser = parser, args = [], paths = [],
    runAs = Nil, env = Nil, exitCodes = #{} }

// 追加参数（Safe 标记）
withArg       : String -> Command mode a -> Command mode a

// 批量追加参数
withArgs      : List String -> Command mode a -> Command mode a

// 追加 flag
//   第二个参数为 Nil → 布尔开关（如 --verbose）
//   第二个参数为 String → 带值 flag（如 -n 50）
withFlag      : String -> ?String -> Command mode a -> Command mode a

// 追加用户输入参数（Unsafe 标记，编译期警告 + 运行时隔离）
withUnsafeArg : String -> Command mode a -> Command mode a

// 声明文件访问路径（用于 Landlock + capability_check）
withPath      : Path -> AccessMode -> Command mode a -> Command mode a

// 设置退出码映射
withExitcode  : Int -> ExitCodeResult -> Command mode a -> Command mode a

type Command mode a =
  { bin : ?String
  , parser : String -> Result a String
  , args : List CmdArg
  , paths : List (Path, AccessMode)
  , runAs : ?RunAs
  , env : ?(Map String String)
  , exitCodes : ExitCodeMap
  }

type AccessMode = Read | Write | ReadWrite

type CmdArg
  = Safe String          // 编译期已知参数（如 flag 名）
  | Unsafe String        // 运行时用户输入参数

type ExitCodeMap = Map Int ExitCodeResult

type ExitCodeResult
  = OkResult             // 退出码 N → Ok (Stream T)
  | OkEmpty              // 退出码 N → Ok Stream.empty
  | ErrResult String     // 退出码 N → Err (IOError.Other msg)
```

### 输出预设

Parser 函数只返回解析后的数据类型，不处理 IO：

```kun
// Parser 签名（仅返回解析后的数据类型，直接使用函数类型）
// raw 适用于两种模式（取决于使用的构造器）
raw : s -> Result s String                  // 原始输入保持不变
json : String -> Result JsonValue String    // 转换为 JSON
```

### 退出码处理

退出码映射是 Builder 调用链的一部分，通过 `exitcode` 设置在 `Command` 值中：

```kun
log : LogOptions -> Command Stream CommitEntry
log = \{ maxCount, branch } ->
  createStreamCommand parseLogLine
    |> withPath Path.cwd Read
    |> withArg "log"
    |> withExitcode 0 OkResult
    |> withExitcode 1 OkEmpty    // git log 无匹配时返回 1，输出为空
```

缺省行为（未调用 `exitcode` 时）：
- 退出码 `0` → `Ok (Stream T)`
- 退出码 `≠ 0` → `Err (IOError.Other "command exited with code N")`

运行时处理逻辑：

```
子进程退出，exit code = N
  │
  ├── N 有显式 exitcode 声明？
  │     ├── OkResult → 返回 Ok
  │     ├── OkEmpty → 返回 Ok Stream.empty
  │     └── ErrResult msg → 返回 Err (IOError.Other msg)
  │
  └── N 无声明？
        ├── N == 0 → Ok
        └── N ≠ 0 → Err (IOError.Other "exit N")
```

## 编译器封装

编译器处理 `.cmd.kun` 时，对每个导出命令函数执行以下封装：

1. 验证返回类型为 `Command T`
2. 收集所有 `withPath` 调用 → 路径摘要（用于 Landlock）
3. 生成完整的 Options Record 类型——通过**扩展积类型**在用户传入的 Options Record 上自动附加隐式字段。用户定义 `LogOptions = { maxCount : ?Int, branch : ?String }`，编译器生成 `LogOptions = { LogOptions_ | runAs : ?RunAs, ... }`（对外导出的 `LogOptions` 是扩展后的类型，原始的 `LogOptions_` 被重命名隐藏）
4. 将命令函数重新封装：识别隐式字段 (`runAs`/`env`/`stdin`/`stdout`/`stderr`/`fd`)，通过 `{runAs, ..opts} = cmdOpts` 从调用方传入的完整 Record 中剥离出用户选项 `opts` 传给原始命令函数，隐式字段传给 `InternalCommand.run`
5. `InternalCommand.run` **覆盖** `Command` 上的 bin/runAs/env 值，防止命令函数内部的注入攻击（无论命令函数怎么设置，最终被覆盖）
6. 封装后返回类型从 `Command T` 提升：
   - 行流模式：`IO (Result (Stream (Result T String)) IOError)`——外层 `Result` 表示进程执行结果，内层 `Result` 表示每行解析结果
   - 文档模式：`IO (Result T IOError)`——解析失败映射为 `IOError`

### 封装原理

```
用户传入完整选项（含隐式字段 + 用户选项）
  │
  ├── 解构 {runAs, env, stdin, stdout, stderr, fd, ..opts} = cmdOpts
  │     ├── 用户选项 opts → 传给原始命令函数
  │     └── 隐式字段 cmdOpts → 传给 InternalCommand.run
  │
  ▼
原始命令函数使用 opts 构造 Command
  │     (opts 中无 runAs/env 等，无法注入恶意值)
  │
  ▼
Record 更新覆盖 Command 上的隐式字段
  │     (无论命令函数内部怎么设置，最终被覆盖)
  │
  ▼
InternalCommand.run 执行沙箱 + 输出解析
```

### 封装示例：`log` 命令

用户编写的 log 命令函数：

```kun
command Git for "git" export
  ( LogOptions
  , log
  )

type LogOptions =
  { maxCount : ?Int
  , branch : ?String
  }

log : LogOptions -> Command Stream CommitEntry
log = \{ maxCount, branch } ->
  createStreamCommand parseLogLine
    |> withArg "log"
    |> (
        case maxCount of
          Nil -> identity
          n -> withFlag "-n" (toString n)
      )
    |> (
        case branch of
          Nil -> identity
          b -> withArg b
      )
```

编译器生成等价代码：

```kun
module Git export
  ( LogOptions
  , log
  )

cmd_bin = "git"

// 用户定义的 Options 和函数名均更名补上 _ 作为其后缀
type LogOptions_ =
  { ...  // 与用户定义的结构完全一致
  }
log_ : LogOptions_ -> Command Stream CommitEntry

// 通过扩展积类型生成完整 Options 类型：
//   用户 LogOptions_ + 隐式字段（runAs/env/stdin/stdout/stderr/fd）
type LogOptions
  = { LogOptions_
  | runAs : ?RunAs
  , env : ?(Map String String)
  , stdin : ?OrPath
  , stdout : ?OrPath
  , stderr : ?OrStdioMode
  , fd : ?(Map Int FdSpec)
  }

// 编译器封装的导出函数
// 编译器识别签名中的 Command Stream ... 标记，选择行流处理路径
log : LogOptions -> IO (Result (Stream (Result CommitEntry String)) IOError)
log = \cmdOpts ->
  let
    { runAs, env, stdin, stdout, stderr, fd, ..opts } = cmdOpts
  in
    // opts 是 LogOptions_，剥离了隐式字段
    // 传给原始命令函数——opts 中不包含 runAs/env 等，无法注入
    log_ opts
      // 隐式字段在 InternalCommand.run 内部覆盖 Command 的对应值
      |> InternalCommand.run cmd_bin cmdOpts
```

### `InternalCommand.run` 的安全覆盖

`InternalCommand` 是可被编译器封装代码直接引用的运行时 primitives，但 `.cmd.kun` 无法导入或调用。访问控制通过以下机制共同保障：

1. **编译期规则**：`.cmd.kun` 的 `import` 语句由编译器特殊处理——普通 Kun 模块和 `.cmd.kun` 文件的导入路径是隔离的。`.cmd.kun` 只能导入标准库的纯函数模块，不能导入运行时 primitives 或访问 `InternalCommand`
2. **`Command` 模块导出控制**：`InternalCommand` 虽然列在 `module Command export` 中，但编译器为 `.cmd.kun` 生成的有限导入列表中不包含此符号。`InternalCommand` 的导出仅对编译器生成的封装代码可见
3. **编译器生成的封装代码**：是**编译期产物**，不经过 `.cmd.kun` 的导入检查。编译器处理 `.cmd.kun` 时根据函数返回类型中的 `Command Stream a` 或 `Command Document a`（幻影类型标记）自动选择对应的行流/文档处理路径

`run_` 负责安全检查 + fork-exec，返回原始 stdout 流。编译器根据幻影类型在封装代码中组合 `run_` 与解析逻辑：

```kun
// 内部安全检查与执行（返回原始 stdout 流）
// 幻影类型 mode 使 run_ 对所有模式通用
run_ :
  String
  -> { o
      | runAs : ?RunAs
      , env : ?(Map String String)
      , stdin : ?OrPath
      , stdout : ?OrPath
      , stderr : ?OrStdioMode
      , fd : ?(Map Int FdSpec)
    }
  -> Command mode a
  -> IO (Result (Stream String) IOError)
run_ = \bin opts cmd ->
  // 1. 强制覆盖隐式字段（防止命令函数内部设置恶意值）
  //    opts 中的值来自调用方，命令函数内部分配的值被丢弃
  let
    newCmd =
      { cmd
      | bin = bin
      , runAs = opts.runAs
      , env = opts.env
      }
  in
    // 2. process.run 白名单检查
    // 3. capability_check（withPath 收集的路径）
    // 4. Namespace 配置（PID + Network）
    // 5. seccomp 通用 profile + conditional
    // 6. Landlock 路径级白名单
    // 7. fork-exec → 返回原始 stdout Stream String
```

编译器在封装代码中根据用户签名中的幻影类型选择调用 `InternalCommand.run1`（行流）或 `InternalCommand.run2`（文档）：

```kun
// 行流模式：命令签名含 Command Stream a
// → InternalCommand.run1（逐行解析）
log = \cmdOpts ->
  let { runAs, env, ..opts } = cmdOpts
  in log_ opts
    |> InternalCommand.run1 cmd_bin cmdOpts

// 文档模式：命令签名含 Command Document a
// → InternalCommand.run2（完整收集后一次解析）
remote_add = \cmdOpts ->
  let { runAs, env, ..opts } = cmdOpts
  in remote_add_ opts
    |> InternalCommand.run2 cmd_bin cmdOpts
```

`InternalCommand.run1`/`run2` 封装了 `run_` + 输出解析的逻辑复用（幻影类型保证编译期模式正确性，无需运行时类型检查）：

```kun
// 行流路径：run_ → 逐行解析 → Stream (Result a String)
run1 : String -> { o | ... } -> Command Stream a
   -> IO (Result (Stream (Result a String)) IOError)
run1 = \bin opts cmd ->
  run_ bin opts cmd
    |> IO.flatMap (\result ->
      result |> Result.andThen (\stdout ->
        stdout |> Stream.map cmd.parser |> Ok
      )
    )

// 文档路径：run_ → 完整收集 → 一次解析 → Result a
run2 : String -> { o | ... } -> Command Document a
   -> IO (Result a IOError)
run2 = \bin opts cmd ->
  run_ bin opts cmd
    |> IO.flatMap (\result ->
      result |> Result.andThen (\stdout ->
        stdout
          |> Stream.collect
          |> cmd.parser
          |> mapErr (\msg -> IOError.Other (f"parse failed: {msg}"))
      )
    )
```

## 安全栈

```
InternalCommand.run(cmd, bin)
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
  │     从 Builder 链推导：写文件？网络？子进程？
  │
  ├─ ⑤ Landlock（内核 5.13+）
  │     withPath 收集的路径 → 路径级白名单
  │     预 5.13 内核：跳过 Landlock，依赖 capability_check + namespace
  │
  ├─ ⑥ 审计日志
  │     记录：timestamp, bin, args, exit_code, user, paths, result
  │     拒绝的尝试也写入审计日志（result: "denied"）
  │
  └─ ⑦ fork-exec + 输出解析
        → Result (Stream T) IOError
```

### seccomp 规则推导

seccomp-BPF 过滤规则由命令的 Builder 调用链自动推导：

| Builder 调用 | 允许的系统调用 |
|-------------|--------------|
| `withPath Read` | `openat`、`read`、`pread64`、`fstat`、`close`、`lseek` |
| `withPath Write` | `openat`、`write`、`pwrite64`、`ftruncate`、`fsync`、`close` |
| `withPath ReadWrite` | 文件读写组合 |
| URL/String 类型参数包含网络特征 | `socket`、`connect`、`sendto`、`recvfrom`、`close` |
| 无上述匹配 | `brk`、`mmap`、`munmap`、`exit_group`（仅内存操作） |

### 审计日志

所有命令执行经过 `InternalCommand.run`，自动记录审计日志：

```json
{
  "timestamp": 1717084800000000000,
  "script": "/home/user/deploy.kun",
  "bin": "git",
  "args": ["status"],
  "exit_code": 0,
  "user": "app",
  "paths": ["/repo:read"],
  "result": "allowed"
}
```

审计日志持久化到 `~/.kun/audit/` 目录，定期轮转。拒绝的尝试也记录（`result: "denied"`），确保安全审计可追溯权限探测行为。

## 编译期验证规则

| # | 规则 | 违规 |
|---|------|------|
| 1 | `command` 在文件第一个非注释行 | 编译期错误 |
| 2 | `import` 在 `command` 之后 | 编译期错误 |
| 3 | `command Xxx for "<bin>"` 中 `<bin>` 为 basename（不含 `"/"`） | 编译期错误 |
| 4 | 导出命令函数返回 `Command Stream T` 或 `Command Document T`（须带幻影类型标记） | 编译期错误 |
| 5 | 无逃逸 IO（禁止 IO 函数导入和调用，非 IO 函数不做限制） | 编译期错误 |
| 6 | 函数参数透传 `withArg`/`withArgs` 需 `withUnsafeArg` | 编译期警告 |
| 7 | 不可导入其他 `.cmd.kun`；不可导入 `InternalCommand` | 编译期错误 |
| 8 | `export` 无重复符号 | 编译期错误 |
| 9 | `export` 中的 type 必须在文件内有定义或从外部导入 | 编译期错误 |
| 10 | 隐式字段名不冲突（`runAs`/`env`/`stdin`/`stdout`/`stderr`/`fd`） | 编译期错误 |

## 内建 Primitive

实现简单、功能单一、有直接内核 API 支持的命令以 Zig 内建实现，编译在运行时二进制中。内建命令与 `.cmd.kun` 命令函数调用方式一致——导入模块名后直接调用函数，调用方不感知实现差异。

### 覆盖范围

命令以实现方式分类：

| 类别 | 命令 | 实现方式 | 映射参数 |
|------|------|---------|---------|
| 文件信息 | `ls` | **内建 Primitive** | `path`、`all`、`recursive`、`sortBy` |
| 文件信息 | `stat` | **内建 Primitive** | `path` |
| 文件信息 | `du` | **内建 Primitive** | `path`、`maxDepth`、`apparentSize` |
| 文件信息 | `df` | **内建 Primitive** | `path`、`type` |
| 文件操作 | `cp`/`mv`/`rm`/`mkdir` | **内建 Primitive** | 核心参数 + 行为参数 |
| 权限操作 | `chmod`/`chown`/`ln`/`readlink`/`realpath` | **内建 Primitive** | 核心参数 + 行为参数 |
| 系统信息 | `ps` | **内建 Primitive** | `all`、`user`、`pid` |
| 系统信息 | `free`/`uname`/`uptime`/`lscpu` | **内建 Primitive** | 无参数 |
| 内容搜索 | `grep` | **内建 Primitive** | `pattern`、`path`、`recursive`、`caseInsensitive`、`invert`、`maxCount` |
| 数据库检索 | `locate` | **内建 Primitive** | `pattern` |
| 目录遍历 | `walkDir` | **内建 Primitive** | `root`、`depth`、`followSymlinks` |
| 目录遍历 | `find` | **不映射** | —（`walkDir` + `filter` 覆盖） |
| 归档压缩 | `tar` | **`.cmd.kun`** | `mode`、`archive`、`files`、`compress`、`strip` |
| 压缩 | `gzip`/`xz`/`zstd` | **`.cmd.kun`** | `mode`、`target`、`level` |
| 归档包 | `zip`/`unzip` | **`.cmd.kun`** | `mode`、`archive`、`files`、`password` |
| 网络连接信息 | `ss` | **`.cmd.kun`** | `tcp`、`udp`、`listening`、`process` |
| 网络交互 | `curl`/`wget` | **`.cmd.kun`** | 优先标准库 `Http` 模块 |
| DNS | `dig` | **`.cmd.kun`** | `domain`、`type`、`server` |
| 网络连通性 | `ping` | **`.cmd.kun`** | `host`、`count`、`interval`、`timeout` |
| 远程同步 | `rsync`/`scp` | **`.cmd.kun`** | `source`、`destination`、`recursive`、`compress` |
| 版本控制 | `git` | **`.cmd.kun`** | 子命令各自核心 + 筛选参数 |
| 容器 | `docker` | **`.cmd.kun`** | 子命令各自核心 + 行为参数 |
| 容器编排 | `kubectl` | **`.cmd.kun`** | `resource`、`name`、`namespace`、`label` |

**不映射**（由 Kun 标准库和语言特性覆盖）：`sed`、`awk`、`sort`、`uniq`、`cut`、`tr`、`head`、`tail`、`cat`、`wc`、`tee`、`echo`、`printf`、`xargs`、`which`、`cd`、`sudo`、`su`

### `walkDir` 设计

```kun
type DirEntry =
  { path : Path
  , fileType : FileType
  , size : Int
  , mtime : DateTime
  }

walkDir :
  { root : Path
  , depth : ?Int
  , followSymlinks : Bool
  , runAs : ?RunAs
  }
  -> IO (Result (Stream DirEntry) IOError)
```

过滤在外部通过 `filter` 完成：

```kun
main =
  do
    entries <-! walkDir { root = p"/var/log" }
    entries
      |> filter (\e -> toString e.path |> endsWith ".log")
      |> filter (\e -> e.fileType == RegularFile)
      |> toList
```

## 自动推导（scaffolding）

`kun cmd init <command>` 从命令的 `man`/`--help` 页面自动生成 `.cmd.kun` 骨架：

```
kun cmd init git
  │
  ├── 解析 man git / git --help
  │
  ├── 提取子命令和选项
  │   ├── 结果影响参数 → 保留
  │   ├── 显示格式参数 → 丢弃
  │   └── 内部行为参数 → 丢弃
  │
  ├── 推断参数类型（String/Int/Bool/枚举）
  │
  └── 生成 git.cmd.kun 骨架
      ├── command Git for "git" export (...)
      ├── 子命令函数骨架（createDocumentCommand textDoc + withArgs）
      └── 类型注解（用户需补充）
```

生成的 `.cmd.kun` 是草稿，用户需审核后补充输出解析器（`createStreamCommand`/`createDocumentCommand`）和自定义类型。自动推导是**开发辅助工具**，非运行时通路。

## 签名与注册中心

### 文件位置

```
~/.kun/cmd/<command>/<version>.cmd.kun    # 已安装的 .cmd.kun
~/.kun/cmd/<command>/<version>.sig        # Ed25519 签名
~/.kun/trusted-keys/                       # 信任的公钥
.kun/trusted-keys/                         # 项目级公钥
```

### 注册中心

社区贡献的 `.cmd.kun` 文件通过注册中心分发：

```bash
kun cmd install git@1.28              # 安装指定版本
kun cmd install git                    # 安装最新版本
kun cmd search git                     # 搜索注册中心
kun cmd list                           # 列出已安装的 .cmd.kun
kun cmd publish ./git.cmd.kun          # 发布到注册中心
```

注册中心中的每个包包含：

```
git/
├── git.cmd.kun           # 命令定义
├── git.cmd.kun.sig       # Ed25519 签名
└── metadata.toml         # 版本号、作者、依赖等信息
```

### 信任链

- **内置库**：编译在运行时二进制中的内置 `.cmd.kun`
- **项目级**：`.kun/trusted-keys/` 中的公钥验证签名
- **注册中心**：注册中心验证提交的语法和安全性，用户通过信任的公钥列表验证签名
- **未签名**：未签名的 `.cmd.kun` 仅可用于开发测试，生产环境拒绝加载

### 版本兼容性

`.cmd.kun` 文件的版本由注册中心管理。版本号遵循语义化版本：

```
<major>.<minor>
```

- Major 版本变更：不兼容的 API 变更（参数改变、返回类型改变）
- Minor 版本变更：向后兼容的新命令或参数

## 隐式字段

编译器通过**扩展积类型**在用户的 Options Record 上自动附加隐式字段。编译器将用户定义的类型更名后（如 `LogOptions_ = { maxCount : ?Int, branch : ?String }`），再生成附加了隐式字段的类型，如 `LogOptions = { LogOptions_ | runAs : ?RunAs, ... }`。

对于无参数命令（即用户的 Options Record 为 `{}`），编译器直接生成纯隐式字段类型。

隐式字段列表：

```kun
type FdSpec
  = ReadFromPath Path
  | WriteToPath Path
  | ReadFromStr String
  | InheritFrom Int
  | RedirectTo Int
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `runAs` | `?RunAs` | 执行用户身份，通过 `process.run-as` 能力控制 |
| `env` | `?(Map String String)` | 子进程环境变量，缺省继承当前进程环境 |
| `stdin` | `?OrPath` | 标准输入来源 |
| `stdout` | `?OrPath` | 标准输出目标。`Nil` → 通过管道捕获（默认，用于返回类型解析）；`FdSource n` → 重定向到指定 fd；`PathSource p` → 写入文件 |
| `stderr` | `?OrStdioMode` | 标准错误目标。`Nil` → 继承父进程 stderr（默认）；`Pipe` → 管道捕获；`Inherit` → 显式继承；其余同 `stdout` |
| `fd` | `?(Map Int FdSpec)` | 额外文件描述符重定向，缺省空 Map |

其中 `Fd`、`OrPath`、`OrStdioMode` 类型：

```kun
type Fd = Fd Int

type OrPath
  = FdSource Fd
  | PathSource Path

type OrStdioMode
  = OrPathMode OrPath
  | Pipe
  | Inherit
```

隐式字段的 argv 映射：

```
env    → setenv/pre-exec 注入
stdin  → dup2 重定向
stdout → dup2 重定向
stderr → dup2 重定向
runAs  → setuid 切换
```

## 导出规则

`command` 和 `module` 声明均支持同时导出类型和函数，语法一致：

```kun
// 导出函数 + 类型
command Git for "git" export
  ( status, log, remote_add
  , StatusEntry, CommitEntry
  )

module MyModule export
  ( process, processAll
  , Config, Result
  )
```

类型必须在文件内有定义（`type Xxx = ...`）或从外部导入后再次导出。函数和类型的导出顺序无关——编译器识别符号的种类。

## 与 `run` 的关系

`run""` 语法保留为**最低优先级入口**，用于执行尚未有 `.cmd.kun` 定义的命令：

```kun
run"kubectl" ["get", "pods"]
// → Stream String
// → 受 process.run 白名单控制
// → 有审计日志 + 基础沙箱
```

有 `.cmd.kun` 的命令通过导入的命令函数调用，无需 `run`。`run` 不自动升级——自动推导（`kun cmd init`）是独立的开发辅助工具，不在运行时触发。

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 0.1.0 | 2026-06-04 | 初始设计。废弃 CDF 方案，改用 `.cmd.kun` + Builder API。全 Kun 语法、退出码链式设置、Landlock 安全、`withUnsafeArg` 用户输入保护、注册中心版本化管理 |
