# 标准库设计

## 设计定位

标准库提供用语言自身表达的实用类型和函数。不同于 `type-system.md` 中编译器固有关联的基础类型，标准库的类型可用 ADT 或 newtype 在语言层面定义，不要求编译器做特殊处理。

所有标准库模块中的函数均需显式导入方可使用（除 `Function` 模块名称始终缺省可用、`Nil` 变体始终缺省可用外）。

## `Int` — 整数操作

### 定位

`Int` 为内置类型（i64），`Int` 模块提供取反、绝对值及类型互转函数。

需显式导入：

```kun
import Int
```

### API

```kun
// 取反
neg : Int -> Int

// 绝对值
abs : Int -> Int

// 从 String 转换为 Int（可能失败）
fromString : String -> Result Int String

// 从 Int 转换为 Float（可能精度损失）
toFloat : Int -> Float

// 从 Int 转换为 String
toString : Int -> String
```

### 示例

```kun
import Int

n = Int.neg 5         // → -5
m = Int.abs (-3)      // → 3
x = Int.fromString "42"   // → Ok 42
y = Int.toFloat 7          // → 7.0
```

## `Float` — 浮点操作

### 定位

`Float` 为内置类型（f64），`Float` 模块提供取反、绝对值、取整、平方根、容差比较及类型互转函数。

需显式导入：

```kun
import Float
```

### API

```kun
// 取反
neg : Float -> Float

// 绝对值
abs : Float -> Float

// 向下取整
floor : Float -> Float

// 向上取整
ceil : Float -> Float

// 四舍五入到最近整数
round : Float -> Float

// 平方根
sqrt : Float -> Float

// 容差比较：|a - b| < epsilon
approxEqual : Float -> Float -> Float -> Bool

// 从 String 转换为 Float（可能失败）
fromString : String -> Result Float String

// 从 Float 转换为 Int（截断小数）
toInt : Float -> Int

// 从 Float 转换为 String（输出舍入到 15 位有效数字）
toString : Float -> String
```

### 示例

```kun
import Float

a = Float.sqrt 16.0                  // → 4.0
b = Float.floor 3.7                  // → 3.0
c = Float.round 3.7                  // → 4.0
d = Float.fromString "2.5"           // → Ok 2.5
e = Float.toInt 3.14                 // → 3

// 容差比较
Float.approxEqual (0.1 + 0.2) 0.3 1e-10    // → true
Float.approxEqual 1.0 1.0001 1e-4          // → true
Float.approxEqual 1.0 1.01 1e-4            // → false
```

## `String` — 字符串操作

### 定位

`String` 为内置类型（UTF-8），`String` 模块提供字符串查询、变换、格式化及类型互转函数。

需显式导入：

```kun
import String
```

### API

#### 查询与变换

```kun
// 拼接两个字符串
(++) : String -> String -> String

// 字符串长度（Unicode 标量值数量）
length : String -> Int

// 切片 [start, end)，左闭右开
slice : Int -> Int -> String -> String

// 是否包含子串
contains : String -> String -> Bool

// 是否以指定前缀开头
startsWith : String -> String -> Bool

// 是否以指定后缀结尾
endsWith : String -> String -> Bool

// 按分隔符切分
split : String -> String -> List String

// 用分隔符拼接列表
join : String -> List String -> String

// 去除首尾空白
trim : String -> String

// 转为大写
toUpper : String -> String

// 转为小写
toLower : String -> String

// 替换第一个匹配
replace : String -> String -> String -> String
```

#### `toString` — 编译器级泛型

> **编译器内置**：`toString` 是编译器层面的泛型函数，不可在纯 Kun 代码中实现。其分发依赖编译期类型内省。

```kun
// 将任意标准库类型转换为字符串
toString : a -> String
```

`toString` 是编译器层面的泛型函数。其分发策略为：
1. 若类型定义了 `toString` 函数，则调用该类型的 `toString`
2. 否则，使用编译器缺省的字符串构造

各标准库中定义了 `toString` 的类型包括：`Port`、`Pid`、`ExitCode`、`DateTime`、`IpAddress`、`Path`、`Uid`、`Gid`、`FileMode`、`FileType`、`Signal`、`Errno`、`Duration`。

内置类型的缺省 `toString` 行为：
- `Int`：十进制字符串
- `Float`：`"3.14"` 形式的十进制字符串
- `Bool`：`"true"` / `"false"`
- `String`：直接返回自身
- `Char`：单字符字符串
- `Bytes`：十六进制字符串 `"48656C6C6F"`
- `Regex`：正则模式字符串 `r"..."`
- `Duration`：纳秒数

### 示例

```kun
import String

name = "  Kun  " |> String.trim          // → "Kun"
parts = "a,b,c" |> String.split ","      // → ["a", "b", "c"]
back = parts |> String.join ":"          // → "a:b:c"
text = Int.toString 42                 // → "42"
num  = Int.fromString "123"             // → Ok 123
```

## `Math` — 数学函数与常量

### 定位

`Math` 模块提供三角函数、指数对数、幂运算、角度转换及实用常量与函数。

需显式导入：

```kun
import Math
```

### API

#### 常量

```kun
// 圆周率 π ≈ 3.141592653589793
pi : Float

// 自然常数 e ≈ 2.718281828459045
e : Float

// τ = 2π ≈ 6.283185307179586
tau : Float
```

#### 三角函数

```kun
// 正弦，参数为弧度
sin : Float -> Float

// 余弦，参数为弧度
cos : Float -> Float

// 正切，参数为弧度
tan : Float -> Float

// 反正弦，返回值域 [-π/2, π/2]
asin : Float -> Float

// 反余弦，返回值域 [0, π]
acos : Float -> Float

// 反正切，返回值域 [-π/2, π/2]
atan : Float -> Float

// 二参数反正切 atan2(y, x)，返回值域 [-π, π]
atan2 : Float -> Float -> Float
```

#### 双曲函数

```kun
// 双曲正弦
sinh : Float -> Float

// 双曲余弦
cosh : Float -> Float

// 双曲正切
tanh : Float -> Float
```

#### 指数与对数

```kun
// e^x
exp : Float -> Float

// 自然对数 ln(x)，x 须 > 0
log : Float -> Float

// 以 2 为底的对数
log2 : Float -> Float

// 以 10 为底的对数
log10 : Float -> Float
```

#### 幂与根

```kun
// x^y
pow : Float -> Float -> Float

// sqrt(x² + y²)，避免溢出
hypot : Float -> Float -> Float
```

#### 角度转换

```kun
// 角度转弧度
degToRad : Float -> Float

// 弧度转角度
radToDeg : Float -> Float
```

#### 实用函数

```kun
// 取较小值
min : Float -> Float -> Float

// 取较大值
max : Float -> Float -> Float

// clamp(x, lo, hi) 将 x 限制在 [lo, hi] 内
clamp : Float -> Float -> Float -> Float
```

### 示例

```kun
import Math

Math.sin (Math.pi / 2)               // → 1.0
Math.clamp 1.5 0.0 1.0               // → 1.0
Math.log Math.e                       // → 1.0
Math.hypot 3.0 4.0                    // → 5.0
Math.degToRad 180                     // → 3.1415...
```

## `Function` — 函数组合子

### 定位

`Function` 模块提供的名称始终缺省自动导入，无需 `import` 即可使用。提供恒等函数、常值函数、管道及函数组合操作符。

### API

```kun
// 恒等函数
identity : a -> a
identity = \x -> x

// 始终返回第一个参数
always : a -> b -> a
always = \x _ -> x

// 反向管道：将右侧值传入左侧函数
(<|) : (a -> b) -> a -> b

// 正向管道：将左侧值传入右侧函数
(|>) : a -> (a -> b) -> b

// 函数组合（从右向左）：(f << g) x = f (g x)
(<<) : (b -> c) -> (a -> b) -> a -> c

// 函数组合（从左向右）：(f >> g) x = g (f x)
(>>) : (a -> b) -> (b -> c) -> a -> c
```

### 示例

```kun
add1 = \x -> x + 1
double = \x -> x * 2
sqrt = Float.sqrt

// 管道
sqrt <| add1 3                         // → sqrt (add1 3)
[1, 2, 3] |> List.map double           // → [2, 4, 6]

// 函数组合
doubleThenAdd1 = add1 << double         // \x -> add1 (double x)
add1ThenDouble = double >> add1         // \x -> double (add1 x)
```

## 系统类型

### `Port`

#### 定位

网络端口号，值域 `0 .. 65535`（u16），以 newtype 形式定义。

```kun
type Port = Port Int
```

#### API

```kun
// 构造 `Port`，调用者须确保参数在 `0..65535` 内
of : Int -> Port

// 检查端口号是否在合法范围 `0..65535` 内
isValid : Port -> Bool
// 端口号 < 1024
isPrivileged : Port -> Bool
// 端口号在 1024-49151 之间
isRegistered : Port -> Bool
// 端口号在 49152-65535 之间
isDynamic : Port -> Bool

// 安全构造，超出 `0..65535` 返回 `Err`
fromInt : Int -> Result Port String
// 提取端口号整数值
toInt : Port -> Int
// 返回端口号的字符串表示
toString : Port -> String
```

与 `Int` 互转：`toInt`（安全，始终成功）、`of`（调用者自保证合法性）、`fromInt`（带校验的安全构造）。

#### 示例

```kun
p = Port.of 80                       // 确信 80 合法
if Port.isValid p then ...           // 有效性检查
number = Port.toInt p                // → 80
Port.isPrivileged p                  // → true
case Port.fromInt 70000 of
  Ok port  -> ...
  Err msg  -> IO.println msg          // "port out of range"
```

语义场景：网络服务端口、防火墙规则、连接目标。

### `Pid`

#### 定位

进程 ID，值域 `1 .. 2^22-1`（Linux 默认 `pid_max`），以 newtype 形式定义。

```kun
type Pid = Pid Int
```

#### API

```kun
// 构造 `Pid`，调用者须确保参数为合法进程 ID
of : Int -> Pid

// 检查 PID 是否在合法范围 `1..2^22-1` 内
isValid : Pid -> Bool
// 是否为 init 进程（PID == 1）
isInit : Pid -> Bool

// 安全构造，非法值（≤ 0 或 > 2^22-1）返回 `Err`
fromInt : Int -> Result Pid String
// 提取进程 ID 整数值
toInt : Pid -> Int
// 返回进程 ID 的字符串表示
toString : Pid -> String
```

#### 示例

```kun
pid = Pid.of 1234                    // 确信 1234 为合法 PID
Pid.toInt pid                        // → 1234
Pid.isInit pid                       // → false
```

语义场景：进程管理、服务监督、信号发送。

### `Signal`

#### 定位

POSIX 信号枚举，平台无关的信号抽象。运行时表示为 i32（信号编号），与 C ABI 兼容。

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

#### API

```kun
number : Signal -> Int
name : Signal -> String

fromInt : Int -> Result Signal String
toInt : Signal -> Int
```

#### 信号接收

```kun
// 注册信号处理函数
on : Signal -> (Signal -> Unit) -> Unit
```

- `on` 注册信号处理函数，收到信号时执行并传递信号值；前一个处理器被替换
- 回调**必须为 `do` 块**
- `Signal.on` 仅可在可执行脚本（无 `export` 声明的 `.kun` 文件）中使用，**库模块禁止调用**

信号处理采用 **signalfd** 机制（Linux 3.8+），并非在 OS 信号上下文中直接执行 Kun 代码。

#### 示例

```kun
// 仅可执行脚本中可用
handleTerminate : -> Unit
handleTerminate = \ ->
  do
    Signal.on
      SIGTERM
      (\sig ->
        do
          IO.println "received SIGTERM, shutting down..."
          Process.exit 0
      )
```

### `Errno`

#### 定位

POSIX 系统调用错误码枚举。运行时表示为 i32，与 C ABI 兼容。

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

#### API

```kun
message : Errno -> String
number : Errno -> Int

fromInt : Int -> Result Errno String
toInt : Errno -> Int
```

#### 示例

```kun
Errno.fromInt 2                     // → Ok ENOENT
Errno.message EACCES                // → "Permission denied"
Errno.toInt EPERM                   // → 1
```

### `FileType`

#### 定位

文件类型枚举，标记文件系统条目的类型（运行时由 `stat` 确定）。

```kun
type FileType
  = Regular
  | Directory
  | SymbolicLink
  | Socket
  | Fifo
  | CharDevice
  | BlockDevice
  | Unknown
```

`Unknown` 变体用于兜底未预期的文件类型。

#### 示例

```kun
// stat : FileStat
case stat.type of
  Regular       -> IO.println "regular file"
  Directory     -> IO.println "directory"
  SymbolicLink  -> IO.println "symlink"
  CharDevice    -> IO.println "char device"
  _             -> IO.println "other"
```

### `FileMode`

#### 定位

文件权限位抽象，封装 Unix 权限位语义。

```kun
type FileMode = FileMode Int    // 八进制权限位，如 0o755、0o644
```

#### API

```kun
// 构造 `FileMode`，调用者须确保参数为合法八进制权限位
of : Int -> FileMode

// 所有者是否可读
isReadable : FileMode -> Bool
// 所有者是否可写
isWritable : FileMode -> Bool
// 所有者是否可执行
isExecutable : FileMode -> Bool
// 是否设置 setuid 位
isSetuid : FileMode -> Bool
// 是否设置 setgid 位
isSetgid : FileMode -> Bool
// 是否设置 sticky 位
isSticky : FileMode -> Bool

// 安全构造，非法权限位（超出 0o777）返回 `Err`
fromInt : Int -> Result FileMode String
// 提取八进制权限值
toInt : FileMode -> Int
```

#### 示例

```kun
mode = FileMode.of 0o755
FileMode.isReadable mode             // → true
FileMode.isExecutable mode           // → true
FileMode.toInt mode                  // → 493
```

### `FileStat`

#### 定位

完整的文件/目录元数据结构，由 `File.stat` 返回。

#### API

```kun
type FileStat =
  { size      : Int
  , type      : FileType
  , mtime     : DateTime
  , ctime     : DateTime
  , atime     : DateTime
  , mode      : FileMode
  , owner     : Uid
  , group     : Gid
  , ownerName : String
  , groupName : String
  , device    : ?{ major : Int, minor : Int }
  }
```

- `owner`/`group` 为数字 ID（`Uid`/`Gid`），源于 `stat` 系统调用的原始返回值
- `device` 仅当 `type` 为 `CharDevice` 或 `BlockDevice` 时有值，其余文件类型为 `Nil`

#### 示例

```kun
case File.stat p"/dev/sda" of
  Ok stat ->
    case stat.device of
      { major, minor } -> IO.println f"device {major}:{minor}"
      Nil              -> IO.println "not a device"
  Err _ -> IO.println "stat failed"
```

### `IOError`

#### 定位

系统调用返回的结构化错误类型。

#### API

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

与 `Errno` 的关系：`IOError` 是面向用户的语义封装，`Errno` 是底层 POSIX 码。

#### 示例

```kun
case File.readString p"/nonexistent" of
  Ok _ -> IO.println "ok"
  Err e ->
    case e of
      NotFound p ->
        IO.println f"{p} not found"
      PermissionDenied { action, target, reason } ->
        IO.println f"cannot {action} {target}: {reason}"
      _ ->
        IO.println "other error"
```

### `CommandError`

#### 定位

命令执行阶段的语义化错误类型。`Cmd.<bin>?` 和 `Cmd.pipe?` 返回 `Result a CommandError`。

#### API

```kun
type CommandError
  = NotFound String
  | PermissionDenied String
  | CommandFailed { command : String, exitCode : Int, stderr : String }
  | KilledBySignal { command : String, signal : Int, stderr : String }
  | IoError IOError
  | PipeFailed { commands : List String, failedAt : Int, error : CommandError }
```

- `CommandFailed` 包含命令名、退出码和完整 stderr 输出
- `PipeFailed` 包含管道链中按序的命令名列表和失败位置

#### 示例

```kun
case Cmd.grep? { pattern = "ERROR" } p"/var/log/app.log" of
  Ok stream -> ...
  Err err ->
    case err of
      CommandFailed { exitCode, stderr } ->
        IO.println f"grep failed ({exitCode}): {stderr}"
      NotFound cmd ->
        IO.println f"command not found: {cmd}"
      _ ->
        IO.println "other error"
```

### `DateTime`

#### 定位

绝对时间点，Unix 纪元以来的纳秒数（i64），以 newtype 形式定义。

```kun
type DateTime = DateTime Int
```

#### API

```kun
// 从 Unix 纳秒数构造 `DateTime`（调用者自保证合法性）
of : Int -> DateTime

// 从 Unix 秒数构造 `DateTime`
fromUnixSecs : Int -> DateTime
// 提取 Unix 秒数
toUnixSecs : DateTime -> Int
// 提取 Unix 纳秒数
toUnixNanos : DateTime -> Int

// 按格式模板格式化时间，格式非法时返回 `Err`
format : String -> DateTime -> Result String String
// 按格式模板解析时间字符串
parse : String -> String -> Result DateTime String

// 提取年份
year : DateTime -> Int
// 提取月份（1-12）
month : DateTime -> Int
// 提取日期（1-31）
day : DateTime -> Int
// 提取小时（0-23）
hour : DateTime -> Int
// 提取分钟（0-59）
minute : DateTime -> Int
// 提取秒（0-59）
second : DateTime -> Int

// 返回 ISO 8601 格式字符串
toString : DateTime -> String
```

支持操作：`+ Duration -> DateTime`、`- Duration -> DateTime`、`- DateTime -> Duration`。

有符号纳秒：`DateTime 0` 表示 1970-01-01T00:00:00Z。

#### 示例

```kun
now = Sys.time
past = DateTime.fromUnixSecs 1700000000
elapsed = now - past

case DateTime.format "yyyy-MM-dd" now of
  Ok s  -> IO.println f"today is {s}"
  Err _ -> IO.println "format error"

dt = DateTime.of 1728000000000000    // 纳秒构造
year = DateTime.year dt              // → 2024
```

### `ExitCode`

#### 定位

进程退出码，值域 `0 .. 255`（u8），以 newtype 形式定义。

```kun
type ExitCode = ExitCode Int
```

#### API

```kun
// 0 — 成功
success : ExitCode
// 1 — 一般错误
generalError : ExitCode
// 127 — 命令未找到
commandNotFound : ExitCode

// 构造 `ExitCode`，调用者须确保参数在 `0..255` 内
of : Int -> ExitCode

// 检查退出码是否在合法范围 `0..255` 内
isValid : ExitCode -> Bool
// 退出码 == 0
isSuccess : ExitCode -> Bool
// 退出码 ≠ 0
isFailure : ExitCode -> Bool

// 安全构造，超出 `0..255` 返回 `Err`
fromInt : Int -> Result ExitCode String
// 提取退出码整数值
toInt : ExitCode -> Int
// 返回退出码的字符串表示
toString : ExitCode -> String
```

语义约定：`0` 表示成功，非零表示失败，`125`-`255` 有特殊含义（与 Shell 惯例对齐）。

#### 示例

```kun
code = ExitCode.of 0
ExitCode.isSuccess code               // → true
ExitCode.isFailure code               // → false
ExitCode.toInt ExitCode.generalError  // → 1
```

### `Path`

#### 定位

文件系统路径类型，运行时表示为 `[]u8`（UTF-8 路径切片）。`Path` 为内置类型，无需 `import Path` 即可在类型标注中使用，但 `Path` 模块中的函数需导入。

需显式导入：

```kun
import Path
```

#### API

```kun
// 当前工作目录，脚本启动时冻结
cwd : Path

// 父目录路径
parent : Path -> Path
// 文件名（含扩展名）
fileName : Path -> String
// 文件扩展名（含 `.`）
extension : Path -> String

// 拼接路径段
join : Path -> String -> Path
// 拼接左右两个路径，自动处理分隔符
(++) : Path -> Path -> Path

// 从字符串构造路径（始终安全，不做文件系统校验）
fromString : String -> Path
// 返回路径的字符串表示
toString : Path -> String
```

#### 示例

```kun
import Path

home = Path.fromString "/home/user"
logs = home ++ p"logs"               // → p"/home/user/logs"
name = Path.fileName p"/tmp/foo.txt" // → "foo.txt"
ext  = Path.extension p"/tmp/foo.txt" // → ".txt"

// 路径语义场景：文件操作路径管理、路径段拼接、父目录定位、文件扩展名提取
```

### `Uid` / `Gid`

#### 定位

用户和组 ID 的数字表示，在需要名称时按需查询。

```kun
type Uid = Uid Int       // 用户 ID
type Gid = Gid Int       // 组 ID
```

#### API

- `Uid` 函数
  ```kun
  current : -> Uid

  // 构造 `Uid`
  of : Int -> Uid

  // 安全构造，非法值（< 0）返回 `Err`
  fromInt : Int -> Result Uid String
  // 提取整数值
  toInt : Uid -> Int
  ```
- `Gid` 函数
  ```kun
  current : -> Gid

  // 构造 `Gid`
  of : Int -> Gid

  // 安全构造，非法值（< 0）返回 `Err`
  fromInt : Int -> Result Gid String
  // 提取整数值
  toInt : Gid -> Int
  ```

#### 示例

```kun
uid = Uid.of 1000
Gid.of 1000
Uid.toInt uid                        // → 1000
```

### `IpAddress`

#### 定位

IP 地址抽象，支持 IPv4 和 IPv6。

```kun
type IpAddress
  = Ipv4 (Int, Int, Int, Int)
  | Ipv6 (Int, Int, Int, Int, Int, Int, Int, Int)
```

#### API

```kun
// 从字符串解析 IP 地址
parse : String -> Result IpAddress String

// 是否为回环地址
isLoopback : IpAddress -> Bool
// 是否为私有地址（RFC 1918 / RFC 4193）
isPrivate : IpAddress -> Bool
// 是否为未指定地址（0.0.0.0 / ::）
isUnspecified : IpAddress -> Bool

// 返回 IP 地址的字符串表示
toString : IpAddress -> String
```

与 `Port` 组合为套接字地址：

```kun
type SocketAddr
  = Tcp IpAddress Port
  | Udp IpAddress Port
```

#### 示例

```kun
case IpAddress.parse "10.0.1.5" of
  Ok ip ->
    IpAddress.isPrivate ip           // → true
    IpAddress.toString ip            // → "10.0.1.5"
    addr = Tcp ip (Port.of 8080)
  Err _ ->
    IO.println "bad address"
```

## `Decimal` — 十进制精确数值

### 定位

`Decimal` 为精确十进制浮点类型。以整数尾数和指数表示数值，避免 IEEE 754 二进制浮点的舍入误差。适用于金融计算、配置文件解析等需要精确小数的场景。`Decimal` 为标准库实现，非编译器内置。

需显式导入：

```kun
import Decimal
```

### API

```kun
type Decimal

// 从字符串构造（调用者自保证合法性，非法输入行为未定义）
of : String -> Decimal

// 从 Int 构造（精确）
fromInt : Int -> Decimal

// 从字符串安全构造（非法格式返回 Err）
fromString : String -> Result Decimal String

// 加法
(+) : Decimal -> Decimal -> Decimal

// 减法
(-) : Decimal -> Decimal -> Decimal

// 乘法
(*) : Decimal -> Decimal -> Decimal

// 除法（可能产生无限小数，需指定精度；精度不足时返回 Err）
divide : Int -> Decimal -> Decimal -> Result Decimal String

// 舍入到指定小数位数
round : Int -> Decimal -> Decimal

// 比较
compare : Decimal -> Decimal -> Order

// 转换为字符串
toString : Decimal -> String
```

- `of` — 从字符串构造，由调用者确保输入合法（如字面量 `"0.1"`）。非法格式为运行时行为，不保证报错
- `fromString` — 安全构造，非法格式返回 `Err`
- `fromInt` 从整数构造，始终成功
- 四则运算均保持精确（除法除外）
- `divide precision a b` — 以 `precision` 位小数精度计算 `a / b`；结果无法在指定精度内精确表示时返回 `Err`
- `round n` — 四舍五入到 `n` 位小数

### 示例

```kun
import Decimal

a = Decimal.of "0.1"
b = Decimal.of "0.2"
sum = a + b                          // → Decimal "0.3"（精确）

// 除法需指定精度
Decimal.of "1.0"
  |> (\d -> Decimal.divide 4 d (Decimal.fromInt 3))
  // → Ok Decimal "0.3333"

// 安全构造（处理不确定来源的输入）
case Decimal.fromString userInput of
  Ok d  -> d
  Err _ -> Decimal.fromInt 0

// 舍入
d = Decimal.of "3.14159"
Decimal.round 2 d                    // → Decimal "3.14"
```

> `Decimal` 与 `Float` 不可隐式互转。需要转换时通过字符串中转：`Float.toString` → `Decimal.fromString`，或 `Decimal.toString` → `Float.fromString`。

## `Nil` — 可选值操作

### 定位

`Nil` 模块提供 `?T`（Nilable）类型的组合子。`Nil` 变体始终缺省自动导入（因为 `case` 模式匹配需要），但模块中函数需显式导入方可使用。

需显式导入：

```kun
import Nil
```

### API

```kun
type Nil = Nil   // 始终缺省自动导入

// Nil 时返回缺省值（解包，返回 a）
withDefault : a -> ?a -> a

// 非 Nil 时应用函数
map : (a -> b) -> ?a -> ?b

// 依次尝试，取首个非 Nil（链式回退，保持 ?a）
orElse : ?a -> ?a -> ?a

// Nil 转为 Err e
toResult : e -> ?a -> Result a e

// 非 Nil 时链式调用可能返回 Nil 的函数（单子绑定）
andThen : (a -> ?b) -> ?a -> ?b
```

- `withDefault` — 提供缺省值并解包。适合「取不到就用默认值」场景
- `map` — 在有值时变换。适合对可选值做纯计算
- `orElse` — 链式尝试多个来源，取首个非 Nil。`orElse` 保持可选包装，可与 `withDefault` 组合使用：`a |> orElse b |> orElse c |> withDefault default`
- `toResult` — 将可选值提升为 `Result`，Nil 携带错误信息
- `andThen` — 串联返回 `?T` 的操作，前一步为 Nil 则短路。适合「取值 → 解析 → 查表」等多步可能失败的操作链

`?T` 为语言内置的类型构造器，`case` 和 `??` / `?.` 为内置操作符，不受 `import Nil` 影响。

### 示例

```kun
import Nil

// withDefault：用缺省值解包
host =
  Map.get "host" #{ "host" = "localhost" }
    |> Nil.withDefault "127.0.0.1"        // → "localhost"

count =
  Map.get "count" #{}                     // → Nil
    |> Nil.withDefault 0                  // → 0

// map：在可选值上做变换
name =
  Map.get "name" #{ "name" = "Kun" }
    |> Nil.map (\s -> String.toUpper s)   // → "KUN"

absent =
  Map.get "name" #{}
    |> Nil.map (\s -> String.toUpper s)   // → Nil

// orElse：依次尝试多个来源
dbConfig : ?String
dbConfig = Nil

config =
  Map.get "host" #{}
    |> Nil.orElse dbConfig                // 回退到 dbConfig
    |> Nil.orElse (Map.get "host" #{ "host" = "prod" })
    |> Nil.withDefault "localhost"        // → "prod"

// toResult：可选值 → Result
required =
  Map.get "port" #{ "port" = "8080" }
    |> Nil.toResult "port is required"    // → Ok "8080"

missing =
  Map.get "port" #{}
    |> Nil.toResult "port is required"    // → Err "port is required"

// andThen：串联可失败的操作链
port =
  Map.get "port" #{ "port" = "8080" }     // ?String
    |> Nil.andThen (\s -> Int.fromString s |> Result.ok)  // ?Int
    |> Nil.withDefault 80                 // → 8080

missingPort =
  Map.get "port" #{}
    |> Nil.andThen (\s -> Int.fromString s |> Result.ok)
    |> Nil.withDefault 80                 // → 80（回退到缺省）
```

## `List` — 列表操作

### 定位

`List` 模块提供不可变列表的查询和变换操作。所有函数为纯函数。

需显式导入：

```kun
import List
```

### API

```kun
// 查询
length  : List a -> Int               // 列表元素个数
isEmpty : List a -> Bool              // 是否为空列表
head    : List a -> ?a                // 首个元素，空列表返回 Nil
last    : List a -> ?a                // 末尾元素，空列表返回 Nil
get     : Int -> List a -> ?a         // 索引访问，越界返回 Nil

// 变换
map       : (a -> b) -> List a -> List b        // 对每个元素应用函数
filter    : (a -> Bool) -> List a -> List a     // 保留满足条件的元素
filterMap : (a -> ?b) -> List a -> List b      // 映射并丢弃 Nil
fold      : (b -> a -> b) -> b -> List a -> b   // 左折叠
reduce    : (a -> a -> a) -> List a -> ?a       // 无初始值的折叠，空列表返回 Nil
iter      : (a -> Unit) -> List a -> Unit       // 遍历每个元素并调用回调
append    : List a -> List a -> List a          // 拼接两个列表
reverse   : List a -> List a                   // 反转列表
```

- `filterMap` 应用函数到每个元素，丢弃返回 `Nil` 的元素
- `fold` 为左折叠，`fold (+) 0 [1, 2, 3]` → `6`
- `reduce` 为无初始值的折叠，以首个元素作为起始累加器，空列表返回 `Nil`
- `iter` 遍历每个元素并调用回调。回调可以是纯函数或效应函数——若回调为效应 lambda（函数体含 `do` 块或调用了效应函数），则整个 `List.iter ...` 表达式本身必须处于 `do` 块中，且效应 lambda 必须在 `do` 块内定义。纯回调无此限制

当回调是 `Cmd.*` 调用时，每次循环独立 fork 子进程（fork ~0.1ms + exec ~0.3ms ≈ ~0.5ms/次）。按规模选择策略：

| 批量规模 | 方案 | 示例 |
|---------|------|------|
| < 50 项 | `List.iter` + `Cmd.*` 直接遍历 | `List.iter (\f -> do Cmd.gzip {} f.path) files` |
| 50-500 项 | 批处理——`Cmd.xargs` 或 `Cmd.withStdin` 注入列表 | `Cmd.xargs { P = "4" } "gzip" \|> Cmd.withStdin fileList` |
| > 500 项 | `Cmd.pipe` 流式 + 并行（`Task.spawn`） | 并发度过低时用 `xargs -P`，大文件走 `File.readBytes` 流式管道 |

### 示例

```kun
import List

nums = [1, 2, 3, 4, 5]
double = List.map (\x -> x * 2) nums           // → [2, 4, 6, 8, 10]
evens = List.filter (\x -> x % 2 == 0) nums    // → [2, 4]
sum   = List.fold (\acc x -> acc + x) 0 nums   // → 15

// do 块中批量副作用
do
  staleFiles = [p"/tmp/a.log", p"/tmp/b.log"]
  List.iter (\p -> do File.remove p) staleFiles
```

## `Map` — 映射表操作

### 定位

`Map` 模块提供不可变字典的查询和变换操作。Map 的键类型必须可哈希（`Int`、`String`、`Bool`、`Char` 等）。

需显式导入：

```kun
import Map
```

### API

```kun
// 查询
get     : String -> Map String a -> ?a       // 获取键值，不存在返回 Nil
keys    : Map String a -> List String         // 所有键
values  : Map String a -> List a              // 所有值
size    : Map String a -> Int                 // 键值对数量
isEmpty : Map String a -> Bool                // 是否为空

// 变换
insert   : String -> a -> Map String a -> Map String a     // 插入/覆写键值对
update   : (a -> a) -> String -> Map String a -> Map String a // 更新已有值
fromList : List (String, a) -> Map String a                // 从列表构造
toList   : Map String a -> List (String, a)                // 转为列表
merge    : Map String a -> Map String a -> Map String a    // 并集合并，右侧覆盖左侧
```

- `insert` 覆写已有键的值
- `update` 对已有值应用变换函数，键不存在时不操作
- `merge` 并集合并，右侧覆盖左侧的相同键

### 示例

```kun
import Map

empty = #{}
data  =
  empty
    |> Map.insert "host" "localhost"
    |> Map.insert "port" 8080

Map.get "host" data                   // → "localhost"
Map.get "missing" data                // → Nil
Map.keys data                         // → ["host", "port"]
Map.size data                         // → 2
```

## `Result` — 错误处理组合子

### 定位

`Result t e` 是 Kun 的核心错误处理类型。`Result` 模块提供函数式组合子用于链式处理。

需显式导入：

```kun
import Result
```

### API

```kun
// 映射
map      : (a -> b) -> Result a e -> Result b e     // 对 Ok 应用函数
mapError : (e -> f) -> Result a e -> Result a f     // 对 Err 应用函数

// 链式
andThen : (a -> Result b e) -> Result a e -> Result b e   // Ok 时链式调用，Err 短路

// 解包
withDefault : a -> Result a e -> a                  // Ok 返回值，Err 返回缺省值

// 查询
ok    : Result a e -> ?a                            // Ok → 值，Err → Nil
isOk  : Result a e -> Bool                          // 是否为 Ok
isErr : Result a e -> Bool                          // 是否为 Err
```

- `map` — 对 `Ok a` 应用函数，`Err` 不变
- `andThen` — 链式调用，`Ok a` 时传入下一函数，`Err` 短路
- `withDefault` — `Ok` 返回值，`Err` 返回缺省值
- `ok` — 将 `Result` 转为 `?T`，`Err` 对应 `Nil`

### 示例

```kun
import Result

parsePort : String -> Result Int String
parsePort = \s ->
  Int.fromString s
    |> Result.andThen (\n ->
      if n >= 0 && n <= 65535 then
        Ok n
      else
        Err "port out of range"
    )

parsePort "8080"
  |> Result.map (\p -> p + 1)
  |> Result.withDefault 80           // → 8081
```

## `Validator` — 校验函数

### 定位

`Validator` 模块提供常用校验函数，供 `Cli.withValidator` 等编译期校验场景使用。所有
函数为纯函数，签名为 `a -> Result a String`——传入原值，`Ok` 通过，`Err` 返回错误信
息。

需显式导入：

```kun
import Validator
```

### API

```kun
// 枚举约束：值必须在列表中
oneOf : List String -> a -> Result a String

// 数值范围：[min, max] 闭区间
range : Int -> Int -> Int -> Result Int String

// 非空字符串
nonEmpty : String -> Result String String

// 正则匹配：模式必须匹配整个字符串
regex : String -> String -> Result String String
```

### 示例

```kun
import Validator

// 与 Cli.withValidator 配合使用
Cli.option "log-level" 'l' "Log level"
  |> Cli.withValidator (Validator.oneOf ["debug", "info", "warn"])

Cli.option "port" 'p' "Server port"
  |> Cli.withValidator (Validator.range 1 65535)

// 独立使用
case Validator.range 1 100 50 of
  Ok v  -> IO.println f"valid: {v}"
  Err e -> IO.println e
```

## `Cli` — 命令行参数解析

需显式导入：

```kun
import Cli
```

对标 Python `argparse`，以类型驱动的方式将 `main` 接收的 `List String` 解析为类型安
全的 Record。`Cli` 模块导出类型结构与声明器函数——`Cli.CliSpec` 和 `Cli.CliMeta`
为普通 Record 类型，用户直接通过 Record 字面量构造和 `Map` 更新语法进行组装。提供
声明式 API、自动 `--help`/`--version` 输出、子命令、互斥组、选项依赖、否定标志、环
境变量回退、自定义校验（对接 `Validator` 模块）等完整 CLI 开发能力。详细设计见
[`Cli` 模块设计文档](cli.md)。

简要示例：

```kun
import Cli

type Config = { verbose : Bool, output : ?Path, jobs : Int, source : String }

parseConfig : List String -> Result Config Cli.CliError
parseConfig =
  Cli.parse
    { meta  = { intro = "build.kun", text = "Compiles and packages." }
    , args =
        [ Cli.flag "verbose" 'v' "Verbose output"
        , Cli.option "output" 'o' "Output file path"
        , Cli.option "jobs" 'j' "Parallel jobs"
            |> Cli.withDefault 4
        , Cli.arg "source" "Source directory"
        ]
    }
```

子命令示例：

```kun
import Cli

type PushConfig = { force : Bool, remote : String, branch : String }
type DeployConfig = { verbose : Bool, push : ?PushConfig }

pushSpec : Cli.CliSpec
pushSpec =
  { meta = { intro = "Push to remote" }
  , args =
      [ Cli.flag "force" 'f' "Force push"
      , Cli.arg "remote" "Remote name"
      , Cli.arg "branch" "Branch name"
      ]
  }

parseConfig : List String -> Result DeployConfig Cli.CliError
parseConfig =
  Cli.parse
    { meta  = { intro = "deploy.kun" }
    , args  = [ Cli.flag "verbose" 'v' "Verbose output" ]
    , subs  = #{ "push" = pushSpec }
    }
```

## `Random` — 随机数

### 定位

提供密码学安全的伪随机数生成器。

需显式导入：

```kun
import Random
```

### API

```kun
// [min, max] 闭区间随机整数
int : Int -> Int -> Int

// 指定长度的随机字节序列
bytes : Int -> Bytes

// [0, 1) 半开区间随机浮点数
float : Float

// Fisher-Yates 洗牌
shuffle : List a -> List a
```

### 示例

```kun
import Random

Random.int 1 100                     // → 随机整数 [1, 100]
Random.float                         // → 随机浮点数 [0, 1)
Random.shuffle [1, 2, 3, 4, 5]       // → 随机排列
```

语义场景：唯一 ID 生成、端口选择、测试数据、负载分配。

## `TempFile` / `TempDir` — 临时文件与目录

### 定位

创建临时文件和目录，遵循安全最佳实践（`mkstemp`）。生命周期：临时文件/目录在脚本退出时自动清理。

需显式导入：

```kun
import TempFile
import TempDir
```

### API

- `TempFile` 函数
  ```kun
  // 创建临时文件，返回路径
  create : -> Result Path IOError
  ```
- `TempDir` 函数
  ```kun
  // 创建临时目录，返回路径
  create : -> Result Path IOError
  ```

### 示例

```kun
import TempFile

do
  case TempFile.create of
    Ok tmp ->
      defer (File.remove tmp)
      File.writeString tmp "content"
      IO.println f"wrote to {tmp}"
    Err _ ->
      IO.println "failed to create temp file"
```

## `Stream` — 惰性序列

### 定位

Stream 是惰性拉取序列，元素在消费时按需求值。不绑定 IO，纯构造和 IO 构造均可。

需显式导入：

```kun
import Stream
```

### API

#### 纯构造

```kun
// 从 List 构造
fromList : List t -> Stream t

// 左闭右开区间 [start, end)
range : Int -> Int -> Stream Int
```

#### 变换（惰性）

```kun
// 对每个元素应用函数
map : (a -> b) -> Stream a -> Stream b

// 保留满足条件的元素
filter : (a -> Bool) -> Stream a -> Stream a

// 取前 n 个元素
take : Int -> Stream a -> Stream a

// 丢弃前 n 个元素
drop : Int -> Stream a -> Stream a

// 按 \n 切分
lines : Stream String -> Stream String

// 映射并跳过失败
parseMap : (a -> Result b e) -> Stream a -> Stream b

// 映射并保留 Result
parseMapKeep : (a -> Result b e) -> Stream a -> Stream (Result b e)
```

变换不触发求值，只构造新的惰性流。

#### 消费（终端）

```kun
// 收集为 List
toList : Stream a -> List a

// 遍历每个元素
iter : (a -> Unit) -> Stream a -> Unit

// 折叠
fold : (b -> a -> b) -> b -> Stream a -> b

// 全文收集为 String
string : Stream String -> String

// 二进制读取
bytes : Stream a -> Bytes
```

终端操作驱动求值，逐一拉取元素。

#### 错误处理辅助

```kun
// 映射并丢弃 Nil
filterMap : (a -> ?b) -> Stream a -> Stream b
// -> Stream.filterMap Result.ok stream — 过滤掉所有 Err 元素
```

#### 纯/效应操作分类

| 操作 | 类别 | 说明 |
|------|------|------|
| `Stream.map` / `Stream.filter` / `Stream.take` | **纯** | 惰性变换，不触发 IO |
| `Stream.parseMap` / `Stream.parseMapKeep` | **纯** | 同上 |
| `Stream.lines` | **纯** | 仅标记换行边界，不触发读取 |
| `Stream.toList` / `Stream.iter` / `Stream.fold` | **效应** | 终端操作，触发读取，仅 `do` 块可用 |
| `Stream.string` / `Stream.bytes` | **效应** | 终端操作 |
| `Stream.fromList` | **纯** | 从纯 List 构造，无 IO 绑定 |

### 示例

```kun
import Stream

// 纯变换
Stream.range 0 100
  |> Stream.filter (\x -> x % 2 == 0)
  |> Stream.take 5
  |> Stream.toList                    // → [0, 2, 4, 6, 8]

// IO 消费
do
  Cmd.cat? p"/var/log/syslog"
    |> Result.withDefault (Stream.fromList [])
    |> Stream.lines
    |> Stream.filter (String.contains "ERROR")
    |> Stream.iter (\line -> do IO.println line)
```

## `IO` — 控制台 IO

### 定位

控制台输入输出操作。所有函数均为效应函数，**只能在 `do` 块中调用**。

需显式导入：

```kun
import IO
```

### API

```kun
// 输出字符串到 stdout（无换行）
print : String -> Unit

// 输出字符串到 stdout（自动换行）
println : String -> Unit

// 从 stdin 读取一行
readln : -> String
```

### 示例

```kun
import IO

do
  IO.print "Enter name: "
  name = IO.readln
  IO.println f"hello, {name}"
```

## `Env` — 环境变量

### 定位

进程环境变量的读写操作。所有函数均为效应函数。

需显式导入：

```kun
import Env
```

### API

```kun
// 读取环境变量，不存在返回 Nil
getenv : String -> ?String

// 设置环境变量
setenv : String -> String -> Unit

// 删除环境变量
unsetenv : String -> Unit
```

`setenv` 内置拒绝列表——以 `LD_` 开头的变量名始终拒绝设置，与子进程 env 始终剔除列表保持一致。

### 示例

```kun
import Env

do
  Env.setenv "KUN_LOG_LEVEL" "debug"
  level = Env.getenv "KUN_LOG_LEVEL" |> Nil.withDefault "info"
  IO.println f"log level: {level}"
```

## `File` — 文件操作（进程内 syscall）

### 定位

文件系统操作，进程内同步 syscall，始终立即执行、始终返回 `Result`。所有函数均为效应函数。

需显式导入：

```kun
import File
```

### API

```kun
// 列出目录内容
list : Path -> Result (List Path) IOError

// 读取文件为字符串
readString : Path -> Result String IOError

// 读取文件为 Bytes 流
readBytes : Path -> Result (Stream Bytes) IOError

// 写入字符串到文件
writeString : Path -> String -> Result Unit IOError

// 写入 Bytes 流到文件
writeBytes : Path -> Stream Bytes -> Result Unit IOError

// 获取文件元数据
stat : Path -> Result FileStat IOError

// 创建/更新时间戳
touch : Path -> Result Unit IOError

// 删除文件
remove : Path -> Result Unit IOError

// 删除目录
removeDir : Path -> Result Unit IOError
```

### 示例

```kun
import File

do
  // 读取文件
  case File.readString p"/etc/hostname" of
    Ok content ->
      IO.println f"hostname: {content}"
    Err _ ->
      IO.println "cannot read hostname"

  // 列出目录并过滤
  case File.list p"/var/log" of
    Ok entries ->
      entries
        |> List.filter (\p -> Path.fileName p |> String.endsWith ".log")
        |> List.iter (\p -> do IO.println (Path.toString p))
    Err _ ->
      IO.println "cannot list directory"
```

## `Cmd` — Command 工具与命令调用

### 定位

子进程命令的构造、修饰与执行。命令调用的语法与机制详见[OS 命令调用机制](command-system.md)。

需显式导入：

```kun
import Cmd
```

### API

> **编译器内置**：`<bin>` 和 `<bin>?` 语法由编译器解析并生成对应的命令调用代码，非普通函数调用。`Command` 类型的延迟执行和 `|>` 隐式触发也由编译器处理。

```kun
// Command 构造
<bin>  : ?{ options } -> posArgs... -> Command
<bin>? : ?{ options } -> posArgs... -> Result (Stream String) CommandError

// OS 管道链
pipe  : List Command -> Command
pipe? : List Command -> Result (Stream String) CommandError

// 添加环境变量
withEnv : Map String String -> Command -> Command

// 追加原始 argv token
withRawOpt : String -> ?String -> Command -> Command

// 注入 stdin（字符串或字节流）
withStdin : String -> Command -> Command
withStdin : Stream Bytes -> Command -> Command

// stderr 合并到 stdout
mergeStderr : Command -> Command

// 指定工作目录
withCwd : Path -> Command -> Command

// 指定执行用户
withRunAs : String -> Command -> Command

// 短路条件组合
andThen : Command -> Command -> Command          // 第一个成功时执行第二个
orElse  : Command -> Command -> Command          // 第一个失败时执行备选

// 工具
which   : String -> ?Path                                                   // PATH 查找
timeout : Duration -> Command -> Result (Stream String) CommandError        // 超时执行
retry   : Int -> Duration -> Command -> Result (Stream String) CommandError // 重试执行
```

- `Cmd.withCwd` 每个 Command 独立设置工作目录（fork 后、exec 前 `chdir`），父进程 CWD 始终不变。缺省使用 `Path.cwd`
- `Cmd.withRunAs` 子进程通过 `setuid()` 切换，需 Kun 进程具备 OS 级权限
- `Cmd.andThen` / `Cmd.orElse` 返回 `Command`（延迟执行），不立即 fork。不引入 `&&`/`||` 运算符以避免与逻辑短路运算符冲突

### 示例

```kun
import Cmd

do
  // 基础调用
  Cmd.ls { l = true, a = true } p"/tmp"

  // 即时执行（返回 Result）
  case Cmd.grep? { i = true, pattern = "error" } p"/var/log/app.log" of
    Ok stream ->
      stream
        |> Stream.lines
        |> Stream.iter (\line -> do IO.println line)
    Err _ ->
      IO.println "grep failed"

  // 管道链
  Cmd.pipe
    [ Cmd.echo {} "hello world"
    , Cmd.wc { w = true }
    ]

  // 短路条件
  Cmd.docker.build { tag = "app" } "."
    |> Cmd.andThen (Cmd.docker.push {} "app:latest")
```

## `Process` — 进程控制

### 定位

当前进程的控制操作。所有函数均为效应函数。

需显式导入：

```kun
import Process
```

### API

```kun
// 以指定退出码终止进程
exit : Int -> Unit

// 获取当前进程 ID
pid : -> Pid

// 阻塞等待指定时长
sleep : Duration -> Unit
```

### 示例

```kun
import Process

do
  currentPid = Process.pid               // → Pid.of <当前进程 ID>
  IO.println f"pid: {Pid.toInt currentPid}"

  Process.sleep 5s                       // 等待 5 秒
  Process.exit 0                         // 正常退出
```

## `Sys` — 类型化系统命令（syscall 实现）

### 定位

操作系统 syscall 级信息查询，仅保留无 OS 命令等价物或 syscall 特有功能。所有函数均为效应函数。

需显式导入：

```kun
import Sys
```

### API

```kun
// 获取当前系统时间
time : -> DateTime

// /proc 遍历进程列表
ps : -> Stream { pid : Pid, cmd : String }

// sysinfo() 内存信息
free : -> { total : Int, used : Int, free : Int }

// statfs() 磁盘信息
df : Path -> { fs : String, total : Int, used : Int, avail : Int }
```

### 示例

```kun
import Sys

do
  now = Sys.time
  IO.println f"current time: {DateTime.format "yyyy-MM-dd" now |> Result.withDefault "unknown"}"

  // 内存信息
  mem = Sys.free
  IO.println f"memory: {mem.free}/{mem.total}"

  // 磁盘信息
  disk = Sys.df p"/"
  IO.println f"disk /: {disk.avail} available of {disk.total}"
```

## `Parser` — 编译期类型安全解析

### `Parser.JSON`

#### 定位

JSON 值类型与字符串互转。`JsonNumber` 已拆分为 `JsonInt` 和 `JsonFloat`，序列化和反序列化时严格区分。

需显式导入：

```kun
import Parser.JSON
```

#### API

```kun
export
  ( JsonValue, JsonValue(..)
  , fromString, toString
  )

type JsonValue
  = JsonNull
  | JsonBool Bool
  | JsonInt Int
  | JsonFloat Float
  | JsonString String
  | JsonArray (List JsonValue)
  | JsonObject (Map String JsonValue)

fromString : String -> Result JsonValue String
toString   : JsonValue -> Result String String
```

- `JsonInt` 对应 JSON 中的整数（无小数点、无指数）
- `JsonFloat` 对应 JSON 中的浮点数（含小数点或指数）

#### 示例

```kun
import Parser.JSON

case Parser.JSON.fromString "{\"name\":\"Kun\",\"version\":1}" of
  Ok (JsonObject obj) ->
    case Map.get "name" obj of
      JsonString name -> IO.println f"name: {name}"
      _               -> IO.println "bad type"
  Err msg -> IO.println f"parse error: {msg}"
```

### `Parser.Record`

#### 定位

利用 Kun 的 HM 类型系统实现泛型反序列化，目标类型由调用点的变量显式类型声明驱动。编译器在编译期为每个调用点生成特化的序列化/反序列化代码，运行时不依赖类型反射。

需显式导入：

```kun
import Parser.Record
```

#### API

```kun
export
  ( fromJson
  , toJson
  )

fromJson : String -> Result a String
toJson   : a -> Result String String
```

#### 示例

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

## 导入一览

| 模块 | 导入方式 | 说明 |
|------|---------|------|
| `Function` | 始终缺省可用 | `identity`、`always`、`<\|`、`\|>`、`<<`、`>>` |
| `Nil` | 变体 `Nil` 缺省可用；函数需 `import Nil` | `withDefault`、`map`、`orElse`、`toResult`、`andThen` |
| `Decimal` | `import Decimal` | 精确十进制数值 |
| `Int` | `import Int` | 整数操作与互转 |
| `Float` | `import Float` | 浮点操作与互转 |
| `String` | `import String` | `toString`、字符串操作及类型互转 |
| `Math` | `import Math` | 数学函数与常量 |
| `List` | `import List` | 列表操作 |
| `Map` | `import Map` | 映射表操作 |
| `Result` | `import Result` | 错误处理组合子 |
| `Cli` | `import Cli` | 命令行参数解析（类型驱动，auto --help，子命令） |
| `Random` | `import Random` | 随机数与洗牌 |
| `TempFile` | `import TempFile` | 临时文件和临时目录 |
| `TempDir` | `import TempDir` | — |
| `Stream` | `import Stream` | 惰性序列 |
| `Validator` | `import Validator` | 校验函数（`oneOf`/`range`/`nonEmpty`/`regex`），供 `Cli.withValidator` 等使用 |
| `IO` | `import IO` | 控制台 IO |
| `Env` | `import Env` | 环境变量 |
| `File` | `import File` | 文件操作 |
| `Cmd` | `import Cmd` | 命令调用 |
| `Process` | `import Process` | 进程控制（含 `sleep`） |
| `Sys` | `import Sys` | 系统信息查询 |
| `Path` | `import Path` | 路径操作函数（类型标注无需导入） |
| `Parser.JSON` | `import Parser.JSON` | JSON 解析 |
| `Parser.Record` | `import Parser.Record` | Record 反序列化 |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.12 | `Nil` 模块新增 `andThen`，`maybe` 重命名为 `withDefault`；新增 `Decimal` 精确十进制类型；`Float` 模块新增 `approxEqual` |
| 2026.06.11 | 新增 `Math` 模块、`Function` 模块（缺省可用的 `identity`/`always`/`<\|`/`\|>`/`<<`/`>>`）；`Pid`/`Port`/`ExitCode`/`DateTime` 改为 newtype 形式，定义 `of`/`isValid`/`fromInt`；新增 `Nil` 模块（`maybe`/`map`/`orElse`/`toResult`）；`FileType` 变体重命名（`Regular`/`SymbolicLink`/`CharDevice`）；`JsonNumber` 拆分为 `JsonInt`/`JsonFloat`；新增 `String` 模块（`toString` 及类型互转函数）；`IO` 改为需显式导入；`Path` 新增 `(++)` 及 `fromString`/`toString`；`Int`/`Float`/`String` 的内置操作移入各自模块并需显式导入；`FileMode` 新增 `of`/`fromInt`；`FileStat` 新增 `device` 字段；移除 `Time` 模块，`sleep` 移至 `Process`，获取当前时间作为 `Sys.time` 实现；所有模块按「定位」「API」「示例」统一结构；重新引入 `Validator` 模块（`oneOf`/`range`/`nonEmpty`/`regex`），更新 `Cli` 章节同步最新设计 |
| 2026.06.10 | 架构重设计：移除 `IO` 类型标记、`Validator`、`RunAs`；新增 `CommandError`、`Cmd.*`/`Cmd.pipe`/`Cmd.withEnv`/`Cmd.withStdin`/`Cmd.withRawOpt`/`Cmd.mergeStderr`、`Parser.Record`；`Uid`/`Gid` 改为 `Int` newtype；`Signal.on` 移至 `Signal` 模块 |
| 2026.05.27 | MVP 基础标准库类型设计定型 |
