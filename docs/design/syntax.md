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

```
content = """
    {
      "name": "Kun",
      "version": "0.1"
    }
    """
// → "{\n  \"name\": \"Kun\",\n  \"version\": \"0.1\"\n}"
```

多行插值字符串以 `f"""` 开头：

```
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

```
[1, 2, 3]              // List
#{ "a" = 1 }           // Map
#[1, 2, 3]             // Set
(1, "hello", true)     // Tuple
{ name = "Kun" }       // Record
```

### Map 字面量与积类型的区别

```
#{ "a" = 1, "b" = 5 }   // Map：键名和数量不确定，值类型相同
{ name = "Kun" }         // 积类型（Record）：字段名和数量确定，字段类型可不相同
```

Map 使用 `=` 而非 `=>` 分隔键值对。Map 不支持解构（因为键不确定），但支持索引访问和更新：

```
name: Maybe String
name = data["name"]

key = "value"
val  = data[key]

// Map 更新
newData = #{ data | "value" = 2 }
```

对 List、Set 的更新只能通过类型模块中的函数，没有简单形式。

## 字符串插值与格式化

### 语法

以 `f"..."` 为前缀的字符串字面量支持嵌入表达式和格式化说明：

```
f"count: {n}"                     // 变量插值，自动 toString(n)
f"result: {a + b}"                // 任意表达式
f"pi = {3.14159:.2f}"             // 带格式说明
f"{name:>10}"                     // 字符串对齐
f"hex: {255:x} / {255:X}"         // 整数进制
```

嵌入表达式使用大括号 `{expr}` 包裹，可在其中任意位置出现。

### 自动 toString

未指定格式说明时，`{expr}` 等价于 `toString(expr)`：

```
n = 42
f"answer is {n}"          // → "answer is 42"
"answer is " ++ toString n  // 等价
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
f"{42:#>6}"     → "####42"          // # 填充，右对齐
f"{42:0>6}"     → "000042"          // 0 填充，右对齐
```

#### DateTime

`DateTime` 类型采用 `%` 引导的格式描述符：

```
f"{now:%yyyy-MM-dd HH:mm:ss.SSS Z}"    // → "2026-05-29 14:30:00.123 +0000"
f"{now:%yyyy-MM-dd}"                   // → "2026-05-29"
```

格式符以 `%` 开头，后接字段名：
- `%yyyy` — 四位数年份
- `%yy` — 两位数年份
- `%MM` — 两位数月份（01-12）
- `%dd` — 两位数日期（01-31）
- `%HH` — 两位数小时（00-23）
- `%mm` — 两位数分钟（00-59）
- `%ss` — 两位数秒（00-59）
- `%SSS` — 三位数毫秒（000-999）
- `%Z` — 时区偏移（+0000）

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

```
f"brace: \{hello\}"         → "brace: {hello}"
f"quote: \""                → "quote: \""
f"list: { join ", " names }"  // 表达式内 " 无需转义
```

### 嵌套

f-string 中嵌入的表达式可包含字符串字面量，其内的引号无需转义。不支持嵌套 f-string（不可写 `f"outer {f"inner"}"`）：

```
f"list: { join ", " names }"        // 表达式内 " 无需转义
f"path: { p"/etc/hosts" }"          // 嵌入 Path 字面量
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
| 类型/变体 | 大写字母开头 | `Int`, `Maybe`, `Just`, `Ok` |
| 类型变量 | 小写字母，单字优先 | `a`, `b`, `key`, `value` |
| 模块 | 大写字母开头 | `List`, `Path`, `System` |

`'`（单引号）是标识符的合法字符，但不被赋予任何特殊语义（不代表重载、重写或变体关系）。用户可按约定使用，例如区分严格/惰性变体：

```
map   : (a -> b) -> List a -> List b
map'  : (a -> b) -> List a -> List b   // 用户的严格变体

value   : Int                           // 惰性绑定
value'  : Int                           // 用户约定的"立即求值"变体
```

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

### 函数类型别名

可为函数类型定义别名：

```
type LongFunc = String -> Int -> Result {v: Int, l: String} String
```

`type` 后直接跟类型名和类型定义，无 `alias` 关键字。不支持为其他非函数类型定义别名（类型别名在导入时指定）。

### 类型标注

类型标注为独立声明行，与值定义分离：

```
add : Int -> Int -> Int
add = \x y -> x + y

identity : a -> a
identity = \x -> x

main : IO Unit
main = do
  content <- readFile p"/tmp/foo"
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
- **不支持无参函数**（不存在 `() -> T` 语法）。详见下方独立章节
- 单参数免除圆括号：`Int -> Int` 而非 `(Int) -> Int`

Record 类型：

```
{ name : String, version : String }
```

### 类型标注补充说明：为何不支持无参函数

#### 问题

`() -> T`（无参函数）在函数式语言中常见，用于表示"一个不需要参数、每次调用产生一个值的函数"。Kun 明确不支持此语法。

#### 常见场景与替代方案

| 场景 | 直觉写法 | 为什么直觉是错误的 | Kun 的替代写法 |
|------|---------|-----------------|--------------|
| **回调/事件处理器** | `onClick : () -> IO Unit` | `IO Unit` 本身已经是"延迟到 `<-` 时才执行的值"。传给事件调度器的 `IO Unit` 在被 `<-` 解包时即执行，每次 `<-` 都是重新执行，不需要函数包装 | `onClick : IO Unit` |
| **工厂函数**（每次调用产生新值） | `newId : () -> IO Id` | 同上。`IO Id` 每次 `<-` 重新执行，产生新值 | `newId : IO Id` |
| **延迟计算（thunk）** | `lazyCompute : () -> Int` | Kun 默认惰性求值，`result = factorial 100` 不会立即求值，只在被使用时才计算。绑定本身即延迟 | `result = factorial 100` |
| **可变参数处理** | `f : () -> Int -> Int` | 将 Unit 作为第一个参数无实际意义，`f : Int -> Int` 即可 | `f : Int -> Int` |

#### 理由展开

#### `IO T` 已经是延迟值

这是最核心的原因。不理解这一点就会觉得需要 `() -> IO T`。

```
main = do
  action = newId       // action : IO Id，未执行
  id1 <- action        // 执行 action，得到 id1
  id2 <- action        // 再次执行 action，得到不同的 id2
```

每写一次 `<-`，就执行一次。`IO Id` 等价于 `() -> IO Id`——只是不需要那个无意义的 `()` 参数。

对比写法：

```
// 其他语言：传入函数，接收方调用 fn()
setCallback : (() -> IO Unit) -> IO Unit
setCallback = \fn ->
  fn ()         // 显式调用函数

// Kun：传入 IO action，接收方解包即执行
setCallback : IO Unit -> IO Unit
setCallback = \fn ->
  do
    fn          // 执行 fn，丢弃 Unit 返回值
    // 或
    _ <- fn     // 显式解包并丢弃
```

Kun 的写法少一层包装，直击核心：传入一个 IO action，接收方在需要的时刻 `<-` 解包即执行。

#### 纯函数求值靠绑定，不需显式 thunk

```
// 其他语言：用 () -> Int 实现延迟计算
lazyCompute : () -> Int
lazyCompute = \() -> ...   // 显式包装

// Kun：绑定即延迟，定义不触发求值
factorial : Int -> Int
factorial = \n ->
  if n <= 1 then 1 else n * factorial (n - 1)

result = factorial 100      // 绑定表达式，不计算
print result                // 在此处才触发实际计算
```

Kun 默认惰性求值，`result = factorial 100` 不会立即计算，只在 `print result` 引用 `result` 时才求值。不需要用 `() -> Int` 来包装"延迟"。

#### 避免无意义的 `()` 参数

`() -> IO T` 中的 `()` 是一个"我只为了让你能调用我而存在的参数"。它在调用时写作 `f ()`，而这个 `()` 不携带任何信息。Kun 的设计原则是"表达式导向"——如果某个参数没有语义意义，就不应该有它。

#### 结论

Kun 的以下特性共同使 `() -> T` 成为多余：

1. **`IO T` 是延迟值**——无需函数包装即可按需执行
2. **默认惰性求值**——纯函数计算通过名字绑定延迟
3. **表达式导向**——不引入无语义意义的参数

因此 `() -> T` 语法不被支持，类型标注中也不存在 `() -> T` 形式。

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
readFile p"/tmp/foo"
pid 1234
add 1 2
```

除非参数本身为元组类型，使用圆括号包裹元组参数：

```
plus (1, 2)                  // 元组参数（单参数）
```

### 名字绑定

名字绑定均直接以 `a = b` 形式定义：

```
name = value
p = p"/tmp/foo"
(x, y, z) = tuple
{ name, version } = record
[x, y, *rest] = list
{ x as x1, y as y1 } = point
```

`let ... in` 表达式用于确保多条语句之后有明确的唯一返回值：

```
a =
  let
    square = \x ->
      x * x
  in
  square 3
```

`let ... in` 并非仅针对多条绑定，它的作用与 Elm 中的 `let ... in` 一致：在一个表达式中引入局部定义，并最终产生一个明确的返回值。

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
  Err _ -> handleError    // 通配忽略
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
if condition then expr1
else if condition2 then expr2
else expr3
```

`if` 是表达式，必有返回值。`else` 分支不可省略。`else if then` 链可用于处理多分支。

### 三元表达式

```
condition ? expr1 : expr2
```

三元表达式是 `if condition then expr1 else expr2` 的简洁形式，适用于简单条件。

### 管道操作符

```
list |> map (\x -> x * 2)
```

将左侧表达式的值作为最后一个参数传入右侧函数。

### 反向管道操作符

```
sqrt <| add 1 3
```

`<|` 将右侧表达式的值作为参数传入左侧函数，是 `|>` 的反向形式，减少括号嵌套：

```
// 无 <|
print (sqrt (add 1 3))

// 有 <|
print <| sqrt <| add 1 3
```

### 函数组合操作符

```
f >> g >> h     // 从左向右组合：h(g(f(x)))
f << g << h     // 从右向左组合：f(g(h(x)))
```

`>>` 和 `<<` 用于组合函数。`f >> g` 表示先应用 `f` 再应用 `g`。`f << g` 表示先应用 `g` 再应用 `f`。

```
add1 = \x -> x + 1
double = \x -> x * 2
add1ThenDouble = add1 >> double    // 等价于 \x -> double (add1 x)
doubleThenAdd1 = add1 << double    // 等价于 \x -> add1 (double x)
```

### Do 记法（IO 顺序组合）

```
main : IO Unit
main = do
  content <- readFile p"/tmp/foo"
  print content
```

`do` 块按顺序执行每一行。`<-` 从 IO 操作中解包值，将结果绑定到左侧名字。

#### `<-` 的解包语义

`do` 块中每一行都是 `IO T` 类型的操作。`<-` 控制是否获取操作结果：

```
do
  readFile p"/tmp/foo"         // 行类型：IO String，执行但丢弃结果
  content <- readFile p"/tmp/foo"  // 执行，解包 String 绑定到 content
  _ <- readFile p"/tmp/foo"    // 执行，用 _ 显式丢弃解包后的值
```

规则：

| 写法 | 含义 | 绑定类型 |
|------|------|---------|
| `expr` | 执行 `expr`（类型 `IO T`），丢弃 `T` | 无绑定 |
| `name <- expr` | 执行 `expr`，解包出 `T` 绑定到 `name` | `name : T` |
| `_ <- expr` | 执行 `expr`，显式解包但丢弃 | 无绑定 |

`<-` 与 `IO` 的关系：

- `readFile` 返回 `IO String`，本身是一个"延迟值"
- `<-` 触发求值：从 `IO String` 中取出 `String`
- 这不是"调用"，而是"解包"——`IO` 包装被剥离，内部值被绑定到名字
- 没有 `<-` 时操作仍会被顺序执行，只是结果被丢弃

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

data["key"]      // Map 索引，返回 Maybe v
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
import Path as P
P.parent p"/tmp/foo"     // 通过模块限定的函数调用
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
config = readConfig? p"/etc/app.toml"
```

`?` 标记在函数名之后（而非表达式之后），表示对该函数返回的 `Result` 进行解包：若结果为 `Ok t` 则取得 `t` 值，若为 `Err e` 则将错误传播到调用者。

等价于不写 `?` 时的显式模式匹配：

```
config = case readConfig p"/etc/app.toml" of
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
| 表达式分组 | `(expr)` | — |
| 成员访问 | `.` | 左结合 |
| 一元 | `-`, `not` | 右结合 |
| 乘除 | `*`, `/`, `%` | 左结合 |
| 加减 | `+`, `-` | 左结合 |
| 拼接 | `++` | 左结合 |
| 比较 | `==`, `!=`, `<`, `>`, `<=`, `>=` | 无结合 |
| 逻辑与 | `&&` | 左结合（短路） |
| 逻辑或 | `\|\|` | 左结合（短路） |
| 函数组合 | `>>`, `<<` | 左结合 |
| 管道 | `\|>`, `<\|` | 左结合 |
| 三元 | `? :` | 右结合 |
| 绑定 | `=` | 右结合 |
| 结果传播 | `?` | 右结合 |

### 优先级（从高到低）

```
最高:  .        (expr)              // . 成员访问，(expr) 表达式分组
      -        not                 // 一元
      *        /        %
      +        -        ++
      ==       !=       <      >      <=      >=
      &&
      ||
      >>       <<
      |>       <|
      ? :
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

所有需要导出的符号均通过 `module export` 声明。不存在 `pub` 关键字。

变体导出语法：
- `Maybe(*)` — 导出类型 `Maybe` 及其所有变体（`Just`、`None`）
- `Maybe(Just)` — 仅导出变体 `Just`（不含 `None`）
- `Maybe` — 仅导出类型名，不导出任何变体

### 导入

```
import List                     // 导入模块，公开符号可直接使用
import List as L                // 模块别名
import List as L with (map as m, filter)  // 模块别名 + 特定符号导入/别名
```

从 ADT 导入变体：

```
import Maybe with (Maybe(*))        // 导入类型及所有变体
import Maybe with (Maybe(Just))     // 仅导入 Just 变体
```

导入变体后，变体名称可直接在代码中使用（`Just`、`None`），无需模块限定。

## 脚本入口

### 入口规则

Kun 脚本的执行入口按以下规则确定：

| 条件 | 行为 |
|------|------|
| 定义 `main : IO Unit` | 从 `main` 启动，忽略命令行参数 |
| 定义 `main : List String -> IO Unit` | 从 `main` 启动，传入命令行参数 |
| 未定义 `main`，但有顶层 IO 表达式 | 按源码顺序执行顶层 IO 表达式 |
| 无 `main` 且无顶层 IO 表达式 | 编译告警：无可执行入口 |
| `main` 签名既非 `IO Unit` 也非 `List String -> IO Unit` | 编译告警：入口函数签名不合法 |

### 命令行参数

脚本通过 `main` 函数的参数接收命令行参数：

```
main : List String -> IO Unit
main = \args ->
  case args of
    []           -> print "no arguments"
    [name]       -> print f"hello, {name}"
    [cmd, *rest] -> print f"{cmd} with {length rest} args"
```

参数规则：
- 脚本名（`argv[0]`）不传入 `args` 列表，仅包含用户提供的参数
- 参数类型为 `List String`，每个元素是单个参数字符串
- 无参数时传入空列表 `[]`

启动命令与参数映射：

```
kun script.kun foo bar       // args = ["foo", "bar"]
kun script.kun               // args = []
```

### 命名参数

实际脚本通常需要命名参数（`--output file.txt`、`-v`）。Kun 通过标准库 `Args` 模块将原始 `List String` 解析为结构化配置：

```
import Args

type Config = Config { output : Maybe String, verbose : Bool, input : Maybe Path }

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

```
case Args.parse [Args.flag "verbose" 'v', Args.option "output" 'o'] raw of
  Ok opts ->
    verbose = Args.get "verbose" opts |> maybe false identity
    output  = Args.get "output" opts
    ...
```

`Args` 模块的详细 API 见[标准库文档](standard-library.md#args)。

### 规则说明

**`main` 优先**：文件定义了 `main` 时，编译器以此作为唯一入口，忽略其他顶层 IO 表达式：

```
main : IO Unit
main = do
  print "entry"       // 只执行此处
```

**无 `main` 按顺序执行**：适合简单脚本，无需 `main = do` 包装：

```
print "hello"
print "world"
```

**库文件不执行顶层表达式**：有 `module export` 的文件即使存在 `main` 或顶层 IO 表达式，也仅作为定义提供，不自动执行：

```
module MyLib export (greet)

greet : IO Unit
greet = print "hi"

// 此文件被导入时，greet 不会自动执行
```

### 告警示例

```
// 告警：main 签名不合法
main : Int
main = 42
// → warning: entry point 'main' must have type IO Unit or List String -> IO Unit, got Int

// 告警：无可执行入口
// → warning: no executable entry point found
```

## 权限声明

### 脚本级声明

```
capability fs.read("/etc"), fs.read("/var/log"), net.http("api.example.com")
```

### 单命令注解

```
cat p"/etc/nginx/nginx.conf" with capabilities fs.read("/etc")
```

### 作用域级权限

```
with capability net.http("api.example.com") {
  response = curl "https://api.example.com/data"
  process response
}
```

`with capability`（单数）引入一个权限作用域块。`with capabilities`（复数）在单命令注解中列举多个权限。

## Stream

### 定位

Stream 是**惰性拉取序列**（lazy pull-based sequence），不绑定 IO。元素在消费时按需求值，适用于大文件处理、无限序列、数据流管道。

### 类型

```
Stream t   // 元素类型为 t 的惰性序列
```

Stream 是标准库类型，通过 `Stream` 模块的函数构造和消费。

### 纯构造

```
Stream.fromList [1, 2, 3]              // 从 List 构造
Stream.range 0 100                     // [0, 1, ..., 99]
Stream.repeat (\() -> random ())        // 反复调用函数产生元素
```

`Stream.repeat` 替代已移除的 `stream` 关键字，将任意表达式包装为反复求值的惰性流。

### IO 构造

IO Stream 必须在 `do` 块中通过 `<-` 解包后才能消费：

```
main : IO Unit
main = do
  lines <- Stream.readLines p"/tmp/large.log"   // lines : Stream String
  lines
    |> filter (\line -> contains "ERROR" line)
    |> take 100
    |> iter (\line -> print line)
```

构造与消费分离：
- **构造**（`<-` 时）：打开文件等初始化操作，在 IO 上下文中执行
- **消费**（`iter` 等终端操作时）：逐元素拉取，按需读取

### 变换（惰性）

```
map    : (a -> b) -> Stream a -> Stream b
filter : (a -> Bool) -> Stream a -> Stream a
take   : Int -> Stream a -> Stream a
```

变换操作不触发求值，只构造新的惰性流。多个变换组合为管线：

```
lines
  |> filter (\line -> ...)     // 不变换
  |> map (\line -> ...)        // 不变换，构造新 Stream
  |> iter (\line -> ...)       // 终端：逐一拉取元素通过管线
```

### 消费（终端）

```
fold   : (b -> a -> b) -> b -> Stream a -> b
toList : Stream a -> List a
iter   : (a -> IO Unit) -> Stream a -> IO Unit
```

终端操作驱动求值，逐一从 Stream 中拉取元素并处理。

### 错误处理

Stream 的错误分两个阶段：

#### 构造阶段（打开文件、网络连接等）

```
Stream.readLines : Path -> IO (Result (Stream String) IOError)
```

外层 `Result` 表示构造可能失败（文件不存在、权限不足）。通过 `?` 解包：

```
// 方案 A：自动解包，构造失败早返回
main = do
  lines? <- Stream.readLines p"/tmp/large.log"
  iter (\line -> print line) lines

// 方案 B：显式处理构造错误
main = do
  result <- Stream.readLines p"/tmp/large.log"
  case result of
    Ok lines -> iter (\line -> print line) lines
    Err e   -> print f"cannot open: {e}"
```

`?` 在绑定标识上（`name? <-`）表示"解包此绑定的 Result，Err 早返回"。

#### 运行时阶段（读取过程中的磁盘故障等）

运行时读失败视为流终止——不再产生新元素。元素类型为纯值，消费端不感知错误：

```
Stream.readLines : Path -> IO (Result (Stream String) IOError)
//                                        ↑ 元素为 String，不是 Result
//                               运行时读失败 → 流静默终止
```

若需要逐元素处理错误，使用安全版本：

```
Stream.readLinesSafe : Path -> IO (Result (Stream (Result String IOError)) IOError)
// 每个元素可能是 Err
```

消费时逐元素处理：

```
main = do
  result <- Stream.readLines p"/tmp/large.log"
  case result of
    Ok lines ->
      lines
        |> filterMap identity          // 跳过 Err 元素，保留 Ok 内容
        |> iter (\line -> print line)
    Err e -> print f"cannot open: {e}"
```

`filterMap identity : Stream (Result t e) -> Stream t` 过滤掉所有 `Err` 元素，仅保留 `Ok t`。

### 完整示例

```
readLines : Path -> IO (Result (Stream (Result String IOError)) IOError)

main = do
  result <- Stream.readLinesSafe p"/tmp/log.txt"
  case result of
    Ok lines ->
      lines
        |> filterMap identity     // 跳过读失败的行
        |> filter (\line -> contains "ERROR" line)
        |> take 100
        |> iter (\line -> print line)
    Err e -> print f"failed to open: {e}"
```

## 与语法分析器的交互

语法设计需与类型检查器协调：

1. **类型标注与值定义分离**：解析器先识别 `name : type` 行，再识别 `name = expr` 行
2. **泛型空格分隔**：`List Int` 中 `List` 和 `Int` 以空格分隔，解析器通过上下文（类型位置 vs 表达式位置）和首字母大小写区分类型标识符与变量
3. **前缀字面量**：`p"..."`、`r"..."`、`f"..."` 三种前缀 + 双引号的字面量，解析器根据前缀字母区分，内容按原始字符串处理
4. **`?` 与函数名的结合**：`?` 紧跟在函数名后，与函数名一同被解析

## 一致性决议

本设计统一如下不一致：

| 原不一致 | 决议 |
|---------|------|
| lambda 参数形式 | `\x ->` 单参数；`\x y ->` 多参数；`\(x, y) ->` 元组解构；`\{x, y} ->` Record 解构；`\[x, y] ->` List 解构 |
| 注释风格 | 使用 `//`，类型/函数/模块上的 `//` 为文档注释，支持 Markdown |
| 字面量引用风格 | `p"..."`（Path）、`r"..."`（Regex）、`f"..."`（插值字符串）统一使用双引号；前缀字面量为原始字符串 |
| 多行字符串 | `"""` 包裹（插值用 `f"""`），自动去公共缩进 |
| 字符串插值 | `f"..."` 前缀 + 大括号嵌入 + `:` 格式说明，编译期展开为 `toString`/格式化链 |
| 泛型语法 | Elm 风格空格分隔（`List Int`），不使用尖括号，嵌套用括号分组 |
| 函数类型 | 柯里化 `Int -> Int -> Int`，除非参数本身为元组 |
| 函数应用 | 空格分隔参数，无逗号；元组参数用圆括号包裹 |
| 名字绑定 | 均以 `a = b` 形式；`let ... in` 用于确保多条语句的唯一返回值 |
| List 模式 | `[a, *rest]` 替代 `a :: rest` |
| Map 字面量 | `#{ "a" = 1 }`（`=` 替代 `=>`）；Map 索引 `data["key"]`；Map 更新使用 `update` 语法 |
| `capability` 单复 | `with capability` 作用域（单数）；`with capabilities` 列举（复数） |
| 点调用语义 | 仅限积类型字段投影和元组索引，无函数调用 |
| `Stream` 构造 | `Stream.fromList`、`Stream.range`、`Stream.repeat` 替代 `stream` 关键字 |
| 模块导入 | `import List as L with (map as m)` 语法；`Maybe(*)` 变体导入语法 |
| 模块导出 | `module List export (map)` 声明语法，无 `pub` 关键字 |
| 导出语法 | 仅 `module export`，无 `pub` 关键字 |
| 类型别名 | 仅函数类型支持 `type LongFunc = ...`，非函数类型别名在导入时指定 |
| 三元表达式 | `condition ? expr1 : expr2` 简化 `if then else` |
| 函数组合 | 从左向右 `>>`, 从右向左 `<<` |
| 反向管道 | 减少括号嵌套 |
| 无参函数 | 不支持 `() -> T`。`IO T` 已是延迟值，`<-` 即执行；纯函数惰性求值靠绑定 |
