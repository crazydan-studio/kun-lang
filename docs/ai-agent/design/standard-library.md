# 标准库设计

## 设计定位

标准库提供用语言自身表达的实用类型和函数。不同于 `type-system.md` 中编译器固有关联的基础类型，标准库的类型可用 ADT 或 newtype 在语言层面定义，不要求编译器做特殊处理。

## 系统类型

### `Port`

- TCP/UDP 端口号，值域 `0 .. 65535`（u16）
- 独立类型，非 `Nat`/`Int` 子类型
- 通过构造器创建而非字面量：`Port.fromInt 80`、`Port.port 80`（超出范围运行时 Panic）
- 与 `Int`/`Nat` 的互转：`toInt : Port -> Int`、`fromInt : Int -> Port`
- 支持操作：`isPrivileged`（< 1024）、`isRegistered`（1024-49151）、`isDynamic`（49152-65535）
- 语义场景：网络服务端口、防火墙规则、连接目标

### `Pid`

- 进程 ID，值域 `1 .. 2^22-1`（Linux 默认 `pid_max`）
- 独立类型，非 `Nat`/`Int` 子类型
- 通过构造器创建：`Pid.pid 1234`（负数或零→运行时 Panic）
- 支持操作：`toInt : Pid -> Int`、`isInit`（== 1）、`isValid`
- 语义场景：进程管理（`kill`、`wait`）、服务监督、信号发送

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
- 语义场景：进程信号发送（`kill`）、信号捕获注册、子进程状态变化通知

#### 信号接收

```kun
on      : Signal -> (Signal -> IO Unit) -> IO Unit  // 注册信号处理器
ignore  : Signal -> IO Unit                          // 忽略指定信号
default : Signal -> IO Unit                          // 恢复默认行为
```

- `on` 注册信号处理函数，收到信号时执行并传递信号值；前一个处理器被替换
- 处理函数接收信号参数（`Signal -> IO Unit`），可用于区分不同信号
- `ignore` 设置 SIG_IGN，`default` 恢复 SIG_DFL

#### 信号投递机制

信号处理采用 **signalfd** 机制（Linux 3.8+），并非在 OS 信号上下文中直接执行 Kun 代码：

1. 进程收到信号时，OS 将信号写入 signalfd 文件描述符
2. Kun 的事件循环在安全时点读取 signalfd，取出待处理信号
3. 在事件循环上下文中调用注册的处理函数

这保证了：
- 处理函数不运行在信号处理上下文中——可执行任意 IO 操作，无需 async-signal-safe 约束
- 信号不会中断关键操作（内存分配、类型检查等）
- 多个信号按接收顺序排队处理

- 典型场景：`Signal.on SIGINT (\sig -> print f"caught {sig}")`、`Signal.ignore SIGPIPE`
- 语义场景：优雅关闭（SIGTERM/SIGINT）、子进程回收（SIGCHLD）、超时处理（SIGALRM）

### `Errno`

- POSIX 系统调用错误码枚举

  ```kun
  type Errno
    = ENOENT     // No such file or directory
    | EACCES     // Permission denied
    | EPERM      // Operation not permitted
    | EINTR      // Interrupted system call
    | EIO        // I/O error
    | ENOMEM     // Out of memory
    | EBADF      // Bad file descriptor
    | EAGAIN     // Resource temporarily unavailable
    | EEXIST     // File exists
    | ENOTDIR    // Not a directory
    | EISDIR     // Is a directory
    | EINVAL     // Invalid argument
    | EPIPE      // Broken pipe
    | EMFILE     // Too many open files
    | ENOSPC     // No space left on device
    | ESPIPE     // Illegal seek
    | EROFS      // Read-only file system
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
- 运行时查询函数：`fileType : Path -> IO (Result FileType IOError)`
- 语义场景：文件操作前的类型检查、目录遍历过滤

### `FileMode`

- 文件权限位抽象，封装 Unix 权限位语义：

  ```kun
  type FileMode = FileMode Int    // 八进制权限位，如 0o755、0o644
  ```

- 构造器参数为八进制权限值（如 `FileMode 0o755`），非法权限位（超出 0o777）编译期报错
- 支持操作：
  | 函数 | 语义 |
  |------|------|
  | `isReadable : FileMode -> Bool` | 所有者可读 |
  | `isWritable : FileMode -> Bool` | 所有者可写 |
  | `isExecutable : FileMode -> Bool` | 所有者可执行 |
  | `isSetuid : FileMode -> Bool` | 设置 setuid 位 |
  | `isSetgid : FileMode -> Bool` | 设置 setgid 位 |
  | `isSticky : FileMode -> Bool` | 设置 sticky 位 |
  | `toInt : FileMode -> Int` | 转为 `Int`（用于 `chmod` 等外部命令） |
- 语义场景：`stat` 结果权限检查、文件创建模式设置、安全审计

### `FileStat`

- 完整的文件/目录元数据结构，由 `stat` 系统调用返回：

  ```kun
  type FileStat
    = { size      : Int       // 字节大小
      , mtime     : DateTime  // 最后修改时间
      , ctime     : DateTime  // 元数据变更时间
      , atime     : DateTime  // 最后访问时间
      , fileType  : FileType  // 文件类型
      , mode      : FileMode  // 权限位
      , owner     : Uid       // 所有者数字 ID（UID）
      , group     : Gid       // 所属组数字 ID（GID）
      , ownerName : String    // 所有者名称（便利字段，可能为空）
      , groupName : String    // 所属组名称（便利字段，可能为空）
      }
  ```

- `owner`/`group` 为数字 ID（`Uid`/`Gid`），源于 `stat` 系统调用的原始返回值。`ownerName`/`groupName` 通过 `getpwuid`/`getgrgid` 查询（查找失败则为空字符串，不影响 `stat` 本身成功）
- 运行时查询函数：`stat : Path -> IO (Result FileStat IOError)`、`lstat : Path -> IO (Result FileStat IOError)`
- `stat` 跟随符号链接，`lstat` 返回符号链接自身信息
- 语义场景：文件大小检查、修改时间比较、权限验证、备份筛选

### `DirEntry`

- 目录树遍历的返回条目，由内建 `walkDir` 函数生成：

  ```kun
  type DirEntry
    = { path     : Path     // 完整路径
      , fileType : FileType // 文件类型
      , size     : Int      // 字节大小
      , mtime    : DateTime // 最后修改时间
      }
  ```

- `walkDir` 只负责遍历，过滤在外部通过 `filter` + lambda 表达，无需系统 `find` 的 `-name -type -size` 语法：

  ```kun
  main =
    do
      entries <-! walkDir { root = p"/var/log" }
      entries
        |> filter (\e -> toString e.path |> endsWith ".log")
        |> filter (\e -> e.fileType == RegularFile)
        |> toList
  ```

### `IOError`

- 系统调用返回的结构化错误类型

  ```kun
  type IOError
    = NotFound Path
    | PermissionDenied Path
    | AlreadyExists Path
    | Unsupported String
    | CommandFailed { command : String, exitCode : Int, stderr : String }
    | Other String
  ```

- 与 `Errno` 的关系：`IOError` 是面向用户的语义封装，`Errno` 是底层 POSIX 码
- 转换函数：`toIOError : Errno -> IOError`（将 POSIX 码映射为语义化错误）
- 语义场景：文件操作、网络操作、进程管理等系统调用的错误报告
- `CommandFailed` 用于命令函数（`.cmd.kun`/`run`）的执行失败，包含命令名、退出码和 stderr 输出

### `DateTime`

- 绝对时间点，Unix 纪元以来的纳秒数（i64）
- 通过构造器创建：`now : IO DateTime`（当前系统时间）、`fromUnixSecs : Int -> DateTime`
- 支持操作：`+ Duration -> DateTime`、`- Duration -> DateTime`、`- DateTime -> Duration`
- 字段提取：`year : DateTime -> Int`、`month : DateTime -> Int`、`day : DateTime -> Int`、`hour : DateTime -> Int`、`minute : DateTime -> Int`、`second : DateTime -> Int`
- 格式化和解析：`format : String -> DateTime -> String`（`%` 引导的格式符，详见语法设计）、`parse : String -> String -> Result DateTime String`
- 与 `Duration` 的关系：`DateTime` 是时间轴上的点，`Duration` 是两点之间的间隔
- 语义场景：文件时间戳（`mtime`、`ctime`）、日志记录、调度触发、超时计算

#### `sleep` / 定时器

- `sleep : Duration -> IO Unit` — 阻塞当前协程指定时长
- `sleepUntil : DateTime -> IO Unit` — 阻塞直到指定绝对时间点
- `Signal.setTimeout : Duration -> IO (Result SignalId IOError)` — 创建一次性定时器，超时后触发指定信号
- `Signal.setInterval : Duration -> IO (Result SignalId IOError)` — 创建周期性定时器，每个周期触发指定信号
- `Signal.clearTimer : SignalId -> IO Unit` — 取消定时器
- 语义场景：轮询等待、速率限制、定时任务间隔、超时控制
- 底层机制：基于 `timerfd_create`（Linux 3.8+），定时器信号通过 signalfd 与其他信号统一排队
- 生命周期：定时器与当前能力作用域绑定——超出作用域时自动取消。脚本退出时全部清理
- `sleep` 期间信号通过 signalfd 机制正常处理，可通过 `Signal.on` 中断等待

### `ExitCode`

- 进程退出码，值域 `0 .. 255`（u8）
- 独立类型，非 `Int`/`Nat` 子类型
- 语义约定：`0` 表示成功，非零表示失败，`125`-`255` 有特殊含义（与 Shell 惯例对齐）
- 构造器：`ExitCode.ofInt 0`、`ExitCode.ofInt 1`（超出 0-255 范围运行时 Panic）
- 支持操作：`isSuccess : ExitCode -> Bool`（== 0）、`isFailure : ExitCode -> Bool`（≠ 0）、`toInt : ExitCode -> Int`
- 预定义常量：`ExitCode.success`（0）、`ExitCode.generalError`（1）、`ExitCode.commandNotFound`（127）
- 脚本退出码：`main : IO Unit` 隐式返回 `ExitCode.success`（0），`main : IO ExitCode` 允许脚本自定义退出码。未处理的 `Err` 传播到顶层时自动以 `ExitCode.generalError`（1）退出
- 语义场景：命令执行结果判断、进程退出值传递、管道错误传播、脚本自定义退出码

### `Uid` / `Gid`

- 用户和组 ID 的数字表示，在需要名称时按需查询

  ```kun
  type Uid = Uid Nat       // 用户 ID（0..2^32-1）
  type Gid = Gid Nat       // 组 ID（0..2^32-1）
  ```

- 运行时查询函数：`currentUid : IO Uid`、`currentGid : IO Gid`
- ID 与名称互查（运行时通过 `getpwuid`/`getgrgid` 查询，查不到时返回 `Err`）：
  `lookupName : Uid -> IO (Result String String)`、`lookupUid : String -> IO (Result Uid String)`
  `lookupGroupName : Gid -> IO (Result String String)`、`lookupGid : String -> IO (Result Gid String)`
- 语义场景：文件所有者查询、权限检查、进程运行身份

### `RunAs`

- 命令函数 `runAs` 参数的类型，支持用户名和 ID 两种形式：

  ```kun
  type RunAs
    = ByName String   // 用户名（如 "root"）
    | ById Nat        // 用户 ID（如 0）
  ```

- `process.run-as` 能力的目标为此类型：

  ```kun
  with caps
    process.run-as = [ByName "root", ById 1000]

  main =
    do
      ls { runAs = ByName "nobody" }   // ✅ 按用户名
      ls { runAs = ById 65534 }         // ✅ 按 UID
      ls { runAs = Nil }                // ✅ 缺省当前用户
  ```

### `IpAddress`

- IP 地址抽象，支持 IPv4 和 IPv6

  ```kun
  type IpAddress
    = Ipv4 (Nat, Nat, Nat, Nat)                                      // each 0-255
    | Ipv6 (Nat, Nat, Nat, Nat, Nat, Nat, Nat, Nat)    // each 0-65535
  ```

- 解析和序列化：`parse : String -> Result IpAddress String`、`toString : IpAddress -> String`
- 支持操作：`isLoopback : IpAddress -> Bool`、`isPrivate : IpAddress -> Bool`、`isUnspecified : IpAddress -> Bool`
- 与 `Port` 组合为套接字地址

  ```kun
  type SocketAddr
    = Tcp IpAddress Port
    | Udp IpAddress Port
  ```

- 语义场景：网络连接配置、防火墙规则、服务监听地址

## `Validator` — 参数验证器

### 定位

命令函数参数运行时验证的统一类型。验证器将值转换为 `Result`，验证失败时返回错误原因。

### 类型

```kun
type Validator t = t -> Result t String   // Ok 原值 或 Err 原因
```

### 内置验证器

```kun
range   : Int -> Int -> Validator Int        // 值在 [min, max]
include : List t -> Validator t              // 值在列表中（白名单）
exclude : List t -> Validator t              // 值不在列表中（黑名单）
length  : Int -> Int -> Validator String     // 字符串长度 [min, max]
regex   : Regex -> Validator String          // 匹配正则，参数为 Regex 字面量
```

### 组合器

```kun
all : List (Validator t) -> Validator t    // 所有通过（AND）
any : List (Validator t) -> Validator t    // 任一通过（OR）
not : Validator t -> Validator t           // 取反
```

### 自定义验证器

任何符合 `Validator t` 签名的**纯函数**（无 IO）均可作为验证器。验证器只能对值本身做校验——不能涉及文件系统、网络等 IO 操作：

```kun
// ✅ 正确：纯校验，不涉及 IO
nameCheck : Validator String
nameCheck = all [length 1 255, regex r"^[a-zA-Z]+$"]

// ❌ 错误：涉及 IO（文件存在性检查），不能作为验证器
fileExists : Validator Path = ...
```

```kun
myPortValidator : Validator Int
myPortValidator = \port ->
  if port >= 1 && port <= 65535 && port /= 666 then
    Ok port
  else
    Err "port must be 1-65535 and not 666"

// 组合使用
portCheck = all [range 1 65535, not (\p -> p == 666)]
```

### 命令函数中使用

```kun
// Validator 在命令函数的 Builder 链中集成
// 在 .cmd.kun 中调用 validator 进行参数校验
// portCheck : Validator Int
// nameCheck : Validator String
```

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
Map.size : Map String a -> Nat
Map.isEmpty : Map String a -> Bool
Map.merge : Map String a -> Map String a -> Map String a
```

- `get` 返回键对应的值，不存在返回 `Nil`
- `insert` 覆写已有键的值
- `update` 对已有值应用变换函数，键不存在时不操作
- `merge` 并集合并，右侧覆盖左侧的相同键

## `Result` — 错误处理组合子

### 定位

`Result t e` 是 Kun 的核心错误处理类型。`=!`/`<-!` 操作符提供了模式匹配的简化语法，`Result` 模块提供函数式组合子用于链式处理。

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

- `maybe` 已在 f-string 中广泛使用：`Args.get "verbose" opts \|> maybe false identity`
- `mapNil` 相当于 `?T` 上的 `map`
- `orElse` 提供链式备选：`get "a" dict \|\| orElse (get "b" dict)`

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
        { verbose = Args.getBool "verbose" opts || Args.getBool "v" opts
        , output  = Args.getPath "output" opts
        , name    = Args.getString "name" opts
        })
    Err msg -> Err msg

main : List String -> IO Unit
main = \raw ->
  case parseCli raw of
    Ok cfg  -> print f"config: {cfg.verbose} {cfg.output}"
    Err msg -> print msg
```

### 启用命令示例

```
kun script.kun --verbose -o /tmp/out --name hello
kun script.kun -v --output /tmp/out
kun script.kun -v
```

## `Random` — 随机数

### 定位

提供密码学安全的伪随机数生成器。

### API

```kun
Random.int : Int -> Int -> IO Int                    // [min, max] 闭区间随机整数
Random.bytes : Nat -> IO Bytes                        // 指定长度的随机字节序列
Random.float : IO Float                               // [0, 1) 闭区间随机浮点数
Random.shuffle : List a -> IO (List a)                // Fisher-Yates 洗牌
```

- 依赖能力：`sys.random = []`
- 语义场景：唯一 ID 生成、端口选择、测试数据、负载分配

## `TempFile` / `TempDir` — 临时文件与目录

### 定位

创建临时文件和目录，遵循安全最佳实践（`O_TMPFILE` 或 `mkstemp`）。

### API

```kun
TempFile.create : IO (Result Path IOError)              // 创建临时文件，返回路径
TempFile.createWith : String -> IO (Result Path IOError) // 创建指定前缀的临时文件
TempDir.create : IO (Result Path IOError)                // 创建临时目录，返回路径
TempDir.createWith : String -> IO (Result Path IOError)  // 创建指定前缀的临时目录
```

- 生命周期：临时文件/目录在脚本退出时由内核或 Arena 终结器自动清理（`O_TMPFILE` 或创建时标记删除）
- 依赖能力：`fs.write`（临时目录路径）
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

### IO 构造

```kun
Stream.readLines : Path -> IO (Result (Stream String) IOError)
Stream.readLinesSafe : Path -> IO (Result (Stream (Result String IOError)) IOError)
```

- `readLines` — 逐行读取文件，运行时读失败静默终止流
- `readLinesSafe` — 每行包裹 `Result`，保留运行时错误

IO 构造必须通过 `<-` 解包后才能消费：

```kun
main =
  do
    lines <-! Stream.readLines p"/tmp/log.txt"
    iter print lines
```

### 变换（惰性）

```kun
map    : (a -> b) -> Stream a -> Stream b
filter : (a -> Bool) -> Stream a -> Stream a
take   : Int -> Stream a -> Stream a
drop   : Int -> Stream a -> Stream a
```

变换不触发求值，只构造新的惰性流。

### 消费（终端）

```kun
fold   : (b -> a -> b) -> b -> Stream a -> b
toList : Stream a -> List a
iter   : (a -> IO Unit) -> Stream a -> IO Unit
```

终端操作驱动求值，逐一拉取元素。

> **信号处理与纯 Stream 消费**：`fold`、`toList` 等纯终端操作不经过 IO thunk，因此 signalfd 信号会排队直到下一个 IO 边界才被处理。长时间纯 Stream 消费（如处理大文件后 `toList`）可能导致 Ctrl+C 响应延迟。如需在消费期间及时响应信号，应使用 `iter`（IO 终端）或其他含 IO 的消费方式。

### 错误处理辅助

```kun
filterMap : (a -> ?b) -> Stream a -> Stream b

// filterMap Result.ok : Stream (Result t e) -> Stream t — 过滤掉所有 Err 元素，保留 Ok 内容
```
