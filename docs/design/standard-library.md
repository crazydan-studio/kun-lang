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

  ```
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

### `Errno`

- POSIX 系统调用错误码枚举

  ```
  type Errno
    // No such file or directory
    = ENOENT
    // Permission denied
    | EACCES
    // Operation not permitted
    | EPERM
    // Interrupted system call
    | EINTR
    // I/O error
    | EIO
    // Out of memory
    | ENOMEM
    // Bad file descriptor
    | EBADF
    // Resource temporarily unavailable
    | EAGAIN
    // File exists
    | EEXIST
    // Not a directory
    | ENOTDIR
    // Is a directory
    | EISDIR
    // Invalid argument
    | EINVAL
    // Broken pipe
    | EPIPE
    // Too many open files
    | EMFILE
    // No space left on device
    | ENOSPC
    // Illegal seek
    | ESPIPE
    // Read-only file system
    | EROFS
  ```

- 运行时表示为 i32（errno 编号），与 C ABI 兼容
- 支持操作：`message : Errno -> String`、`number : Errno -> Int`
- 与 `Int` 互转：`fromInt : Int -> Result Errno String`、`toInt : Errno -> Int`

### `FileType`

- 文件类型枚举，标记文件系统条目的类型（运行时由 `stat` 确定）

  ```
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

### `IOError`

- 系统调用返回的结构化错误类型

  ```
  type IOError
    = NotFound Path
    | PermissionDenied Path
    | AlreadyExists Path
    | Unsupported String
    | Other String
  ```

- 与 `Errno` 的关系：`IOError` 是面向用户的语义封装，`Errno` 是底层 POSIX 码
- 转换函数：`toIOError : Errno -> IOError`（将 POSIX 码映射为语义化错误）
- 语义场景：文件操作、网络操作、进程管理等系统调用的错误报告

### `DateTime`

- 绝对时间点，Unix 纪元以来的纳秒数（i64）
- 通过构造器创建：`now : IO DateTime`（当前系统时间）、`fromUnixSecs : Int -> DateTime`
- 支持操作：`+ Duration -> DateTime`、`- Duration -> DateTime`、`- DateTime -> Duration`
- 字段提取：`year : DateTime -> Int`、`month : DateTime -> Int`、`day : DateTime -> Int`、`hour : DateTime -> Int`、`minute : DateTime -> Int`、`second : DateTime -> Int`
- 格式化和解析：`format : String -> DateTime -> String`（`%` 引导的格式符，详见语法设计）、`parse : String -> String -> Result DateTime String`
- 与 `Duration` 的关系：`DateTime` 是时间轴上的点，`Duration` 是两点之间的间隔
- 语义场景：文件时间戳（`mtime`、`ctime`）、日志记录、调度触发、超时计算

### `ExitCode`

- 进程退出码，值域 `0 .. 255`（u8）
- 独立类型，非 `Int`/`Nat` 子类型
- 语义约定：`0` 表示成功，非零表示失败，`125`-`255` 有特殊含义（与 Shell 惯例对齐）
- 构造器：`ExitCode.ofInt 0`、`ExitCode.ofInt 1`（超出 0-255 范围运行时 Panic）
- 支持操作：`isSuccess : ExitCode -> Bool`（== 0）、`isFailure : ExitCode -> Bool`（≠ 0）、`toInt : ExitCode -> Int`
- 预定义常量：`ExitCode.success`、`ExitCode.generalError`（1）、`ExitCode.commandNotFound`（127）
- 语义场景：命令执行结果判断、进程退出值传递、管道错误传播

### `User` / `Group`

- 用户和组身份的抽象，包括名称和数字 ID

  ```
  // 登录名
  type UserName
    = UserName String
  // 用户 ID（0..2^32-1）
  type Uid
    = Uid Nat
  // 组名
  type GroupName
    = GroupName String
  // 组 ID（0..2^32-1）
  type Gid
    = Gid Nat
  ```

- 运行时查询函数：`currentUser : IO UserName`、`currentUid : IO Uid`、`currentGroup : IO GroupName`、`currentGid : IO Gid`
- 名称与 ID 互查：`lookupUser : UserName -> IO (Result Uid String)`、`lookupUid : Uid -> IO (Result UserName String)`、`lookupGroup : GroupName -> IO (Result Gid String)`、`lookupGid : Gid -> IO (Result GroupName String)`
- 语义场景：文件所有者查询、权限检查、进程运行身份

### `IpAddress`

- IP 地址抽象，支持 IPv4 和 IPv6

  ```
  type IpAddress
    // each 0-255
    = Ipv4 (Nat, Nat, Nat, Nat)
    // each 0-65535
    | Ipv6 (Nat, Nat, Nat, Nat, Nat, Nat, Nat, Nat)
  ```

- 解析和序列化：`parse : String -> Result IpAddress String`、`toString : IpAddress -> String`
- 支持操作：`isLoopback : IpAddress -> Bool`、`isPrivate : IpAddress -> Bool`、`isUnspecified : IpAddress -> Bool`
- 与 `Port` 组合为套接字地址

  ```
  type SocketAddr
    = Tcp IpAddress Port
    | Udp IpAddress Port
  ```

- 语义场景：网络连接配置、防火墙规则、服务监听地址

## `Args` — 命令行参数解析

### 定位

将 `main` 接收的原始 `List String` 解析为结构化配置，支持命名参数（`--flag` / `-f`）、带值选项（`--key value` / `-k value`）和位置参数。

### 声明器

```
// 布尔开关
Args.flag : String -> Char -> Arg
// 带值选项
Args.option : String -> Char -> Arg
// 位置参数
Args.positional : Int -> Arg
```

- `flag`：匹配 `--name` 或 `-c`，类型 `Bool`
- `option`：匹配 `--name value` 或 `-c value`，输出值类型为 `String`
- `positional`：按出现顺序匹配，输出值类型为 `String`

### 解析

```
Args.parse : List Arg -> List String -> Result (Map String ArgsValue) String
```

- 返回 `Ok (Map String ArgsValue)` — 参数名到值的映射
- 返回 `Err String` — 解析失败（如未知选项、缺少值）

### 值访问

```
Args.get : String -> Map String ArgsValue -> Maybe ArgsValue
Args.getBool : String -> Map String ArgsValue -> Bool
Args.getString : String -> Map String ArgsValue -> Maybe String
Args.getPath : String -> Map String ArgsValue -> Maybe Path
```

### 示例

```
import Args

type Config
  = Config { verbose : Bool, output : Maybe Path, name : Maybe String }

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

## `Stream` — 惰性序列

### 定位

Stream 是惰性拉取序列，元素在消费时按需求值。不绑定 IO，纯构造和 IO 构造均可。

### 纯构造

```
Stream.fromList : List t -> Stream t
Stream.range : Int -> Int -> Stream Int
```

- `fromList` — 从 List 构造
- `range start end` — 左闭右开区间 `[start, end)`

### IO 构造

```
Stream.readLines : Path -> IO (Result (Stream String) IOError)
Stream.readLinesSafe : Path -> IO (Result (Stream (Result String IOError)) IOError)
```

- `readLines` — 逐行读取文件，运行时读失败静默终止流
- `readLinesSafe` — 每行包裹 `Result`，保留运行时错误

IO 构造必须通过 `<-` 解包后才能消费：

```
main =
  do
    lines <-? Stream.readLines p"/tmp/log.txt"
    iter print lines
```

### 变换（惰性）

```
map    : (a -> b) -> Stream a -> Stream b
filter : (a -> Bool) -> Stream a -> Stream a
take   : Int -> Stream a -> Stream a
drop   : Int -> Stream a -> Stream a
```

变换不触发求值，只构造新的惰性流。

### 消费（终端）

```
fold   : (b -> a -> b) -> b -> Stream a -> b
toList : Stream a -> List a
iter   : (a -> IO Unit) -> Stream a -> IO Unit
```

终端操作驱动求值，逐一拉取元素。

### 错误处理辅助

```
filterMap : (a -> Maybe b) -> Stream a -> Stream b
```

`filterMap toMaybe : Stream (Result t e) -> Stream t` — 过滤掉所有 `Err` 元素，保留 `Ok` 内容。

### 示例

```
import Stream
import Path

main =
  do
    result <- Stream.readLinesSafe p"/tmp/access.log"
    case result of
      Ok lines ->
        lines
          // 跳过读失败的行
          |> filterMap toMaybe
          |> filter (contains "ERROR")
          |> take 100
          |> iter print
      Err e -> print f"cannot open: {e}"
```
