# 标准库设计

## 设计定位

标准库提供用语言自身表达的实用类型和函数。不同于 `type-system.md` 中编译器固有关联的基础类型，标准库的类型可用 ADT 或 newtype 在语言层面定义，不要求编译器做特殊处理。

所有标准库模块中的函数均需显式导入方可使用（除 `Function` 模块名称始终缺省可用、`Nil` 变体始终缺省可用外）。

### 约定：`of` 构造函数

标准库中 `Xxx.of` 形式的构造函数由编译器保证转换安全——调用者以字面量（或编译期已知值）调用时在编译期校验合法性；运行时传入非法值时**抛出 panic**。需要处理不确定来源数据的场景应使用 `Xxx.fromString` / `Xxx.fromInt` 等返回 `Result` 的安全构造。

## `Int` — 整数操作

### 定位

`Int` 为内置类型（i64），`Int` 模块提供绝对值、最值比较、幂运算、范围钳制及类型互转函数。

需显式导入：

```kun
import Int
```

### API

```kun
// [PureKun] 绝对值
abs : Int -> Int

// [PureKun] 取较小值
min : Int -> Int -> Int

// [PureKun] 取较大值
max : Int -> Int -> Int

// [PureKun] 幂运算 x^n，n 须 >= 0
pow : Int -> Int -> Int

// [PureKun] clamp(x, lo, hi) 将 x 限制在 [lo, hi] 内
clamp : Int -> Int -> Int -> Int

// [PureKun] 从 String 转换为 Int（可能失败）
fromString : String -> Result Int String

// [PureKun] 从 Int 转换为 Float（可能精度损失）
toFloat : Int -> Float

// [PureKun] 从 Int 转换为 String
toString : Int -> String
```

### 示例

```kun
import Int

m = Int.abs (-3)        // → 3
n = Int.min 5 10         // → 5
x = Int.max 5 10         // → 10
p = Int.pow 2 10         // → 1024
c = Int.clamp 50 0 100   // → 50
x = Int.fromString "42"   // → Ok 42
y = Int.toFloat 7          // → 7.0
```

## `Float` — 浮点操作与数学函数

### 定位

`Float` 为内置类型（f64），`Float` 模块提供绝对值、取整、平方根、三角函数、指数对数、幂运算、容差比较、类型互转及实用常量与函数。

需显式导入：

```kun
import Float
```

### API

#### 常量

```kun
// [PureKun] 圆周率 π ≈ 3.141592653589793
pi : Float

// [PureKun] 自然常数 e ≈ 2.718281828459045
e : Float
```

#### 绝对值与取整

```kun
// [PureKun] 绝对值
abs : Float -> Float

// [PureKun] 向下取整
floor : Float -> Float

// [PureKun] 向上取整
ceil : Float -> Float

// [PureKun] 四舍五入到最近整数
round : Float -> Float
```

#### 三角函数

```kun
// [PureKun] 正弦，参数为弧度
sin : Float -> Float

// [PureKun] 余弦，参数为弧度
cos : Float -> Float

// [PureKun] 正切，参数为弧度
tan : Float -> Float
```

#### 指数与对数

```kun
// [PureKun] e^x
exp : Float -> Float

// [PureKun] 自然对数 ln(x)，x 须 > 0
log : Float -> Float

// [PureKun] 以 2 为底的对数
log2 : Float -> Float

// [PureKun] 以 10 为底的对数
log10 : Float -> Float
```

#### 幂与根

```kun
// [PureKun] x^y
pow : Float -> Float -> Float

// [PureKun] 平方根
sqrt : Float -> Float
```

#### 比较与实用函数

```kun
// [PureKun] 容差比较：|a - b| < epsilon
approxEqual : Float -> Float -> Float -> Bool

// [PureKun] 取较小值
min : Float -> Float -> Float

// [PureKun] 取较大值
max : Float -> Float -> Float

// [PureKun] clamp(x, lo, hi) 将 x 限制在 [lo, hi] 内
clamp : Float -> Float -> Float -> Float
```

#### 类型互转

```kun
// [PureKun] 从 String 转换为 Float（可能失败）
fromString : String -> Result Float String

// [PureKun] 从 Float 转换为 Int（截断小数）
toInt : Float -> Int

// [PureKun] 从 Float 转换为 String（输出舍入到 15 位有效数字）
toString : Float -> String
```

### 示例

```kun
import Float

// 三角函数
Float.sin (Float.pi / 2)               // → 1.0
Float.cos Float.pi                      // → -1.0

// 指数对数
Float.log Float.e                       // → 1.0
Float.pow 2.0 3.0                       // → 8.0

// 取整
Float.floor 3.7                         // → 3.0
Float.round 3.7                         // → 4.0

// 实用函数
Float.clamp 1.5 0.0 1.0                 // → 1.0

// 容差比较
Float.approxEqual (0.1 + 0.2) 0.3 1e-10    // → true

// 类型互转
val = Float.fromString "2.5"            // → Ok 2.5
n   = Float.toInt 3.14                  // → 3
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
// [PureKun] 拼接两个字符串
(++) : String -> String -> String

// [Primitive] 字符串长度（Unicode 标量值数量）
length : String -> Int

// [Primitive] 切片 [start, end)，左闭右开
slice : Int -> Int -> String -> String

// [PureKun] 是否包含子串
contains : String -> String -> Bool

// [PureKun] 是否以指定前缀开头
startsWith : String -> String -> Bool

// [PureKun] 是否以指定后缀结尾
endsWith : String -> String -> Bool

// [PureKun] 按分隔符切分
split : String -> String -> List String

// [PureKun] 用分隔符拼接列表
join : String -> List String -> String

// [PureKun] 去除首尾空白
trim : String -> String

// [PureKun] 去除首部空白
trimStart : String -> String

// [PureKun] 去除尾部空白
trimEnd: String -> String

// [PureKun] 左侧填充到指定长度
padStart : Int -> Char -> String -> String

// [PureKun] 右侧填充到指定长度
padEnd : Int -> Char -> String -> String

// [PureKun] 转为大写
toUpper : String -> String

// [PureKun] 转为小写
toLower : String -> String

// [PureKun] 重复字符串 n 次
repeat : Int -> String -> String

// [PureKun] 替换第一个匹配
replace : String -> String -> String -> String

// [PureKun] 替换所有匹配
replaceAll : String -> String -> String -> String
```

#### `toString` — 编译器级泛型

> **编译器内置**：`toString` 是编译器层面的泛型函数，不可在纯 Kun 代码中实现。其分发依赖编译期类型内省。

```kun
// [Primitive] 将任意标准库类型转换为字符串
// 编译器内置泛型，分发依赖编译期类型内省
toString : a -> String
```

`toString` 是编译器层面的泛型函数。其分发策略为：
1. 若类型定义了 `toString` 函数（显式实现或标准库 newtype 提供），则调用该类型的 `toString`
2. 其他所有类型（编译器内置基础类型、标准库 ADT、用户自定义 ADT/Record/Tuple）均由编译器自动生成缺省表示
3. 自动生成的路径标注为 `#[auto]`——若类型同时定义了显式 `toString`，显式定义优先

编译器自动生成的缺省 `toString` 行为统一遵循 **类型名 + 负载数据** 格式：

| 类别 | 生成格式 | 示例 |
|------|---------|------|
| 内置基础类型 | `TypeName(value)` | `Int(42)`、`Float(3.14)`、`Bool(true)`、`Char('A')`、`Duration(5s)`、`Unit()` |
| 字符串/Bytes | `TypeName("content")` | `String("hello")`、`Bytes("48656C6C6F")` |
| ADT 变体 | `VariantName` 或 `VariantName(fields)` | `Ok(42)`、`Err("not found")`、`None` |
| Record | `TypeName{ field = value, ... }` | `{ name = "Kun", age = 1 }` |
| Tuple | `(value, value, ...)` | `(42, "hello")` |
| List | `[value, value, ...]` | `[1, 2, 3]` |
| Map | `#{ key = value, ... }` | `#{ "a" = 1, "b" = 2 }` |
| Set | `#[ value, value, ... ]` | `#[ 1, 2, 3 ]` |
| Nilable `?T` | `Nil` 或 内层 T 的表示 | `Nil`、`"hello"`（?String 自动收窄） |
| 不透明类型（Command/Regex/Stream） | `TypeName(<opaque>)` | `Command(<opaque>)`、`Regex(r"[0-9]+")` |

> `Path`、`Duration`、`Decimal` 的标准库模块提供了显式 `toString` 实现（优先于编译器缺省生成）。`Regex` 的 `toString` 由编译器内置（格式 `Regex(r"...")`）——见上方不透明类型行。

### 示例

```kun
import String
import Int

name = "  Kun  " |> String.trim          // → "Kun"
prefix = String.trimStart "  Kun  "      // → "Kun  "
suffix = String.trimEnd "  Kun  "        // → "  Kun"
col = String.padEnd 10 ' ' "Kun"         // → "Kun       "
line = String.repeat 40 "="               // → "========================================"
parts = "a,b,c" |> String.split ","      // → ["a", "b", "c"]
back = parts |> String.join ":"          // → "a:b:c"
text = Int.toString 42                 // → "42"
num  = Int.fromString "123"             // → Ok 123
```

## `Bytes` — 二进制数据编解码

### 定位

`Bytes` 为内置类型（不可变二进制数据，`[]u8` 切片），`Bytes` 模块提供长度、拼接及编解码函数。

需显式导入：

```kun
import Bytes
```

### API

```kun
// [PureKun] 拼接两个 Bytes 值
(++) : Bytes -> Bytes -> Bytes

// [Primitive] 字节长度
length : Bytes -> Int

// [Primitive] 切片 [start, end)，左闭右开
slice : Int -> Int -> Bytes -> Bytes

// [PureKun] 是否包含子序列
contains : Bytes -> Bytes -> Bool

// [PureKun] 从十六进制字符串解码
fromHex : String -> Result Bytes String

// [PureKun] 编码为十六进制字符串
toHex : Bytes -> String

// [PureKun] 从 String 转换为 Bytes（始终成功，UTF-8 编码）
fromString : String -> Bytes

// [PureKun] 从 Bytes 转换为 String（非法 UTF-8 序列运行时 Panic）
toString : Bytes -> String
```

### 示例

```kun
import Bytes

Bytes.length 0x48656C6C6F                    // → 5
Bytes.toHex 0x48656C6C6F                    // → "48656C6C6F"
Bytes.fromString "hello"                     // → 0x68656C6C6F
Bytes.toString 0x68656C6C6F                  // → "hello"

case Bytes.fromHex "48656C6C6F" of
  Ok b  -> b
  Err _ -> 0x00
```

## `Char` — 字符操作

### 定位

`Char` 为内置类型（Unicode 标量值，运行时表示为 u32），`Char` 模块提供字符分类、转换及构造函数。

需显式导入：

```kun
import Char
```

### API

#### 构造

```kun
// [PureKun] 从 Int 构造 Char（调用者自保证合法性，非法码点 panic）
// 合法范围：0..0x10FFFF，排除代理对 0xD800..0xDFFF
of : Int -> Char

// [PureKun] 从 Int 安全构造 Char（非法码点返回 Err）
fromInt : Int -> Result Char String
```

#### 分类

```kun
// [PureKun] 是否为数字字符 '0'..'9'
isDigit : Char -> Bool

// [PureKun] 是否为字母字符（Unicode 字母类别）
isAlpha : Char -> Bool

// [PureKun] 是否为大写字母
isUpper : Char -> Bool

// [PureKun] 是否为小写字母
isLower : Char -> Bool

// [PureKun] 是否为空白字符（空格、制表、换行等，Unicode 空白）
isWhitespace : Char -> Bool

// [PureKun] 是否为控制字符（C0 和 C1 控制码、U+007F DEL）
isControl : Char -> Bool
```

#### 转换

```kun
// [PureKun] 转为大写（非字母字符返回自身）
toUpper : Char -> Char

// [PureKun] 转为小写（非字母字符返回自身）
toLower : Char -> Char

// [PureKun] 提取 Unicode 码点值
toInt : Char -> Int
```

### 示例

```kun
import Char

ch = Char.of 65              // → 'A'
Char.isDigit '5'             // → true
Char.isAlpha 'A'             // → true
Char.isUpper 'A'             // → true
Char.toLower 'A'             // → 'a'
Char.toInt 'A'               // → 65
Char.isWhitespace '\n'       // → true

// 安全构造
case Char.fromInt 0xD800 of    // 代理对，非法
  Ok c  -> c
   Err _ -> Char.of 0xFFFD     // 回退到 Unicode 替换字符
```

## `Regex` — 正则操作

### 定位

`Regex` 为编译器内置类型，编译期验证正则语法。`Regex` 模块提供正则匹配和替换操作。

需显式导入：

```kun
import Regex
```

### API

```kun
// [Primitive] 检查字符串是否匹配整个正则
isMatch : Regex -> String -> Bool

// [Primitive] 返回第一个匹配（含捕获组），无匹配返回 Nil
firstMatch : Regex -> String -> ?{ matched : String, groups : List String }

// [Primitive] 返回所有匹配
allMatches : Regex -> String -> List { matched : String, groups : List String }

// [Primitive] 替换第一个匹配
replace : Regex -> String -> String -> String

// [Primitive] 替换所有匹配
replaceAll : Regex -> String -> String -> String

// [Primitive] 分割字符串
split : Regex -> String -> List String

// [Primitive] 从字符串编译正则（运行时动态构造）
fromString : String -> Result Regex String
```

`fromString` 支持运行时从用户输入或配置文件动态构造正则表达式。编译期 `r"..."` 字面量适用于静态模式，`fromString` 补充动态场景。

### 示例

```kun
import Regex

r = r"(?i)([a-z]+)"

Regex.isMatch r"^\d+$" "12345"              // → true

Regex.firstMatch r"(\d+)" "abc 123 def"     // → { matched = "123", groups = ["123"] }

Regex.replaceAll r"x" "0" "x1 x2 x3"        // → "01 02 03"

Regex.split r",\s*" "a, b, c"               // → ["a", "b", "c"]
```

## `Function` — 函数组合子

### 定位

`Function` 模块提供的名称始终缺省自动导入，无需 `import` 即可使用。提供恒等函数、常值函数、管道及函数组合操作符。

### API

```kun
// [PureKun] 恒等函数
identity : a -> a
identity = \x -> x

// [PureKun] 始终返回第一个参数
always : a -> b -> a
always = \x _ -> x

// [PureKun] 反向管道：将右侧值传入左侧函数
(<|) : (a -> b) -> a -> b

// [PureKun] 正向管道：将左侧值传入右侧函数
(|>) : a -> (a -> b) -> b

// [PureKun] 函数组合（从右向左）：(f << g) x = f (g x)
(<<) : (b -> c) -> (a -> b) -> a -> c

// [PureKun] 函数组合（从左向右）：(f >> g) x = g (f x)
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
add1ThenDouble = add1 >> double         // \x -> double (add1 x)
```

## 系统类型

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
// [PureKun] 信号名称
name : Signal -> String

// [PureKun] 从编号构造
fromInt : Int -> Result Signal String
// [PureKun] 获取信号编号
toInt : Signal -> Int
// [PureKun] 转换为信号名称
toString : Signal -> String
```

#### 信号接收

```kun
// [Primitive] 注册信号处理函数——收到信号时执行回调并传递信号值；前一个处理器被替换 [推迟 v1.0]
on : Signal -> (Signal -> Unit)! -> Unit
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

> **Errno 集成**：POSIX 系统调用错误码（`ENOENT`、`EACCES`、`EPERM` 等）内置于 `IOError` 的运行时实现中，不做为独立模块暴露给用户。需要访问原始错误码的场景通过 `IOError` 的 `Other String` 变体返回描述信息。

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

// [PureKun] 将 IOError 转换为人类可读的字符串
show : IOError -> String
```
#### 示例

```kun
do
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
  | Timeout { duration : Duration, command : Command }

// [PureKun] 将 CommandError 转换为人类可读的字符串
show : CommandError -> String
```

- `CommandFailed` 包含命令名、退出码和完整 stderr 输出
- `Timeout` — 命令执行超时（由 `Cmd.timeout` 触发），含超时时长和原始命令值
- `PipeFailed` 包含管道链中按序的命令名列表和失败位置

> **嵌套限制**：`Cmd.pipe` 链中若 `andThen` 或 `orElse` 产生嵌套 `PipeFailed`（内层 `error` 字段为 `CommandError`，其中含另一个 `PipeFailed`），嵌套深度上限为 16。超出时 panic 并返回最外层 `PipeFailed`，内层错误信息通过 stderr `warn` 日志输出。
- `show : CommandError -> String` 返回格式化的错误描述字符串

#### 示例

```kun
do
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
// [PureKun] 从 Unix 纳秒数构造 `DateTime`（调用者自保证合法性，非法输入 panic）
of : Int -> DateTime

// [PureKun] 从 Unix 秒数构造 `DateTime`
fromUnixSecs : Int -> DateTime
// [PureKun] 从 Unix 毫秒数构造 `DateTime`
fromUnixMillis : Int -> DateTime
// [PureKun] 提取 Unix 秒数
toUnixSecs : DateTime -> Int
// [PureKun] 提取 Unix 纳秒数
toUnixNanos : DateTime -> Int
// [PureKun] 提取 Unix 毫秒数
toUnixMillis : DateTime -> Int

// [Primitive] 按格式模板格式化时间，格式非法时返回 `Err`
format : String -> DateTime -> Result String String
// 格式字段名：`yyyy`（年）、`yy`（年两位数）、`MM`（月）、`dd`（日）、`HH`（时）、`mm`（分）、`ss`（秒）、`SSS`（毫秒）、`Z`（时区偏移）

// [Primitive] 按格式模板解析时间字符串
parse : String -> String -> Result DateTime String

// [PureKun] 提取年份
year : DateTime -> Int
// [PureKun] 提取月份（1-12）
month : DateTime -> Int
// [PureKun] 提取日期（1-31）
day : DateTime -> Int
// [PureKun] 提取小时（0-23）
hour : DateTime -> Int
// [PureKun] 提取分钟（0-59）
minute : DateTime -> Int
// [PureKun] 提取秒（0-59）
second : DateTime -> Int

// [PureKun] 返回 ISO 8601 格式字符串
toString : DateTime -> String

// [Primitive] 获取当前系统时间
now : -> DateTime

// [PureKun] DateTime + Duration = DateTime
(+) : DateTime -> Duration -> DateTime
// [PureKun] DateTime - Duration = DateTime
(-) : DateTime -> Duration -> DateTime
// [PureKun] DateTime - DateTime = Duration
(-) : DateTime -> DateTime -> Duration
// [PureKun] 比较两个时间点（返回 -1/0/1）
compare : DateTime -> DateTime -> Int
// [PureKun] 是否早于
before : DateTime -> DateTime -> Bool
// [PureKun] 是否晚于
after : DateTime -> DateTime -> Bool
```

有符号纳秒：`DateTime 0` 表示 1970-01-01T00:00:00Z。

#### 示例

```kun
import DateTime

do
  now = DateTime.now
  past = DateTime.fromUnixSecs 1700000000
  elapsed = now - past

  case DateTime.format "yyyy-MM-dd" now of
    Ok s  -> IO.println f"today is {s}"
    Err _ -> IO.println "format error"

  dt = DateTime.of 1728000000000000    // 纳秒构造
  year = DateTime.year dt              // → 1970
```

### `Duration`

#### 定位

时间段，纳秒精度，运行时表示为 i64。`Duration` 为编译器内置类型，字面量使用数字 + 单位后缀（`5s`、`100ms`、`2h`、`30m`、`1d`、`500us`、`200ns`）。无需 `import Duration` 即可在类型标注中使用。

需显式导入：

```kun
import Duration
```

#### API

```kun
// [PureKun] 算术运算（均返回 Duration）
(+) : Duration -> Duration -> Duration
// [PureKun] 算术运算（均返回 Duration）
(-) : Duration -> Duration -> Duration
// [PureKun] 算术运算（均返回 Duration）
(*) : Int -> Duration -> Duration
// [PureKun] 算术运算（均返回 Duration）
(/) : Duration -> Int -> Duration

// [PureKun] 比较（== / /= / < / > / <= / >= 运算符直接可用，底层委托 compare）
compare : Duration -> Duration -> Int    // -1 / 0 / 1

// [PureKun] 单位提取
toNanos : Duration -> Int
toMicros : Duration -> Int
toMillis : Duration -> Int
toSeconds : Duration -> Int
toMinutes : Duration -> Int
toHours : Duration -> Int
toDays : Duration -> Int

// [PureKun] 解析与格式化
fromString : String -> Result Duration String    // 解析 "5s" / "100ms" / "2h30m" / "1d"
// [PureKun] 从毫秒数构造 Duration
fromMillis : Int -> Duration
toString : Duration -> String                    // 纳秒数（如 "5100000000"）
format : String -> Duration -> Result String String  // 自定义格式

// [PureKun] 负值支持
negate : Duration -> Duration    // 取反，-(5s) → -5000000000ns
isNegative : Duration -> Bool
abs : Duration -> Duration       // 绝对值
```

`fromString` 支持的格式：

| 单位 | 后缀 | 示例 |
|------|------|------|
| 纳秒 | `ns` | `"500ns"` |
| 微秒 | `us` | `"500us"` |
| 毫秒 | `ms` | `"100ms"` |
| 秒 | `s` | `"5s"` |
| 分钟 | `m` | `"30m"` |
| 小时 | `h` | `"2h"` |
| 天 | `d` | `"1d"` |
| 组合 | 多单位拼接 | `"2h30m"`、`"1d12h"` |

`format` 格式说明符：

| 说明符 | 输出 | 示例（输入=3661000000000ns） |
|--------|------|------|
| `"H:MM:SS"` | 时:分:秒 | `"1:01:01"` |
| `"M:SS"` | 分:秒 | `"61:01"` |
| `"S"` | 总秒数 | `"3661"` |
| `"s"` | 带单位的简短格式 | `"1h1m1s"` |

**负 Duration**：字面量 `-5s` 合法（等同于 `negate 5s`）。负 Duration 的算术运算按符号处理——`(-5s) + 10s = 5s`，`(-5s) * 2 = -10s`。比较运算符按符号比较——`-5s < 0s < 5s`。除法向零截断——`(-5s) / 2 = -2s`。

#### 示例

```kun
import Duration

d1 = 5s
d2 = 100ms
sum = d1 + d2                           // → 5100000000ns

Duration.toSeconds 2h                      // → 7200
Duration.toMillis (5s - 100ms)           // → 4900
```

### `Path`

#### 定位

文件系统路径类型，运行时表示为 `[]u8`（字节切片）。`Path` 为内置类型，无需 `import Path` 即可在类型标注中使用，但 `Path` 模块中的函数需导入。

Path 的内部字节序列不保证为 UTF-8——Linux 内核将路径视为以 NUL 结尾的任意字节序列（禁止 `\0` 和 `/` 作为文件名字节），对编码不做约束。Kun 提供两条构造路径以覆盖不同场景：`p"..."` 字面量和 `Path.fromString` 适用于绝大多数 UTF-8 路径（编译期或运行时验证 UTF-8）；`Path.fromBytes` 从任意 `Bytes` 构造路径以覆盖非 UTF-8 文件系统场景（如解压不同编码的 zip、老旧 NAS 遗留文件）。`toString` 在路径含非法 UTF-8 字节时用 U+FFFD 替代，需精确保留原始字节的代码使用 `toBytes`。

需显式导入：

```kun
import Path
```

#### API

```kun
// [PureKun] 父目录路径
parent : Path -> Path
// [PureKun] 文件名（含扩展名）——尝试 UTF-8 解码，非 UTF-8 字节用 U+FFFD 替换
fileName : Path -> String
// [PureKun] 文件扩展名（含 `.`）——同 fileName 的 UTF-8 规则
extension : Path -> String

// [PureKun] 拼接路径段
join : Path -> String -> Path
// [PureKun] 拼接左右两个路径，自动处理分隔符
(++) : Path -> Path -> Path

// [PureKun] 从 UTF-8 字符串构造路径（始终安全，不做文件系统校验）
// 任意有效 UTF-8 字符串均可为路径，故不返回 Result
fromString : String -> Path

// [PureKun] 从字节数组构造路径（覆盖非 UTF-8 文件系统场景）
// 验证规则：拒绝含 `\0` 字节 → Err "Path contains NUL byte"
//            允许非 UTF-8 字节序列（不做编码验证）
fromBytes : Bytes -> Result Path String

// [PureKun] 从字节数组构造单路径组件（文件名/目录名）
// 验证规则：拒绝含 `\0` 字节 → Err "Path component contains NUL byte"
//           拒绝含 `/` 字节  → Err "Path component contains '/' byte"
//           拒绝空字节序列    → Err "Path component is empty"
//           允许非 UTF-8 字节序列（不做编码验证）
component : Bytes -> Result Path String

// [PureKun] 返回路径的字符串表示
// 若内部字节为合法 UTF-8 → 返回等价 String
// 若内部字节含非法 UTF-8 序列 → 非法字节用 U+FFFD（replacement character）替换
toString : Path -> String

// [PureKun] 以 Bytes 返回路径的原始字节表示（零开销，无验证）
toBytes : Path -> Bytes

// [PureKun] 解析相对路径为绝对路径（基于 File.currentDir）
resolve : Path -> Path
// [PureKun] 规范化路径（解析 `.` 和 `..`）
normalize : Path -> Path
// [PureKun] 路径是否为绝对路径
isAbsolute : Path -> Bool
// [PureKun] 路径是否为相对路径
isRelative : Path -> Bool
// [PureKun] 计算 from → to 的相对路径
relative : Path -> Path -> Path
```

#### 示例

```kun
import Path

home = Path.fromString "/home/user"
logs = home ++ p"logs"               // → p"/home/user/logs"
name = Path.fileName p"/tmp/foo.txt" // → "foo.txt"
ext  = Path.extension p"/tmp/foo.txt" // → ".txt"

// 路径工具函数
Path.isAbsolute p"/usr/bin"          // → true
Path.isRelative p"docs/file.md"      // → true
Path.normalize p"/a/b/../c"          // → p"/a/c"

// fromBytes：覆盖非 UTF-8 文件系统场景（Linux ext4/xfs 合法）
// 受限 Landlock `--allow-path` 范围，仅 NUL 被拒绝
case Path.fromBytes 0x2F746D702FBAADF00D of
  Ok path  -> Path.toString path  // 显示用 U+FFFD 替代非 UTF-8 字节
  Err _    -> p"/tmp/fallback"

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
  // [PureKun] 构造 `Uid`，调用者须确保参数合法，非法输入 panic
  of : Int -> Uid

  // [PureKun] 安全构造，非法值（< 0）返回 `Err`
  fromInt : Int -> Result Uid String
  // [PureKun] 提取整数值
  toInt : Uid -> Int
  // [PureKun] 转换为字符串
  toString : Uid -> String
  ```
- `Gid` 函数
  ```kun
  // [PureKun] 构造 `Gid`，调用者须确保参数合法，非法输入 panic
  of : Int -> Gid

  // [PureKun] 安全构造，非法值（< 0）返回 `Err`
  fromInt : Int -> Result Gid String
  // [PureKun] 提取整数值
  toInt : Gid -> Int
  // [PureKun] 转换为字符串
  toString : Gid -> String
  ```

#### 示例

```kun
uid = Uid.of 1000
Gid.of 1000
Uid.toInt uid                        // → 1000
```

## `Decimal` — 十进制精确数值

### 定位

`Decimal` 为精确十进制浮点类型。以整数尾数和指数表示数值，避免 IEEE 754 二进制浮点的舍入误差。适用于金融计算、配置文件解析等需要精确小数的场景。`Decimal` 为标准库类型——编译器提供 TypeEnv 变体 (`decimal_t`) 和固定运行时表示 (`struct { int64_t mantissa, int32_t exponent }`, 12 字节)，但 `Decimal` 模块中的函数（`of`/`fromString`/算术/`round` 等）为标准库实现，非 Primitive。

需显式导入：

```kun
import Decimal
```

### API

```kun
type Decimal

// [PureKun] 从字符串构造（调用者自保证合法性，非法输入 panic）
of : String -> Decimal

// [PureKun] 从 Int 构造（精确）
fromInt : Int -> Decimal

// [PureKun] 从字符串安全构造（非法格式返回 Err）
fromString : String -> Result Decimal String

// [PureKun] 加法
(+) : Decimal -> Decimal -> Decimal

// [PureKun] 减法
(-) : Decimal -> Decimal -> Decimal

// [PureKun] 乘法
(*) : Decimal -> Decimal -> Decimal

// [PureKun] 除法（可能产生无限小数，需指定精度；精度不足时返回 Err）
divide : Int -> Decimal -> Decimal -> Result Decimal String

// [PureKun] 舍入到指定小数位数
round : Int -> Decimal -> Decimal

// [PureKun] 比较（返回 -1 / 0 / 1，同 Int 比较语义）
compare : Decimal -> Decimal -> Int

// [PureKun] 转换为字符串
toString : Decimal -> String
```

- `of` — 从字符串构造，由调用者确保输入合法。遵循[全局 `of` 约定](#约定of-构造函数)：非法输入 panic
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
// 以下为编译器内置伪代码，用户无需自行定义
type Nil = Nil   // 始终缺省自动导入

// [PureKun] Nil 时返回缺省值（解包，返回 a）
withDefault : a -> ?a -> a

// [PureKun] 非 Nil 时应用函数
map : (a -> b) -> ?a -> ?b

// [PureKun] 依次尝试，取首个非 Nil（链式回退，保持 ?a）
orElse : ?a -> ?a -> ?a

// [PureKun] Nil 转为 Err e
toResult : e -> ?a -> Result a e

// [PureKun] 非 Nil 时链式调用可能返回 Nil 的函数（单子绑定）
andThen : (a -> ?b) -> ?a -> ?b

// [PureKun] 是否为 Nil
isNil : ?a -> Bool

// [PureKun] 是否为非 Nil
isSome : ?a -> Bool

// [PureKun] 按谓词过滤可选值
filter : (a -> Bool) -> ?a -> ?a
```

- `withDefault` — 提供缺省值并解包。适合「取不到就用默认值」场景
- `map` — 在有值时变换。适合对可选值做纯计算
- `orElse` — 链式尝试多个来源，取首个非 Nil。`orElse` 保持可选包装，可与 `withDefault` 组合使用：`a |> orElse b |> orElse c |> withDefault default`
- `toResult` — 将可选值提升为 `Result`，Nil 携带错误信息
- `andThen` — 串联返回 `?T` 的操作，前一步为 Nil 则短路。适合「取值 → 解析 → 查表」等多步可能失败的操作链
- `isNil` — 检查可选值是否为 `Nil`
- `isSome` — 检查可选值是否为非 `Nil`（即存在值）
- `filter` — 在值存在且满足谓词时保留值，否则返回 `Nil`

`?T` 为语言内置的类型构造器，`case` 和 `??` / `?.` 为内置操作符，不受 `import Nil` 影响。

### 示例

```kun
import Nil
import Map
import Int
import Result
import String

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
// [Primitive] 列表元素个数
length  : List a -> Int               // 列表元素个数
// [Primitive] 是否为空列表
isEmpty : List a -> Bool              // 是否为空列表
// [Primitive] 首个元素，空列表返回 Nil
head    : List a -> ?a                // 首个元素，空列表返回 Nil
// [Primitive] 末尾元素，空列表返回 Nil
last    : List a -> ?a                // 末尾元素，空列表返回 Nil
// [Primitive] 索引访问，越界返回 Nil
get     : Int -> List a -> ?a         // 索引访问，越界返回 Nil

// 变换
// [PureKun] 对每个元素应用函数
map       : (a -> b) -> List a -> List b
// [PureKun] 保留满足条件的元素
filter    : (a -> Bool) -> List a -> List a
// [PureKun] 映射并丢弃 Nil
filterMap : (a -> ?b) -> List a -> List b
// [PureKun] 左折叠
fold      : (b -> a -> b) -> b -> List a -> b
// [PureKun] 无初始值的折叠，空列表返回 Nil
reduce    : (a -> a -> a) -> List a -> ?a
// [PureKun] 遍历每个元素并调用效应回调
iter      : (a -> Unit)! -> List a -> Unit
// [Primitive] 拼接两个列表
append    : List a -> List a -> List a
// [Primitive] 反转列表
reverse   : List a -> List a
// [Primitive] 排序（比较函数返回 -1/0/1）
sort      : (a -> a -> Int) -> List a -> List a
// [PureKun] 按键函数排序
sortBy    : (a -> k) -> List a -> List a
// [Primitive] 子列表 [start, end)
slice     : Int -> Int -> List a -> List a
// [Primitive] 取前 n 个元素
take      : Int -> List a -> List a
// [Primitive] 丢弃前 n 个元素
drop      : Int -> List a -> List a
// [PureKun] 全部满足条件
all       : (a -> Bool) -> List a -> Bool
// [PureKun] 任一满足条件
any       : (a -> Bool) -> List a -> Bool

// [PureKun] 查找第一个匹配元素
find : (a -> Bool) -> List a -> ?a

// [PureKun] 查找第一个匹配元素的索引
findIndex : (a -> Bool) -> List a -> ?Int

// [PureKun] 元素是否存在
elem : a -> List a -> Bool

// [PureKun] 两列表按元素配对
zip : List a -> List b -> List (a, b)

// [PureKun] 两列表按元素配对并应用函数
zipWith : (a -> b -> c) -> List a -> List b -> List c

// [PureKun] 按谓词分割为两列表
partition : (a -> Bool) -> List a -> (List a, List a)

// [PureKun] 展平嵌套列表
concat : List (List a) -> List a

// [PureKun] 生成整数范围列表 [start, end)，不含 end
range : Int -> Int -> List Int

// [PureKun] 求和（元素类型须支持 + 运算符）
sum : List Int -> Int

// [PureKun] 最小值
minimum : List a -> ?a

// [PureKun] 最大值
maximum : List a -> ?a

// [PureKun] 按 key 函数分组
groupBy : (a -> k) -> List a -> Map k (List a)
```

- `filterMap` 应用函数到每个元素，丢弃返回 `Nil` 的元素
- `fold` 为左折叠，`fold (+) 0 [1, 2, 3]` → `6`
- `reduce` 为无初始值的折叠，以首个元素作为起始累加器，空列表返回 `Nil`
- `iter` 遍历每个元素并调用回调。签名为 `(a -> Unit)! -> List a -> Unit`——`!` 标注回调**必须是**效应函数（含 `do` 块或效应命名空间函数），不可传入纯函数。`List.iter` 表达式本身必须在 `do` 块中调用（因为声明了 `!` 参数）

> **回调纯函数约束**：除 `iter` 外，`List` 模块的所有高阶函数（`map`、`filter`、`filterMap`、`fold`、`reduce`、`all`、`any`、`take`、`drop`）的回调参数**必须为纯函数**。这些操作的语义是「从 A 计算出 B」的纯变换，不应掺杂副作用。`List.iter` 的回调必须为**效应函数**（签名标注 `(a -> Unit)!`），用于逐元素执行副作用。

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

`Map` 模块提供不可变字典的查询和变换操作。Map 的键类型必须可哈希（`Int`、`String`、`Bool`、`Char`、`Path` 等编译器内置可哈希类型及 `Duration`）。Kun 当前不提供用户自定义类型的哈希接口——使用非内置可哈希类型作为 Map 键将在编译期报错。

> 哈希约束的编译期检查：编译器对 `Map k v` 类型构造中的 `k` 执行硬编码类型白名单检查（`Int`/`String`/`Bool`/`Char`/`Path`/`Duration`），非白名单类型在类型检查阶段报错。这是无类型类的临时方案，避免了运行时哈希崩溃，符合"所有类型安全检查在编译期完成"的原则。后续可引入 `Hashable` 类型类以支持用户自定义哈希。

需显式导入：

```kun
import Map
```

### API

```kun
// [Primitive] 获取键值，不存在返回 Nil
get     : k -> Map k v -> ?v                 // 获取键值，不存在返回 Nil
// [Primitive] 所有键
keys    : Map k v -> List k                   // 所有键
// [Primitive] 所有值
values  : Map k v -> List v                   // 所有值
// [Primitive] 键值对数量
size    : Map k v -> Int                      // 键值对数量
// [Primitive] 是否为空
isEmpty : Map k v -> Bool                     // 是否为空

// 变换
// [Primitive] 插入/覆写键值对
insert   : k -> v -> Map k v -> Map k v             // 插入/覆写键值对
// [Primitive] 移除键值对（键不存在时无操作）
remove   : k -> Map k v -> Map k v                  // 移除键值对（键不存在时无操作）
// [PureKun] 更新已有值
update   : (v -> v) -> k -> Map k v -> Map k v      // 更新已有值
// [PureKun] 从列表构造
fromList : List (k, v) -> Map k v                   // 从列表构造
// [PureKun] 转为列表
toList   : Map k v -> List (k, v)                   // 转为列表
// [PureKun] 并集合并，右侧覆盖左侧
merge    : Map k v -> Map k v -> Map k v            // 并集合并，右侧覆盖左侧

// [PureKun] 键是否存在
containsKey : k -> Map k v -> Bool

// [PureKun] 按值谓词过滤
filter : (v -> Bool) -> Map k v -> Map k v

// [PureKun] 变换值
map : (v -> w) -> Map k v -> Map k w

// [PureKun] 左优先合并两 Map
union : Map k v -> Map k v -> Map k v

// [PureKun] 交集（仅在两 Map 共有的键上保留值）
intersect : Map k v -> Map k v -> Map k v

// [PureKun] 差集（在左 Map 中移除右 Map 含有的键）
difference : Map k v -> Map k v -> Map k v
```

- `insert` 覆写已有键的值
- `update` 对已有值应用变换函数，键不存在时不操作。变换函数必须为纯函数——逐个元素执行副作用应遍历 `List (k, v)` 并在 `do` 块中使用 `List.iter`
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

## `Set` — 集合操作

### 定位

`Set` 模块提供不可变无序集合的查询和变换操作。元素唯一，基于哈希表实现（与 `Map` 共享同一哈希表结构）。Set 的值类型必须可哈希（`Int`、`String`、`Bool`、`Char`、`Path`、`Duration` 等编译器内置可哈希类型）。

需显式导入：

```kun
import Set
```

### API

```kun
// [Primitive] 集合元素数量
size    : Set a -> Int                 // 集合元素数量
// [Primitive] 是否为空
isEmpty : Set a -> Bool                // 是否为空
// [Primitive] 是否包含元素
contains : a -> Set a -> Bool          // 是否包含元素

// 变换
// [Primitive] 插入元素（幂等）
insert  : a -> Set a -> Set a          // 插入元素（幂等）
// [Primitive] 移除元素
remove  : a -> Set a -> Set a          // 移除元素
// [PureKun] 并集
union   : Set a -> Set a -> Set a      // 并集
// [PureKun] 交集
intersect : Set a -> Set a -> Set a    // 交集
// [PureKun] 差集
diff    : Set a -> Set a -> Set a      // 差集

// 转换
// [PureKun] 转为去重列表（顺序非确定）
toList  : Set a -> List a              // 转为去重列表（顺序非确定）
// [PureKun] 从列表构造（自动去重）
fromList : List a -> Set a             // 从列表构造（自动去重）

// [PureKun] 按谓词过滤
filter : (a -> Bool) -> Set a -> Set a

// [PureKun] 变换元素（需结果可哈希）
map : (a -> b) -> Set a -> Set b

// [PureKun] 左 Set 是否为右 Set 的子集
isSubset : Set a -> Set a -> Bool

// [PureKun] 左 Set 是否为右 Set 的超集
isSuperset : Set a -> Set a -> Bool

// [PureKun] 两集合是否无交集
disjoint : Set a -> Set a -> Bool

// [PureKun] 折叠（与 List.fold 相同签名）
fold : (b -> a -> b) -> b -> Set a -> b
```

### 示例

```kun
import Set

s = #[1, 2, 3]
Set.size s                              // → 3
Set.contains 2 s                        // → true
Set.insert 3 s                          // → #[1, 2, 3]（幂等）
Set.union s #[3, 4, 5]                  // → #[1, 2, 3, 4, 5]
Set.toList (Set.fromList [1, 2, 2, 3])  // → [1, 2, 3]（去重）
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
// [PureKun] 对 Ok 应用函数
map      : (a -> b) -> Result a e -> Result b e     // 对 Ok 应用函数
// [PureKun] 对 Err 应用函数
mapError : (e -> f) -> Result a e -> Result a f     // 对 Err 应用函数

// 链式
// [PureKun] Ok 时链式调用，Err 短路
andThen : (a -> Result b e) -> Result a e -> Result b e   // Ok 时链式调用，Err 短路

// 解包
// [PureKun] Ok 返回值，Err 返回缺省值
withDefault : a -> Result a e -> a                  // Ok 返回值，Err 返回缺省值

// 查询
// [PureKun] Ok → 值，Err → Nil
ok    : Result a e -> ?a                            // Ok → 值，Err → Nil
// [PureKun] 是否为 Ok
isOk  : Result a e -> Bool                          // 是否为 Ok
// [PureKun] 是否为 Err
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

`Validator` 模块提供常用校验函数，供 `Cli.withValidator` 等编译期校验场景使用。所有函数为纯函数，签名为 `a -> Result a String`——传入原值，`Ok` 通过，`Err` 返回错误信息。

需显式导入：

```kun
import Validator
```

### API

```kun
// [PureKun] 枚举约束：值必须在列表中
oneOf : List String -> String -> Result String String

// [PureKun] 数值范围：[min, max] 闭区间
range : Int -> Int -> Int -> Result Int String

// [PureKun] 非空字符串
nonEmpty : String -> Result String String

// [Primitive] 正则匹配：模式必须匹配整个字符串（依赖 C 正则引擎）
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
do
  case Validator.range 1 100 50 of
    Ok v  -> IO.println f"valid: {v}"
    Err e -> IO.println e
```

## `Cli` — 命令行参数解析

### 定位

`Cli` 模块提供类型驱动的命令行参数解析，将 `main` 接收的 `List String` 解析为类型安全的 Record。`--help` / `-h` 和 `--version` / `-V` 自动可用。

需显式导入：

```kun
import Cli
```

### API

#### 声明器

```kun
// [PureKun] 布尔开关（--name / -c），不出现 → false
flag : String -> ?Char -> String -> CliArg

// [PureKun] 带值选项（--name VAL / -c VAL）
//   字段为 ?T → 不出现 → Nil；字段为 T → 无缺省则必填；字段为 List T → 可重复
option : String -> ?Char -> String -> CliArg

// [PureKun] 计数型标志（-c → 1，-ccc → 3），不出现 → 0
count : String -> ?Char -> String -> CliArg

// [PureKun] 位置参数（按声明顺序消费 token）
arg : String -> String -> CliArg
```

#### 修饰器

```kun
// [PureKun] 设置缺省值（编译期序列化，解析时按目标字段类型反序列化）
withDefault : a -> CliArg -> CliArg

// [PureKun] 选项依赖
withRequires : String -> CliArg -> CliArg

// [PureKun] 为 Bool 型 flag 自动生成 --no-<name> 否定形式
withNegation : CliArg -> CliArg

// [PureKun] 环境变量回退：命令行未提供时从指定环境变量读取
withEnvVar : String -> CliArg -> CliArg

// [PureKun] 自定义校验（签名 a -> Result a String）
withValidator : (a -> Result a String) -> CliArg -> CliArg
```

#### 解析

```kun
// [PureKun] 互斥组（at most one：成员中最多允许一个出现）
oneOf : String -> List CliArg -> CliArgGroup

// [Primitive] 解析原始参数列表为目标 Record（类型 a 由调用点 HM 推断）
parse : CliSpec -> List String -> Result a CliError

// [Primitive] 将解析错误转为人类可读字符串
show : CliError -> String
```

> 完整设计、命名约定、kebab-case→camelCase 映射、子命令及示例见 [`Cli` 模块](cli.md)。

### 示例

```kun
import Cli
import IO

type BuildConfig =
  { verbose : Bool
  , output  : ?Path
  , jobs    : Int
  , source  : String
  }

parseConfig : List String -> Result BuildConfig Cli.CliError
parseConfig =
  Cli.parse
    { meta  = { intro = "build.kun", text = "Compiles and packages." }
    , args =
        [ Cli.flag "verbose" 'v' "Enable verbose output"
        , Cli.option "output" 'o' "Output file path"
        , Cli.option "jobs" 'j' "Parallel jobs" |> Cli.withDefault 4
        , Cli.arg "source" "Source directory"
        ]
    }

main : List String -> Unit
main = \raw ->
  do
    case parseConfig raw of
      Ok cfg ->
        IO.println f"building {cfg.source} with {cfg.jobs} jobs"
      Err err ->
        IO.println (Cli.show err)
```

## `Random` — 随机数

### 定位

提供密码学安全的伪随机数生成器。所有函数均为效应函数，**只能在 `do` 块中调用**。

需显式导入：

```kun
import Random
```

### API

```kun
// [Primitive] 生成随机整数  // [推迟 v0.5]
int : Int -> Int -> Int

// [Primitive] 生成随机字节  // [推迟 v0.5]
bytes : Int -> Bytes

// [Primitive] 生成随机浮点数  // [推迟 v0.5]
float : Float -> Float -> Float

// [Primitive] 随机打乱列表  // [推迟 v0.5]
shuffle : List a -> List a
```

### 示例

```kun
import Random

do
  n = Random.int 1 100
  f = Random.float 0.0 1.0
  s = Random.shuffle [1, 2, 3, 4, 5]
```

语义场景：唯一 ID 生成、端口选择、测试数据、负载分配。

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
// [Primitive] 从 List 构造
fromList : List t -> Stream t

// [Primitive] 从 start 到 end（不含），步长为 step
range : Int -> Int -> Int -> Stream Int

// [PureKun] — 变化为一对多映射然后展平
flatMap : (a -> Stream b) -> Stream a -> Stream b

// [PureKun] 拼接两个 Stream
append : Stream a -> Stream a -> Stream a

// [PureKun] 逐元素配对
zip : Stream a -> Stream b -> Stream (a, b)

// [PureKun] 带状态的折叠（emit 中间状态）
scan : (a -> b -> b) -> b -> Stream a -> Stream b

// [PureKun] 查找第一个匹配元素
find : (a -> Bool) -> Stream a -> ?a

// [PureKun] 所有元素是否满足谓词
all : (a -> Bool) -> Stream a -> Bool

// [PureKun] 是否存在满足谓词的元素
any : (a -> Bool) -> Stream a -> Bool

// [PureKun] 排序（需完全物化，仅对有限 Stream）
sort : Stream a -> Stream a

// [PureKun] 连续分组
group : (a -> a -> Bool) -> Stream a -> Stream (List a)

// [PureKun] 取第 n 个元素
nth : Int -> Stream a -> ?a

// [Primitive] 创建无限迭代的 Stream
iterate : (a -> a) -> a -> Stream a
```

`range start end` 为 `range start end 1` 的语法糖——编译器在约束生成阶段将 2 参数的 `range` 调用自动脱糖为 3 参数形式，HM 类型检查仅需处理 `Int -> Int -> Int -> Stream Int` 单一签名。

#### 变换（惰性）

```kun
// [PureKun] 对每个元素应用函数
map : (a -> b) -> Stream a -> Stream b

// [PureKun] 保留满足条件的元素
filter : (a -> Bool) -> Stream a -> Stream a

// [PureKun] 取前 n 个元素
take : Int -> Stream a -> Stream a

// [PureKun] 丢弃前 n 个元素
drop : Int -> Stream a -> Stream a

// [PureKun] 取元素直到谓词首次为 false
takeWhile : (a -> Bool) -> Stream a -> Stream a

// [PureKun] 丢弃元素直到谓词首次为 false
dropWhile : (a -> Bool) -> Stream a -> Stream a

// [Primitive] 按 \n 切分
lines : Stream String -> Stream (Result String LineError)

// [Primitive] 同上，指定行长上限
linesMax : Int -> Stream String -> Stream (Result String LineError)
```

`LineError` 定义：

```kun
type LineError =
  LineTruncated { partial_len: Int }
```

```kun
// [PureKun] 映射并跳过失败
parseMap : (a -> Result b e) -> Stream a -> Stream b

// [PureKun] 映射并保留 Result
parseMapKeep : (a -> Result b e) -> Stream a -> Stream (Result b e)
```

变换不触发求值，只构造新的惰性流。

#### 消费（终端）

```kun
// [Primitive] 收集为 List
toList : Stream a -> List a

// [Primitive] 遍历每个元素
iter : (a -> Unit)! -> Stream a -> Unit

// [Primitive] 折叠
fold : (b -> a -> b) -> b -> Stream a -> b

// [Primitive] 全文收集为 String
string : Stream String -> String

// [Primitive] 二进制读取
bytes : Stream a -> Bytes
```

终端操作驱动求值，逐一拉取元素。

#### 错误处理辅助

```kun
// [PureKun] 映射并丢弃 Nil
filterMap : (a -> ?b) -> Stream a -> Stream b
// -> Stream.filterMap Result.ok stream — 过滤掉所有 Err 元素
```

#### 纯/效应操作分类

| 操作 | 类别 | 说明 |
|------|------|------|
| `Stream.map` / `Stream.filter` / `Stream.take` / `Stream.drop` / `Stream.takeWhile` / `Stream.dropWhile` / `Stream.flatMap` / `Stream.append` / `Stream.zip` / `Stream.scan` / `Stream.find` / `Stream.all` / `Stream.any` / `Stream.sort` / `Stream.group` / `Stream.nth` | **纯** | 惰性变换，不触发 IO |
| `Stream.parseMap` / `Stream.parseMapKeep` | **纯** | 同上 |
| `Stream.lines` | **纯** | 仅标记换行边界，不触发读取 |
| `Stream.toList` / `Stream.iter` / `Stream.fold` | **终端** | 驱动求值；`Stream.iter` 声明了 `(a -> Unit)!` 回调，自身为效应函数（必须在 `do` 块中调用）；纯 Stream（`range`/`fromList`）的 `Stream.toList`/`Stream.fold` 可在 `do` 外使用 |
| `Stream.string` / `Stream.bytes` | **终端** | 同上 |
| `Stream.fromList` | **纯** | 从纯 List 构造，无 IO 绑定 |

> **回调纯函数约束**：`Stream.map`、`Stream.filter`、`Stream.take`、`Stream.parseMap`、`Stream.parseMapKeep` 的回调参数**必须为纯函数**。这些是惰性变换，不应掺杂副作用。`Stream.iter` 的回调必须为**效应函数**（签名标注 `(a -> Unit)!`），用于逐元素执行副作用。

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
  Cmd.cat p"/var/log/syslog"
    |> Stream.lines
    |> Stream.filter (String.contains "ERROR")
    |> Stream.iter IO.println
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
// [Primitive] 输出字符串到 stdout（无换行）
print : String -> Unit

// [Primitive] 输出字符串到 stdout（自动换行）
println : String -> Unit

// [Primitive] 从 stdin 读取一行
readln : -> String

// [Primitive] 输出到标准错误（stderr）
eprint : String -> Unit

// [Primitive] 输出到标准错误并换行
eprintln : String -> Unit

// [Primitive] 从标准输入读取原始字节
readBytes : Int -> Result Bytes IOError

// [Primitive] 读取标准输入全部内容为字符串
readAll : -> String

// [Primitive] 读取标准输入全部内容为原始字节
readAllBytes : -> Bytes

// [Primitive] 标准输出是否连接到终端
isTerminal : Bool

// [Primitive] 强制刷新标准输出缓冲区
flush : -> Unit
```

### 示例

```kun
import IO

do
  IO.print "Enter name: "
  name = IO.readln
  IO.println f"hello, {name}"

// 管道模式：读取全部 stdin
do
  content = IO.readAll
  IO.println f"received {String.length content} bytes"

  data = IO.readAllBytes
  IO.println f"binary: {Bytes.length data} bytes"
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
// [Primitive] 读取环境变量，不存在返回 Nil
getenv : String -> ?String

// [Primitive] 列举所有环境变量
list : Map String String

// [Primitive] 检查环境变量是否存在
contains : String -> Bool
```

### 示例

```kun
import Env

do
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
// [Primitive] 列出目录内容
list : Path -> Result (List Path) IOError

// [Primitive] 创建目录
mkdir : Path -> Result Unit IOError

// [Primitive] 递归创建目录树（等价于 mkdir -p）
mkdirAll : Path -> Result Unit IOError

// [Primitive] 读取文件为字符串
// 注：`File.exists` 已移除——`File.stat p |> Result.isOk` 等价，且更高效（单次 stat 同时获取元数据）
readString : Path -> Result String IOError

// [Primitive] 读取文件为 Bytes 流
readBytes : Path -> Result (Stream Bytes) IOError

// [Primitive] 写入字符串到文件
writeString : Path -> String -> Result Unit IOError

// [Primitive] 写入 Bytes 流到文件
writeBytes : Path -> Stream Bytes -> Result Unit IOError

// [Primitive] 获取文件元数据
stat : Path -> Result Stat IOError

// [Primitive] 创建/更新时间戳
touch : Path -> Result Unit IOError

// [Primitive] 删除文件
remove : Path -> Result Unit IOError

// [Primitive] 删除目录
removeDir : Path -> Result Unit IOError

// [Primitive] 创建临时文件，脚本退出时自动清理，返回路径
createTempFile : -> Result Path IOError

// [Primitive] 创建临时目录，脚本退出时自动清理，返回路径
createTempDir : -> Result Path IOError

// [PureKun] 复制文件/目录
copy : Path -> Path -> Result Unit IOError

// [Primitive] 移动/重命名文件
rename : Path -> Path -> Result Unit IOError

// [Primitive] — 需要 opendir/readdir/closedir 系统调用；glob 遍历的路径受 Landlock 规则约束——仅返回 Landlock 允许路径内的匹配项
glob : String -> Path -> Result (List Path) IOError

// [Primitive] 追加字符串到文件末尾
appendString : Path -> String -> Result Unit IOError

// [Primitive] 追加二进制数据到文件末尾
appendBytes : Path -> Bytes -> Result Unit IOError

// [Primitive] 以字符流形式逐行读取文件
readLines : Path -> Stream (Result String IOError)

// [Primitive] 递归遍历目录
walkDir : Path -> Stream Path

// [Primitive] 获取当前工作目录（脚本启动时冻结）
currentDir : Path

// [Primitive] 递归删除目录及其内容
removeAll : Path -> Result Unit IOError

// [Primitive] 用户主目录路径
homeDir : Path

// [Primitive] 系统临时目录路径
tempDir : Path

// [Primitive] 原子写入——写入临时文件后 rename
atomicWriteString : Path -> String -> Result Unit IOError
```

#### 关联类型

##### `File.Type` — 文件类型枚举

```kun
type Type
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

```kun
// [PureKun] 转换为文件类型名称
toString : Type -> String
```

##### `File.Mode` — 文件权限位

```kun
type Mode = Mode Int    // 八进制权限位，如 0o755、0o644

// [PureKun] 构造，调用者须确保参数为合法八进制权限位，非法输入 panic
of : Int -> Mode
// [PureKun] 所有者是否可读
isReadable : Mode -> Bool
// [PureKun] 所有者是否可写
isWritable : Mode -> Bool
// [PureKun] 所有者是否可执行
isExecutable : Mode -> Bool
// [PureKun] 安全构造，非法权限位（超出 0o777）返回 `Err`
fromInt : Int -> Result Mode String
// [PureKun] 提取八进制权限值
toInt : Mode -> Int
// [PureKun] 转换为八进制权限字符串
toString : Mode -> String
```

##### `File.Stat` — 文件元数据

由 `File.stat` 返回。

```kun
type Stat =
  { size      : Int
  , type      : Type
  , mtime     : DateTime
  , ctime     : DateTime
  , atime     : DateTime
  , mode      : Mode
  , owner     : Uid
  , group     : Gid
  , ownerName : String
  , groupName : String
  , device    : ?{ major : Int, minor : Int }
  }
```

`Stat` 辅助函数（纯）：
- `isDir : Stat -> Bool` — 等价于 `s.type == Directory`
- `isFile : Stat -> Bool` — 等价于 `s.type == Regular`
- `isSymlink : Stat -> Bool` — 等价于 `s.type == SymbolicLink`

> 注：`File.isDir`/`File.isFile`/`File.isSymlink` 已移除——通过 `File.stat` 获取 `Stat` 记录后使用上述纯访问器即可，避免多次 stat 系统调用。`File.exists` 同理：`File.stat p |> Result.isOk`。

- `owner`/`group` 为数字 ID（`Uid`/`Gid`），源于 `stat` 系统调用的原始返回值
- `device` 仅当 `type` 为 `CharDevice` 或 `BlockDevice` 时有值，其余文件类型为 `Nil`

> **MVP 已知限制 — 阻塞型文件**：`readString` 和 `readBytes` 通过 `read(2)` 系统调用实现，在 FIFO（命名管道）、socket、字符设备等阻塞型文件上会无限期阻塞直到对端写入或连接。MVP 不提供超时参数。
>
> 未来方案（v1.1 候选）：为 `readString` 和 `readBytes` 增加可选的 `Duration` 超时参数。
>
> 临时规避：将阻塞读取放入 `Cmd.cat?` 子进程并用 `Cmd.timeout` 包裹——子进程超时后 `Cmd.timeout` 返回 `Err`，父进程不受影响。

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

  // 创建临时文件
  case File.createTempFile of
    Ok tmp ->
      defer (File.remove tmp)
      File.writeString tmp "content"
      IO.println f"wrote to {tmp}"
    Err _ ->
      IO.println "failed to create temp file"
```

## `Cmd` — Command 工具与命令调用

### 定位

`Cmd` 模块提供类型化 OS 命令调用。所有函数按执行时机分为纯操作（构造和修饰 Command 值）与效应操作（立即执行）。

需显式导入：

```kun
import Cmd
```

### API

#### Command 构造（编译器内置语法）

```kun
// <bin> 为动态命令名——Cmd.ls、Cmd.git、Cmd["ntfs-3g"] 等均为合法形式
// [编译器内置语法] Cmd.<bin> 构造 Command 值
// [Primitive] <bin>?  : ?[options] -> posArgs... -> Result (Stream String) CommandError  // 立即执行
```

#### OS 管道

```kun
// [PureKun] 将多个 Command 连接为 OS 管道链（纯操作，延迟执行）
pipe : List Command -> Command

// [Primitive] 同上，失败时返回 Err 而非 panic（效应函数，立即执行）
pipe? : List Command -> Result (Stream String) CommandError
```

#### 修饰函数（纯操作，接收并返回 Command）

```kun
// [PureKun] 添加环境变量到子进程
withEnv : Map String String -> Command -> Command

// [PureKun] 追加原始 argv token（用于不适合 camelCase 自动映射的 flag）
withRawOpt : String -> ?String -> Command -> Command

// [PureKun] 注入 stdin（字符串模式）
withStdin : String -> Command -> Command

// [PureKun] 注入 stdin（流式模式，适用于大体积输入）
withStdin : Stream Bytes -> Command -> Command

// [PureKun] 将 stderr 合并到 stdout 流
mergeStderr : Command -> Command

// [PureKun] 指定子进程工作目录（fork 后、exec 前 chdir）
withWorkDir : Path -> Command -> Command

// [PureKun] 指定子进程执行用户（需 OS 级权限）
withRunAs : String -> Command -> Command  // [推迟 v1.0]

// [PureKun] 从文件路径注入 stdin
withStdinFile : Path -> Command -> Command
```

#### 短路条件组合（纯操作，返回 Command）

```kun
// [PureKun] 前一个成功时执行后一个
andThen : Command -> Command -> Command

// [PureKun] 前一个失败时执行备选
orElse : Command -> Command -> Command
```

#### 立即执行（效应函数）

```kun
// [Primitive] 显式执行 Command 值，执行失败 panic（stdout 被消费但不保留）
exec : Command -> Unit

// [Primitive] 超时执行，过期返回 Err（立即 fork）
timeout : Duration -> Command -> Result (Stream String) CommandError  // [推迟 v1.0]

// [Primitive] 重试 n 次执行，每次失败后等待 interval（立即 fork）
retry : Int -> Duration -> Command -> Result (Stream String) CommandError  // [推迟 v1.0]

// [Primitive] PATH 查找命令位置，不可执行/未找到返回 Nil
which : String -> ?Path

// [Primitive] 收集 stdout 到 String（等同于 |> Stream.string）
stdoutToString : Command -> Result String CommandError

// [Primitive] 收集合并后的 stderr 到 String（需先 mergeStderr）
stderrToString : Command -> Result String CommandError

// [Primitive] 执行 Command 的安全变体——失败返回 Err 而不 panic
execSafe : Command -> Result Unit CommandError
```

#### 效应分类

| 操作 | 类别 | 说明 |
|------|------|------|
| `Cmd.<bin>` | **纯** | 构造 Command 值，不执行 |
| `Cmd.pipe` / `Cmd.withEnv` / `Cmd.withStdin` / `Cmd.withRawOpt` / `Cmd.mergeStderr` / `Cmd.withWorkDir` / `Cmd.withRunAs` / `Cmd.withStdinFile` | **纯** | 修饰函数，接收并返回 Command |
| `Cmd.andThen` / `Cmd.orElse` | **纯** | 短路条件组合，返回 Command |
| `Cmd.<bin>?` / `Cmd.pipe?` | **效应** | 立即执行并返回 Result |
| `Cmd.exec` / `Cmd.execSafe` / `Cmd.stdoutToString` / `Cmd.stderrToString` / `Cmd.timeout` / `Cmd.retry` | **效应** | 立即执行 |
| `Cmd.which` | **效应** | PATH 查找（需文件系统访问） |

> 完整语法、执行模型、选项映射及示例见 [OS 命令调用机制](command-system.md)。

### 示例

```kun
import Cmd

// 构造 Command（纯操作，可在外层使用）
c = Cmd.ls { long = true, all = true } p"/tmp"
  |> Cmd.withWorkDir p"/home"
  |> Cmd.mergeStderr

do
  // 管道隐式执行
  Cmd.ls {} p"/var/log"
    |> Stream.lines
    |> Stream.iter IO.println

  // 显式执行
  Cmd.exec c

  // 立即执行 + 错误处理
  case Cmd.ls? p"/nonexistent" of
    Ok stream -> ...
    Err e -> IO.println (CommandError.show e)

  // 短路条件
  Cmd.git.clone {} "https://..."
    |> Cmd.andThen (Cmd.make {} "-C" "repo")
    |> Cmd.exec
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
// [Primitive] 以指定退出码终止进程
// 若 n 超出 0..255 范围，运行时 panic（纯运行时错误 → 退出码 1）
exit : Int -> Unit

// [Primitive] 获取当前进程 ID
pid : -> Pid

// [Primitive] 获取当前进程的实时用户 ID
uid : -> Int

// [Primitive] 获取当前进程的实时组 ID
gid : -> Int

// [Primitive] — 可向任意 PID 发送信号；实际效果取决于 OS 级权限（CAP_KILL 或同 UID）；无沙箱模式下可影响系统服务
kill : Signal -> Pid -> Result Unit IOError

// [Primitive] 等待子进程——返回 ?ExitCode（无子进程时返回 Nil）
wait : -> ?ExitCode

// [Primitive] 阻塞等待指定时长
sleep : Duration -> Unit


```

#### 关联类型

##### `Process.Pid` — 进程 ID

```kun
type Pid = Pid Int    // 值域 1 .. 2^22-1（Linux 默认 pid_max）

// [PureKun] 构造 `Pid`，调用者须确保参数为合法进程 ID，非法输入 panic
of : Int -> Pid
// [PureKun] 检查 PID 是否在合法范围 `1..2^22-1` 内
isValid : Pid -> Bool
// [PureKun] 是否为 init 进程（PID == 1）
isInit : Pid -> Bool
// [PureKun] 安全构造，非法值（≤ 0 或 > 2^22-1）返回 `Err`
fromInt : Int -> Result Pid String
// [PureKun] 提取进程 ID 整数值
toInt : Pid -> Int
// [PureKun] 返回进程 ID 的字符串表示
toString : Pid -> String
```

##### `Process.ExitCode` — 退出码

```kun
type ExitCode = ExitCode Int    // 值域 0 .. 255（u8），0 成功，非零失败

// [PureKun] 0 — 成功
success : ExitCode
// [PureKun] 1 — 一般错误
generalError : ExitCode
// [PureKun] 127 — 命令未找到
commandNotFound : ExitCode

// [PureKun] 构造，调用者须确保参数在 `0..255` 内，非法输入 panic
of : Int -> ExitCode
// [PureKun] 检查退出码是否在合法范围 `0..255` 内
isValid : ExitCode -> Bool
// [PureKun] 退出码 == 0
isSuccess : ExitCode -> Bool
// [PureKun] 退出码 ≠ 0
isFailure : ExitCode -> Bool
// [PureKun] 安全构造，超出 `0..255` 返回 `Err`
fromInt : Int -> Result ExitCode String
// [PureKun] 提取退出码整数值
toInt : ExitCode -> Int
// [PureKun] 返回退出码的字符串表示
toString : ExitCode -> String
```

- `kill` 向任意进程发送信号，需要 OS 级权限（root 或进程所有者为当前用户）——失败返回 `Err (PermissionDenied)`
- `wait` 等待任意已 fork 的子进程退出并返回退出码；若无可回收子进程（`ECHILD`）返回 `Nil`

### 示例

```kun
import Process

do
  currentPid = Process.pid                     // → Process.Pid.of <当前进程 ID>
  IO.println f"pid: {Process.Pid.toInt currentPid}"

  Process.sleep 5s                             // 等待 5 秒
  Process.exit 0                               // 正常退出

  // 向进程发送信号
  case Process.kill SIGTERM targetPid of
    Ok _  -> IO.println "signal sent"
    Err _ -> IO.println "permission denied"
```

## `Hash` — 哈希函数

### 定位

`Hash` 模块提供密码学哈希函数，适用于文件完整性校验、数据指纹等场景。所有函数均为纯函数。

需显式导入：

```kun
import Hash
```

### API

```kun
// [Primitive] SHA-256 哈希
sha256 : Bytes -> Bytes
// [Primitive] SHA-256 哈希，返回十六进制字符串
sha256Hex : Bytes -> String

// [Primitive] SHA-256 流式哈希——逐块处理 Stream，避免大文件全部加载到内存
sha256Stream : Stream Bytes -> Bytes

// [Primitive] MD5 哈希 [推迟 v0.5]
md5 : Bytes -> Bytes
// [Primitive] MD5 哈希，返回十六进制字符串 [推迟 v0.5]
md5Hex : Bytes -> String
```

### 示例

```kun
import Hash

do
  case File.readBytes p"/path/to/file" of
    Ok data ->
      hash = Hash.sha256Hex data
      IO.println f"SHA-256: {hash}"
    Err _ ->
      IO.println "read failed"

// 大文件流式哈希
do
  case File.readBytes p"/path/to/large.iso" of
    Ok stream ->
      hash = Hash.sha256Stream stream
      IO.println f"SHA-256: {Bytes.toHex hash}"
    Err _ ->
      IO.println "read failed"
```

## `Base64` — Base64 编解码

### 定位

`Base64` 模块提供 Base64 编码与解码功能，适用于二进制数据传输、API 密钥编码等场景。

需显式导入：

```kun
import Base64
```

### API

```kun
// [Primitive] Base64 编码
encode : Bytes -> String
// [Primitive] Base64 解码
decode : String -> Result Bytes String
```

### 示例

```kun
import Base64

// 编码
data = Bytes.fromString "hello"
encoded = Base64.encode data  // → "aGVsbG8="

// 解码
case Base64.decode "aGVsbG8=" of
  Ok raw  -> ...
  Err _   -> IO.println "invalid base64"
```

## `Task` — 并发任务

### 定位

`Task` 模块提供并发命令执行能力，解决批量命令场景中 `List.iter` + `Cmd.*` 串行 fork 的性能瓶颈。所有函数均为效应函数。

需显式导入：

```kun
import Task
```

### API

```kun
// [Primitive] 并发执行命令列表，最大并行数为 n
spawn : Int -> List Command -> Stream (Result (Stream String) CommandError)

// [Primitive] 等待所有 Task 完成，收集结果
all : Stream (Result a e) -> List (Result a e)
```

- `spawn n cmds` 并发 fork 最多 `n` 个子进程，返回结果流（按完成顺序，非提交顺序）
- `all` 消费结果流，等待全部子进程退出后收集为 List
- 子进程仍受 `seccomp + rlimit` 约束，沙箱策略与单命令一致
- `Cmd.timeout`/`Cmd.retry` 是立即执行函数（返回 `Result`），**不可与 `Task.spawn` 组合**——`spawn` 需要 `List Command`（未执行）。批量超时控制通过 `Task.spawn` 的并发度参数间接实现：并发度限制 + 子进程各自的 rlimit CPU 限制 (`--cpu-limit`) 提供超时兜底

#### 运行时模型

`Task.spawn` 通过主线程的 **epoll/poll 事件循环**管理多个子进程的 stdout/stderr pipe——不引入额外线程。子进程 fork 后各自独立，彼此无共享内存。文件冲突由内核文件系统锁定处理（多进程写同一文件的行为由 OS 定义），Kun 不做额外管理。

> **MVP 不包含**：`Task` 模块（`spawn`/`all`）列为 v0.5 特性（见 [MVP 定义](../requirements/mvp.md)）。

### 示例

```kun
import Task

do
  files = [p"/tmp/a.log", p"/tmp/b.log", p"/tmp/c.log"]
  cmds  = List.map (\f -> Cmd.gzip {} f) files
  Task.spawn 4 cmds
    |> Task.all
    |> List.iter (\r ->
      case r of
        Ok _  -> IO.println "ok"
        Err e -> IO.println f"failed: {CommandError.show e}"
    )
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

// [Primitive] 从 JSON 字符串解析
fromString : String -> Result JsonValue String
// [Primitive] 转换为 JSON 字符串
toString   : JsonValue -> Result String String
```

- `JsonInt` 对应 JSON 中的整数（无小数点、无指数）
- `JsonFloat` 对应 JSON 中的浮点数（含小数点或指数）

#### 示例

```kun
import Parser.JSON

do
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

// [Primitive] 从 JSON 字符串反序列化（编译期代码生成）
fromJson : String -> Result a String
// [Primitive] 序列化为 JSON 字符串（编译期代码生成）
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

## `Test` — 测试断言

### 定位

`Test` 模块提供基础测试断言函数，用于编写自测试 Kun 脚本。`kun test` 子命令发现并执行测试文件，收集断言失败报告。所有断言函数在失败时通过 panic 报告错误（含文件名、行号、期望值、实际值），由测试运行器捕获。

> **推迟至 v1.0**：Test 模块在 MVP（v0.1）中仅提供类型签名作为设计参考，不实现。`kun test` 子命令同样推迟 v1.0。在 v1.0 前，Kun 脚本的验证通过直接运行脚本并检查退出码（`Cmd.<bin>?` 返回 `Result`）完成。

需显式导入：

```kun
import Test
```

### API

```kun
// [PureKun] 断言两个值相等
equal : a -> a -> String -> Unit

// [PureKun] 断言条件为 true
ok : Bool -> String -> Unit

// [PureKun] 断言不相等
notEqual : a -> a -> Unit

// [PureKun] 断言近似相等（浮点容差）
approxEqual : Float -> Float -> Float -> Unit

// [PureKun] 断言结果为 Ok
isOk : Result a e -> a

// [PureKun] 断言结果为 Err
isErr : Result a e -> e

// [PureKun] 断言值非 Nil
isSome : ?a -> a

// [PureKun] 断言值为 Nil
isNil : ?a -> Unit

// [PureKun] 断言 thunk 执行时 panic——捕获任何 panic 即通过
panics : (-> a) -> String -> Unit
```

- `equal expected actual message`：`expected == actual` 通过，否则 panic 并报告差异
- `ok condition message`：`condition` 为 `true` 通过，否则 panic
- `panics thunk message`：`thunk` 为 `-> a` 纯函数，若 `thunk ()` 触发 panic 则通过，正常返回则 panic（"expected panic"）。`panics` 仅接受纯函数 thunk（无 `do` 块或效应命名空间调用），所有 `Test` 断言均为纯函数

### 示例

```kun
import Test

// 测试脚本（tests/test-example.kun）
main : List String -> Unit
main = \_ ->
  do
    Test.equal 4 (2 + 2) "basic arithmetic"
    Test.ok (List.length [1, 2, 3] == 3) "list length"
    Test.panics (\ -> List.head []) "head of empty list panics"
    IO.println "all tests passed"
```

测试文件约定：
- 测试文件放置在 `tests/` 目录下
- 文件名遵循 `test-*.kun` 模式
- 入口函数签名为 `main : List String -> Unit`
- `kun test` 自动发现并运行所有测试文件，报告通过/失败统计


## 导入一览

| 模块 | 导入方式 | 说明 |
|------|---------|------|
| `Function` | 始终缺省可用 | `identity`、`always`、`<\|`、`\|>`、`<<`、`>>` |
| `Nil` | 变体 `Nil` 缺省可用；函数需 `import Nil` | `withDefault`、`map`、`orElse`、`toResult`、`andThen` |
| `Bytes` | `import Bytes` | 二进制数据操作 |
| `Char` | `import Char` | 字符分类与转换 |
| `Decimal` | `import Decimal` | 精确十进制数值 |
| `Int` | `import Int` | 整数操作、幂运算、钳制及互转 |
| `Float` | `import Float` | 浮点操作、数学函数、常量及互转 |
| `String` | `import String` | 字符串操作及类型互转（`toString` 为编译器级泛型） |
| `Regex` | `import Regex` | 正则匹配与替换 |
| `Hash` | `import Hash` | 哈希函数（SHA-256） |
| `Base64` | `import Base64` | Base64 编解码 |
| `List` | `import List` | 列表操作 |
| `Map` | `import Map` | 映射表操作 |
| `Set` | `import Set` | 集合操作 |
| `Result` | `import Result` | 错误处理组合子 |
| `Cli` | `import Cli` | 命令行参数解析（类型驱动，auto --help，子命令） |
| `Random` | `import Random` | 随机数与洗牌 |
| `Stream` | `import Stream` | 惰性序列 |
| `Validator` | `import Validator` | 校验函数（`oneOf`/`range`/`nonEmpty`/`regex`），供 `Cli.withValidator` 等使用 |
| `IO` | `import IO` | 控制台 IO |
| `Env` | `import Env` | 环境变量 |
| `File` | `import File` | 文件操作及关联类型（`File.Type`/`File.Mode`/`File.Stat`） |
| `Cmd` | `import Cmd` | 命令调用 |
| `Task` | `import Task` | 并发命令执行（`spawn`/`all`） |
| `Process` | `import Process` | 进程控制（`exit`/`pid`/`uid`/`gid`/`kill`/`wait`/`sleep`）及关联类型（`Process.Pid`/`Process.ExitCode`） |
| `Duration` | `import Duration` | 时间段操作 |
| `Path` | `import Path` | 路径操作函数（类型标注无需导入） |
| `Signal` | `import Signal` | 信号枚举与注册 |
| `IOError` | `import IOError` | 系统调用结构化错误 |
| `CommandError` | `import CommandError` | 命令执行语义化错误 |
| `DateTime` | `import DateTime` | 时间点操作（`format`/`parse`/`year` 等） |
| `Uid` | `import Uid` | 用户 ID 操作 |
| `Gid` | `import Gid` | 组 ID 操作 |
| `Parser.JSON` | `import Parser.JSON` | JSON 解析 |
| `Parser.Record` | `import Parser.Record` | Record 反序列化 |
| `Test` | `import Test` | 测试断言（`equal`/`ok`/`panics`） |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.17 | 新增 `List.sortBy`、`Stream.takeWhile`/`Stream.dropWhile`、`Duration.fromMillis`、`DateTime.toUnixMillis`（P1+P2 最后补全） |
| 2026.06.17 | FileType/FileMode/FileStat 并入 File 模块（`File.Type`/`File.Mode`/`File.Stat`）；Pid/ExitCode 并入 Process 模块（`Process.Pid`/`Process.ExitCode`）；新增 `Bytes.slice`/`Bytes.contains`；净消除 5 模块（41→36） |
| 2026.06.17 | 移除 `File.changeDir`（全局可变状态），`Cmd.withCwd` 更名为 `Cmd.withWorkDir` |
| 2026.06.17 | 移除 `Path.cwd`（与 `File.currentDir` 冗余，`getcwd()` 归属 File 更合理） |
| 2026.06.17 | 新增 `Bytes.length`、`IO.readAll`/`IO.readAllBytes`、`String.repeat`（P0+P1+P2 补全） |
| 2026.06.17 | Math 模块并入 Float（pi/e/sin/cos/tan/exp/log/log2/log10/pow/min/max/clamp 迁入）；移除 Math 模块；Int 新增 pow/clamp |
| 2026.06.17 | 标准库深度精简：移除 Math 反三角/双曲/角度转换/hypot/tau（11 项）、Int.neg、Float.neg、List.intersperse/product、Stream.cycle/repeat；新增 Int.min/max、String.trimStart/trimEnd/padStart/padEnd、Hash.sha256Stream、DateTime.fromUnixMillis、List.range |
| 2026.06.17 | 标准库精简与补充：移除 `Sys`/`Port`/`IpAddress`/`SocketAddr`/`Errno` 模块（功能由 `Cmd.xxx` 替代或并入 IOError）；移除非必要的 File 函数（`chmod`/`chown`/`symlink`/`readlink`）和 Env 函数（`setenv`/`unsetenv`）、FileMode 低频谓词（`isSetuid`/`isSetgid`/`isSticky`）；新增 `DateTime` 算术（`+ Duration`/`- Duration`/`- DateTime`/`compare`/`before`/`after`）及 `DateTime.now`；新增 `Process.uid`/`Process.gid`；新增 `Path` 工具函数（`resolve`/`normalize`/`isAbsolute`/`isRelative`/`relative`）；新增 `Hash` 模块（SHA-256）和 `Base64` 模块 |
| 2026.06.15 | 审计修复四轮：73 函数 API 补全（List/Map/Set/Stream/IO/File/Cmd/Process/Test 模块）；Test 模块推迟 v1.0；Uid.current/Gid.current 移除（Sys.uid/gid 替代） |
| 2026.06.15 | 审计修复六轮：分类表更新 + 效应列表补全 + Cmd 函数推迟标注 |
| 2026.06.14 | `File` 新增 `mkdir`/`mkdirAll`/`exists`；`Bytes` 新增 `fromString`/`toString`；`Map` 新增 `remove`；`String` 新增 `replaceAll`；新增 `Test` 模块（`equal`/`ok`/`panics`） |
| 2026.06.14 | `List.iter`/`Stream.iter`/`Signal.on` 签名新增 `(a -> b)!` 效应回调标注——回调必须是效应函数；新增 `Cmd.exec : Command -> Unit` 显式执行；Stream IO 消费示例更新 |
| 2026.06.13 | 示例代码语法合规修复；新增 `Regex`/`Duration`/`Set`/`Task` 模块；`Map` API 签名泛化（`k`/`v`）；`List` 新增 `sort`/`slice`/`take`/`drop`/`all`/`any`；`Process` 新增 `kill`/`wait`；`File` 新增 `glob`；`Regex` 新增 `fromString` |
| 2026.06.12 | `Nil` 模块新增 `andThen`，`maybe` 重命名为 `withDefault`；新增 `Decimal` 精确十进制类型；`Float` 模块新增 `approxEqual` |
| 2026.06.11 | 新增 `Math` 模块、`Function` 模块（缺省可用的 `identity`/`always`/`<\|`/`\|>`/`<<`/`>>`）；`Pid`/`Port`/`ExitCode`/`DateTime` 改为 newtype 形式，定义 `of`/`isValid`/`fromInt`；新增 `Nil` 模块（`maybe`/`map`/`orElse`/`toResult`）；`FileType` 变体重命名（`Regular`/`SymbolicLink`/`CharDevice`）；`JsonNumber` 拆分为 `JsonInt`/`JsonFloat`；新增 `String` 模块（`toString` 及类型互转函数）；`IO` 改为需显式导入；`Path` 新增 `(++)` 及 `fromString`/`toString`；`Int`/`Float`/`String` 的内置操作移入各自模块并需显式导入；`FileMode` 新增 `of`/`fromInt`；`FileStat` 新增 `device` 字段；移除 `Time` 模块，`sleep` 移至 `Process`，获取当前时间作为 `Sys.time` 实现；所有模块按「定位」「API」「示例」统一结构；重新引入 `Validator` 模块（`oneOf`/`range`/`nonEmpty`/`regex`），更新 `Cli` 章节同步最新设计 |
| 2026.06.10 | 架构重设计：移除 `IO` 类型标记、`Validator`、`RunAs`；新增 `CommandError`、`Cmd.*`/`Cmd.pipe`/`Cmd.withEnv`/`Cmd.withStdin`/`Cmd.withRawOpt`/`Cmd.mergeStderr`、`Parser.Record`；`Uid`/`Gid` 改为 `Int` newtype；`Signal.on` 移至 `Signal` 模块 |
| 2026.05.27 | MVP 基础标准库类型设计定型 |
