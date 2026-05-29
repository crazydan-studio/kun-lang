# 语法设计

## 设计原则

1. **表达式导向**：所有语句均为表达式，具有返回值
2. **简洁一致**：借鉴 Elm（为主）、Haskell 和 Rust，避免冗余关键字
3. **声明与实现分离**：类型标注与值定义为独立行，便于读取
4. **显式边界**：副作用（IO）、错误处理（Result）、权限（capability）均有显式语法标记
5. **最小惊喜**：优先采用 Shell 用户熟悉的符号约定

## 注释

```
// 行注释
//
// 多行注释也是每行以 // 开头
//
// 类型、函数、let 绑定、模块上的注释均视为文档注释
// 注释内容支持 Markdown 语法
//
// 文档注释中的 Markdown：
// - **粗体**、`代码`、[链接](url)
// - 列表、表格、代码块
```

Kun 仅支持 `//` 风格的注释。没有块注释语法（`/* */`）。连续多行 `//` 构成多行注释块。

文档注释规则：
- 直接位于 `type`、`pub`、函数定义、let 绑定、`module` 声明上方的注释行自动视为文档注释
- 文档注释内容支持 Markdown 语法，生成文档时会被渲染
- 非附着在上述结构上的注释视为普通代码注释，不进入文档生成

## 字面量

| 类型 | 语法 | 示例 |
|------|------|------|
| Int | 十进制、`0x`/`0o`/`0b` 前缀、`_` 分隔 | `42`, `-3`, `0xFF`, `1_000_000` |
| Nat | Int 字面量加后缀 `u`，支持 `_` 分隔 | `42u`, `0u`, `20_000u` |
| Float | 十进制浮点或科学计数法 | `3.14`, `-2.5e10` |
| Bool | 关键字 | `true`, `false` |
| String | 双引号包裹，支持转义序列 | `"hello"`, `"line1\nline2"` |
| String (多行) | `'''` 包裹，自动去公共缩进 | `'''` |
| String (插值) | `` f`...` `` 前缀 + 反引号，`{expr}` 嵌入表达式，可选 `:` 格式说明 | `` f`count: {n}` ``, `` f`pi: {3.14:.2f}` `` |
| Bytes | `0x` 前缀后接十六进制字节序列 | `0x48656C6C6F` |
| Char | 单引号包裹 | `'A'`, `'\n'`, `'好'` |
| Regex | `` r`...` `` 前缀 + 反引号 | `` r`[0-9]+` `` |
| Duration | 整数 + 单位后缀 | `5s`, `100ms`, `2h`, `30m`, `1d`, `500us`, `200ns` |
| Unit | 空圆括号 | `()` |
| Path | `` p`...` `` 前缀 + 反引号 | `` p`/tmp/foo` ``, `` p`./foo` `` |

各类型选用最符合其内容的引用风格：
- **双引号**：String — 需要转义序列支持
- **反引号**：Path、Regex、f-string — 避免与路径中的反斜杠和字符串转义冲突

### 多行字符串

以 `'''` 开头和结尾，自动去除每行开头的公共缩进：

```
content = '''
    {
      "name": "Kun",
      "version": "0.1"
    }
    '''
// → "{\n  \"name\": \"Kun\",\n  \"version\": \"0.1\"\n}"
```

规则：
- 开头 `'''` 后紧跟换行
- 结尾 `'''` 前的缩进量决定公共缩进基准
- 每行开头的公共缩进被移除
- 首行和末行的空行不计入内容
- 多行字符串内不支持插值，如需插值应使用 `` f`...` ``

容器字面量：

```
[1, 2, 3]              -- List
#{ "a" = 1 }           -- Map
#[1, 2, 3]             -- Set
(1, "hello", true)     -- Tuple
{ name = "Kun" }       -- Record
```

### Map 字面量与积类型的区别

```
#{ "a" = 1, "b" = 5 }   -- Map：键名和数量不确定，值类型相同
{ name = "Kun" }         -- 积类型（Record）：字段名和数量确定，字段类型可不相同
```

Map 使用 `=` 而非 `=>` 分隔键值对。Map 不支持解构（因为键不确定），仅支持索引访问。

容器字面量中的 `_` 仅作为位置占位符使用，不可用于访问或传递。

## 字符串插值与格式化

### 语法

以 `` f`...` `` 为前缀的字符串字面量支持嵌入表达式和格式化说明：

```
f`count: {n}`                     // 变量插值，自动 toString(n)
f`result: {a + b}`                // 任意表达式
f`pi = {3.14159:.2f}`             // 带格式说明
f`{name:>10}`                     // 字符串对齐
f`hex: {255:x} / {255:X}`         // 整数进制
```

嵌入表达式使用大括号 `{expr}` 包裹，可在其中任意位置出现。`` f` `` 与 `}` 之间可以有任意内容。

### 自动 toString

未指定格式说明时，`{expr}` 等价于 `toString(expr)`：

```
n = 42
f`answer is {n}`          // → "answer is 42"
"answer is " ++ toString(n)  // 等价
```

对 `String` 类型，`toString` 直接返回自身。

### 格式说明

格式说明以冒号 `:` 分隔，语法为 `{expr:format_spec}`。格式说明按类型分类：

#### 整数（Int / Nat）

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

```
f`{42:#>6}`     → "####42"          // # 填充，右对齐
f`{42:0>6}`     → "000042"          // 0 填充，右对齐
```

#### DateTime

`DateTime` 类型支持 `%` 格式符，委托到 `strftime`：

```
f`{now:%Y-%m-%d %H:%M:%S}`    // → "2026-05-29 14:30:00"
f`{now:%F}`                    // → "2026-05-29"
```

### 转义

| 需要输出 | 写法 | 说明 |
|---------|------|------|
| 字面量 `{` | `\{` | 大括号转义 |
| 字面量 `}` | `\}` | 大括号转义 |
| 字面量 `` ` `` | `` \` `` | 反引号转义 |
| 字面量 `\` | `\\` | 反斜杠转义 |

示例：

```
f`brace: \{hello\}`    → "brace: {hello}"
f`backslash: \\`       → "backslash: \"
f`backtick: \``        → "backtick: `"
```

### 嵌套

f-string 中嵌入的表达式本身可包含字符串字面量，但不支持嵌套 f-string（不可写 `` f`outer {f`inner`}` ``）：

```
f`list: {join ", " names}`         // 函数调用，参数为普通字符串
f`path: {p`/etc/hosts`}`           // 嵌入 Path 字面量
```

### 与普通字符串的关系

- `"..."` — 普通字符串，不支持插值，`{` 无特殊含义
- `` f`...` `` — 插值字符串，`{expr}` 被求值并格式化，`\{` 转义输出字面量 `{`
- 运行时类型：两者均为 `String`，插值在编译期展开为 `toString`/格式化调用链

设计依据：

1. **反引号前缀与 Path/Regex 一致**——`` p`...` ``（Path）、`` r`...` ``（Regex）、`` f`...` ``（插值字符串）统一使用反引号作为字面量边界
2. **普通字符串不受影响**——无需在非插值字符串中转义 `{`，仅 `` f`...` `` 内大括号有特殊含义
3. **Python 对齐**——格式说明语法与 Python 3 的格式规范微型语言保持一致，降低学习成本
4. **编译期展开无运行时开销**——插值在编译期展开为 `++` 和 `toString`/格式化函数调用，与手写等价

## 标识符与命名

| 类别 | 规则 | 示例 |
|------|------|------|
| 变量/函数 | 小写字母或下划线开头 | `map`, `identity`, `_temp` |
| 类型/变体 | 大写字母开头 | `Int`, `Maybe`, `Just`, `Ok` |
| 类型变量 | 小写字母，单字优先 | `a`, `b`, `key`, `value` |
| 模块 | 大写字母开头 | `List`, `Path`, `System` |

## 类型声明

### 泛型语法

Kun 使用 **Elm 风格**的空格分隔泛型参数，不使用尖括号：

```
List Int                  // 单参数
Maybe String              // 单参数
Result String IOError     // 多参数
IO (Result FileType IOError)  // 嵌套泛型用括号分组
```

规则：
- 类型构造器与类型参数之间以空格分隔
- 多参数之间也以空格分隔
- 嵌套泛型用圆括号分组

### ADT（和类型）

```
type Color
  = Red
  | Green
  | Blue

type Maybe t
  = Just t
  | None

type Result t e
  = Ok t
  | Err e

type SocketAddr
  = Tcp IpAddress Port
  | Udp IpAddress Port
```

变体字段支持三种形式：

```
type IpAddress
  = Ipv4 (Nat, Nat, Nat, Nat)     // 无名字段（元组风格）
  | Ipv6 (Nat, Nat, Nat, Nat, Nat, Nat, Nat, Nat)

type Error
  = NotFound Path                   // 无名字段（空格分隔）
  | PermissionDenied Path

type Color
  = Rgb { r : Int, g : Int, b : Int }   // 具名字段（Record 风格）
```

### Newtype

单变体 ADT 为 newtype：

```
type UserName = UserName String
type Uid = Uid Nat
```

### 类型别名

```
type alias IOError = ...   // 待定
```

（当前设计直接使用 ADT 而非别名，后续按需引入。）

### 类型标注

类型标注为独立声明行，与值定义分离：

```
add : Int -> Int -> Int
add = \x y -> x + y

identity : a -> a
identity = \x -> x

main : IO Unit
main = do
  content <- readFile p`/tmp/foo`
  print content
```

函数类型语法：

```
T1 -> T2 -> T3           // 柯里化函数
(T1, T2) -> T3           // 元组参数（参数本身为元组）
IO T                    // IO 包装
List Int                // 泛型
```

规则：
- 除非参数本身是元组类型，否则函数类型均为柯里化形式（`Int -> Int -> Int`）
- 无参数函数即变量绑定（不存在 `() -> T` 语法）
- 单参数免除圆括号：`Int -> Int` 而非 `(Int) -> Int`

Record 类型：

```
{ name : String, version : String }
```

## 表达式

### 变量引用与字面量

```
42                           // Int 字面量
"hello"                      // String 字面量
[1, 2, 3]                    // List 字面量
myVariable                   // 变量引用
```

### Lambda

```
\x -> x + 1                  // 单参数
\x y -> x + y                // 多参数
\(x, y) -> x + y             // 元组解构（参数本身为元组）
\{x, y} -> x + y             // Record 解构
\[x, y] -> x + y             // List 解构（最少长度 2）
```

### 函数应用

函数应用通过空格分隔，不使用逗号：

```
identity 42
map (\x -> x * 2) list
readFile p`/tmp/foo`
pid 1234
add 1 2
```

除非参数本身为元组类型，使用圆括号包裹元组参数：

```
plus (1, 2)                  // 元组参数（单参数）
```

### Let 绑定

单条 let 绑定不使用 `let` 关键字：

```
name = value                     // 简单绑定
p = p`/tmp/foo`
(x, y, z) = tuple                // 元组解构
{ name, version } = record       // Record 解构
[x, y, *rest] = list             // List 解构
{ x as x1, y as y1 } = point     // Record 解构带别名
```

多条 let 绑定使用 `let ... in` 语法：

```
sumSquares = \x y ->
  let
    a = x * x
    b = y * y
  in
    a + b
```

### Case 表达式（模式匹配）

```
case expr of
  pattern1 -> result1
  pattern2 -> result2
  _        -> default
```

模式类型：

#### 变体模式

```
case parse "42" of
  Ok n  -> process n        // 变体模式 + 变量绑定
  Err _ -> handleError ()   // 通配忽略
```

#### List 模式

```
case list of
  []              -> 0
  [_]             -> 1
  [_, y]          -> 2 * y
  [1, _, z]       -> 3
  [_, _, _, *rest] -> -1
```

列表模式的规则：
- `[]` 表示空列表
- `[a, b]` 匹配长度恰好为 2 的列表
- `[a, *rest]` 匹配长度至少为 1，`rest` 为剩余部分
- `_` 为位置占位符

#### 元组模式

```
case tuple of
  (1, y) -> 1 + y
  (x, 2) -> 2 * x
  _      -> 0
```

#### Record 模式

```
case record of
  {x = 1, y = 2} -> x * y
  {x as x1, y}   -> x1 + y
  _              -> 0
```

#### 守卫子句

```
case n of
  m when m > 0 && m <= 10  -> "small"
  m when m > 10            -> "large"
  _                        -> "other"
```

#### 通配模式

`_` 作为通配符（位置占位符），匹配任意值但不绑定：

```
case result of
  Ok _  -> "success"        // 忽略 Ok 内部的值
  Err _ -> "failed"         // 忽略 Err 内部的值
```

穷举检查：对自定义和类型（含 `Maybe`、`Result`）、`Bool` 强制穷举。

### If 表达式

```
if condition then expr1 else expr2
```

`if` 是表达式，必有返回值。`else` 分支不可省略。

### 管道操作符

```
list |> map (\x -> x * 2)
```

将左侧表达式的值作为最后一个参数传入右侧函数。

### Do 记法（IO 顺序组合）

```
main : IO Unit
main = do
  content <- readFile p`/tmp/foo`
  print content
```

`<-` 从 IO 操作中解包值。纯表达式直接写。

### Record 操作

```
{ name = "Kun", version = "0.1" }    // 创建
record.name                            // 字段访问
{ record | version = "0.2" }           // 更新（不可变复制+修改）

// 解构带别名
{x as x1, y as y1} = point
```

### 索引访问

```
list[i]          // List 索引，返回 Maybe t
str[i]           // String 索引，返回 Char
tuple.0          // Tuple 索引（0-based）
tuple.1
```

### 点调用

点号 `.` 仅用于积类型的字段投影和元组的索引访问，不能用于函数调用：

```
record.name          // 字段访问（正确）
tuple.0              // 元组索引（正确）

// 以下为不合法：
// p.parent()            // 错误：不能用点号调用函数
// record.toJson()       // 错误：不能用点号调用函数
```

函数只从属于模块，通过模块导入后，以 `模块名.函数名` 形式调用：

```
from Path import (parent)
parent p`/tmp/foo`        // 通过模块导入的函数名调用
```

显式导入的函数可直接通过函数名调用，无需模块限定。

### List 解构与展开

解构操作仅针对最小长度可确定的情况：

```
[a, b, *rest] = list        // 解构前两个元素 + 剩余部分
```

对于长度不确定的 List，采用模式匹配：

```
case list of
  [] -> "empty"
  [a, *rest] -> process a rest
```

List 展开语法：

```
newList = [1, 2, *list]           // 在列表前方展开
merged  = [*la, 0, *lb]           // 在列表中间展开
```

展开操作 `*list` 将 List 中的元素原地展开到新的 List 字面量中。

### `?` 操作符

```
readConfig : Path -> IO (Result Config String)
config = readConfig? p`/etc/app.toml`
```

`?` 标记在函数名之后（而非表达式之后），表示对该函数返回的 `Result` 进行解包：若结果为 `Ok t` 则取得 `t` 值，若为 `Err e` 则将错误传播到调用者。

等价于不写 `?` 时的显式模式匹配：

```
config = case readConfig p`/etc/app.toml` of
  Ok v  -> v
  Err e -> propagate e
```

## 函数定义

函数定义由可选的类型标注行和值定义行组成：

```
add : Int -> Int -> Int
add = \x y -> x + y

// 或匿名函数绑定
increment = \x -> x + 1
```

顶层函数建议标注类型签名。局部函数可省略：

```
main = do
  double = \x -> x * 2
  print (double 21)
```

函数参数支持直接解构：

```
// 元组参数解构
addPair : (Int, Int) -> Int
addPair = \(x, y) -> x + y

// Record 参数解构
sumCoordinates : { x : Int, y : Int } -> Int
sumCoordinates = \{x, y} -> x + y

// List 参数解构（最少长度 3）
firstThree : List Int -> (Int, Int, Int)
firstThree = \[a, b, c] -> (a, b, c)
```

## 运算符与优先级

### 运算符列表

| 类别 | 运算符 | 结合性 |
|------|--------|--------|
| 成员访问 | `.` | 左结合 |
| 函数应用 | 空格 | 左结合 |
| 一元 | `-`, `not` | 右结合 |
| 乘除 | `*`, `/`, `%` | 左结合 |
| 加减 | `+`, `-` | 左结合 |
| 拼接 | `++` | 左结合 |
| 比较 | `==`, `!=`, `<`, `>`, `<=`, `>=` | 无结合 |
| 逻辑与 | `&&` | 左结合（短路） |
| 逻辑或 | `\|\|` | 左结合（短路） |
| 管道 | `\|>` | 左结合 |
| 绑定 | `=` | 右结合 |
| 结果传播 | `?` | 右结合 |

### 优先级（从高到低）

```
最高:  .   ()  (函数应用)
      -   not   (一元)
      *   /   %
      +   -   ++
      ==  !=  <  >  <=  >=
      &&
      ||
      |>
      =
最低:  ?
```

## 模块

### 模块声明

每个源文件以 `module` 声明开头，声明模块名和导出符号：

```
module List export (map, filter, fold)

module Maybe export (Maybe, Maybe(*))     // 导出类型及所有变体
module Maybe export (Maybe(Just))         // 仅导出 Just 变体
```

变体导出语法：
- `Maybe(*)` — 导出类型 `Maybe` 及其所有变体（`Just`、`None`）
- `Maybe(Just)` — 仅导出变体 `Just`（不含 `None`）
- `Maybe` — 仅导出类型名，不导出任何变体

### 导入

```
import List                     // 导入模块，公开符号可直接使用
import List as L                // 限定别名
from List import (map, filter)  // 限定导入特定符号
from List import (map as listMap)  // 别名导入
```

从 ADT 导入变体：

```
from Maybe import (Maybe, Maybe(*))    // 导入 Maybe、Just、None
from Maybe import (Maybe(*))           // 仅导入变体 Just、None
from Maybe import (Maybe(Just))        // 仅导入变体 Just
```

导入变体后，变体名称可直接在代码中使用（`Just`、`None`），无需模块限定。

## 权限声明

### 脚本级声明

```
capability fs.read("/etc"), fs.read("/var/log"), net.http("api.example.com")
```

### 单命令注解

```
cat p`/etc/nginx/nginx.conf` with capabilities fs.read("/etc")
```

### 作用域级权限

```
with capability net.http("api.example.com") {
  response = curl "https://api.example.com/data"
  process response
}
```

`with capability`（单数）引入一个权限作用域块。`with capabilities`（复数）在单命令注解中列举多个权限。

## Stream 表达式

```
stream expr                        // 从表达式创建惰性流

stream readFile p`/tmp/large.log`
  |> filter (\line -> contains "ERROR" line)
  |> map parseLine
```

`stream` 关键字将表达式的求值延迟到消费时，适用于大文件处理和惰性管道。

## 与语法分析器的交互

语法设计需与类型检查器协调：

1. **类型标注与值定义分离**：解析器先识别 `name : type` 行，再识别 `name = expr` 行
2. **泛型空格分隔**：`List Int` 中 `List` 和 `Int` 以空格分隔，解析器通过上下文（类型位置 vs 表达式位置）和首字母大小写区分类型标识符与变量
3. **反引号字面量**：`` p`...` ``、`` r`...` ``、`` f`...` `` 三种前缀 + 反引号的字面量，解析器根据前缀字母区分
4. **`?` 与函数名的结合**：`?` 紧跟在函数名后，与函数名一同被解析

## 一致性决议

本设计统一如下不一致：

| 原不一致 | 决议 |
|---------|------|
| lambda 参数形式 | `\x ->` 单参数；`\x y ->` 多参数；`\(x, y) ->` 元组解构；`\{x, y} ->` Record 解构；`\[x, y] ->` List 解构 |
| 注释风格 | 使用 `//`，类型/函数/let/模块上的 `//` 为文档注释，支持 Markdown |
| 字面量引用风格 | `` p`...` ``（Path）、`` r`...` ``（Regex）、`` f`...` ``（插值字符串）统一使用反引号 |
| 字符串插值 | `` f`...` `` 前缀 + 大括号嵌入 + `:` 格式说明，编译期展开为 `toString`/格式化链 |
| 泛型语法 | Elm 风格空格分隔（`List Int`），不使用尖括号，嵌套用括号分组 |
| 函数类型 | 柯里化 `Int -> Int -> Int`，除非参数本身为元组 |
| 函数应用 | 空格分隔参数，无逗号；元组参数用圆括号包裹 |
| `let` 绑定 | 单条不使用 `let`；多条用 `let ... in` |
| List 模式 | `[a, *rest]` 替代 `a :: rest` |
| Map 字面量 | `#{ "a" = 1 }`（`=` 替代 `=>`） |
| `capability` 单复 | `with capability` 作用域（单数）；`with capabilities` 列举（复数） |
| 点调用语义 | 仅限积类型字段投影和元组索引，无函数调用 |
| `Stream` 构造 | `stream expr` 关键字语法 |
| 模块导入 | `from List import (map)` 限定导入语法；`Maybe(*)` 变体导入语法 |
| 模块导出 | `module List export (map)` 声明语法 |
