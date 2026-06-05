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

### 文件结构与声明顺序

```kun-cmd
// ① command 声明（文件第一个非注释行）
// with 后紧跟二进制名，需在 PATH 中可被搜索到
command Git with "git" export
  ( log, status, remote_add
  , CommitEntry, StatusEntry )

// ② import（可导入任意非 IO 函数，不可导入其他 .cmd.kun）
import Command with
  ( Command, OutputMode(..)
  , withOutput, withArg, withArgs, withFlag
  , withPath, withUnsafeArg, withEnv
  , exitcode, ExitCodeResult(..) )
import Stream with (..)
import Parser with (rawText, parseLogLine, parseStatusLine)
import Validator with (range, regex, not)

// ④ type 定义（可选，与 export 列表中的类型对应）
type CommitEntry = { hash : String, author : String, message : String }
type StatusEntry = { file : Path, status : String }

// ⑤ 命令函数（导出）
// log 是主示例——用户定义 LogOptions 积类型，编译器自动附加隐式字段
type LogOptions =
  { maxCount : ?Int
  , branch : ?String
  }

log : LogOptions -> Command (Stream CommitEntry)
log = \{ maxCount, branch } ->
  withOutput (LineStream parseLogLine)
    |> withPath Path.cwd Read
    |> withArg "log"
    |> ( case maxCount of
           n -> withFlag "-n" n
           Nil -> identity
       )
    |> ( case branch of
           b -> withArg b
           Nil -> identity
       )

// status 命令（无额外选项）
status : {} -> Command (Stream StatusEntry)
status = \{} ->
  withOutput (LineStream parseStatusLine)
    |> withPath Path.cwd Read
    |> withArgs ["status"]

// remote_add 命令（含用户输入参数）
remote_add : { name : String, url : String } -> Command String
remote_add = \{ name, url } ->
  withOutput rawText
    |> withPath Path.cwd Read
    |> withArgs ["remote", "add", name, url]
    |> withUnsafeArg name
    |> withUnsafeArg url
```

### 调用方使用

```kun
import Cmd.Git as Git

with caps
  process.run = ["git"]
  fs.read = [Path.cwd]

main =
  do
    commits <-! Git.log { maxCount = 50, branch = "main" }
    // commits : Stream Git.CommitEntry
    // Git.log 的实际签名由编译器封装为：
    //   log : LogOptions_ -> IO (Result (Stream CommitEntry) IOError)
    // 其中 LogOptions_ = { LogOptions | runAs : ?RunAs, env : ... }
```

命令函数调用与普通函数调用完全一致。导入什么名字就使用什么名字，没有内置规则或隐式转换。

## Builder API

```kun
module Command export
  ( Command, OutputMode(..)
  , withOutput, withArg, withArgs, withFlag
  , withPath, withUnsafeArg, withEnv, withRunAs
  , exitcode, ExitCodeResult(..) )

// 构造 Command 并确定输出的数据类型
withOutput    : OutputMode a -> Command a

// 追加参数（Safe 标记）
withArg       : Command a -> String -> Command a

// 批量追加参数
withArgs      : Command a -> List String -> Command a

// 追加 flag（自动处理 --flag value 形式）
withFlag      : Command a -> String -> ?String -> Command a

// 追加用户输入参数（Unsafe 标记，编译期警告 + 运行时隔离）
withUnsafeArg : Command a -> String -> Command a

// 声明文件访问路径（用于 Landlock + capability_check）
withPath      : Command a -> Path -> AccessMode -> Command a

// 设置环境变量
withEnv       : Command a -> Map String String -> Command a

// 设置运行用户
withRunAs     : Command a -> RunAs -> Command a

// 设置退出码映射
exitcode      : Command a -> ExitCodeMap -> Command a

type Command a =
  { bin : ?String
  , output : OutputMode a
  , args : List CmdArg
  , paths : List (Path, AccessMode)
  , runAs : ?RunAs
  , env : Map String String
  , exitCodes : ExitCodeMap
  }

type OutputMode a
  = LineStream (Stream String -> a)   // 行流：逐行解析，Parser 仅返回数据类型
  | Document (String -> a)             // 文档：完整输出一次解析，Parser 仅返回数据类型

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

Parser 函数只返回解析后的数据类型，不处理 IO 或 Result：

```kun
// Parser 签名（仅返回解析后的数据类型）
parseLogLine    : String -> CommitEntry                    // 行流：每行解析为一个 CommitEntry
parseStatusLine : String -> StatusEntry                    // 行流：每行解析为一个 StatusEntry
parseJsonDoc    : String -> JsonValue                      // 文档：完整输出解析为 JsonValue

// 内置 OutputMode 便利值（定义在 Parser 模块中）
rawText    : OutputMode String                           // 原始文本（文档模式）
rawLines   : OutputMode (Stream String)                  // 原始行（行流模式）
jsonDoc    : OutputMode JsonValue                        // JSON 文档模式
jsonLines  : OutputMode (Stream JsonValue)               // JSON 行流模式
```

### 退出码处理

退出码映射是 Builder 调用链的一部分，通过 `exitcode` 设置在 `Command` 值中：

```kun
log : LogOptions -> Command (Stream CommitEntry)
log = \{ maxCount, branch } ->
  withOutput (LineStream parseLogLine)
    |> withPath Path.cwd Read
    |> withArg "log"
    |> exitcode
      { 0 = OkResult
      , 1 = OkEmpty          // git log 无匹配时返回 1，输出为空
      , _ = ErrResult "git log failed: exit {code}"
      }
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

1. 验证返回类型为 `Command (Stream T)` 或 `Command T`
2. 收集所有 `withPath` 调用 → 路径摘要（用于 Landlock）
3. 生成完整的 Options Record 类型——通过**扩展积类型**在用户传入的 Options Record 上自动附加隐式字段
4. 将命令函数重新封装，解构隐式字段与用户选项，通过 `InternalCommand.run` 执行
5. `InternalCommand.run` **覆盖** `Command` 上的隐式字段值，防止命令函数内部的注入攻击
6. 封装后返回类型从 `Command (Stream T)` 提升为 `IO (Result (Stream T) IOError)`

### 封装原理

```
用户传入完整选项（含隐式字段 + 用户选项）
  │
  ├── 解构 {runAs, env, stdin, stdout, stderr, fd, ..opts}
  │     ├── 隐式字段 → 传给 withRunAs/withEnv 覆盖 Command
  │     └── 用户选项 opts → 传给原始命令函数
  │
  ▼
原始命令函数使用 opts 构造 Command
  │     (opts 中无 runAs/env 等，无法注入恶意值)
  │
  ▼
withRunAs/withEnv 覆盖 Command 上的隐式字段
  │     (无论命令函数内部怎么设置，最终被覆盖)
  │
  ▼
InternalCommand.run 执行沙箱 + 输出解析
```

### 封装示例：`log` 命令

```kun
// 用户编写 log 命令函数（LogOptions 仅包含用户选项）
type LogOptions =
  { maxCount : ?Int
  , branch : ?String
  }

log : LogOptions -> Command (Stream CommitEntry)
log = \{ maxCount, branch } ->
  withOutput (LineStream parseLogLine)
    |> withArg "log"
    |> ( case maxCount of
           n -> withFlag "-n" n
           Nil -> identity
       )
    |> ( case branch of
           b -> withArg b
           Nil -> identity
       )

// 编译器生成等价代码
cmd_bin = "git"

// 通过扩展积类型生成完整 Options 类型：
//   用户 LogOptions + 隐式字段（runAs/env/stdin/stdout/stderr/fd）
type LogOptions_
  = { LogOptions
  | runAs : ?RunAs
  , env : ?(Map String String)
  , stdin : ?(Fd OrPath)
  , stdout : ?(Fd OrPath)
  , stderr : ?(Fd OrPath OrStdioMode)
  , fd : Map Int FdSpec
  }

// 编译器封装的导出函数
log : LogOptions_ -> IO (Result (Stream CommitEntry) IOError)
log = \{ runAs, env, stdin, stdout, stderr, fd, ..opts } ->
  // opts 是 LogOptions，剥离了隐式字段
  // 传给原始命令函数——opts 中不包含 runAs/env 等，无法注入
  log_ opts
    // 隐式字段在 ExternalCommand.run 内部覆盖 Command 的对应值
    |> withRunAs runAs
    |> withEnv env
    |> InternalCommand.run cmd_bin
```

### 封装示例：`status` 命令（无用户选项）

```kun
// 用户编写（无参数命令）
status : {} -> Command (Stream StatusEntry)
status = \{} ->
  withOutput (LineStream parseStatusLine)
    |> withArg "status"

// 编译器生成
type StatusOptions =
  { runAs : ?RunAs
  , env : ?(Map String String)
  , stdin : ?(Fd OrPath)
  , stdout : ?(Fd OrPath)
  , stderr : ?(Fd OrPath OrStdioMode)
  , fd : Map Int FdSpec
  }

status : StatusOptions -> IO (Result (Stream StatusEntry) IOError)
status = \{ runAs, env, stdin, stdout, stderr, fd } ->
  status_ {}
    |> withRunAs runAs
    |> withEnv env
    |> InternalCommand.run cmd_bin
```

### `InternalCommand.run` 的安全覆盖

`InternalCommand` 是 Kun 内部模块，不能被外部调用。`run` 函数负责最后的安全检查，并在输出解析前强制覆盖 `Command` 上的隐式字段：

```kun
run : String -> Command a -> IO (Result a IOError)
run = \bin cmd ->
  // 1. process.run 白名单检查
  // 2. capability_check（withPath 收集的路径）
  // 3. 强制覆盖隐式字段（防止命令函数内部设置恶意值）
  cmd = cmd
    |> withRunAs (cmd.runAs)     // 用封装层传入的值，忽略命令函数内部分配的值
    |> withEnv (cmd.env)          // 同上
  // 4. Namespace 配置（PID + Network）
  // 5. seccomp 通用 profile + conditional
  // 6. Landlock 路径级白名单
  // 7. fork-exec + 输出解析
  //    解析过程中 Parser 返回的数据类型错误（如 JSON 解析失败）
  //    视为 IOError，与退出码错误统一为 Err Result
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
| 3 | `command Xxx with "<bin>"` 中 `<bin>` 为 basename（不含 `"/"`） | 编译期错误 |
| 4 | 导出命令函数返回 `Command (Stream T)` 或 `Command T` | 编译期错误 |
| 5 | 无逃逸 IO（禁止 IO 函数导入和调用，非 IO 函数不做限制） | 编译期错误 |
| 6 | 函数参数透传 `withArg`/`withArgs` 需 `withUnsafeArg` | 编译期警告 |
| 7 | 不可导入其他 `.cmd.kun` | 编译期错误 |
| 8 | `export` 无重复符号 | 编译期错误 |
| 9 | `export` 中的 type 必须在文件内有定义或从外部导入 | 编译期错误 |
| 10 | 隐式字段名不冲突（`runAs`/`env`/`stdin`/`stdout`/`stderr`/`fd`） | 编译期错误 |

## 内建 Primitive

实现简单、功能单一、有直接内核 API 支持的命令以 Zig 内建实现，编译在运行时二进制中。内建命令与 `.cmd.kun` 命令函数调用方式一致——导入模块名后直接调用函数，调用方不感知实现差异。

### 覆盖范围

| 类别 | 命令 | 映射参数 |
|------|------|---------|
| 文件信息 | `ls` | `path`、`all`、`recursive`、`sortBy` |
| 文件信息 | `stat` | `path` |
| 文件信息 | `du` | `path`、`maxDepth`、`apparentSize` |
| 文件信息 | `df` | `path`、`type` |
| 文件操作 | `cp`/`mv`/`rm`/`mkdir` | 核心参数 + 行为参数 |
| 权限操作 | `chmod`/`chown`/`ln`/`readlink`/`realpath` | 核心参数 + 行为参数 |
| 系统信息 | `ps` | `all`、`user`、`pid` |
| 系统信息 | `free`/`uname`/`uptime`/`lscpu` | 无参数 |
| 内容搜索 | `grep` | `pattern`、`path`、`recursive`、`caseInsensitive`、`invert`、`maxCount` |
| 数据库检索 | `locate` | `pattern` |
| 目录遍历 | `walkDir` | `root`、`depth`、`followSymlinks` |

**不映射**（由标准库覆盖）：`sed`、`awk`、`sort`、`uniq`、`cut`、`tr`、`head`、`tail`、`cat`、`wc`、`tee`、`echo`、`printf`、`xargs`、`which`、`cd`、`sudo`、`su`

### `walkDir` 设计

```kun
type DirEntry = { path : Path, fileType : FileType, size : Int, mtime : DateTime }

walkDir : { root : Path, depth : ?Int
          , followSymlinks : Bool
          , runAs : ?RunAs
           } -> IO (Result (Stream DirEntry) IOError)
```

过滤在外部通过 `filter` 完成：

```kun
walkDir { root = p"/var/log" }
  |> filter (\e -> e.name |> endsWith ".log")
  |> filter (\e -> e.fileType == RegularFile)
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
      ├── command Git with "git" export (...)
      ├── 子命令函数骨架（withOutput rawText + withArgs）
      └── 类型注解（用户需补充）
```

生成的 `.cmd.kun` 是草稿，用户需审核后补充输出解析器（`LineStream`/`Document`）和自定义类型。自动推导是**开发辅助工具**，非运行时通路。

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

编译器通过**扩展积类型**在用户的 Options Record 上自动附加隐式字段。用户定义 `LogOptions = { maxCount : ?Int, branch : ?String }`，编译器生成 `LogOptions_ = { LogOptions | runAs : ?RunAs, ... }`。

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
| `env` | `?Map String String` | 子进程环境变量，缺省继承当前进程环境 |
| `stdin` | `?(Fd OrPath)` | 标准输入来源 |
| `stdout` | `?(Fd OrPath)` | 标准输出目标 |
| `stderr` | `?(Fd OrPath OrStdioMode)` | 标准错误目标 |
| `fd` | `Map Int FdSpec` | 额外文件描述符重定向 |

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
command Git with "git" export
  ( status, log, remote_add
  , StatusEntry, CommitEntry )

module MyModule export
  ( process, processAll
  , Config, Result )
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
