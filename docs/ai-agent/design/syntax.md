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
| Nat | Int 字面量加后缀 `u`，支持 `_` 分隔 | `42u`, `0u`, `20_000u` |
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
| Unit | 空圆括号 | `()` |
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

Map 使用 `=` 而非 `=>` 分隔键值对。Map 不支持解构（因为键不确定），但支持索引访问和更新：

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

设计依据：

1. **双引号统一**——所有字符串类字面量统一使用双引号，前缀 (`f`/`p`/`r`) 区分类型
2. **原始字符串简化转义**——前缀字面量原始内容不处理 `\n` 等转义序列；`f"..."` 的 `{...}` 表达式内按常规解析，`"` 无需转义
3. **Python 对齐**——格式说明语法与 Python 3 的格式规范微型语言保持一致；f-string 内表达式中的引号不需要转义的设计与 Python 一致

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
List Int                    // 单参数
?String                     // Nilable
Result String IOError       // 多参数
IO (Result FileType IOError)  // 嵌套泛型用括号分组
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
  = Ipv4 (Nat, Nat, Nat, Nat)                              // 无名字段（元组风格）
  | Ipv6 (Nat, Nat, Nat, Nat, Nat, Nat, Nat, Nat)

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
  = Uid Nat
```

### 函数类型别名

可为函数类型定义别名：

```kun
type LongFunc = String -> Int -> Result {v: Int, l: String} String
```

`type` 后直接跟类型名和类型定义，无 `alias` 关键字。不支持为其他非函数类型定义别名（类型别名在导入时指定）。

### 类型标注

类型标注为独立声明行，与值定义分离：

```kun
add : Int -> Int -> Int
add = \x y -> x + y

identity : a -> a
identity = \x -> x

main : IO Unit
main =
  do
    content <- readFile p"/tmp/foo"
    print content
```

函数类型语法：

```kun
T1 -> T2 -> T3          // 柯里化函数
(T1, T2) -> T3          // 元组参数（参数本身为元组）
IO T                    // IO 包装
List Int                // 泛型
```

规则：
- 除非参数本身是元组类型，否则函数类型均为柯里化形式（`Int -> Int -> Int`）
- **不支持无参函数**（不存在 `() -> T` 语法）。需接收 Unit 参数的函数应显式声明参数（如 `\_ -> body`）。无参回调的所有实际场景均已被替代机制覆盖：

  | 场景 | 其他语言无参回调 | Kun 替代方案 |
  |------|----------------|-------------|
  | 重试/超时 | `retry(3, \() -> ioOp())` | `retry 3 ioOp` — `IO T` 本身就是 thunk，每次 `<-` 重新求值 |
  | 定时器/事件 | `setInterval(5s, \() -> f())` | `setInterval 5s f` — 函数引用直接传递 |
  | 延迟求值 | `defaultLazy(\() -> expensive())` | `let x = expensive() in maybe default x` — `let` 惰性绑定 |
  | 高阶遍历 | `repeat 5 (\() -> random())` | `repeat 5 random` — `random : IO Int`，IO thunk 每次触发求值 |
  | 资源回调 | `withFile path (\() -> ...)` | `withFile path (\f -> ...)` — 带参数回调，更精确 |
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
\x -> x + 1               // 单参数
\x y -> x + y             // 多参数
\(x, y) -> x + y          // 元组解构（参数本身为元组）
\{x, y} -> x + y          // Record 解构
\[x, y] -> x + y          // List 解构（最少长度 2）
```

### 函数应用

函数应用通过空格分隔，不使用逗号：

```kun
identity 42
map (\x -> x * 2) list
readFile p"/tmp/foo"
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
print (sqrt (add 1 3))    // 无 <|

print    // 有 <|
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

### Do 记法（IO 顺序组合）

`do` 块按顺序执行 IO 操作。`<-` 从 IO 操作中解包值，将结果绑定到左侧名字。

无返回值的 `do` 块：

```kun
main : IO Unit
main =
  do
    content <- readFile p"/tmp/foo"
    print content
```

有返回值的 `do` 块使用 `do in` 语法，与 `let in` 类似——IO 效应放在 `do` 和 `in` 之间，返回值放在 `in` 之后：

```kun
type Config
  = Config { content : String, size : Int }

loadConfig : Path -> IO Config
loadConfig = \path ->
  do
    content <- readFile path
  in
    Config { content = content, size = length content }

processAndReturn : Path -> IO String
processAndReturn = \path ->
  do
    content <- readFile path
    result <- parse content
  in
    result
```

`do in` 确保 `do` 块始终为一个单一表达式（与 `let in` 确保函数体为单一表达式同理）。没有 `in` 部分的 `do` 块无返回值，类型为 `IO Unit`。

#### `<-` 的解包语义

`do` 块中每一行都是 `IO T` 类型的操作。`<-` 控制是否获取操作结果：

```kun
do
  readFile p"/tmp/foo"                // 行类型：IO String，执行但丢弃结果
  content <- readFile p"/tmp/foo"     // 执行，解包 String 绑定到 content
  _ <- readFile p"/tmp/foo"           // 执行，用 _ 显式丢弃解包后的值
```

规则：

| 写法 | 含义 | 绑定类型 |
|------|------|---------|
| `expr` | 执行 `expr`（类型 `IO T`），丢弃 `T` | 无绑定 |
| `name <- expr` | 执行 `expr`，解包出 `T` 绑定到 `name` | `name : T` |
| `name <-! expr` | 执行 `expr`（类型 `IO (Result T E)`），解包 IO 和 Result，Err 早返回 | `name : T` |
| `name =! expr` | 执行 `expr`（类型 `Result T E`），解包 Result，Err 早返回 | `name : T` |
| `_ <- expr` | 执行 `expr`，显式解包但丢弃 | 无绑定 |

`=` 与 `=!` 的对比：`name = expr` 为纯值绑定（类型 `T`），`name =! expr` 为带早返回的 Result 绑定（类型 `Result T E` → 解包为 `T`）。

`<-` 与 `IO` 的关系：

- `readFile` 返回 `IO String`，本身是一个"延迟值"
- `<-` 触发求值：从 `IO String` 中取出 `String`
- 这不是"调用"，而是"解包"——`IO` 包装被剥离，内部值被绑定到名字
- 没有 `<-` 时操作仍会被顺序执行，只是结果被丢弃

### Record 操作

```kun
{ name = "Kun", version = "0.1" }    // 创建
record.name                           // 字段访问
{ record | version = "0.2" }          // 更新（不可变复制+修改）

{x as x1, y as y1} = point            // 解构带别名
```

### 行多态 Record 类型

行多态允许函数接受"至少包含某些字段"的 Record，剩余字段由类型变量 `a` 表示：

```kun
getName : { a | name : String } -> String
getName = \{ name } ->
  name

// 接受任何包含 name : String 的 Record
getName { name = "Kun" }                    // → "Kun"
getName { name = "Kun", version = "0.1" }   // → "Kun"
```

语法 `{ a | field1 : T1, field2 : T2 }` 中，`a` 是行变量（小写字母），代表剩余字段的类型。行多态不是子类型——它是参数化多态在 Record 字段上的应用，编译期通过行合一精确替换。

### 扩展积类型

基于已有 Record 类型声明扩展类型，编译期展开为完整字段：

```kun
type CmdOptions = { runAs : ?RunAs }

type GitCommitOptions =
  { CmdOptions
  | message : String
  }
// 展开后：{ runAs : ?RunAs, message : String }
```

基类型必须是有名 Record 类型（`type T = { ... }`），字段名冲突时扩展字段覆盖基类型字段。

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
record.name    // 字段访问（正确）
tuple.0        // 元组索引（正确）

// 以下为不合法：
// p.parent()            // 错误：不能用点号调用函数
// record.toJson()       // 错误：不能用点号调用函数
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
  |> iter print
```

等价于：

```kun
lines
  |> filter (contains "ERROR")
  |> map (String.slice 0 100)
  |> iter print
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

### `=!` / `<-!` 操作符

Kun 中早返回操作符共两种，含义相同（解包 `Result`，`Err` 早返回），按绑定情景区分：

| 用法 | 语法 | 解包对象 | 示例 |
|------|------|---------|------|
| 纯绑定 | `name =! expr` | `expr` 返回值中的 `Result` | `config =! readConfig p"/etc/app.toml"` — `readConfig` 返回 `Result Config String`，`=!` 解包 Result |
| IO 绑定 | `name <-! expr` | 绑定表达式值中的 `Result` | `lines <-! Stream.readLines path` — `Stream.readLines` 返回 `IO (Result (Stream String) e)`，`<-!` 解 IO + Result |

早返回**仅允许在变量绑定时发生**，直接处理函数返回值不支持早返回。Stream 元素为 `Result t e` 时，应使用 `filterMap Result.ok` 跳过 Err 元素。

```kun
readConfig : Path -> Result Config String
config =! readConfig p"/etc/app.toml"
```

`=!` 在变量绑定中对右侧表达式的 `Result` 进行解包：若结果为 `Ok t` 则取得 `t` 值绑定到左侧名字，若为 `Err e` 则将错误传播到调用者。

等价于不写 `=!` 时的显式模式匹配：

```kun
config =
  case readConfig p"/etc/app.toml" of
    Ok v  -> v
    Err e -> propagate e
```

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
    print (double 21)
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
| 拼接 | `++` | 左结合 |
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

### 模块声明

每个源文件以 `module` 声明开头，声明模块名和导出符号：

```kun
module List export (map, filter, fold)

module Result export (Result, Result(..))    // 导出类型及所有变体
module Result export (Result(Ok))           // 仅导出 Ok 变体
```

所有需要导出的符号均通过 `module export` 声明。不存在 `pub` 关键字。

变体导出语法：
- `Result(..)` — 导出类型 `Result` 及其所有变体（`Ok`、`Err`）
- `Result(Ok)` — 仅导出变体 `Ok`（不含 `Err`）
- `Result` — 仅导出类型名，不导出任何变体

未导出的 ADT 变体在导入方**不可引用**——既不能用于构造值也不能用于模式匹配。编译器对尝试使用未导出变体的代码报"符号未找到"。

### 导入

导入有三种互斥的风格：**模块别名**（`as`）、**精选导入**（`with (symbols)`）和**全量导入**（`with (..)`），不可组合使用。

```kun
// 风格一：模块别名 — 所有公开符号通过别名限定访问
import List                            // 直接通过 List.map 访问
import List as L                       // 通过 L.map 访问（短别名）

import List with (map, filter)         // 风格二：精选导入 — 仅选择的符号可直接使用
import List with (map as m, filter)    // 导入时重命名
import List with (..)                  // 风格三：全量导入 — 所有公开符号可直接使用
```

从 ADT 导入变体（精选导入风格）：

```kun
import Result with (Result(..))     // 导入类型及所有变体
import Result with (Result(Ok))    // 仅导入 Ok 变体
```

导入变体后，变体名称可直接在代码中使用（`Ok`、`Err`），无需模块限定。

## 脚本入口

### 入口规则

Kun 脚本的执行入口按以下规则确定：

| 条件 | 行为 |
|------|------|
| 定义 `main : IO Unit` | 从 `main` 启动，忽略命令行参数。退出码为 `ExitCode.success`（0） |
| 定义 `main : IO ExitCode` | 从 `main` 启动，忽略命令行参数，返回自定义退出码 |
| 定义 `main : List String -> IO Unit` | 从 `main` 启动，传入命令行参数。退出码为 `ExitCode.success`（0） |
| 定义 `main : List String -> IO ExitCode` | 从 `main` 启动，传入命令行参数，返回自定义退出码 |
| 未定义 `main`，但有顶层 IO 表达式 | 按源码顺序执行顶层 IO 表达式，退出码为 `ExitCode.success`（0） |
| 无 `main` 且无顶层 IO 表达式 | 编译告警：无可执行入口 |
| `main` 签名不合法 | 编译告警：入口函数签名不合法 |

### 命令行参数

脚本通过 `main` 函数的参数接收命令行参数：

```kun
main : List String -> IO Unit
main = \args ->
  case args of
    []           -> print "no arguments"
    [name]       -> print f"hello, {name}"
    [cmd, ..rest] -> print f"{cmd} with {length rest} args"
```

参数规则：
- 脚本名（`argv[0]`）不传入 `args` 列表，仅包含用户提供的参数
- 参数类型为 `List String`，每个元素是单个参数字符串
- 无参数时传入空列表 `[]`

启动命令与参数映射：

```kun
kun script.kun foo bar    // args = ["foo", "bar"]
kun script.kun            // args = []
```

### 命名参数

实际脚本通常需要命名参数（`--output file.txt`、`-v`）。Kun 通过标准库 `Args` 模块将原始 `List String` 解析为结构化配置：

```kun
import Args

type Config
  = Config { output : ?String, verbose : Bool, input : ?Path }

main : List String -> IO Unit
main = \raw ->
  case Args.parse [ Args.flag "verbose" 'v', Args.option "output" 'o' ] raw of
    Ok cfg  -> process cfg
    Err msg -> print msg
```

`Args` 模块的设计：

| 声明器 | 含义 | 匹配形式 |
|--------|------|---------|
| `Args.flag name short` | 布尔开关 | `--verbose` / `-v` |
| `Args.option name short` | 带值选项 | `--output file` / `-o file` |
| `Args.positional index` | 位置参数 | 按出现顺序匹配 |

解析结果返回 `Result (Map String ArgsValue) String`，可通过键名访问：

```kun
case Args.parse [Args.flag "verbose" 'v', Args.option "output" 'o'] raw of
  Ok opts ->
    verbose = Args.get "verbose" opts |> maybe false identity
    output  = Args.get "output" opts
    ...
```

`Args` 模块的详细 API 见[标准库文档](standard-library.md#args)。

### 模块名冲突

不同路径下的模块可能同名（如 `./lib/json.kun` 和 `./vendor/json.kun`）。搜索优先级决定哪个模块被导入：

1. 项目本地路径 `./modules/` 优先于标准库路径 `<runtime_prefix>/lib/kun/`
2. 同一路径下同名模块为编译期错误（无法确定开发者意图）
3. 项目本地路径下同名模块按搜索顺序首命中，不告警

### 规则说明

**`main` 优先**：文件定义了 `main` 时，编译器以此作为唯一入口，忽略其他顶层 IO 表达式：

```kun
main : IO Unit
main =
  do
    print "entry"    // 只执行此处
```

**无 `main` 按顺序执行**：适合简单脚本，无需 `main = do` 包装：

```kun
print "hello"
print "world"
```

**库文件不执行顶层表达式**：有 `module export` 的文件即使存在 `main` 或顶层 IO 表达式，也仅作为定义提供，不自动执行：

```kun
module MyLib export (greet)

greet : IO Unit
greet = print "hi"

// 此文件被导入时，greet 不会自动执行
```

### 告警示例

```kun
main : Int    // 告警：main 签名不合法
main = 42
// → warning: entry point 'main' must have type IO Unit or List String -> IO Unit, got Int

// 告警：无可执行入口
// → warning: no executable entry point found
```

## 权限声明

### 脚本级声明

可执行脚本在模块顶部声明能力：

```kun
with caps
  fs.read = [Path.cwd, p"/tmp/"]
  fs.write = fs.read

main =
  do
    ...
```

### 函数内能力声明

能力声明仅针对 IO 操作，IO 操作必然在 `do`（含 `do in`）内，因此能力声明附着于 `do` 块：

```kun
readConfig =
  with caps
    fs.read = [p"/etc/kun/config"]
  do
    conf <-! readFile p"/etc/kun/config"
  in
    conf
```

- `with caps` 与 `do` 在同一缩进层级
- `do` 块本身是单一表达式，加上 `with caps` 后仍是单一表达式，仅添加了能力声明
- 同一个表达式的能力声明只能出现一次
- `with caps` 可以附着在任意层级的 `do` 块上

### 空能力集

未声明任何能力的脚本只能使用默认权限（空）：

```kun
main =
  do
    readFile Path.cwd   // 若未声明 fs.read → 运行时 PermissionError
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

### IO 构造

IO Stream 必须在 `do` 块中通过 `<-` / `<-!` 解包后才能消费：

```kun
main : IO Unit
main =
  do
    lines <-! Stream.readLines p"/tmp/large.log"    // lines : Stream String
    lines
      |> filter (contains "ERROR")
      |> take 100
      |> iter print
```

构造与消费分离：
- **构造**（`<-` 时）：打开文件等初始化操作，在 IO 上下文中执行
- **消费**（`iter` 等终端操作时）：逐元素拉取，按需读取

### 变换（惰性）

```kun
map    : (a -> b) -> Stream a -> Stream b
filter : (a -> Bool) -> Stream a -> Stream a
take   : Int -> Stream a -> Stream a
```

变换操作不触发求值，只构造新的惰性流。多个变换组合为管线：

```kun
lines
  |> filter (\line -> ...)    // 不变换
  |> map (\line -> ...)       // 不变换，构造新 Stream
  |> iter (\line -> ...)      // 终端：逐一拉取元素通过管线
```

### 消费（终端）

```kun
fold   : (b -> a -> b) -> b -> Stream a -> b
toList : Stream a -> List a
iter   : (a -> IO Unit) -> Stream a -> IO Unit
```

终端操作驱动求值，逐一从 Stream 中拉取元素并处理。

### 错误处理

Stream 的错误分两个阶段：

#### 构造阶段（打开文件、网络连接等）

```kun
Stream.readLines : Path -> IO (Result (Stream String) IOError)
```

外层 `Result` 表示构造可能失败（文件不存在、权限不足）。通过 `<-!` 解包：

```kun
main =                                          // 方案 A：自动解包，构造失败早返回
  do
    lines <-! Stream.readLines p"/tmp/large.log"
    iter print lines

main =                                          // 方案 B：显式处理构造错误
  do
    result <- Stream.readLines p"/tmp/large.log"
    case result of
      Ok lines -> iter print lines
      Err e   -> print f"cannot open: {e}"
```

`<-!` 在绑定时同时解包 IO 和 Result，Err 早返回：

#### 运行时阶段（读取过程中的磁盘故障等）

运行时读失败视为流终止——不再产生新元素。元素类型为纯值，消费端不感知错误：

```kun
Stream.readLines : Path -> IO (Result (Stream String) IOError)
//                                        ↑ 元素为 String，不是 Result
//                               运行时读失败 → 流静默终止
```

若需要逐元素处理错误，使用安全版本：

```kun
Stream.readLinesSafe : Path -> IO (Result (Stream (Result String IOError)) IOError)
// 每个元素可能是 Err
```

消费时逐元素处理：

```kun
main =
  do
    result <- Stream.readLinesSafe p"/tmp/log.txt"
    case result of
      Ok lines ->
        lines
          |> filterMap Result.ok    // 跳过读失败的行
          |> filter (contains "ERROR")
          |> take 100
          |> iter print
      Err e -> print f"failed to open: {e}"
```

`filterMap Result.ok : Stream (Result t e) -> Stream t` 过滤掉所有 `Err` 元素，仅保留 `Ok t`。

## 与语法分析器的交互

语法设计需与类型检查器协调：

1. **类型标注与值定义分离**：解析器先识别 `name : type` 行，再识别 `name = expr` 行
2. **泛型空格分隔**：`List Int` 中 `List` 和 `Int` 以空格分隔，解析器通过上下文（类型位置 vs 表达式位置）和首字母大小写区分类型标识符与变量
3. **前缀字面量**：`p"..."`、`r"..."`、`f"..."` 三种前缀 + 双引号的字面量，解析器根据前缀字母区分，内容按原始字符串处理
4. **`?` 在类型中的角色**：`?T` 为 Nilable 类型构造器，`?.` 为可选链，`??` 为 Nil 合并，`? :` 为三元。`?` 不作为独立后缀操作符使用（已由 `=!`/`<-!` 替代）
