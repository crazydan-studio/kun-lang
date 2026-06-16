# 语法设计

## 设计原则

1. **表达式导向**：所有语句均为表达式，具有返回值
2. **简洁一致**：借鉴 Elm（为主）、Haskell 和 Rust，避免冗余关键字
3. **声明与实现分离**：类型标注与值定义为独立行，便于读取
4. **显式边界**：副作用（`do` 块）、错误处理（`Result`）均有显式语法标记
5. **最小惊喜**：优先采用 Shell 用户熟悉的符号约定

## 词法分析

### Token 类型

词法分析器将源码扫描为以下 Token 类型：

| Token 类别 | 示例 | 说明 |
|-----------|------|------|
| 关键字 | `type`、`case`、`of`、`if`、`then`、`else`、`do`、`in`、`let`、`defer`、`import`、`export`、`as`、`when`、`not`、`true`、`false`、`Nil` | 详见关键字表 |
| 标识符 | `myVar`、`MyType`、`snake_case_func` | 小写开头为变量/函数，大写开头为类型/变体/模块 |
| 整数字面量 | `42`、`0xFF`、`0o77`、`0b1010`、`1_000_000` | 十进制/十六进制/八进制/二进制，`_` 分隔符可选 |
| 浮点数字面量 | `3.14`、`2.5e10`、`1.0` | 必须含 `.` 且至少一位数字在小数点两侧 |
| 字符串字面量 | `"hello"`、`"""multiline"""` | 支持转义序列（见下方转义序列表） |
| 前缀字符串 | `p"/tmp"`、`r"[0-9]+"`、`f"hello {name}"` | 原始字符串——仅 `\"` 需转义 |
| 字符字面量 | `'A'`、`'\n'`、`'好'` | Unicode 标量值 |
| Duration 字面量 | `5s`、`100ms`、`2h`、`30m`、`1d` | 数字 + 单位后缀 |
| 运算符/标点 | `\|>`、`<\|`、`>>`、`<<`、`++`、`?.`、`??`、`&&`、`\|\|`、`==`、`/=`、`<=`、`>=`、`+`、`-`、`*`、`/`、`%`、`=`、`:`、`.`、`,`、`\|` | 多字符运算符最长匹配 |
| 括号/定界符 | `(` `)`、`[` `]`、`{` `}`、`#(` `)`、`#[` `]`、`#{` `}` | 元组/列表/Record/Map/Set 字面量 |
| 注释 | `// ...` | 行注释，无块注释 |
| EOF | — | 输入结束 |

### 转义序列

普通字符串 `"..."` 和字符字面量 `'...'` 支持以下转义序列：

| 序列 | 含义 | Unicode |
|------|------|---------|
| `\n` | 换行 | U+000A |
| `\r` | 回车 | U+000D |
| `\t` | 制表 | U+0009 |
| `\\` | 反斜杠 | U+005C |
| `\"` | 双引号 | U+0022 |
| `\'` | 单引号（仅字符字面量） | U+0027 |
| `\0` | NULL 字符 | U+0000 |
| `\xNN` | 十六进制字节（2 位） | U+00NN |
| `\u{NNNNNN}` | Unicode 码点（1-6 位十六进制） | U+NNNNNN |

> 前缀字符串（`p"..."`、`r"..."`、`f"..."`、`f"""..."""`）为原始字符串——仅 `\"` 和 `\{`（f-string）需要转义。多行字符串 `"""..."""` 不处理任何转义序列。

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
- 直接位于 `type`、函数定义、`export` 声明上方的注释行自动视为文档注释
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
| `Nil` | `Nil` | Nilable 类型的「不存在」值 |
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

> **空容器类型推断**：空 `Map` 字面量 `#{}` 和空 `Set` 字面量 `#[]` 的类型由上下文推断——期望类型为 `Map k v` 或 `Set t` 时，HM 合一将空容器的未知类型变量绑定为期望类型的参数。若上下文无类型信息（如 `let empty = #{}`），编译期报错："empty collection requires a type annotation"。

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

f-string 的插值表达式在编译期展开为编译器缺省 `toString` 调用——所有类型均通过「类型名 + 负载数据」格式自动生成字符串表示（详见标准库 `String` 模块的 `toString` 编译器级泛型章节）。无需用户为自定义类型显式实现 `toString`：编译器缺省生成可在编译期完成全部类型校验，无运行时 panic 风险。

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

`DateTime` 类型采用 `%` 引导符进入格式模式，后接字段名组合的格式模板（如 `%yyyy-MM-dd`）。完整字段名列表见 [`DateTime` 模块](standard-library.md#datetime)。

```kun
// → "2026-05-29 14:30:00.123 +0000"
f"{now:%yyyy-MM-dd HH:mm:ss.SSS Z}"
// → "2026-05-29"
f"{now:%yyyy-MM-dd}"
```

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

### 关键字

以下为 Kun 的保留关键字，不可用作标识符名：

| 类别 | 关键字 |
|------|-------|
| 声明 | `type`、`export`、`import`、`as` |
| 控制流 | `if`、`then`、`else`、`case`、`of`、`when` |
| 绑定 | `let`、`in`、`do` |
| 清理 | `defer` |
| 字面量 | `true`、`false`、`Nil` |
| 运算符 | `not` |

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

type Option a
  = Some a
  | None

type Shape
  = Circle Float
  | Rectangle Float Float
```

变体字段支持三种形式：

```kun
type Point
  = Cartesian (Float, Float)                              // 无名字段（元组风格）
  | Polar (Float, Float)

type Event
  = Click (Int, Int)          // 无名字段（空格分隔）
  | KeyPress Char

type Person
  = Person { name : String, age : Int }    // 具名字段（Record 风格）
```

### Newtype

单变体 ADT 为 newtype：

```kun
type UserId
  = UserId Int
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
-> T                     // 零参函数（仅效应函数）
T1 -> T2 -> T3           // 柯里化函数
(T1, T2) -> T3           // 元组参数（参数本身为元组）
(T1 -> T2)!               // 效应回调参数（仅限函数类型参数）
List Int                 // 泛型
```

规则：
- 除非参数本身是元组类型，否则函数类型均为柯里化形式（`Int -> Int -> Int`）
- 零参函数类型 `-> T` 仅用于效应函数（纯零参函数退化为常量，使用 `let` 绑定）
- 单参数免除圆括号：`Int -> Int` 而非 `(Int) -> Int`
- `(a -> b)!` 标注效应回调参数——该参数**必须是**效应函数，不能传入纯函数。声明了 `!` 参数的函数自身是效应函数。纯函数不能声明 `!` 参数。详细语义见[类型系统设计](type-system.md#效应回调标记-)」

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
[1..10]         // Stream 范围字面量（惰性，等价于 Stream.range 1 10）
[0..99999]      // 大范围惰性流，不预分配内存
myVariable      // 变量引用
```

`[start..end]` 范围字面量：左闭右开区间 `[start, end)`，生成 `Stream Int`。元素**惰性求值**，仅在被消费时按需计算。适用于大范围迭代：

```kun
[0..1000000] |> filter (\n -> n % 2 == 0) |> take 10
```

### Lambda

```kun
\ -> expr                  // 零参 Lambda（仅用于效应函数）
\x -> x + 1                // 单参数
\x y -> x + y              // 多参数
\(x, y) -> x + y           // 元组解构（参数本身为元组）
\{x, y} -> x + y           // Record 解构
\[x, y] -> x + y           // List 解构（最少长度 2）
```

零参 Lambda `\ -> expr` 仅用于函数类型为 `-> T` 的效应函数。纯函数不允许定义为零参。

`_` 可作为 Lambda 参数名表示丢弃该参数——`\_ -> expr` 等价于 `\x -> expr`（`x` 未在函数体中出现）。丢弃多个参数使用多重 `_`：`\_ _ -> expr` 丢弃前两个参数；`\_ y -> expr` 丢弃第一个参数并绑定第二个参数为 `y`。

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

解构赋值中 `_` 表示丢弃对应元素：`(x, _, z) = tuple` 丢弃第二个元素；`{ a, _ }` 仅提取 `a` 字段。`_` 在解构中总是丢弃，不会创建绑定。

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

多绑定使用换行分隔（不可在同一行逗号分隔）：

```kun
let
  name = expr
  f = \x -> expr
in
  use name f
```

多绑定的求值顺序：绑定之间按声明顺序求值（前面的绑定在后继绑定的表达式中可见）。相互引用（如 `a = ... b ...` 和 `b = ... a ...`）需通过 Lambda 包装实现：`a = \x -> ... b x ...`。

> **纯性约束**：`let ... in` 绑定的表达式必须是纯的——不得包含 `do` 块、效应命名空间调用（`IO.*`、`File.*`、`Env.*`、`Process.*`、`Sys.*`、`Task.*`、`Random.*`、`Signal.on`）及 `Cmd.<bin>?`/`Cmd.pipe?`/`Cmd.timeout`/`Cmd.retry`/`Cmd.which`/`Cmd.exec`。`let` 绑定采用延迟求值（仅在 `in` 之后被引用时才求值），若允许效应代码，效应执行时机不确定且可能被多次触发（泛化后多次引用）。效应代码必须在 `do` 块内使用 `=` 绑定顺序执行。

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

#### List 模式穷举规则

编译器对 List 类型的穷举检查遵循以下规则：

- `[]` 覆盖长度 0 的列表（空列表）
- `[..rest]` 覆盖任意长度的列表（`rest` 为空列表时等同于 `[]` 匹配）：单独使用即穷举
- `[a, ..rest]` 覆盖长度 ≥ 1 的列表
- `[]` + `[a, ..rest]` 覆盖所有长度：`[]` → len=0，`[a, ..rest]` → len ≥ 1
- `[a]` + `[a, b, ..rest]` 覆盖长度 1 和 ≥2，但缺少长度 0——检查器报告缺失 `[]` 分支
- `[a, b]` + `[a, b, c, ..rest]` 覆盖长度 2 和 ≥3，但缺少长度 0 和 1——检查器报告缺失 `[]` 和 `[a]` 分支

List 类型**强制穷举**——缺少分支时产生编译错误，错误信息列出未覆盖的长度范围（如「长度 1 的列表未被覆盖」）。

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

穷举检查：对自定义和类型（含 `Result`）、`Bool` 强制穷举。穷举检查算法为标准的矩阵分解法（Pattern Matrix Decomposition），覆盖嵌套模式、or 模式和守卫子句——守卫子句不改变穷举性判定（不能将守卫视为覆盖未守卫分支的替代）。缺失分支的错误消息列出未被覆盖的构造器组合。

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

`do` 块按顺序执行效应操作，块类型由最后一条语句的类型决定。`do` 块内使用 `=` 绑定值：

最后一条语句返回 `Unit` 的 `do` 块：

```kun
main : List String -> Unit
main = \_ ->
  do
    content = File.readString p"/tmp/foo"
    case content of
      Ok text -> IO.print text
      Err _   -> IO.println "failed"
```

> 注：上例 `do` 块类型为 `Unit`，因为最后一条语句（`case` 的每个分支末尾）为 `IO.print`/`IO.println`，均返回 `Unit`。`do` 块类型由最后一条语句决定，并非固定为 `Unit`。

需要在外层访问 `do` 块内部绑定值或显式指定返回值时，使用 `do in` 语法：

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
- 效应函数（`IO.*`、`File.*`、`Env.*`、`Process.*`、`Sys.*`、`Task.*`、`Random.*` 命名空间的函数 + `Signal.on` + `Cmd.<bin>?`/`Cmd.pipe?`/`Cmd.timeout`/`Cmd.retry`/`Cmd.which`/`Cmd.exec` + 用户定义含 `do` 块的函数 + 签名中声明了 `(a -> b)!` 参数的函数）只能在 `do` 块中调用；`Cmd.<bin>` 构造 `Command` 值及 `Cmd` 装饰函数（`Cmd.pipe`、`Cmd.withEnv` 等，接收并返回 `Command`）为纯操作，可在 `do` 块外使用
- 含 `do` 块的函数自动标记为效应函数
- 签名中声明了 `(a -> b)!` 参数的函数自动标记为效应函数
- 纯函数（无 `do` 块、无 `!` 参数）不能调用效应函数
- 外层 `do` 块的效应上下文自动传播到 `if`/`case` 的每个分支

`case` 分支内嵌 `do` 块时，内层 `do` 开始新的效应上下文——内层 `do` 注册的 `defer` 在该分支退出时执行（先于外层 `do` 的 `defer`）：

```kun
case command of
  Deploy config ->
    do
      defer cleanupDeploy ()
      ...
  Rollback version ->
    do
      defer cleanupRollback ()
      ...
```
// 内层 defer 已在上述分支退出时执行

- `let ... in` 表达式不可出现在 `do` 块内——`do` 块内使用 `=` 绑定（顺序求值）和 `do in` 形式（绑定后返回值）。若需在 `do` 块内引入局部定义并立即求值，使用 `=` 绑定；若需在副作用后返回纯值，使用 `do in`
- `do` 块内的 `Cmd.<bin>` 表达式不会被隐式执行——需通过 `|>` 管道触发、`Cmd.exec` 显式执行或 `?` 后缀立即执行。未被消费的 `Command` 值在 `do` 块内是编译错误

### defer 资源清理

`defer expr` 在 `do` 块内注册资源清理操作，`do` 块退出时（正常返回或 panic unwind）按 LIFO 逆序执行：

```kun
do
  case File.createTempFile of
    Ok tmp ->
      defer (File.remove tmp)
      Cmd.ffmpeg {} "input.mp4" tmp
    Err _ -> IO.println "failed to create temp file"
// do 块退出时自动 remove tmp
```

规则：
- `defer` 仅在 `do` 块内有效
- 嵌套 `do` 块各自管理独立的 `defer` 链——内层 `do` 块的 `defer` 在内层退出时执行，外层 `do` 块的 `defer` 在退出时执行。所有嵌套层的 `defer` 按 LIFO 逆序跨层执行（内层先于外层）
- 多个 `defer` 按注册顺序的逆序（LIFO）执行
- panic 触发 unwind 时 `defer` 始终执行
- `defer` 表达式本身不返回值（类型为 `Unit`）

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

`.name` 不依赖 Record 宽度子类型。编译器将其脱糖为 `\x -> x.name`，`x` 的具体 Record 类型由调用点 HM 上下文确定——`x` 的类型与所在高阶函数的参数类型合一（例如 `map .name` 中 `x` 的类型由 `map` 的 `a -> b` 参数与列表元素类型合一得出）。`.name` 本身不具备多态类型——每次出现均由上下文推断为具体 Record 到字段类型的函数。

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
  |> filter (String.contains "ERROR")
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
| 函数应用 | (空格) | 左结合 |
| Nil 合并 | `??` | 右结合 |
| 一元 | `-`, `not` | 右结合 |
| 乘除 | `*`, `/`, `%` | 左结合 |
| 加减 | `+`, `-` | 左结合 |
| 拼接 | `++` | 左结合，适用于 `String`（`"a" ++ "b"`）、`Bytes`（`0x01 ++ 0x02`）、`Path`（`p"/etc" ++ p"config"`） |
| 比较 | `==`, `/=`, `<`, `>`, `<=`, `>=` | 无结合 |
| 逻辑与 | `&&` | 左结合（短路） |
| 逻辑或 | `\|\|` | 左结合（短路） |
| 函数组合 | `>>`, `<<` | 左结合 |
| 正向管道 | `\|>` | 左结合 |
| 反向管道 | `<\|` | 右结合 |
| 三元 | `? :` | 右结合 |
| 绑定 | `=` | 右结合 |

`Nil` 字面量为内置常量值，类型为多态 `?a`，可赋值给任何 `?T` 类型的变量或在模式匹配中使用。详见 [类型系统](../design/type-system.md#nilable-类型-t)。

### 优先级（从高到低）

```
最高:
  .
  ?.
  (expr)
  函数应用
  -        not
  *        /        %
  +        -        ++
  ==       /=       <      >      <=      >=
  &&
  ??
  ||
  >>       <<
  ? :
  if/case/let-in
  |>       <|
最低:  =
```

- **函数应用** `f a b` 优先级高于所有运算符：`f a b + c` → `(f a b) + c`；`f a |> g` → `(f a) |> g`
- **`if`/`case`/`let-in`** 优先级高于管道操作符：`if a then b else c |> f` → `(if a then b else c) |> f`；`case x of A -> y |> z` → `(case x of A -> y) |> z`

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

> **重复导入**：同一文件中对相同模块的重复 `import`（如 `import List` 后 `import List (map, filter)`）编译期报错——模块仅需导入一次。使用限制性导入扩大导入范围时，更新原有的 `import` 语句（而非新增第二条）。

### 模块名冲突

不同路径下的模块可能同名（如 `./lib/json.kun` 和 `./vendor/json.kun`）。搜索优先级决定哪个模块被导入：

1. 项目本地路径 `./modules/` 优先于标准库路径 `<runtime_prefix>/lib/kun/`
2. 同一路径下同名模块为编译期错误（无法确定开发者意图）
3. 项目本地路径下同名模块按搜索顺序首命中，不告警

## 脚本入口

可执行脚本与 `main` 函数的约定详见 [`kun` CLI 工具](kun-cli-tool.md#脚本入口)。

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
Stream.drop   : Int -> Stream a -> Stream a
Stream.lines  : Stream String -> Stream (Result String LineError)
Stream.linesMax : Int -> Stream String -> Stream (Result String LineError)
Stream.parseMap     : (a -> Result b e) -> Stream a -> Stream b
Stream.parseMapKeep : (a -> Result b e) -> Stream a -> Stream (Result b e)
```

### 消费（终端）

```kun
Stream.toList  : Stream a -> List a                 // 终端
Stream.iter    : (a -> Unit)! -> Stream a -> Unit    // 终端
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

### 解析歧义消解规则

以下场景存在 token 级别的解析歧义，解析器按以下规则确定性处理：

#### 类型构造器 vs 函数调用

| 上下文 | `List Int` 的语义 | 解析规则 |
|--------|-----------------|---------|
| 类型标注行（`x : ...`） | 类型构造器应用 `List<Int>` | 大写标识符后跟空格 → 类型构造器 |
| 表达式行（`x = ...`） | 编译期错误——类型名不可作为值 | 大写标识符在表达式位置报错 |
| `import` 中的 `as` 别名 | 模块别名（`import List as L`） | `as` 后标识符保留为模块别名 |

解析器通过上下文（`:` 后为类型位置，`=` 后为表达式位置）和首字母大小写区分类型构造器与函数调用。

#### 点号 `.` 的五种语义消歧

| 模式 | 语义 | 解析规则 |
|------|------|---------|
| `X.y`（X 大写，在导入表） | 模块限定函数调用 | 导入表查找 `X` → 模块名 |
| `x.y`（x 小写） | Record 字段访问 | 产生 `recordAccess` AST 节点 |
| `tuple.0`（数字后缀） | Tuple 索引 | `.` 后为数字字面量 |
| `.name`（高阶参数位置） | 字段访问速记 | 仅在 `map .name`、`filter .size` 等位置有效；其他位置为语法错误 |
| `Cmd.ls` | Cmd 命令调用 | `Cmd` 为保留模块名，解析器产生 `CmdCall` 节点 |

#### 范围字面量 vs List 字面量

`[` 后解析第一个表达式，前瞻 1 token（LL(1)）判定：

- `[` `expr` `..` → **范围字面量**（产生 `range` AST 节点）
- `[` `expr` `,` 或 `]` → **List 字面量**（产生 `list` AST 节点）
- `[` `expr` 其他 → 语法错误（期望 `,`、`]` 或 `..`）
- `..` 为保留 token，不可作为用户定义运算符

#### 浮点字面量

浮点字面量**必须包含前导数字**：

- `0.5` → 合法浮点字面量
- `.5` → 语法错误（`.5` 与字段访问速记 `.name` 的前缀冲突）
- `3.` → 语法错误（期望小数部分）

**`.` 的消除歧义**：解析器在遇到 `.` token 时执行以下前瞻：
1. 左侧为大写标识符且在导入表中 → 模块限定调用（`M.func`）
2. 左侧为 `Cmd` 关键字 → 命令调用（`Cmd.ls`）——`Cmd` 为编译器预留名
3. `.` 右侧为数字起始 → 元组索引（`tuple.0`）
4. `.` 为 Lambda 参数的显式字段访问速记（`.name`）→ 在函数参数位置
5. 其余情况 → Record 字段访问（`record.field`）

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.15 | 审计修复三轮：`?.`/`??` 补入优先级层次图；关键字表格新增；`_` 参数/解构语义文档化；空容器 HM 推断规则；布局敏感性澄清；`.` 消除歧义机制 |
| 2026.06.15 | 审计修复：Nil 字面量补入字面量表格与 Nilable 章节 |
| 2026.06.14 | 函数类型语法新增 `(a -> b)!` 效应回调标注；do 块规则更新：含 `!` 参数的函数为效应函数；`do` 块内 Command 取消隐式执行，需通过 `Cmd.exec`/`|>`/`?` 显式触发；未被消费的 Command 是编译错误 |
| 2026.06.13 | 管道示例统一模块限定风格；冗余引用路径修正 |
| 2026.06.11 | 模块系统：目录即命名空间，`export (…)`/`import X (…)` |
| 2026.06.10 | 架构重设计：运算符、管道、表达式、函数定义等语法定型 |
