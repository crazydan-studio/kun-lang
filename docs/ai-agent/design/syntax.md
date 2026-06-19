# 语法设计

## 设计原则

1. **表达式导向**：一切皆为单一表达式，每条表达式返回一个确定类型的值
2. **简洁一致**：借鉴 Elm（为主）、Haskell 和 Rust，避免冗余关键字
3. **声明与实现分离**：类型标注与值定义为独立行，便于读取
4. **显式边界**：副作用（`do` 块）、错误处理（`Result`）均有显式语法标记
5. **最小惊喜**：优先采用 Shell 用户熟悉的符号约定

## 单一表达式范式

Kun 采用**单一表达式**（Single Expression）范式——程序中所有构造均为表达式，求值后得到具体类型的值。类型的实例即为值。类型包括基础类型、函数类型和 `Unit` 类型。

### 表达式分类

| 表达式形式 | 是否单一表达式 | 结果类型 | 说明 |
|-----------|--------------|---------|------|
| 字面量、变量访问 | 是 | 对应类型 | `42`、`"hello"`、`myVar` |
| 函数调用 | 是 | 函数返回类型 | `add 1 2` → `Int` |
| 类型值（类型名本身） | 是 | 自身类型 | `Int`、`String` |
| `if/then/else`、`case/of`、三元 `? :` | 是 | 各分支的统一类型 | 分支结果类型必须相同 |
| `do <body>` | 是 | `Unit` | 裸 do 固定返回 Unit |
| `do <body> in <expr>` | 是 | `<expr>` 的类型 | 必须为非 Unit |
| `let <body> in <expr>` | 是 | `<expr>` 的类型 | 纯上下文，必须为非 Unit |
| `=`（值绑定） | **否** | 无（不返回值） | 绑定名通过变量访问获取值 |

### 多语句与作用域

仅 `do`、`do in`、`let in` 三种复合表达式的 `<body>` 中允许包含多条语句。`do` 和 `let` 表达式可包含值绑定（含局部函数定义），但仅 `do` 允许效应函数调用。

- `do` 本质为效应函数的顶级表达式。效应函数的函数体必须显式以 `do`/`do in` 为顶级表达式。匿名效应函数同样如此。
- `let in` 为纯函数的顶级表达式。纯函数体为单一表达式时可省略 `let in` 包裹。匿名纯函数同样如此。
- `do` 内可嵌套 `do`，`let` 内可嵌套 `let`，但 `do` 与 `let` 在同一函数 scope 内不可互相嵌套。

### 分支表达式的多语句规则

`case`/`if` 表达式中，根据表达式结果是否被消费，分支的包裹规则不同：

- **Unbound**（结果未被值绑定，也不作为函数返回值）：在 `do` 上下文时，各分支隐式作为 `do` 块，分语句无需显式 `do`/`do in` 包裹，分支结果均视为 `Unit`。若分支内无效应调用，编译器告警。
- **Bound/Returned**（结果被值绑定或作为函数返回值）：各分支必须返回相同类型的值。多语句分支必须用 `do in`（效应上下文）或 `let in`（纯上下文）包裹为单一表达式；单表达式分支可直接书写。

分支内 `do` 上下文采用**链式继承**——外层 `do` → unbound 分支（隐式 `do`）→ 嵌套 unbound 分支（继续隐式 `do`）→ …，直到被 bound 表达式或函数定义边界打断。

### 函数体与 Scope 规则

- 每个函数体均为独立 scope，单一表达式规则从头应用。
- 效应函数内可定义纯函数（新的纯 scope），但纯函数内不得定义或调用效应函数（编译错误）。
- 函数体无论是单语句还是多语句，效应函数必须显式包裹 `do`/`do in`，纯函数体单一表达式可省略 `let in` 包裹。
- `main` 签名固定为 `List String -> Unit`，退出码通过 `Process.exit n` 返回。

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

`DateTime` 类型在 f-string 中采用 `%` 引导符进入格式模式，后接字段名组合的格式模板（如 `%yyyy-MM-dd`）。格式字段名与 `DateTime.format` 函数（见 [`DateTime` 模块](standard-library.md#datetime)）完全一致——唯一区别是 f-string 需 `%` 前缀引导而 `DateTime.format` 的第一个参数直接为格式模板字符串（不含 `%` 前缀）。完整字段名列表见 `DateTime` 模块文档。

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
?(Result File.Type IOError)    // Nilable + 多词类型用括号包裹
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

pid : -> Process.Pid
pid = \ ->
  do
    Process.pid

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
- 纯函数返回类型不可为 `Unit`——纯 `Unit` 返回值无意义（无输出、无副作用），退化为无操作（no-op），编译期报错。效应函数可返回 `Unit`
- 单参数免除圆括号：`Int -> Int` 而非 `(Int) -> Int`
- `(a -> b)!` 标注效应回调参数——该参数**必须是**效应函数，不能传入纯函数。声明了 `!` 参数的函数自身是效应函数。纯函数不能声明 `!` 参数。详细语义见[类型系统设计](type-system.md#效应回调标记-)

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

零参 Lambda `\ -> expr` 仅用于函数类型为 `-> T` 的效应函数。纯函数不允许定义为零参，且返回类型不可为 `Unit`。

`_` 可作为 Lambda 参数名表示丢弃该参数——`\_ -> expr` 等价于 `\x -> expr`（`x` 未在函数体中出现）。丢弃多个参数使用多重 `_`：`\_ _ -> expr` 丢弃前两个参数；`\_ y -> expr` 丢弃第一个参数并绑定第二个参数为 `y`。

#### 匿名函数 body 规则

匿名函数为独立 scope，单一表达式规则从头应用。函数体规则与具名函数一致：

- **效应匿名函数**：函数体必须显式以 `do`/`do in` 包裹，不可省略：
  ```kun
  \x ->
    do
      IO.println x        // 单语句或多语句，必须包裹 do
  ```
- **纯匿名函数**：函数体单一表达式时可省略 `let in` 包裹；多语句时须用 `let in` 包裹：
  ```kun
  \x -> x + 1             // 单表达式，省略 let in
  \x ->
    let
      y = x + 1
    in
      y * 2               // 多语句，必须 let in
  ```

作为实参的匿名函数同样遵循以上规则，根据是否包含效应函数调用来确定采用 `do` 还是 `let in` 包裹多语句。

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
{ a, .._ } = config          // 解构 a，丢弃剩余字段
[x, y, ..rest] = list
[x, .._] = list              // 提取首元素，丢弃后续部分
{ x as x1, y as y1 } = point
```

解构赋值中 `_` 表示丢弃对应元素：`(x, _, z) = tuple` 丢弃第二个元素。`.._` 用于丢弃 Record 或 List 的全部剩余字段/元素：`{ a, .._ }` 提取 `a` 并丢弃其余字段，`[x, .._]` 提取首元素并丢弃后续部分。**裸 `..` 不是合法语法**——必须后跟变量名（`..rest`）或 `_`（`.._`）。

`let ... in` 表达式在纯上下文中引入局部定义并产生明确的返回值。`let ... in` 整体为单一表达式，结果为 `in` 之后表达式的值。

### 基本形式

```kun
let
  square = \x ->
    x * x
in
  square 3
```

`let ... in` 的 `<body>` 可包含多条纯值绑定（含局部函数定义），绑定的值在 `in` 表达式中可见。多绑定使用换行分隔（不可在同一行逗号分隔）：

```kun
let
  name = expr
  f = \x -> expr
in
  use name f
```

### 空 body 约束

`let in` 空 body（无任何绑定的 `let in <expr>`）为编译错误。直接在需要的位置书写 `<expr>` 即可。

```kun
// ❌ 编译错误：空 body
result = let in x + 1

// ✅ 直接书写表达式
result = x + 1
```

### 在 case/if 分支中使用

`case`/`if` 表达式中，当结果被值绑定或作为函数返回值（bound/returned）时，多语句分支须用 `let in` 包裹为单一表达式。单表达式分支直接书写即可。各分支结果类型必须相同：

```kun
result =
  let
    items = [1, 2, 3, 4]
  in
    case items of
      [] ->
        0
      [x] ->
        x * 2
      list ->
        let
          sum = List.sum list
          len = List.length list
        in
          sum / len
```

### 求值策略

`let` 绑定采用**延迟求值（lazy evaluation）**——绑定的表达式不立即计算，仅构建 thunk（闭包 + 求值函数）。`in` 表达式中首次引用某个绑定时才真正求值，结果被 memoize 缓存，后续引用直接返回缓存值。

#### 相互递归

延迟求值允许多绑定互相引用，无需显式 Lambda 包装即可实现递归定义：

```kun
let
  isEven = \n -> if n == 0 then true else isOdd (n - 1)
  isOdd  = \n -> if n == 0 then false else isEven (n - 1)
in
  (isEven 10, isOdd 11)           // → (true, true)
```

每个绑定的 thunk 在闭包中持有其他绑定的 thunk 引用。首次引用 `isEven` 时，依赖拓扑顺次求值——`isEven` 求值过程引用 `isOdd`，触发 `isOdd` 求值，`isOdd` 又通过 `isEven` 闭包递归调用。递归调用通过已构建的闭包正常完成语义，不产生循环初始化错误。

若在 `case`/`if` 的多语句分支中尝试等价写法，`=` 绑定按声明顺序严格求值——`isEven` 求值时 `isOdd` 尚未绑定，编译期或运行时报错。

#### 死代码消除

`let` 中未被引用的绑定**不会被求值**，在条件分支中效果显著：

```kun
let
  expensive = heavyCompute data     // thunk 构建，不求值
  cheap     = lightCheck data       // thunk 构建，不求值
in
  if cheap then default else expensive
  // cheap == true → expensive 永不被求值
```

多语句分支体中所有 `=` 绑定无条件按序求值——`heavyCompute` 在判断条件之前已执行完毕，丧失了短路优化。

#### 与 case/if 多语句分支的对比

| 维度 | `let ... in` | `case`/`if` 多语句分支（bound） |
|------|-------------|------------------------------|
| 求值策略 | 延迟（lazy，按需 + memoize） | 严格（eager，按声明顺序） |
| 可用位置 | 任意表达式内（管道、实参、Record 字段） | 仅分支体内部 |
| 相互递归 | 支持（通过 thunk 闭包） | 不支持（前置引用未定义） |
| 死代码消除 | 自然支持（未引用 = 不求值） | 不支持（全量求值） |
| 效应调用 | 禁止（编译错误） | `do` 上下文链式继承（unbound 分支为隐式 `do`；bound 多语句须 `do in` 包裹；纯上下文 bound 多语句须 `let in` 包裹） |

多绑定的求值顺序：绑定之间按声明顺序求值（前面的绑定在后继绑定的表达式中可见）。thunk 的依赖拓扑求解由运行时按首次引用顺序自动完成——对用户透明。

### 纯性约束

`let ... in` 的 `<body>` 和 `in` 表达式均处于纯上下文，**完全禁止**任何效应操作的痕迹，违者编译错误：

- 禁止调用效应函数：`IO.*`、`File.*`、`Env.*`、`Process.*`、`Task.*`、`Random.*`、`Signal.on`、`Cmd.<bin>?`/`Cmd.<bin>!`、`Cmd.pipe?`/`Cmd.pipe!`、`Cmd.timeout`、`Cmd.retry`、`Cmd.which`、`Cmd.exec`、`Cmd.execSafe`
- 禁止定义效应函数（`f = \x -> do ...`）
- 禁止引用效应命名空间函数作为值绑定（如 `myPrint = IO.println`）
- 禁止 `do` 块

效应代码必须在 `do` 块内使用 `=` 绑定顺序执行。若需在纯计算中引入局部定义并返回值，使用 `let in`；若需在副作用执行后返回值，使用 `do in`（`in` 处于效应上下文，结果必须为非 `Unit`）。

### Case 表达式（模式匹配）

```kun
case expr of
  pattern1 -> result1
  pattern2 -> result2
  _        -> default
```

#### 分支体

`case`/`if` 的每个分支体为**单表达式**。分支体根据表达式结果是否被消费，分为 **unbound** 和 **bound/returned** 两种场景：

##### Unbound（结果未被消费）

当 `case`/`if` 表达式的结果未被值绑定（`=`），也不作为函数返回值——其结果被丢弃——且表达式处于 `do` 效应上下文时，各分支隐式作为 `do` 块。分支内可直接书写多语句，无需显式 `do` 包裹，结果均视为 `Unit`：

```kun
do
  case content of
    Ok text ->
      IO.println "processing..."
      result = process text
      IO.println (toString result)
    Err e ->
      IO.println (toString e)
```

若 unbound 分支内仅含纯值绑定而无效应调用，编译器告警。

`defer` 在 unbound 分支中挂载到该分支自身的隐式 `do` 块——退出该分支时立即执行，而非等到外层 `do` 退出：

```kun
do
  case command of
    Deploy config ->
      defer cleanupDeploy ()
      Cmd.ffmpeg {} "input.mp4" "output.mp4" |> Cmd.exec
    // defer cleanupDeploy 在此处执行（分支退出时）
    Rollback version ->
      defer cleanupRollback ()
      Cmd.restore {} version |> Cmd.exec
    // defer cleanupRollback 在此处执行
```

若需要分支共享外层 `do` 的 `defer` 生命周期，可将 `defer` 语句写在外层 `do` 中。

##### Bound/Returned（结果被消费）

当 `case`/`if` 表达式的结果被值绑定或作为函数返回值时，各分支必须返回**相同类型**的值：

- **单表达式**分支：直接书写表达式即可，无需包裹
- **多语句**分支：必须用 `do in`（效应上下文）或 `let in`（纯上下文）包裹为单一表达式

```kun
result =
  case File.readString p"/tmp/foo" of
    Ok text ->
      text                     // 单表达式，无需包裹
    Err e ->
      do
        IO.println (toString e)
      in
        defaultText            // 多语句，须用 do in 包裹
```

纯上下文中的 bound/returned 分支——多语句分支须用 `let in` 包裹：

```kun
processedItems =
  case items of
    [] ->
      []
    list ->
      let
        filtered = List.filter isPositive list
        squared = List.map square filtered
      in
        List.sum squared |> List.singleton
```

##### 链式继承

`do` 上下文在嵌套分支中按链式继承传播：外层 `do` → unbound 分支（隐式 `do`）→ 嵌套的 unbound 分支（继续隐式 `do`）→ ...，直到被 bound 表达式或函数定义边界打断。同一函数 scope 内不可出现 `do` 与 `let` 互嵌套（详见[单一表达式范式](#单一表达式范式)）。

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
- `[a, .._]` 匹配长度至少为 1，丢弃剩余部分
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
  {x, .._ }             -> x          // 提取 x，丢弃其余字段
  {x, ..rest }          -> x + rest.a // 提取 x，剩余字段作为 Record 绑定到 rest
  _                     -> 0
```

规则：
- `{field = literal}` — 匹配字面量值
- `{field as alias}` — 将字段值绑定到别名
- `{field as alias = literal}` — 同时进行字面量匹配和别名绑定：先检查值是否等于字面量，匹配后将值绑定到别名
- `{field, .._}` — 提取指定字段，丢弃其余字段（`.._` 必须出现在模式末尾）
- `{field, ..rest}` — 提取指定字段，剩余字段作为 Record 绑定到 `rest`（`..rest` 必须出现在模式末尾）
- 三种字段形式可在同一个 Record 模式中混用：`{x = 1, y as y1, z as z1 = 3}`
- **裸 `..`（无变量名或 `_`）不是合法语法**——必须使用 `..rest`（绑定）或 `.._`（丢弃）

#### 守卫子句

```kun
case n of
  m when m > 0 && m <= 10  -> "small"
  m when m > 10            -> "large"
  _                        -> "other"
```

守卫子句的 `condition` 不影响分支体语义——`->` 后的分支体仍可单表达式或多语句，规则同无守卫分支。

#### 通配模式

`_` 作为通配符（位置占位符），匹配任意值但不绑定：

```kun
case result of
  Ok _  -> "success"    // 忽略 Ok 内部的值
  Err _ -> "failed"     // 忽略 Err 内部的值
```

#### Or 模式（多模式匹配）

多个变体或字面量共享同一分支体时，使用 `|` 连接：

```kun
case level of
  Info | Success  -> "good"
  Warning         -> "warn"
  Failure | Rollback -> "danger"
```

`|` 的语义是逻辑或——从左到右依次尝试每个子模式，首个匹配即进入该分支。

`|` 连接的子模式共享同一分支体，分支体支持多语句序列，规则同单模式分支。

`when` 守卫作用于整个 or 模式（而非仅最后一个子模式）：

```kun
case color of
  Red | Blue when darkMode -> "dark accent"
  Red | Blue               -> "accent"
  Green                    -> "secondary"
```

上例中 `Red | Blue when darkMode` 等价于 `Red when darkMode -> "dark accent"` 和 `Blue when darkMode -> "dark accent"` 两个独立分支的简写。

**变量绑定一致性**：or 模式的所有子模式必须绑定**相同名称和相同类型**的变量。以下为非法组合：

```kun
// 非法：变量名不一致
Ok a | Err b -> process a

// 非法：一个绑定一个通配
Ok a | Err _ -> process a
```

合法写法是各子模式绑定一致的变量名：

```kun
case result of
  Ok a | Err a -> toString a        // ✅ 都绑定 a
  Nil -> "nothing"
```

**不可嵌套**：or 模式是 case 分支级别的语法糖，不能出现在模式内部（如 `(A | B, C)`）。需要此场景用并列分支代替。

穷举检查：对自定义和类型（含 `Result`）、`Bool` 强制穷举。穷举检查算法为标准的矩阵分解法（Pattern Matrix Decomposition），覆盖嵌套模式、or 模式和守卫子句。or 模式的分支视为已覆盖所有列出的变体——守卫子句不改变穷举性判定（不能将守卫视为覆盖未守卫分支的替代）。变量绑定不一致在编译期报错。缺失分支的错误消息列出未被覆盖的构造器组合。

### If 表达式

```kun
if condition then
  expr1
else if condition2 then
  expr2
else
  expr3
```

`if` 是表达式，必有返回值。`else` 分支**可省略**——省略时隐式类型为 `Unit`。在 bound 位置（结果被值绑定或作为函数返回值）省略 `else` 时，`then` 分支也必须返回 `Unit`（如使用 `do`），否则分支类型不一致导致编译错误。

`if` 分支体遵循与 `case` 相同的 [unbound / bound 规则](#分支体)：

- **Unbound**（结果未被消费，处于 `do` 上下文）：分支内可直接书写多语句，结果视为 `Unit`，无需显式 `do` 包裹。若分支内无效应调用则告警。
- **Bound/Returned**（结果被值绑定或作为函数返回值）：多语句分支须用 `do in`（效应上下文）或 `let in`（纯上下文）包裹为单一表达式；单表达式分支直接书写。各分支结果类型必须相同。

`if` 分支体内可包含 `case` 表达式，其嵌套分支边界由 `else if`/`else` 定界，不受 `case` 内部 `pattern ->` 影响。

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

`do` 块在效应上下文中按顺序执行操作。`do` 块内使用 `=` 绑定值（严格求值，按声明顺序）。

#### 裸 `do`（返回 Unit）

裸 `do` 表达式的结果始终为 `Unit`。空 body 的 `do` 为编译错误：

```kun
main : List String -> Unit
main = \_ ->
  do
    content = File.readString p"/tmp/foo"
    case content of
      Ok text -> IO.print text
      Err _   -> IO.println "failed"
```

> `do` 表达式的结果固定为 `Unit`，不由 body 内任何语句决定。

#### `do in`（返回具体值）

需要从效应上下文中返回值时使用 `do in`。`in` 之后的表达式结果即为整个 `do in` 的结果。`in` 处于效应上下文内，可调用效应函数。`do in` 的结果必须为非 `Unit` 类型；`in` 内表达式的结果为 `Unit` 时编译错误。

空 body 的 `do in` 为编译错误——若仅有 `in` 中的表达式而 body 无任何语句，直接书写表达式即可：

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

#### 效应函数体约束

包括 `main` 在内的所有效应函数，其函数体必须显式以 `do` 或 `do in` 包裹——无论单语句还是多语句。匿名效应函数同样如此。

纯函数体为 `let in`（单一表达式时可省略），不得使用 `do`/`do in`。

#### 告警规则

- 顶级 `do`/`do in` 表达式内无任何效应函数调用：告警（`do` 是为效应操作设计的，无效应调用无意义）
- Unbound 分支（隐式 `do`）内无效应函数调用：告警
- `do` body 中纯表达式作为独立语句且结果未被消费：告警
- 纯函数调用结果绑定到变量后未被引用：告警
- 纯函数调用结果绑定到 `_` 时：告警（浪费 CPU，无意义）
- `do` body 最后一条语句是纯表达式：告警

#### 与 `let in` 的互斥

同一函数 scope 内，`do` 与 `let` 不可互相嵌套：
- `do` 内不可出现 `let in`——需多语句局部定义时使用 `=` 绑定（严格求值），需返回值时使用 `do in`
- `let in` 内不可出现 `do`/`do in`——纯上下文禁止效应操作
- `do` 内可嵌套 `do`，`let` 内可嵌套 `let`

#### do 块规则

- `do` 块内使用 `=` 绑定值（严格求值，按声明顺序）
- 效应函数（`IO.*`、`File.*`、`Env.*`、`Process.*`、`Task.*`、`Random.*` 命名空间的函数 + `Signal.on` + `Cmd.<bin>?`/`Cmd.<bin>!`/`Cmd.pipe?`/`Cmd.pipe!`/`Cmd.timeout`/`Cmd.retry`/`Cmd.which`/`Cmd.exec`/`Cmd.execSafe` + 用户定义含 `do` 块的函数 + 签名中声明了 `(a -> b)!` 参数的函数）只能在 `do` 块中调用；`Cmd.<bin>` 构造 `Command` 值及 `Cmd` 装饰函数（`Cmd.pipe`、`Cmd.withEnv` 等，接收并返回 `Command`）为纯操作，可在 `do` 块外使用
- 含 `do` 块的函数自动标记为效应函数
- 签名中声明了 `(a -> b)!` 参数的函数自动标记为效应函数
- 纯函数（无 `do` 块、无 `!` 参数）不能调用效应函数
- `do` 块内的 `Cmd.<bin>` 表达式不会被隐式执行——需通过 `|>` 管道触发、`Cmd.exec` 显式执行或 `?` 后缀立即执行。未被消费的 `Command` 值在 `do` 块内是编译错误

### defer 资源清理

`defer expr` 在 `do` 块内注册资源清理操作，其父级表达式必须为 `do` 表达式。`defer` 所属 `do` 块退出时（正常返回或 panic unwind）按 LIFO 逆序执行。

`defer` 的作用域为**最接近的外层 `do` 块**——包括显式 `do` 和隐式 `do`（unbound case/if 分支）。嵌套 `do` 块各自管理独立的 `defer` 链：

```kun
do                                           // 外层 do
  case command of
    Deploy config ->                         // unbound 分支 → 隐式 do
      defer cleanupDeploy ()                 // 挂载到分支的隐式 do
      Cmd.ffmpeg {} "input.mp4" tmp |> Cmd.exec
      // defer cleanupDeploy 在此处执行（分支退出时）
    Rollback version ->
      do                                    // 显式内层 do
        defer cleanupRollback ()
        // ...
      // defer cleanupRollback 在此处执行（内层 do 退出时）
  // 外层 do 的 defer（若有）在此处执行
```

> **defer 在 unbound 分支中**：属于该分支自身的隐式 `do`，退出分支时立即执行。若需共享外层 `do` 的 `defer` 生命周期，将 `defer` 语句写在外层 `do` 中而不在分支内。

规则：
- `defer` 仅在 `do` 块内有效（`let in` 上下文中不可使用）
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
{a, .._} = config                    // 解构，丢弃剩余字段

{x as x1, y as y1} = point            // 解构带别名

> Record rest 模式：`..rest` 将未匹配的剩余字段作为新 Record 绑定到 `rest`；`.._` 丢弃剩余字段（不绑定）。**裸 `..`（无变量名）不是合法语法**——必须后跟绑定变量或 `_`。`..rest` / `.._` 必须出现在 Record 模式和解构模式的末尾。

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

### 函数体约束

每个函数体为独立 scope，单一表达式规则从头应用：

- **效应函数**：函数体必须显式以 `do`/`do in` 包裹，无论单语句还是多语句：
  ```kun
  main : List String -> Unit
  main = \_ ->
    do
      content = File.readString p"/tmp/foo"
      IO.print content
  ```
- **纯函数**：函数体为 `let in`（单一表达式时可省略）：
  ```kun
  add : Int -> Int -> Int
  add = \x y ->
    x + y                           // 单表达式，let in 省略

  sumAndFloor : List Int -> Int
  sumAndFloor = \items ->
    let
      total = List.sum items
    in
      toInt (toFloat total / 3.0)    // 多语句，须用 let in
  ```
- 效应函数内可定义纯函数（纯函数获得独立的纯 scope），但纯函数内不得定义或调用效应函数（编译错误）。
- `main` 签名固定为 `List String -> Unit`，退出码通过 `Process.exit n` 返回。

顶层函数建议标注类型签名。局部函数可省略：

```kun
main = \_ ->
  do
    double = \x -> x * 2
    IO.print (toString (double 21))
```

### 函数参数支持直接解构

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

`Nil` 字面量为内置常量值，类型为多态 `?a`，可赋值给任何 `?T` 类型的变量或在模式匹配中使用。详见 [类型系统](type-system.md#nilable-类型-t)。

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

> **项目库根 `lib/`**：项目内的所有库模块**必须**放置在项目根目录的 `lib/` 子目录下。`lib/` 本身不进入模块命名空间——其内的文件路径（相对于 `lib/`）直接决定模块名。入口脚本（含 `main` 的可执行文件）与 `lib/` 并列置于项目根。

> **命名强制**：`lib/` 内的模块文件及各级子目录均采用 **PascalCase**（大驼峰）命名——与模块名语义一致。入口脚本采用 **kebab-case** 命名。

### 模块组织

```
my-project/
├── deploy.kun                  ← 可执行脚本（有 main，无 export）
├── build.kun                   ← 可执行脚本
└── lib/                        ← 项目库根（编译器从此搜索，不参与模块命名）
    ├── File.kun                ← 模块 File
    ├── List.kun                ← 模块 List
    ├── Cmd/                    ← 子命名空间 Cmd（PascalCase）
    │   ├── Git.kun             ← 模块 Cmd.Git
    │   └── Docker.kun          ← 模块 Cmd.Docker
    ├── Parser/                 ← 子命名空间 Parser（PascalCase）
    │   ├── JSON.kun            ← 模块 Parser.JSON
    │   └── Record.kun          ← 模块 Parser.Record
    └── MyApp/                  ← 自定义命名空间 MyApp
        ├── Config.kun          ← 模块 MyApp.Config
        └── Handler.kun         ← 模块 MyApp.Handler
```

> 标准库的物理路径为 `<runtime>/lib/kun/`，其 `lib/kun/` 即为库根。导入 `List` 时编译器在 `lib/kun/List.kun` 查找。

### 搜索路径

编译器按以下优先级查找模块：

| 优先级 | 路径 | 范围 |
|--------|------|------|
| 1 | 项目 `lib/` | 从项目根 `lib/` 出发按模块路径查找。编译期索引全库，O(1) |
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

1. 项目本地路径 `./lib/` 优先于标准库路径 `<runtime_prefix>/lib/kun/`
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
Stream.filterMap    : (a -> ?b) -> Stream a -> Stream b      // 映射并丢弃 Nil
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
| 2026.06.19 | 单一表达式范式全面定稿：新增「单一表达式范式」章节；`do` 固定返回 `Unit`，`do in` 返回值至外部作用域（必须非 `Unit`，`in` 处于效应上下文）；空 body 的 `do`/`do in`/`let in` 为编译错误；`case`/`if` 分支按 unbound/bound 区分隐式 `do`（不需包裹）/显式 `do in` 或 `let in`（多语句须包裹）；`do` 上下文链式继承；`let in` 禁止效应函数调用、定义及引用（编译错误）；`defer` 作用域为最近外层 `do`（含隐式 `do`）；匿名函数 body 必须显式 `do`/`let in` 包裹；纯函数体单一表达式可省略 `let in`；效应函数体必须显式 `do`/`do in` 包裹；`main` 固定 `List String -> Unit`；新增告警与错误清单 |
| 2026.06.18 | Record/List rest 模式文档补全：新增 `.._`（丢弃剩余）形式，明确裸 `..` 不是合法语法；Record 模式、List 模式、名字绑定三处同步 |
| 2026.06.18 | Cmd API 精简：效应函数列表移除 `Cmd.execSafe`（旧 `Result Unit`）、`Cmd.stdoutToString`、`Cmd.stderrToString`；新增 `Cmd.<bin>!`/`Cmd.pipe!`/`Cmd.execSafe`（新 `Result (Stream String)`） |
| 2026.06.18 | 审计修复：Stream 变换 API 补充 `filterMap` |
| 2026.06.18 | 审计修复：DateTime f-string `%` 引导符与 `DateTime.format` API 的差异化说明 |
| 2026.06.18 | 新增 Or 模式语法：`case` 分支中支持 `Pat1 \| Pat2 -> expr`，含变量绑定一致性检查和守卫子句规则 |
| 2026.06.17 | 模块组织：明确项目模块必须置于 `lib/` 子目录；`lib/` 内子目录及模块文件强制 PascalCase 命名；入口脚本 kebab-case；移除 `./modules/` 陈旧引用 |
| 2026.06.15 | 审计修复三轮：`?.`/`??` 补入优先级层次图；关键字表格新增；`_` 参数/解构语义文档化；空容器 HM 推断规则；布局敏感性澄清；`.` 消除歧义机制 |
| 2026.06.15 | 审计修复：Nil 字面量补入字面量表格与 Nilable 章节 |
| 2026.06.14 | 函数类型语法新增 `(a -> b)!` 效应回调标注；do 块规则更新：含 `!` 参数的函数为效应函数；`do` 块内 Command 取消隐式执行，需通过 `Cmd.exec`/`|>`/`?` 显式触发；未被消费的 Command 是编译错误 |
| 2026.06.13 | 管道示例统一模块限定风格；冗余引用路径修正 |
| 2026.06.11 | 模块系统：目录即命名空间，`export (…)`/`import X (…)` |
| 2026.06.10 | 架构重设计：运算符、管道、表达式、函数定义等语法定型 |
