# 语法设计

## 设计原则

1. **表达式导向**：所有语句均为表达式，具有返回值
2. **简洁一致**：借鉴 Elm（为主）、Haskell 和 Rust，避免冗余关键字
3. **声明与实现分离**：类型标注与值定义为独立行，便于读取
4. **显式边界**：副作用（`do` 块）、错误处理（`Result`）均有显式语法标记
5. **最小惊喜**：优先采用 Shell 用户熟悉的符号约定

## 注释

```kun
// 行注释
//
// 多行注释也是每行以 // 开头
//
// 类型、函数、模块上的注释均视为文档注释
// 注释内容支持 Markdown 语法
//
// 文档注释中的 Markdown：
// - **粗体**、`代码`、[链接](url)
// - 列表、表格、代码块
```

Kun 仅支持 `//` 风格的注释。没有块注释语法（`/* */`）。连续多行 `//` 构成多行注释块。

文档注释规则：
- 直接位于 `type`、函数定义、`module` 声明上方的注释行自动视为文档注释
- 文档注释内容支持 Markdown 语法，生成文档时会被渲染
- 非附着在上述结构上的注释视为普通代码注释，不进入文档生成

## 字面量

| 类型 | 语法 | 示例 |
|------|------|------|
| Int | 十进制、`0x`/`0o`/`0b` 前缀、`_` 分隔 | `42`, `-3`, `0xFF`, `1_000_000` |
| Float | 十进制浮点或科学计数法 | `3.14`, `-2.5e10` |
| Bool | 关键字 | `true`, `false` |
| String | 双引号包裹，支持转义序列 | `"hello"`, `"line1\nline2"` |
| String (多行) | `"""` 包裹，自动去公共缩进 | `"""` |
| String (多行插值) | `f"""` 包裹，支持 `{expr}` 插值 | `f"""` |
| String (插值) | `f"..."` 前缀 + 双引号，`{expr}` 嵌入，可选 `:` 格式说明 | `f"count: {n}"`, `f"pi: {3.14:.2f}"` |
| Bytes | `0x` 前缀后接十六进制字节序列 | `0x48656C6C6F` |
| Char | 单引号包裹 | `'A'`, `'\n'`, `'好'` |
| Regex | `r"..."` 前缀 + 双引号 | `r"(?i)[a-z]+"` |
| Duration | 整数 + 单位后缀 | `5s`, `100ms`, `2h`, `30m`, `1d`, `500us`, `200ns` |
| Unit | 无字面量 | — |
| Path | `p"..."` 前缀 + 双引号 | `p"/tmp/foo"`, `p"./foo"`, `p"/tmp/foo.sh"` |

前缀字面量（`p"..."`、`r"..."`、`f"..."`）的内容为**原始字符串**，不处理转义序列，仅双引号本身通过 `\"` 转义。这与普通字符串 `"..."`（处理 `\n`、`\t` 等转义）形成对照。

### 多行字符串

以 `"""` 开头和结尾，自动去除每行开头的公共缩进：

```kun
content = """
    {
      "name": "Kun",
      "version": "0.1"
    }
    """
// → "{\n  \"name\": \"Kun\",\n  \"version\": \"0.1\"\n}"
```

多行插值字符串以 `f"""` 开头：

```kun
name = "Kun"
content = f"""
    {name} version 0.1
    """
```

规则：
- 开头 `"""` 或 `f"""` 后紧跟换行
- 结尾 `"""` 前的缩进量决定公共缩进基准
- 每行开头的公共缩进被移除
- 首行和末行的空行不计入内容
- `f"""` 内支持插值语法 `{expr}`，普通 `"""` 不支持

容器字面量：

```kun
[1, 2, 3]           // List
#{ "a" = 1 }        // Map
#[1, 2, 3]          // Set
(1, "hello", true)  // Tuple
{ name = "Kun" }    // Record
```

### Map 字面量与积类型的区别

```kun
#{ "a" = 1, "b" = 5 }    // Map：键名和数量不确定，值类型相同
{ name = "Kun" }         // 积类型（Record）：字段名和数量确定，字段类型可不相同
```

Map 使用 `=` 分隔键值对。Map 不支持解构（因为键不确定），但支持索引访问和更新：

```kun
name: ?String
name = data["name"]

key = "value"
val  = data[key]

newData = #{ data | "value" = 2 }    // Map 更新
```

对 List、Set 的更新只能通过类型模块中的函数，没有简单形式。

## 字符串插值与格式化

### 语法

以 `f"..."` 为前缀的字符串字面量支持嵌入表达式和格式化说明：

```kun
f"count: {n}"                      // 变量插值，自动 toString(n)
f"result: {a + b}"                 // 任意表达式
f"pi = {3.14159:.2f}"              // 带格式说明
f"{name:>10}"                      // 字符串对齐
f"hex: {255:x} / {255:X}"         // 整数进制
```

嵌入表达式使用大括号 `{expr}` 包裹，可在其中任意位置出现。

### 自动 toString

未指定格式说明时，`{expr}` 等价于 `toString(expr)`：

```kun
n = 42
// → "answer is 42"
f"answer is {n}"
"answer is " ++ toString n    // 等价
```

对 `String` 类型，`toString` 直接返回自身。

### 格式说明

格式说明以冒号 `:` 分隔，语法为 `{expr:format_spec}`。格式说明按类型分类：

#### 整数（Int）

| 格式符 | 含义 | 示例 |
|--------|------|------|
| (无) | 十进制，等价于 `toString` | `{42}` → `"42"` |
| `d` | 十进制（显式） | `{42:d}` → `"42"` |
| `x` | 十六进制（小写） | `{255:x}` → `"ff"` |
| `X` | 十六进制（大写） | `{255:X}` → `"FF"` |
| `o` | 八进制 | `{63:o}` → `"77"` |
| `b` | 二进制 | `{5:b}` → `"101"` |

#### 浮点（Float）

| 格式符 | 含义 | 示例 |
|--------|------|------|
| (无) | `toString` | `{3.14}` → `"3.14"` |
| `f` | 固定小数点（默认 6 位） | `{3.14:f}` → `"3.140000"` |
| `.Nf` | 精度 N 位小数 | `{3.14159:.2f}` → `"3.14"` |
| `e` | 科学计数法（默认 6 位） | `{1000:e}` → `"1.000000e+03"` |
| `.Ne` | 科学计数法 + 精度 | `{1000:.2e}` → `"1.00e+03"` |

#### 字符串

| 格式符 | 含义 | 示例 |
|--------|------|------|
| (无) | 原样输出 | `{"hi"}` → `"hi"` |
| `>N` | 右对齐，宽度 N | `{"hi":>5}` → `"   hi"` |
| `<N` | 左对齐，宽度 N | `{"hi":<5}` → `"hi   "` |
| `^N` | 居中，宽度 N | `{"hi":^5}` → `" hi  "` |
| `.N` | 截断到 N 字符 | `{"hello":.3}` → `"hel"` |

对齐格式支持填充字符指定（`fill` + `align`）：

```kun
f"{42:#>6}"     → "####42"    // # 填充，右对齐
f"{42:0>6}"     → "000042"    // 0 填充，右对齐
```

#### DateTime

`DateTime` 类型采用 `%` 引导的格式描述符：

```kun
// → "2026-05-29 14:30:00.123 +0000"
f"{now:%yyyy-MM-dd HH:mm:ss.SSS Z}"
// → "2026-05-29"
f"{now:%yyyy-MM-dd}"
```

格式模板为字段名直接组合（如 `yyyy-MM-dd`），在 `f"..."` 字符串中整体以 `%` 开头进入格式模式。支持的字段名：
- `yyyy` — 四位数年份
- `yy` — 两位数年份
- `MM` — 两位数月份（01-12）
- `dd` — 两位数日期（01-31）
- `HH` — 两位数小时（00-23）
- `mm` — 两位数分钟（00-59）
- `ss` — 两位数秒（00-59）
- `SSS` — 三位数毫秒（000-999）
- `Z` — 时区偏移（+0000）

### 转义

f-string 的解析分为两个阶段：

- **原始内容**（`{...}` 之外的部分）：不处理转义序列，仅 `{` 需转义为 `\{` 表示字面量，`\"` 表示字面量双引号
- **表达式**（`{...}` 内部）：按常规 Kun 表达式解析，字符串字面量直接使用 `"` 无需转义

| 位置 | 需要输出 | 写法 |
|------|---------|------|
| 原始内容 | 字面量 `{` | `\{` |
| 原始内容 | 字面量 `}` | `\}` |
| 原始内容 | 字面量 `"` | `\"` |
| 表达式内 | 字面量 `"` | `"`（原生字符串字面量） |

示例：

```kun
f"brace: \{hello\}"         → "brace: {hello}"
f"quote: \""                → "quote: \""
f"list: { join ", " names }"    // 表达式内 " 无需转义
```

### 嵌套

f-string 中嵌入的表达式可包含字符串字面量，其内的引号无需转义。不支持嵌套 f-string（不可写 `f"outer {f"inner"}"`）：

```kun
f"list: { join ", " names }"    // 表达式内 " 无需转义
f"path: { p"/etc/hosts" }"     // 嵌入 Path 字面量
```

### 与普通字符串的关系

- `"..."` — 普通字符串，支持转义序列，`{` 无特殊含义
- `f"..."` — 插值字符串，`{expr}` 被求值并格式化，内容为原始字符串
- `p"..."` — Path 字面量，内容为原始字符串
- `r"..."` — Regex 字面量，内容为原始字符串
- 运行时类型：`"..."` 和 `f"..."` 均为 `String`，插值在编译期展开为 `toString`/格式化调用链

## 标识符与命名

| 类别 | 规则 | 示例 |
|------|------|------|
| 变量/函数 | 小写字母或下划线开头 | `map`, `identity`, `_temp` |
| 类型/变体 | 大写字母开头 | `Int`, `Result`, `Ok`, `Err` |
| 类型变量 | 小写字母，单字优先 | `a`, `b`, `key`, `value` |
| 模块 | 大写字母开头 | `List`, `Path`, `System` |

`'`（单引号）是标识符的合法字符，但不被赋予任何特殊语义（不代表重载、重写或变体关系）。用户可按约定使用，例如区分严格/惰性变体：

```kun
map   : (a -> b) -> List a -> List b
map'  : (a -> b) -> List a -> List b    // 用户的严格变体

value   : Int                           // 惰性绑定
value'  : Int                           // 用户约定的"立即求值"变体
```

## 类型声明

### 泛型语法

Kun 使用 **Elm 风格**的空格分隔泛型参数，不使用尖括号：

```kun
List Int                      // 单参数
?String                       // Nilable
Result String IOError         // 多参数
?(Result FileType IOError)    // Nilable + 多词类型用括号包裹
```

规则：
- 类型构造器与类型参数之间以空格分隔
- 多参数之间也以空格分隔
- 嵌套泛型用圆括号分组

### ADT（和类型）

```kun
type Color
  = Red
  | Green
  | Blue

type Result t e
  = Ok t
  | Err e

type SocketAddr
  = Tcp IpAddress Port
  | Udp IpAddress Port
```

变体字段支持三种形式：

```kun
type IpAddress
  = Ipv4 (Int, Int, Int, Int)                              // 无名字段（元组风格）
  | Ipv6 (Int, Int, Int, Int, Int, Int, Int, Int)

type Error
  = NotFound Path          // 无名字段（空格分隔）
  | PermissionDenied Path

type Color
  = Rgb { r : Int, g : Int, b : Int }    // 具名字段（Record 风格）
```

### Newtype

单变体 ADT 为 newtype：

```kun
type Uid
  = Uid Int
```

### 函数类型别名

可为函数类型定义别名：

```kun
type LongFunc = String -> Int -> Result { v : Int, l : String } String
```

`type` 后直接跟类型名和类型定义，无 `alias` 关键字。不支持为其他非函数类型定义别名（类型别名在导入时指定）。

### 类型标注

类型标注为独立声明行，与值定义分离：

```kun
add : Int -> Int -> Int
add = \x y -> x + y

identity : a -> a
identity = \x -> x

now : -> DateTime
now = \ ->
  do
    Sys.time

main : List String -> Unit
main = \_ ->
  do
    content = File.readString p"/tmp/foo"
    case content of
      Ok text -> IO.print text
      Err _   -> IO.println "failed"
```

函数类型语法：

```kun
-> T                     // 零参函数（仅 IO 效应）
T1 -> T2 -> T3           // 柯里化函数
(T1, T2) -> T3           // 元组参数（参数本身为元组）
List Int                 // 泛型
```

规则：
- 除非参数本身是元组类型，否则函数类型均为柯里化形式（`Int -> Int -> Int`）
- 零参函数类型 `-> T` 仅用于 IO 效应函数（纯零参函数退化为常量，使用 `let` 绑定）
- 单参数免除圆括号：`Int -> Int` 而非 `(Int) -> Int`

Record 类型：

```kun
{ name : String, version : String }
```

## 表达式

### 变量引用与字面量

```kun
42              // Int 字面量
"hello"         // String 字面量
[1, 2, 3]       // List 字面量
[1..10]         // List 范围字面量（惰性，等价于 range 1 11）
[0..99999]      // 大范围惰性列表，不预分配内存
myVariable      // 变量引用
```

`[start..end]` 范围字面量：左闭右开区间 `[start, end)`，生成 `List Int`。元素**惰性求值**——不预分配内存，仅在遍历时按需计算。适用于大范围迭代：

```kun
[0..1000000] |> filter (\n -> n % 2 == 0) |> take 10
```

### Lambda

```kun
\ -> expr                  // 零参 Lambda（仅用于 IO 效应函数）
\x -> x + 1                // 单参数
\x y -> x + y              // 多参数
\(x, y) -> x + y           // 元组解构（参数本身为元组）
\{x, y} -> x + y           // Record 解构
\[x, y] -> x + y           // List 解构（最少长度 2）
```

零参 Lambda `\ -> expr` 仅用于函数类型为 `-> T` 的 IO 效应函数。纯函数不允许定义为零参。

### 函数应用

函数应用通过空格分隔，不使用逗号：

```kun
identity 42
map (\x -> x * 2) list
File.readString p"/tmp/foo"
pid 1234
add 1 2
```

除非参数本身为元组类型，使用圆括号包裹元组参数：

```kun
plus (1, 2)    // 元组参数（单参数）
```

### 名字绑定

名字绑定均直接以 `a = b` 形式定义：

```kun
name = value
p = p"/tmp/foo"
(x, y, z) = tuple
{ name, version } = record
{ a, ..rest } = config       // 解构 a，剩余字段作为 Record 绑定到 rest
[x, y, ..rest] = list
{ x as x1, y as y1 } = point
```

`let ... in` 表达式用于确保多条语句之后有明确的唯一返回值：

```kun
a =
  let
    square = \x ->
      x * x
  in
    square 3
```

`let ... in` 并非仅针对多条绑定，它的作用与 Elm 中的 `let ... in` 一致：在一个表达式中引入局部定义，并最终产生一个明确的返回值。

### Case 表达式（模式匹配）

```kun
case expr of
  pattern1 -> result1
  pattern2 -> result2
  _        -> default
```

模式类型：

#### 变体模式

```kun
case parse "42" of
  Ok n  -> process n    // 变体模式 + 变量绑定
  Err _ -> handleError  // 通配忽略
```

#### List 模式

```kun
case list of
  []              -> 0
  [_]             -> 1
  [_, y]          -> 2 * y
  [1, _, z]       -> 3
  [_, _, _, ..rest] -> -1
```

列表模式的规则：
- `[]` 表示空列表
- `[a, b]` 匹配长度恰好为 2 的列表
- `[a, ..rest]` 匹配长度至少为 1，`rest` 为剩余部分
- `_` 为位置占位符

#### 元组模式

```kun
case tuple of
  (1, y) -> 1 + y
  (x, 2) -> 2 * x
  _      -> 0
```

#### Record 模式

```kun
case record of
  {x = 1, y = 2}        -> x * y      // 字面量匹配：x==1 且 y==2
  {x as x1, y}          -> x1 + y     // 别名绑定：x 绑定到 x1
  { name as n = "Wang" } -> f n       // 别名 + 字面量：字段 name 匹配 "Wang" 后绑定到 n
  _                     -> 0
```

规则：
- `{field = literal}` — 匹配字面量值
- `{field as alias}` — 将字段值绑定到别名
- `{field as alias = literal}` — 同时进行字面量匹配和别名绑定：先检查值是否等于字面量，匹配后将值绑定到别名
- 三种形式可在同一个 Record 模式中混用：`{x = 1, y as y1, z as z1 = 3}`

#### 守卫子句

```kun
case n of
  m when m > 0 && m <= 10  -> "small"
  m when m > 10            -> "large"
  _                        -> "other"
```

#### 通配模式

`_` 作为通配符（位置占位符），匹配任意值但不绑定：

```kun
case result of
  Ok _  -> "success"    // 忽略 Ok 内部的值
  Err _ -> "failed"     // 忽略 Err 内部的值
```

穷举检查：对自定义和类型（含 `Result`）、`Bool` 强制穷举。

### If 表达式

```kun
if condition then
  expr1
else if condition2 then
  expr2
else
  expr3
```

`if` 是表达式，必有返回值。`else` 分支不可省略。`else if then` 链可用于处理多分支。

### 三元表达式

```kun
condition ? expr1 : expr2
```

三元表达式是 `if condition then expr1 else expr2` 的简洁形式，适用于简单条件。

### 管道操作符

```kun
list |> map (\x -> x * 2)
```

将左侧表达式的值作为最后一个参数传入右侧函数。

### 反向管道操作符

```kun
sqrt <| add 1 3
```

`<|` 将右侧表达式的值作为参数传入左侧函数，是 `|>` 的反向形式，减少括号嵌套：

```kun
IO.print (sqrt (add 1 3))    // 无 <|

IO.print    // 有 <|
  <| sqrt
  <| add 1 3
```

### 函数组合操作符

```kun
f >> g >> h    // 从左向右组合：h(g(f(x)))
f << g << h    // 从右向左组合：f(g(h(x)))
```

`>>` 和 `<<` 用于组合函数。`f >> g` 表示先应用 `f` 再应用 `g`。`f << g` 表示先应用 `g` 再应用 `f`。

```kun
add1 = \x -> x + 1
double = \x -> x * 2
add1ThenDouble = add1 >> double    // 等价于 \x -> double (add1 x)
doubleThenAdd1 = add1 << double    // 等价于 \x -> add1 (double x)
```

### Do 块（顺序执行）

`do` 块按顺序执行效应操作。`do` 块内使用 `=` 绑定值：

无返回值的 `do` 块（类型为 `Unit`）：

```kun
main : List String -> Unit
main = \_ ->
  do
    content = File.readString p"/tmp/foo"
    case content of
      Ok text -> IO.print text
      Err _   -> IO.println "failed"
```

有返回值的 `do` 块使用 `do in` 语法：

```kun
countFiles : Path -> Int
countFiles = \dir ->
  do
    entries =
      Cmd.ls { all = true } dir
        |> Stream.lines
        |> Stream.toList
  in
    List.length entries
```

`do` 块规则：

- `do` 块内使用 `=` 绑定值
- 效应函数（`Cmd.*`、`IO.*`、`File.*` 等命名空间的函数 + 用户定义含 `do` 块的函数）只能在 `do` 块中调用
- 含 `do` 块的函数自动标记为效应函数
- 纯函数（无 `do` 块）不能调用效应函数
- 外层 `do` 块的效应上下文自动传播到 `if`/`case` 的每个分支

### Record 操作

```kun
{ name = "Kun", version = "0.1" }    // 创建
record.name                           // 字段访问
{ record | version = "0.2" }          // 更新（不可变复制+修改）
{a, ..rest} = config                  // 解构，剩余字段作为 Record 绑定到 rest

{x as x1, y as y1} = point            // 解构带别名
```

`{a, ..rest} = config` 将 Record 中的字段 `a` 解构出来，剩余字段作为新的 Record 绑定到 `rest`。剩余字段类型与原始 Record 去除 `a` 字段后的结构等价。`..rest` 必须出现在解构模式的末尾。

### 索引访问

```kun
list[i]        // List 索引，返回 ?t
str[i]         // String 索引，返回 Char
tuple.0        // Tuple 索引（0-based）
tuple.1

data["key"]    // Map 索引，返回 ?v
```

### 点调用

点号 `.` 仅用于积类型的字段投影和元组的索引访问，不能用于函数调用：

```kun
record.name    // 字段访问
tuple.0        // 元组索引
```

函数只从属于模块，通过模块导入后，以 `模块名.函数名` 形式调用：

```kun
import Path as P
P.parent p"/tmp/foo"    // 通过模块限定的函数调用
```

显式导入的函数可直接通过函数名调用，无需模块限定。

### 字段访问速记

在高阶函数中，可直接以 `.字段名` 形式获取积类型上的字段值：

```kun
records = [{ name = "a", size = 1 }, { name = "b", size = 5 }]

names = records |> map .name              // 等价于 map (\r -> r.name)
sizes = records |> map .size              // 等价于 map (\r -> r.size)

big = records |> filter (\r -> r.size > 3)  // 与 filter 结合
namesOfBig = big |> map .name
```

`.name` 等价于 `\x -> x.name`，适用于任何接受回调的高阶函数。

### 柯里化简写

Kun 函数默认柯里化。当函数已接收部分参数时，实际返回仍为函数，接受剩余参数：

```kun
contains "ERROR"          // String -> Bool，已接收第一个参数
filter (contains "ERROR") // 等价于 filter (\line -> contains "ERROR" line)

add 1                     // Int -> Int，已接收第一个参数
map (add 1)               // 等价于 map (\x -> add 1 x)
```

这种写法在管道中尤其简洁：

```kun
lines
  |> filter (contains "ERROR")
  |> map (String.slice 0 100)
  |> iter IO.print
```

### List 解构与展开

解构操作仅针对最小长度可确定的情况：

```kun
[a, b, ..rest] = list    // 解构前两个元素 + 剩余部分
```

对于长度不确定的 List，采用模式匹配：

```kun
case list of
  [] -> "empty"
  [a, ..rest] -> process a rest
```

List 展开语法：

```kun
newList = [1, 2, ..list]    // 在列表前方展开
merged  = [..la, 0, ..lb]   // 在列表中间展开
```

展开操作 `..list` 将 List 中的元素原地展开到新的 List 字面量中。

## 函数定义

函数定义由可选的类型标注行和值定义行组成：

```kun
add : Int -> Int -> Int
add = \x y -> x + y

increment = \x -> x + 1    // 或匿名函数绑定
```

顶层函数建议标注类型签名。局部函数可省略：

```kun
main =
  do
    double = \x -> x * 2
    IO.print (toString (double 21))
```

函数参数支持直接解构：

```kun
addPair : (Int, Int) -> Int                     // 元组参数解构
addPair = \(x, y) -> x + y

sumCoordinates : { x : Int, y : Int } -> Int    // Record 参数解构
sumCoordinates = \{x, y} -> x + y

firstThree : List Int -> (Int, Int, Int)         // List 参数解构（最少长度 3）
firstThree = \[a, b, c] -> (a, b, c)
```

### 多参数函数：空格分隔，单 Lambda

多参数函数使用**一个 `\` 后跟空格分隔的参数名列表**，而非 `\a -> \b -> \c ->` 箭头链：

```kun
// ✅ 正确：空格分隔，单 Lambda
add : Int -> Int -> Int
add = \x y -> x + y

// ❌ 错误：箭头链不是 Kun 的多参数函数语法
add = \x -> \y -> x + y
```

`\x -> \y -> x + y` 在 Kun 中是合法表达式，但其语义与 `\x y -> x + y` 不同——前者返回的是一个**单参数函数**（其返回值是另一个单参数函数），后者直接是**多参数函数**。虽然两者在默认的柯里化语义下观察行为等价（`add 1 2` 都能工作），但编译器将它们视为不同的 AST 节点：多参数 Lambda 比箭头链更高效（单次调用 vs 逐参数闭包构造），且部分应用行为不同：

```kun
add1 : Int -> Int
add1 = add 1

// \x y -> x + y  部分应用：add 1 → Int -> Int（单步完成，高效）
// \x -> \y -> x + y 部分应用：add 1 → \y -> 1 + y（构造闭包，多一步）
```

## 运算符与优先级

### 运算符列表

| 类别 | 运算符 | 结合性 |
|------|--------|--------|
| 表达式分组 | `(expr)` | — |
| 成员访问 | `.` | 左结合 |
| 可选链 | `?.` | 左结合 |
| Nil 合并 | `??` | 右结合 |
| 一元 | `-`, `not` | 右结合 |
| 乘除 | `*`, `/`, `%` | 左结合 |
| 加减 | `+`, `-` | 左结合 |
| 拼接 | `++` | 左结合，适用于 `String`（`"a" ++ "b"`）、`Bytes`（`0x01 ++ 0x02`）、`Path`（`p"/etc" ++ p"config"`） |
| 比较 | `==`, `/=`, `<`, `>`, `<=`, `>=` | 无结合 |
| 逻辑与 | `&&` | 左结合（短路） |
| 逻辑或 | `\|\|` | 左结合（短路） |
| 函数组合 | `>>`, `<<` | 左结合 |
| 管道 | `\|>`, `<\|` | 左结合 |
| 三元 | `? :` | 右结合 |
| 绑定 | `=` | 右结合 |

### 优先级（从高到低）

```
最高:
  .        (expr)         // . 成员访问，(expr) 表达式分组
  -        not            // 一元
  *        /        %
  +        -        ++
  ==       /=       <      >      <=      >=
  &&
  ||
  >>       <<
  |>       <|
  ? :
最低:  =
```

## 模块

Kun 采用**目录即命名空间**的方案：文件名（去掉 `.kun` 后缀）即模块名，目录层级表达名字空间。文件路径唯一决定模块名，无需 `module` 声明。

### 模块组织

```
lib/                          ← 项目库根目录
  Cmd/                        ← 命名空间：Cmd
    Git.kun                   ← 模块 Cmd.Git
    Docker.kun                ← 模块 Cmd.Docker
  Parser/
    JSON.kun                  ← 模块 Parser.JSON
    Record.kun                ← 模块 Parser.Record
  File.kun                    ← 模块 File
  List.kun                    ← 模块 List
deploy.kun                    ← 可执行脚本（有 main，无 export）
```

### 搜索路径

编译器按以下优先级查找模块：

| 优先级 | 路径 | 范围 |
|--------|------|------|
| 1 | 同库相对路径 | 项目内模块互引。从当前文件所在库根出发，向上遍历查找 |
| 2 | `$KUN_PATH` | 全系统共享的 Kun 模块 |
| 3 | `<runtime>/lib/kun/` | 标准库 |
| 4 | `~/.kun/cmd/` | 类型化命令模块 |

编译器在首次编译时遍历库根目录一次，索引全部模块到缓存中，后续查找为 O(1)。

### 导出

库模块文件以 `export (...)` 声明公开符号。文件路径即模块名，无需在声明中重复：

```kun
export (map, filter, fold)

export (Result, Result(..))    // 导出类型及所有变体
export (Result(Ok))           // 仅导出 Ok 变体
```

可执行脚本文件**不能有 `export` 声明**（其 `main` 为唯一入口）。有 `export` 而无 `main` 为库模块；有 `main` 而无 `export` 为可执行脚本。两者同时出现是编译错误。

导出语法：
- `Result(..)` — 导出类型 `Result` 及其所有变体（`Ok`、`Err`）
- `Result(Ok)` — 仅导出变体 `Ok`（不含 `Err`）
- `Result` — 仅导出类型名，不导出任何变体
- `Command` — 仅导出 Record 类型名，不导出任何字段
- `Command(field1, field2)` — 仅导出指定字段
- `Command(..)` — 导出 Record 类型及其所有字段

未导出的 ADT 变体/Record 字段在导入方**不可引用**。

### 导入

导入有三种互斥风格：

```kun
// 风格一：模块别名 — 通过别名限定访问
import List                            // 直接通过 List.map 访问
import List as L                       // 通过 L.map 访问（短别名）

// 风格二：精选导入 — 仅选择的符号可直接使用
import List (map, filter)
import List (map as m, filter)         // 导入时重命名

// 风格三：全量导入 — 所有公开符号可直接使用
import List (..)
```

从 ADT 导入变体：

```kun
import Result (Result(..))     // 导入类型及所有变体
import Result (Result(Ok))    // 仅导入 Ok 变体
```

导入变体后，变体名称可直接在代码中使用（`Ok`、`Err`），无需模块限定。

## 脚本入口

### 入口规则

Kun 脚本的执行入口按以下规则确定：

| 条件 | 行为 |
|------|------|
| 定义 `main : List String -> Unit` | 从 `main` 启动，传入命令行参数。退出码为 0 |
| 定义 `main` (无类型标注) | 编译器自动按 `List String -> Unit` 类型检查 |
| 未定义 `main` | 编译错误：可执行脚本缺少 `main` 入口 |
| `main` 签名不合法 | 类型标注不为 `List String -> Unit` 时编译错误 |

可执行脚本文件**不能有 `export` 声明**。有 `export` 为库模块，有 `main` 为可执行脚本，两者同时出现是编译错误。

### 命令行参数

脚本通过 `main` 函数的参数接收命令行参数：

```kun
main : List String -> Unit
main = \args ->
  do
    case args of
      []           -> IO.println "no arguments"
      [name]       -> IO.println f"hello, {name}"
      [cmd, ..rest] -> IO.println f"{cmd} with {List.length rest} args"
```

参数规则：
- 脚本名（`argv[0]`）不传入 `args` 列表，仅包含用户提供的参数
- 参数类型为 `List String`，每个元素是单个参数字符串
- 无参数时传入空列表 `[]`

启动命令与参数映射：

```bash
kun script.kun foo bar    # args = ["foo", "bar"]
kun script.kun            # args = []
```

### 命名参数

实际脚本通常需要命名参数（`--output file.txt`、`-v`）。Kun 通过标准库 `Cli` 模块
将原始 `List String` 解析为结构化配置：

```kun
import Cli
import IO

type Config =
  { verbose : Bool
  , output  : ?Path
  , name    : ?String
  }

parseConfig : List String -> Result Config Cli.CliError
parseConfig =
  Cli.parse
    { meta  = { intro = "script.kun" }
    , args =
        [ Cli.flag "verbose" 'v' "Verbose output"
        , Cli.option "output" 'o' "Output file"
        , Cli.option "name" 'n' "Config name"
        ]
    }

main : List String -> Unit
main = \raw ->
  do
    case parseConfig raw of
      Ok cfg  -> IO.println f"config: {cfg.verbose} {cfg.output}"
      Err err -> IO.println (Cli.show err)
```

`Cli` 模块的详细 API 见 [`Cli` 模块设计文档](cli.md)。

### 模块名冲突

不同路径下的模块可能同名（如 `./lib/json.kun` 和 `./vendor/json.kun`）。搜索优先级决定哪个模块被导入：

1. 项目本地路径 `./modules/` 优先于标准库路径 `<runtime_prefix>/lib/kun/`
2. 同一路径下同名模块为编译期错误（无法确定开发者意图）
3. 项目本地路径下同名模块按搜索顺序首命中，不告警

## 可执行脚本约束

- 可执行脚本文件**不能有 `export` 声明**
- 有 `export` 而无 `main` → 库模块
- 有 `main` 而无 `export` → 可执行脚本
- `main` 的签名**唯一合法形式为 `List String -> Unit`**
- 不需要命令行参数时用 `\_ ->` 忽略参数
- 支持 Shebang（`#!/usr/bin/env kun`）

```kun
// ✅ 正确：可执行脚本
main : List String -> Unit
main = \_ ->
  do
    IO.println "hello"

// ❌ 错误：可执行脚本不能有 export
export (helper)    // 编译错误
main : List String -> Unit
main = \_ -> do IO.println "hello"

// ❌ 错误：main 签名不合法
main : Unit        // 编译错误
```

## Stream

### 定位

Stream 是**惰性拉取序列**（lazy pull-based sequence），不绑定 IO。元素在消费时按需求值，适用于大文件处理、无限序列、数据流管道。

### 类型

```kun
Stream t    // 元素类型为 t 的惰性序列
```

Stream 是标准库类型，通过 `Stream` 模块的函数构造和消费。

### 纯构造

```kun
Stream.fromList [1, 2, 3]    // 从 List 构造
Stream.range 0 100           // [0, 1, ..., 99]
```

### 变换（惰性）

```kun
Stream.map    : (a -> b) -> Stream a -> Stream b
Stream.filter : (a -> Bool) -> Stream a -> Stream a
Stream.take   : Int -> Stream a -> Stream a
Stream.parseMap     : (a -> Result b e) -> Stream a -> Stream b
Stream.parseMapKeep : (a -> Result b e) -> Stream a -> Stream (Result b e)
```

### 消费（终端）

```kun
Stream.toList  : Stream a -> List a                 // 终端
Stream.iter    : (a -> Unit) -> Stream a -> Unit     // 终端
Stream.fold    : (b -> a -> b) -> b -> Stream a -> b // 终端
Stream.string  : Stream String -> String             // 终端：全文收集
Stream.bytes   : Stream a -> Bytes                   // 终端：二进制读取
```

Stream 必须由终端操作消费——未被消费的 Stream 导致子进程变为僵尸和 fd 泄漏。

## 与语法分析器的交互

语法设计需与类型检查器协调：

1. **类型标注与值定义分离**：解析器先识别 `name : type` 行，再识别 `name = expr` 行
2. **泛型空格分隔**：`List Int` 中 `List` 和 `Int` 以空格分隔，解析器通过上下文（类型位置 vs 表达式位置）和首字母大小写区分类型标识符与变量
3. **前缀字面量**：`p"..."`、`r"..."`、`f"..."` 三种前缀 + 双引号的字面量，解析器根据前缀字母区分，内容按原始字符串处理
4. **`?` 在类型中的角色**：`?T` 为 Nilable 类型构造器，`?.` 为可选链，`??` 为 Nil 合并，`? :` 为三元
