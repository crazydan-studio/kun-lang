# 标准库设计

## 设计定位

标准库提供用语言自身表达的实用类型和函数。不同于 `type-system.md` 中编译器固有关联的基础类型，标准库的类型可用 ADT 或 newtype 在语言层面定义，不要求编译器做特殊处理。

## 系统类型

### `Port`

- TCP/UDP 端口号，值域 `0 .. 65535`（u16）
- 独立类型，非 `Int` 子类型
- 通过构造器创建而非字面量：`Port.fromInt 80`（超出范围运行时 Panic）
- 与 `Int` 的互转：`toInt : Port -> Int`、`fromInt : Int -> Port`
- 支持操作：`isPrivileged`（< 1024）、`isRegistered`（1024-49151）、`isDynamic`（49152-65535）
- 语义场景：网络服务端口、防火墙规则、连接目标

### `Pid`

- 进程 ID，值域 `1 .. 2^22-1`（Linux 默认 `pid_max`）
- 独立类型，非 `Int` 子类型
- 通过构造器创建：`Pid.pid 1234`（负数或零→运行时 Panic）
- 支持操作：`toInt : Pid -> Int`、`isInit`（== 1）、`isValid`
- 语义场景：进程管理、服务监督、信号发送

### `Signal`

- POSIX 信号枚举，平台无关的信号抽象

  ```kun
  type Signal
    = SIGINT
    | SIGTERM
    | SIGKILL
    | SIGSTOP
    | SIGHUP
    | SIGQUIT
    | SIGUSR1
    | SIGUSR2
    | SIGCHLD
    | SIGCONT
    | SIGTSTP
    | SIGPIPE
    | SIGALRM
    | SIGABRT
  ```

- 运行时表示为 i32（信号编号），与 C ABI 兼容
- 支持操作：`number : Signal -> Int`、`name : Signal -> String`
- 与 `Int` 互转：`fromInt : Int -> Result Signal String`（非法编号返回 `Err`）、`toInt : Signal -> Int`
- 语义场景：进程信号发送、信号捕获注册、子进程状态变化通知

#### 信号接收

```kun
Signal.on : Signal -> (Signal -> Unit) -> Unit  // 注册信号处理器
```

- `on` 注册信号处理函数，收到信号时执行并传递信号值；前一个处理器被替换
- 回调**必须为 `do` 块**
- `Signal.on` 仅可在可执行脚本（无 `module` 声明的 `.kun` 文件）中使用，**库模块禁止调用**

#### 信号投递机制

信号处理采用 **signalfd** 机制（Linux 3.8+），并非在 OS 信号上下文中直接执行 Kun 代码。事件循环在安全时点读取 signalfd，在事件循环上下文中调用注册的处理函数。

### `Errno`

- POSIX 系统调用错误码枚举

  ```kun
  type Errno
    = ENOENT
    | EACCES
    | EPERM
    | EINTR
    | EIO
    | ENOMEM
    | EBADF
    | EAGAIN
    | EEXIST
    | ENOTDIR
    | EISDIR
    | EINVAL
    | EPIPE
    | EMFILE
    | ENOSPC
    | ESPIPE
    | EROFS
  ```

- 运行时表示为 i32（errno 编号），与 C ABI 兼容
- 支持操作：`message : Errno -> String`、`number : Errno -> Int`
- 与 `Int` 互转：`fromInt : Int -> Result Errno String`、`toInt : Errno -> Int`

### `FileType`

- 文件类型枚举，标记文件系统条目的类型（运行时由 `stat` 确定）

  ```kun
  type FileType
    = RegularFile
    | Directory
    | Symlink
    | Socket
    | Fifo
    | CharacterDevice
    | BlockDevice
    | Unknown
  ```

- `Unknown` 变体用于兜底未预期的文件类型
- 运行时查询函数：`File.stat : Path -> Result FileStat IOError`
- 语义场景：文件操作前的类型检查、目录遍历过滤

### `FileMode`

- 文件权限位抽象，封装 Unix 权限位语义：

  ```kun
  type FileMode = FileMode Int    // 八进制权限位，如 0o755、0o644
  ```

- 构造器参数为八进制权限值（如 `FileMode 0o755`），非法权限位（超出 0o777）编译期报错
- 支持操作：`isReadable`、`isWritable`、`isExecutable`、`isSetuid`、`isSetgid`、`isSticky`、`toInt`
- 语义场景：`stat` 结果权限检查、文件创建模式设置、安全审计

### `FileStat`

- 完整的文件/目录元数据结构，由 `File.stat` 返回：

  ```kun
  type FileStat
    = { size      : Int
      , mtime     : DateTime
      , ctime     : DateTime
      , atime     : DateTime
      , fileType  : FileType
      , mode      : FileMode
      , owner     : Uid
      , group     : Gid
      , ownerName : String
      , groupName : String
      }
  ```

- `owner`/`group` 为数字 ID（`Uid`/`Gid`），源于 `stat` 系统调用的原始返回值
- 运行时查询函数：`File.stat : Path -> Result FileStat IOError`
- 语义场景：文件大小检查、修改时间比较、权限验证、备份筛选

### `IOError`

- 系统调用返回的结构化错误类型

  ```kun
  type IOError
    = NotFound Path
    | PermissionDenied
        { action    : String
        , target    : String
        , reason    : String
        }
    | AlreadyExists Path
    | Unsupported String
    | Other String
  ```

- 与 `Errno` 的关系：`IOError` 是面向用户的语义封装，`Errno` 是底层 POSIX 码
- 转换函数：`toIOError : Errno -> IOError`（将 POSIX 码映射为语义化错误）
- 语义场景：文件操作、网络操作等系统调用的错误报告

### `CommandError`

- 命令执行阶段的语义化错误类型

  ```kun
  type CommandError
    = NotFound String
    | PermissionDenied String
    | CommandFailed { command : String, exitCode : Int, stderr : String }
    | KilledBySignal { command : String, signal : Int, stderr : String }
    | IoError IOError
    | PipeFailed { commands : List String, failedAt : Int, error : CommandError }
  ```

- `Cmd.<bin>?` 和 `Cmd.pipe?` 返回 `Result a CommandError`
- `CommandFailed` 包含命令名、退出码和完整 stderr 输出
- `PipeFailed` 包含管道链中按序的命令名列表和失败位置

### `DateTime`

- 绝对时间点，Unix 纪元以来的纳秒数（i64）
- 通过构造器创建：`Time.now : -> DateTime`（当前系统时间）、`fromUnixSecs : Int -> DateTime`
- 支持操作：`+ Duration -> DateTime`、`- Duration -> DateTime`、`- DateTime -> Duration`
- 字段提取：`year`、`month`、`day`、`hour`、`minute`、`second`
- 格式化和解析：`format : String -> DateTime -> String`（`%` 引导的格式符，详见语法设计）、`parse : String -> String -> Result DateTime String`
- 与 `Duration` 的关系：`DateTime` 是时间轴上的点，`Duration` 是两点之间的间隔
- 语义场景：文件时间戳（`mtime`、`ctime`）、日志记录、调度触发、超时计算

### `ExitCode`

- 进程退出码，值域 `0 .. 255`（u8）
- 独立类型，非 `Int` 子类型
- 语义约定：`0` 表示成功，非零表示失败，`125`-`255` 有特殊含义（与 Shell 惯例对齐）
- 构造器：`ExitCode.ofInt 0`、`ExitCode.ofInt 1`（超出 0-255 范围运行时 Panic）
- 支持操作：`isSuccess : ExitCode -> Bool`（== 0）、`isFailure : ExitCode -> Bool`（≠ 0）、`toInt : ExitCode -> Int`
- 预定义常量：`ExitCode.success`（0）、`ExitCode.generalError`（1）、`ExitCode.commandNotFound`（127）
- 语义场景：命令执行结果判断、进程退出值传递、管道错误传播

### `Path`

- 文件系统路径类型，运行时表示为 `[]u8`（UTF-8 路径切片）
- 内置类型，无需 `import Path` 即可在类型标注中使用，但 `Path` 模块中的函数需导入：

```kun
import Path
```

- 常量和函数：

| 名称 | 类型 | 说明 |
|------|------|------|
| `cwd` | `Path` | 当前工作目录，脚本启动时冻结 |
| `parent` | `Path -> Path` | 父目录路径 |
| `fileName` | `Path -> String` | 文件名（含扩展名） |
| `extension` | `Path -> String` | 文件扩展名 |
| `join` | `Path -> String -> Path` | 拼接路径段 |

```kun
Path.cwd                                          // 当前目录
Path.parent p"/tmp/foo/bar.txt"                   // → p"/tmp/foo"
Path.fileName p"/tmp/foo/bar.txt"                 // → "bar.txt"
Path.extension p"/tmp/foo/bar.txt"                // → ".txt"
Path.join Path.cwd "subdir"                       // → p"<cwd>/subdir"
```

- 语义场景：文件操作路径管理、路径段拼接、父目录定位、文件扩展名提取

### `Uid` / `Gid`

- 用户和组 ID 的数字表示，在需要名称时按需查询

  ```kun
  type Uid = Uid Int       // 用户 ID
  type Gid = Gid Int       // 组 ID
  ```

- 运行时查询函数：`currentUid : -> Uid`、`currentGid : -> Gid`
- 语义场景：文件所有者查询、权限检查、进程运行身份

### `IpAddress`

- IP 地址抽象，支持 IPv4 和 IPv6

  ```kun
  type IpAddress
    = Ipv4 (Int, Int, Int, Int)
    | Ipv6 (Int, Int, Int, Int, Int, Int, Int, Int)
  ```

- 解析和序列化：`parse : String -> Result IpAddress String`、`toString : IpAddress -> String`
- 支持操作：`isLoopback : IpAddress -> Bool`、`isPrivate : IpAddress -> Bool`、`isUnspecified : IpAddress -> Bool`
- 与 `Port` 组合为套接字地址：

  ```kun
  type SocketAddr
    = Tcp IpAddress Port
    | Udp IpAddress Port
  ```

- 语义场景：网络连接配置、防火墙规则、服务监听地址

## `List` — 列表操作

### 定位

`List` 模块提供不可变列表的查询和变换操作。所有函数为纯函数。

### API

```kun
List.length : List a -> Int
List.isEmpty : List a -> Bool
List.head : List a -> ?a
List.last : List a -> ?a
List.get : Int -> List a -> ?a
List.map : (a -> b) -> List a -> List b
List.filter : (a -> Bool) -> List a -> List a
List.filterMap : (a -> ?b) -> List a -> List b
List.fold : (b -> a -> b) -> b -> List a -> b
List.append : List a -> List a -> List a
List.reverse : List a -> List a
```

- `head` 返回首个元素，空列表返回 `Nil`
- `filterMap` 应用函数到每个元素，丢弃返回 `Nil` 的元素，保留非 `Nil` 的值
- `fold` 为左折叠，`fold (+) 0 [1, 2, 3]` → `6`

## `Map` — 映射表操作

### 定位

`Map` 模块提供不可变字典的查询和变换操作。Map 的键类型必须可哈希（`Int`、`String`、`Bool`、`Char` 等）。

### API

```kun
Map.get : String -> Map String a -> ?a
Map.insert : String -> a -> Map String a -> Map String a
Map.fromList : List (String, a) -> Map String a
Map.toList : Map String a -> List (String, a)
Map.keys : Map String a -> List String
Map.values : Map String a -> List a
Map.update : (a -> a) -> String -> Map String a -> Map String a
Map.size : Map String a -> Int
Map.isEmpty : Map String a -> Bool
Map.merge : Map String a -> Map String a -> Map String a
```

- `get` 返回键对应的值，不存在返回 `Nil`
- `insert` 覆写已有键的值
- `update` 对已有值应用变换函数，键不存在时不操作
- `merge` 并集合并，右侧覆盖左侧的相同键

## `Result` — 错误处理组合子

### 定位

`Result t e` 是 Kun 的核心错误处理类型。`Result` 模块提供函数式组合子用于链式处理。

### API

```kun
Result.map : (a -> b) -> Result a e -> Result b e
Result.mapError : (e -> f) -> Result a e -> Result a f
Result.andThen : (a -> Result b e) -> Result a e -> Result b e
Result.withDefault : a -> Result a e -> a
Result.ok : Result a e -> ?a
Result.isOk : Result a e -> Bool
Result.isErr : Result a e -> Bool
```

- `map` — 对 `Ok a` 应用函数，`Err` 不变
- `andThen` — 链式调用，`Ok a` 时传入下一函数，`Err` 短路
- `withDefault` — `Ok` 返回值，`Err` 返回缺省值
- `ok` — 将 `Result` 转为 `?T`，`Err` 对应 `Nil`

## `?T` (Nilable) — 可选值操作

### 定位

`?T` 是 Kun 的内置 Nilable 类型。`case` 和 `??` 提供了基础操作，模块函数提供组合子。

### API

```kun
maybe : a -> ?a -> a                    // Nil 时返回缺省值
mapNil : (a -> b) -> ?a -> ?b           // 非 Nil 时应用函数
orElse : ?a -> ?a -> ?a                  // Nil 时返回备选
toResult : e -> ?a -> Result a e         // Nil 转为 Err
```

- `maybe` 已在 f-string 中广泛使用：`Args.get "verbose" opts |> maybe false identity`
- `mapNil` 相当于 `?T` 上的 `map`
- `orElse` 提供链式备选：`get "a" dict || orElse (get "b" dict)`

## `Args` — 命令行参数解析

### 定位

将 `main` 接收的原始 `List String` 解析为结构化配置，支持命名参数（`--flag` / `-f`）、带值选项（`--key value` / `-k value`）和位置参数。

### 声明器

```kun
Args.flag : String -> Char -> Arg        // 布尔开关
Args.option : String -> Char -> Arg      // 带值选项
Args.positional : Int -> Arg             // 位置参数
```

- `flag`：匹配 `--name` 或 `-c`，类型 `Bool`
- `option`：匹配 `--name value` 或 `-c value`，输出值类型为 `String`
- `positional`：按出现顺序匹配，输出值类型为 `String`

### 解析

```kun
Args.parse : List Arg -> List String -> Result (Map String ArgsValue) String
```

- 返回 `Ok (Map String ArgsValue)` — 参数名到值的映射
- 返回 `Err String` — 解析失败（如未知选项、缺少值）

### 值访问

```kun
Args.get : String -> Map String ArgsValue -> ?ArgsValue
Args.getBool : String -> Map String ArgsValue -> Bool
Args.getString : String -> Map String ArgsValue -> ?String
Args.getPath : String -> Map String ArgsValue -> ?Path
```

### 示例

```kun
import Args

type Config
  = Config { verbose : Bool, output : ?Path, name : ?String }

parseCli : List String -> Result Config String
parseCli = \raw ->
  case Args.parse
    [ Args.flag "verbose" 'v'
    , Args.option "output" 'o'
    , Args.option "name" 'n'
    ] raw of
    Ok opts ->
      Ok (Config
        { verbose = Args.getBool "verbose" opts
        , output  = Args.getPath "output" opts
        , name    = Args.getString "name" opts
        })
    Err msg -> Err msg

main : List String -> Unit
main = \raw ->
  case parseCli raw of
    Ok cfg  -> IO.println f"config: {cfg.verbose} {cfg.output}"
    Err msg -> IO.println msg
```

## `Random` — 随机数

### 定位

提供密码学安全的伪随机数生成器。

### API

```kun
Random.int : Int -> Int -> Int                          // [min, max] 闭区间随机整数
Random.bytes : Int -> Bytes                             // 指定长度的随机字节序列
Random.float : Float                                    // [0, 1) 闭区间随机浮点数
Random.shuffle : List a -> List a                      // Fisher-Yates 洗牌
```

- 语义场景：唯一 ID 生成、端口选择、测试数据、负载分配

## `TempFile` — 临时文件与目录

### 定位

创建临时文件和目录，遵循安全最佳实践（`mkstemp`）。

### API

```kun
TempFile.create : -> Result Path IOError        // 创建临时文件，返回路径
TempDir.create  : -> Result Path IOError        // 创建临时目录，返回路径
```

- 生命周期：临时文件/目录在脚本退出时自动清理
- 语义场景：配置文件生成、中间结果缓存、锁文件、安全的数据交换

## `Stream` — 惰性序列

### 定位

Stream 是惰性拉取序列，元素在消费时按需求值。不绑定 IO，纯构造和 IO 构造均可。

### 纯构造

```kun
Stream.fromList : List t -> Stream t
Stream.range : Int -> Int -> Stream Int
```

- `fromList` — 从 List 构造
- `range start end` — 左闭右开区间 `[start, end)`

### 变换（惰性）

```kun
Stream.map     : (a -> b) -> Stream a -> Stream b
Stream.filter  : (a -> Bool) -> Stream a -> Stream a
Stream.take    : Int -> Stream a -> Stream a
Stream.drop    : Int -> Stream a -> Stream a
Stream.lines   : Stream String -> Stream String     // 按 \n 切分
Stream.parseMap     : (a -> Result b e) -> Stream a -> Stream b          // 跳过失败
Stream.parseMapKeep : (a -> Result b e) -> Stream a -> Stream (Result b e) // 保留 Result
```

变换不触发求值，只构造新的惰性流。

### 消费（终端）

```kun
Stream.toList  : Stream a -> List a                 // 终端
Stream.iter    : (a -> Unit) -> Stream a -> Unit     // 终端
Stream.fold    : (b -> a -> b) -> b -> Stream a -> b // 终端
Stream.string  : Stream String -> String             // 终端：全文收集
Stream.bytes   : Stream a -> Bytes                   // 终端：二进制读取
```

终端操作驱动求值，逐一拉取元素。

### 错误处理辅助

```kun
Stream.filterMap : (a -> ?b) -> Stream a -> Stream b

// Stream.filterMap Result.ok : Stream (Result t e) -> Stream t — 过滤掉所有 Err 元素
```

### 纯/效应操作分类

| 操作 | 类别 | 说明 |
|------|------|------|
| `Stream.map` / `Stream.filter` / `Stream.take` | **纯** | 惰性变换，不触发 IO，纯上下文中可用 |
| `Stream.parseMap` / `Stream.parseMapKeep` | **纯** | 同上 |
| `Stream.lines` | **纯** | 仅标记换行边界，不触发读取 |
| `Stream.toList` / `Stream.iter` / `Stream.fold` | **效应** | 终端操作，触发 pipe 读取 + waitpid，仅 `do` 块可用 |
| `Stream.string` / `Stream.bytes` | **效应** | 终端操作 |
| `Stream.fromList` | **纯** | 从纯 List 构造 Stream，无 IO 绑定 |

## `IO` — 控制台 IO（缺省自动导入）

```kun
IO.print    : String -> Unit
IO.println  : String -> Unit
IO.readln   : -> String
```

## `Env` — 环境变量

```kun
Env.getenv   : String -> ?String
Env.setenv   : String -> String -> Unit
Env.unsetenv : String -> Unit
```

`Env.setenv` 内置拒绝列表——以 `LD_` 开头的变量名始终拒绝设置，与子进程 env 始终剔除列表保持一致。

## `File` — 文件操作（进程内 syscall）

```kun
File.list        : Path -> Result (List Path) IOError
File.readString  : Path -> Result String IOError
File.readBytes   : Path -> Result (Stream Bytes) IOError
File.writeString : Path -> String -> Result Unit IOError
File.writeBytes  : Path -> Stream Bytes -> Result Unit IOError
File.stat        : Path -> Result FileStat IOError
File.touch       : Path -> Result Unit IOError
File.remove      : Path -> Result Unit IOError
File.removeDir   : Path -> Result Unit IOError
```

`File.*` 函数是进程内同步 syscall，始终立即执行、始终返回 `Result`。

## `Cmd` — Command 工具与命令调用

```kun
// Command 构造
Cmd.<bin> : { options }? -> posArgs... -> Command
Cmd.<bin>? : { options }? -> posArgs... -> Result (Stream String) CommandError

// OS 管道链
Cmd.pipe  : List Command -> Command
Cmd.pipe? : List Command -> Result (Stream String) CommandError

// Command 修饰
Cmd.withEnv     : Map String String -> Command -> Command
Cmd.withRawOpt  : String -> ?String -> Command -> Command
Cmd.withStdin   : String -> Command -> Command
Cmd.withStdin   : Stream Bytes -> Command -> Command
Cmd.mergeStderr : Command -> Command

// 工具
Cmd.which   : String -> ?Path
Cmd.timeout : Duration -> Command -> Result (Stream String) CommandError
Cmd.retry   : Int -> Duration -> Command -> Result (Stream String) CommandError
```

## `Time` — 时间与等待

```kun
Time.sleep    : Duration -> Unit
Time.now      : -> DateTime
```

## `Process` — 进程控制

```kun
Process.exit     : Int -> Unit
Process.pid      : -> Pid
```

## `Std` — 通用工具（缺省自动导入）

```kun
Std.cd       : Path -> Unit
Std.cwd      : -> Path
```

逻辑 CWD：`Std.cd` 更新运行时维护的逻辑 CWD。fork 子进程时，在 `exec` 前 `chdir` 到此值。Kun 进程的 OS CWD 始终不变。

## `Sys` — 类型化系统命令（种子生态，syscall 实现）

```kun
Sys.ps     : -> Stream { pid : Pid, cmd : String }
Sys.free   : -> { total : Int, used : Int, free : Int }
Sys.df     : Path -> { fs : String, total : Int, used : Int, avail : Int }
```

`Sys` 仅保留无 OS 命令等价物或 syscall 特有功能——`/proc` 遍历（`ps`）、`sysinfo()`（`free`）、`statfs()`（`df`）。

## `Parser` — 编译期类型安全解析

### `Parser.JSON` — JSON 值类型与字符串互转

```kun
module Parser.JSON export
  ( JsonValue, JsonValue(..)
  , fromString, toString
  )

type JsonValue
  = JsonNull
  | JsonBool Bool
  | JsonNumber Float
  | JsonString String
  | JsonArray (List JsonValue)
  | JsonObject (Map String JsonValue)

fromString : String -> Result JsonValue String
toString : JsonValue -> Result String String
```

### `Parser.Record` — Record 类型安全反序列化

利用 Kun 的 HM 类型系统实现泛型反序列化，目标类型由调用点的变量显式类型声明驱动。编译器在编译期为每个调用点生成特化的序列化/反序列化代码，运行时不依赖类型反射。

```kun
module Parser.Record export (fromJson, toJson)

fromJson : String -> Result a String
toJson : a -> Result String String
```

使用示例：

```kun
import Parser.JSON
import Parser.Record

type Config = { host : String, port : Int, debug : Bool }

main : List String -> Unit
main = \_ ->
  do
    raw = File.readString p"/etc/app/config.json"
    case raw of
      Ok text ->
        parsed : Result Config String
        parsed = Parser.Record.fromJson text
        case parsed of
          Ok cfg ->
            IO.println f"connecting to {cfg.host}:{cfg.port}"
          Err msg ->
            IO.println f"parse error: {msg}"
      Err _ ->
        IO.println "failed to read config"
```

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 0.3.0 | 2026-06-10 | 架构重设计：移除 `IO` 类型标记、`Validator`、`RunAs`；新增 `CommandError`、`Cmd.*`/`Cmd.pipe`/`Cmd.withEnv`/`Cmd.withStdin`/`Cmd.withRawOpt`/`Cmd.mergeStderr`、`Parser.Record`；`Uid`/`Gid` 改为 `Int` newtype；`Signal.on` 移至 `Signal` 模块 |
| 0.1.0 | 2026-05-27 | MVP 基础标准库类型设计定型 |
