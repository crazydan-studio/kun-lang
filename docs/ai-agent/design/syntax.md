# 语法设计

## 设计原则

1. **单表达式**：一切皆为表达式，每条表达式返回一个确定类型的值；多语句形式以 `let ... in ...`（返回值）或 `do ...`（返回 `Unit`，≡ `let ... in ()`）表达
2. **简洁一致**：借鉴 Elm（为主）、Haskell 和 Rust，避免冗余关键字
3. **声明与实现可分离或同行**：类型标注与值定义可分两行（`name : Type` 然后 `name = expr`），也可写在一行（`name : Type = expr`）。多语句函数体或长类型推荐分两行，简单绑定可同行
4. **显式边界**：副作用通过效应集 `! E` 在类型层显式标注；错误处理（`Result`）显式
5. **最小惊喜**：优先采用 Shell 用户熟悉的符号约定
6. **立即求值**：所有表达式立即求值，`let in` 绑定立即；`Lazy`/`Stream` 为显式惰性特区
7. **显式执行**：Command 执行全显式（`Cmd.exec`/`Cmd.execSafe`/`Cmd.stream`），无 Command 的 `?`/`!` 后缀糖，无 `|>` 隐式触发；零参函数执行用 `!` 后缀（见[类型系统 - 零参效应函数类型](type-system.md#零参效应函数类型-t-e)）

## 单表达式

Kun 采用**单表达式**（Single Expression）范式——程序中所有构造均为表达式，求值后得到具体类型的值。类型的实例即为值。多语句形式分两类：返回值的 `let <body> in <expr>` 与返回 `Unit` 的 `do <body>`（≡ `let <body> in ()`）。`do` 是 `let ... in ()` 的语法糖，可紧跟 `->`（函数箭头或分支箭头）以减少缩进。

### 表达式分类

| 表达式形式 | 是否单表达式 | 结果类型 | 说明 |
|-----------|--------------|---------|------|
| 字面量、变量访问 | 是 | 对应类型 | `42`、`"hello"`、`myVar` |
| 函数调用 | 是 | 函数返回类型 | `add 1 2` → `Int` |
| 类型值（类型名本身） | 是 | 自身类型 | `Int`、`String` |
| `if/then/else`、`case/of`、三元 `? :` | 是 | 各分支的统一类型 | 分支结果类型必须相同（可为 `Unit`） |
| `let <body> in <expr>` | 是 | `<expr>` 的类型 | 多语句 + 返回值；用于函数体/if/case 分支/值绑定 |
| `do <body>` | 是 | `Unit` | 多语句 + 无返回值；≡ `let <body> in ()`；可紧跟 `->` |
| `handle <expr> with <handler>` | 是 | `<expr>` 的类型（效应被消解） | 仅 `main`/`TestCase.body` 内可用 |
| `=`（值绑定） | **否** | 无（不返回值） | 绑定名通过变量访问获取值 |

### 三种形式的选用

| 场景 | 语法 | 返回值 | 说明 |
|---|---|---|---|
| 多语句 + 返回值 | `let <body> in <expr>` | `<expr>` 的类型 | 直接用于函数体/if/case 分支/值绑定 |
| 多语句 + 无返回值 | `do <body>` | `Unit` | ≡ `let <body> in ()`；`do` 可紧跟箭头 |
| 单语句 | 直接书写 | 语句类型 | if/case 分支须同类型 |

### 多语句与作用域

`let in` 的 `<body>` 中允许包含多条语句——三种语句类型：

| 语句 | 语法 | 求值 |
|---|---|---|
| 绑定 | `name = <expr>` | 立即求值并绑定 |
| 效应调用（无绑定） | `<expr>` | 立即执行，结果丢弃 |
| 纯表达式（无绑定） | `<expr>` | 告警（无意义） |

所有语句按声明顺序立即求值（call-by-value，立即求值，**非延迟**）。`Lazy` 模块（`Lazy.lazy`/`Lazy.force`）与 `Stream` 为显式惰性特区。

### 分支表达式的多语句规则

`case`/`if` 表达式中，根据表达式结果是否被消费，分支的包裹规则不同（详见 [unbound/bound 分支规则](#unboundbound-分支规则)）：

- **Unbound**（结果未被值绑定，也不作为函数返回值）：继承外层 `do`/`let in` 效应上下文，分支内可直接写多语句，结果视为 `Unit`
- **Bound/Returned**（结果被值绑定或作为函数返回值）：各分支必须返回相同类型的值（可为 `Unit`）。多语句返回 `Unit` 用 `do`；多语句返回非 `Unit` 用 `let in`；单语句直接书写

### 函数体与 Scope 规则

- 每个函数体均为独立 scope，单表达式规则从头应用
- 函数体多语句返回 `Unit` 用 `do`；多语句返回非 `Unit` 用 `let in`；单语句直接书写
- `main` 签名为 `List String -> Unit ! {IO, File, Cmd, ...}`，效应集允许所有内置效应；退出码通过 `Process.exit n` 返回或 panic 退出码规则

## 词法分析

### Token 类型

词法分析器将源码扫描为以下 Token 类型：

| Token 类别 | 示例 | 说明 |
|-----------|------|------|
| 关键字 | `type`、`alias`、`effect`、`handler`、`handle`、`with`、`extern`、`cmd`、`continue`、`abort`、`case`、`of`、`if`、`then`、`else`、`let`、`in`、`do`、`defer`、`import`、`export`、`as`、`not`、`true`、`false` | 详见关键字表。`Nil` 和 `Some` 不是关键字——它们是 `Nilable` ADT 的变体名，通过缺省导入可用（类似 `Ok`/`Err`）。`assert`/`fail`/`skip` 不是关键字——它们是 `Test` 标准库效应的操作（需 `import Test`） |
| 标识符 | `myVar`、`MyType`、`snake_case_func` | 小写开头为变量/函数，大写开头为类型/变体/模块 |
| 整数字面量 | `42`、`0xFF`、`0o77`、`0b1010`、`1_000_000` | 十进制/十六进制/八进制/二进制，`_` 分隔符可选 |
| 浮点数字面量 | `3.14`、`2.5e10`、`1.0` | 必须含 `.` 且至少一位数字在小数点两侧 |
| 字符串字面量 | `"hello"`、`"""multiline"""` | 支持转义序列（见下方转义序列表） |
| 前缀字符串 | `p"/tmp"`、`r"[0-9]+"`、`f"hello {name}"` | 原始字符串——仅 `\"` 需转义 |
| 字符字面量 | `'A'`、`'\n'`、`'好'` | Unicode 标量值 |
| Duration 字面量 | `5s`、`100ms`、`2h`、`30m`、`1d` | 数字 + 单位后缀 |
| `cmd` 字面量 | `cmd ls { a } [ "/tmp" ]` | 四段式命令构造，详见 [cmd 字面量](#cmd-字面量) |
| 运算符/标点 | `\|>`、`<\|`、`>>`、`<<`、`++`、`&&`、`\|\|`、`==`、`/=`、`<=`、`>=`、`+`、`-`、`*`、`/`、`%`、`&`、`\|`、`^`、`=`、`:`、`.`、`,`、`\|`、`!` | 多字符运算符最长匹配；`&`/`\|`/`^` 为 `Int` 位运算；`!` 为效应集引导符 |
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

## 注释与文档注释

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
// - 交叉引用 [[Module.func]]
```

Kun 仅支持 `//` 风格的注释。没有块注释语法（`/* */`）。连续多行 `//` 构成多行注释块。

### 文档注释规范

文档注释采用**多行 `//`**，支持 **Markdown 语法**。紧邻声明（`type`/`alias`/`effect`/`handler`/`extern`/函数/`export`）上方，由 `kun doc` 提取生成文档。

**语法**：连续的 `//` 行，每行 `//` 后加一个空格再写内容。

```kun
// 计算两数之和
//
// # 参数
// - `x`: 第一个数
// - `y`: 第二个数
//
// # 示例
// ```kun
// add 1 2  // 3
// ```
//
// # 注意
// 溢出时 panic（Debug 模式）。
add : Int -> Int -> Int
add = \x y -> x + y
```

**支持的 Markdown 子集**：

| 语法 | 说明 |
|---|---|
| `#`/`##`/`###` | 标题 |
| `` `code` `` | 行内代码 |
| ` ```kun ``` ` | 代码块（支持语法标注） |
| `-` / `*` | 列表 |
| `**bold**` | 加粗 |
| `*italic*` | 斜体 |
| `[text](url)` | 链接 |
| `[[Module.func]]` | 交叉引用（链接到其他模块/函数） |
| `>` | 引用 |

**规则**：

1. 文档注释必须紧邻声明（中间无空行）
2. 连续 `//` 行视为同一文档注释块
3. 遇到非 `//` 行或空行，文档注释块结束
4. `kun doc` 提取文档注释生成 Markdown 文档
5. 行尾注释（代码后 `//`）不视为文档注释

```kun
// 这是一个文档注释（紧邻 add 声明）
add : Int -> Int -> Int
add = \x y -> x + y

// 这是普通注释（与声明间有空行，非文档注释）

foo : Int -> Int
foo = \n -> n + 1

bar : Int -> Int
bar = \n -> n * 2  // 这是行尾注释，非文档注释
```

## 字面量

| 类型 | 语法 | 示例 |
|------|------|------|
| Int | 十进制、`0x`/`0o`/`0b` 前缀、`_` 分隔 | `42`, `-3`, `0xFF`, `0o644`, `1_000_000` |
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
| `Nil` | `Nil` | `Nilable T`（`?T`）类型的 `Nil` 变体——与 `Some` 同为缺省可用的 ADT 变体，非特殊字面量 |
| Path | `p"..."` 前缀 + 双引号 | `p"/tmp/foo"`, `p"./foo"`, `p"/tmp/foo.sh"` |
| cmd | `cmd <命令> <子命令>* <选项>? <位置参数>?` | `cmd ls { a } [ "/tmp" ]` |

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
| 类型变量 | 小写字母，单字优先 | `a`, `b`, `key`, `value`, `e`（效应变量） |
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
| 类型声明 | `type`、`alias` |
| 效应声明 | `effect`、`handler`、`handle`、`with`、`extern` |
| 命令字面量 | `cmd` |
| 控制流 | `if`、`then`、`else`、`case`、`of`、`continue`、`abort` |
| 绑定 | `let`、`in`、`do` |
| 清理 | `defer` |
| 测试 | （无关键字；`assert`/`fail`/`skip` 为 `Test` 标准库效应的操作，需 `import Test`） |
| 模块 | `export`、`import`、`as` |
| 字面量 | `true`、`false` |
| 运算符 | `not` |

> `Nil` 和 `Some` 不是关键字——它们是编译器内置 ADT `Nilable a` 的变体名，始终缺省可用（类似 `Ok`/`Err`）。`Nil` 不是特殊字面量，而是 `Nilable` ADT 的无 payload 变体。
>
> `do` 是关键字，作为 `let <body> in ()` 的语法糖，用于多语句返回 `Unit` 的场景，可紧跟 `->`（函数箭头或分支箭头）以减少缩进。

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

### `alias`：别名定义

`alias` 定义任意类型（含 Record）的**透明别名**，编译期展开为底层类型，结构等价，无运行时存在，无构造器：

```kun
// Record 别名
alias Point = { x : Float, y : Float }
alias Config = { host : String, port : Int }

// 基础类型别名
alias UserId = Int
alias Age = Int

// 复合类型别名
alias Users = List User
alias UserMap = Map String User

// 函数类型别名
alias Comparator a = a -> a -> Int
```

**语义**：

- 编译期展开为底层类型，无运行时开销
- 结构等价：`Point` 与 `{ x : Float, y : Float }` 完全等价
- 无构造器，无抽象屏障
- 用于类型缩写，简化签名

```kun
alias Point = { x : Float, y : Float }

p : Point
p = { x = 1.0, y = 2.0 }   // ✅ 匿名 Record 直接赋值
p.x                         // ✅ 直接访问字段

// Point 不是构造器
// p = Point { x = 1.0, y = 2.0 }   // ❌ 编译错误：Point 不是函数
```

### `type`：ADT 定义

`type` 定义代数数据类型，名义等价，有抽象屏障。支持单变体（包装类型）与多变体（和类型），二者保持一致的 ADT 语义（均含构造器，均有 tag，**不做 tag 擦除**）。

**单变体 ADT（包装类型，有抽象屏障）**：

```kun
type User = User { name : String, id : Int }
type Session = Session { name : String, id : Int }
type UserId = UserId Int
type Email = Email String
```

- 名义等价：`User` ≠ `Session`，`User` ≠ `{ name, id }`
- 有构造器：`User : { name, id } -> User`
- 有 tag：与多变体 ADT 一致，**不做 tag 擦除**
- 用于需要抽象屏障的类型包装

**多变体 ADT（和类型）**：

```kun
type Color
  = Red
  | Green
  | Blue

type Result a e = Ok a | Err e

type Tree a = Leaf | Node a (Tree a) (Tree a)

type Shape
  = Circle Float
  | Rectangle Float Float

type Person = Person { name : String, age : Int }
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

**单变体与多变体的一致性**：单变体 `type User = User { ... }` 与多变体 `type Result a e = Ok a | Err e` 都是 ADT，运行时均为 tagged union。**不做 tag 擦除优化**，保持 ADT 语义统一。单变体可自然演化为多变体（添加变体），无需改变运行时表示或编译器处理。

### 构造与解构

```kun
type User = User { name : String, id : Int }

// 构造（用构造器）
user : User
user = User { name = "alice", id = 1 }

// 解构（模式匹配）
name =
  case user of
    User r -> r.name

// Record 更新语法糖
user1 =
  case user of
    User r ->
      User { r | name = "bob" }
```

### 类型标注

类型标注与值定义可写在一行（`name : Type = expr`），也可分两行（`name : Type` 后接 `name = expr`），二者语义等价：

```kun
add : Int -> Int -> Int = \x y -> x + y
identity : a -> a = \x -> x
x : Int = 5
```

等价于分两行写法：

```kun
add : Int -> Int -> Int
add = \x y -> x + y

identity : a -> a
identity = \x -> x

x : Int
x = 5
```

选择原则：

- **简单绑定、短类型** → 同行（如 `x : Int = 5`）
- **多语句函数体、长类型** → 分两行（便于阅读）
- **函数体使用 `let in` 包裹** → 分两行（`let in` 块不便于同行）

`let in` 块内同样支持同行标注：

```kun
let
  x : Int = 5
  y : String = "hello"
  z : ?Path = Nil
in
  ...
```

零参效应函数标注示例：

```kun
pid : Process.Pid ! {Process}
pid = \ ->
  let
    p = Process.pid!
  in
    p

main : List String -> Unit ! {IO}
main = \_ -> do
  content = File.read p"/tmp/foo"
  case content of
    Ok text -> IO.print text
    Err _   -> IO.println "failed"
```

函数类型语法：

```kun
T ! {E}                   // 零参效应函数（无 `->`，有 `! {E}`）
T1 -> T2 -> T3           // 柯里化函数
(T1, T2) -> T3           // 元组参数（参数本身为元组）
T1 -> T2 ! {IO}          // 效应函数（IO 效应）
T1 -> T2 ! {}            // 纯函数（效应空集）
T1 -> T2                 // 等价 T1 -> T2 ! {}（无 ! 即纯）
(a -> b ! e) -> List a -> List b ! e   // 效应多态（单变量 e）
```

规则：

- 除非参数本身是元组类型，否则函数类型均为柯里化形式（`Int -> Int -> Int`）
- 零参效应函数类型为 `T ! {E}`（无 `->`，有 `! {E}`）；纯零参函数退化为常量，使用 `let` 绑定。`! {E}` 存在且无 `->` 即标识零参效应函数
- 零参函数的执行用 `!` 后缀（如 `DateTime.now!`）；裸名 `DateTime.now` 是函数引用，可作为一等值传递。此 `!` 与已废弃的 Command 断言执行 `!`（旧 `c!` → 现 `Cmd.exec c`）是不同特性
- 纯函数返回类型不可为 `Unit`——纯 `Unit` 返回值无意义（无输出、无副作用），退化为无操作（no-op），编译期报错。效应函数可返回 `Unit`
- 单参数免除圆括号：`Int -> Int` 而非 `(Int) -> Int`
- 零参效应函数类型作参数须括号化：`runThunk : (Unit ! {IO}) -> Unit ! {IO}`（参数为零参效应函数引用，体内 `f!` 执行）
- 效应集 `! E` 是函数类型的组成部分，参与 HM 合一；无 `!` ≡ `! {}`（纯）
- 效应多态通过单效应变量 `e` 表达，调用时实例化

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
[0..1000000] |> Stream.filter (\n -> n % 2 == 0) |> Stream.take 10 |> Stream.toList
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

零参 Lambda `\ -> expr` 用于函数类型为 `T ! {E}`（无 `->`）的效应函数。调用通过 `!` 后缀执行。纯函数不允许定义为零参，且返回类型不可为 `Unit`。

`_` 可作为 Lambda 参数名表示丢弃该参数——`\_ -> expr` 等价于 `\x -> expr`（`x` 未在函数体中出现）。丢弃多个参数使用多重 `_`：`\_ _ -> expr` 丢弃前两个参数；`\_ y -> expr` 丢弃第一个参数并绑定第二个参数为 `y`。

#### 匿名函数 body 规则

匿名函数为独立 scope，单表达式规则从头应用。函数体规则与具名函数一致：

- **返回 `Unit` 的多语句匿名函数**：函数体用 `do`，可紧跟 `->`：
  ```kun
  \x -> do
    IO.println x        // 单语句或多语句
  ```
- **返回非 `Unit` 的多语句匿名函数**：函数体用 `let in`：
  ```kun
  \x ->
    let
      y = x + 1
    in
      y * 2               // 多语句，必须 let in
  ```
- **单语句匿名函数**：直接书写，无需 `do`/`let in` 包裹：
  ```kun
  \x -> x + 1             // 单表达式
  ```

作为实参的匿名函数同样遵循以上规则。

### 函数应用

函数应用通过空格分隔，不使用逗号：

```kun
identity 42
map (\x -> x * 2) list
File.read p"/tmp/foo"
lookup 1234
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
{x as x1, y as y1} = point
```

解构赋值中 `_` 表示丢弃对应元素：`(x, _, z) = tuple` 丢弃第二个元素。`.._` 用于丢弃 Record 或 List 的全部剩余字段/元素：`{ a, .._ }` 提取 `a` 并丢弃其余字段，`[x, .._]` 提取首元素并丢弃后续部分。**裸 `..` 不是合法语法**——必须后跟变量名（`..rest`）或 `_`（`.._`）。

## 单表达式：`let in` 与 `do`

单表达式有两种多语句形式：返回值的 `let <body> in <expr>` 与返回 `Unit` 的 `do <body>`（≡ `let <body> in ()`）。`do` 是 `let ... in ()` 的语法糖，可紧跟 `->`（函数箭头或分支箭头）以减少缩进。**`do in` 不再使用**——返回值的场景一律用 `let ... in ...`。

### 基本形式

**`let ... in ...`**（多语句 + 返回值）：

```kun
let
  <stmt1>
  <stmt2>
  ...
in
  <expr>
```

- `stmt`：语句（绑定、效应调用、纯表达式）
- `expr`：返回表达式

```kun
let
  square = \x ->
    x * x
in
  square 3
```

**`do ...`**（多语句 + 返回 `Unit`，≡ `let <body> in ()`）：

```kun
do
  <stmt1>
  <stmt2>
  ...
```

- `stmt`：语句（绑定、效应调用、纯表达式）
- 隐式返回 `()`

```kun
action = do
  IO.println "line1"
  IO.println "line2"
```

### 三种语句类型

| 语句 | 语法 | 求值 |
|---|---|---|
| 绑定 | `name = <expr>` | 立即求值并绑定 |
| 效应调用（无绑定） | `<expr>` | 立即执行，结果丢弃 |
| 纯表达式（无绑定） | `<expr>` | 告警（无意义） |

```kun
let
  users = DB.query all          // 绑定：立即求值并绑定
  count = List.length users     // 绑定：立即求值并绑定
  IO.println "done"             // 效应调用：立即执行，结果丢弃
  1 + 2                         // 纯表达式：告警（无意义）
in
  count
```

### `do` 作为 `let ... in ()` 的语法糖

返回 `Unit` 的多语句块用 `do` 更为简洁——与 `let <body> in ()` 语义等价：

**`do <body>`（推荐形式）**：

```kun
do
  IO.println "line1"
  IO.println "line2"
// ≡ let
//      IO.println "line1"
//      IO.println "line2"
//    in ()
```

**`let <body> in ()`（等价但冗余）**：

```kun
let
  IO.println "line1"
  IO.println "line2"
in
  ()
```

**规则**：`do <body>` ≡ `let <body> in ()`，固定返回 `Unit`，效应集为体内效应并集。`do` 可紧跟 `->`（函数箭头或分支箭头）以减少缩进。

### `do` 紧跟箭头（减少缩进）

函数体与 case/if 分支中的多语句 Unit 块用 `do` 紧跟箭头，使 body 缩进减少一层：

```kun
// 函数箭头后 do
main : List String -> Unit ! {IO}
main = \args -> do
  IO.println "starting"
  IO.println "done"

// case 分支箭头后 do
case result of
  Ok user -> do
    Log.info "found"
    IO.println user.name
  Err _ -> do
    Log.error "not found"
    IO.exit 1
```

### 解析器识别规则（关键字定界）

`do`/`let` 后的语句块以**关键字定界**判定结束，**不依赖缩进**：

1. `let <body> in <expr>` — `let` 后遇 `in` 关键字结束 body，`in` 后必须有表达式
2. `do <body>` — `do` 后语句持续至遇到定界符（下一个 `pattern ->`、`else`/`else if`、`in`、`}`、`)` 或外层块结束）
3. `let` 后**必须**有 `in`——不再支持无 `in` 的 `let <body>` 形式（Unit 返回用 `do`）
4. `let in`（空 body + 空 expr）或 `do`（空 body）→ 编译错误
5. 缩进仅用于格式可读性，不影响解析；缩进不一致 → lint 告警

```kun
// do 形式：关键字定界
main = \args -> do
  IO.println "line1"
  IO.println "line2"
// 函数体结束，do 块随之结束

case result of
  Ok x -> do
    IO.println "ok"
    process x
  Err _ -> do
    IO.println "err"
    fallback
// 下一个 pattern -> (Err _) 结束 Ok 分支的 do 块

// let in 完整形式：显式 in
let
  x = compute
  IO.println "done"
in
  x
```

> **注**：解析器不依赖缩进来解析 `do`/`let` 块结构——所有代码块由显式关键字界定（`do`、`let...in`、`case...of`、`handle...with`）。分支体内多语句的边界通过 `pattern ->` / `else if` / `else` 关键字定界 + `case...of` 配对跟踪实现。缩进规则仅约束代码**格式**（可读性），不约束代码**语义**。

**笔误检测**：

- `in` 后无表达式 → 编译错误
- `do` 仅单语句 → lint 告警“单语句 Unit 块可省略 `do`，直接书写”

适用场景：`main` 函数、仅副作用的函数、循环体等 Unit 返回场景。

### 效应集推导

`let in`/`do` 效应集 = 体内所有效应语句的并集：

```kun
let
  users = DB.query all          // {DB}
  count = List.length users     // {}（纯）
  IO.println "done"             // {IO}
in
  count
// 效应集：{DB, IO}
// 类型：Int ! {DB, IO}
```

### 嵌套 `let in`

```kun
let
  users = DB.query all
  names =
    let
      active = List.filter isActive users
    in
      List.map (.name) active

  IO.println "done"
in
  names
```

嵌套 `let in` 的值可在后续语句使用。**所有 `let in` 立即求值**——内层 `let in` 在外层语句执行到时立即求值，非延迟。

### 空 body 约束

`let in` 空 body（无任何绑定的 `let in <expr>`）为编译错误。直接在需要的位置书写 `<expr>` 即可。

```kun
// ❌ 编译错误：空 body
result = let in x + 1

// ✅ 直接书写表达式
result = x + 1
```

### 在 case/if 分支中使用

`case`/`if` 表达式中，当结果被值绑定或作为函数返回值（bound/returned）时，多语句分支：返回 `Unit` 用 `do`，返回非 `Unit` 用 `let in`。单语句分支直接书写即可。各分支结果类型必须相同（可为 `Unit`）：

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

### 求值策略：立即求值

`let in` 绑定采用**立即求值**（eager evaluation）——绑定的表达式立即计算并绑定。**这是新设计与旧设计的关键差异**：旧设计 `let in` 采用延迟求值，新设计统一为立即求值。

**相互递归**：立即求值下，相互递归通过 `let in` 绑定组支持的递归 `let` 实现——编译器为递归绑定分配类型变量，函数体检查后泛化：

```kun
let
  isEven = \n -> if n == 0 then true else isOdd (n - 1)
  isOdd  = \n -> if n == 0 then false else isEven (n - 1)
in
  (isEven 10, isOdd 11)           // → (true, true)
```

**显式惰性特区**：若需延迟求值，使用 `Lazy` 模块：

```kun
import Lazy (Lazy, lazy, force)

let
  x = lazy (\_ -> expensiveCalc unused)    // thunk，未计算
  y = cheapCalc
in
  if unused then y else force x            // 引用时才计算
```

- `lazy : (Unit -> a) -> Lazy a`：构造 thunk
- `force : Lazy a -> a`：强制求值（memoize）

`Stream` 内置惰性，元素按需拉取：

```kun
let
  naturals = Stream.range 1 Infinity       // 无限流，惰性
  first10 = Stream.take 10 naturals        // 取前 10
  list = Stream.toList first10             // 转为 List（强制求值）
in
  list
```

### `do in` 不再使用

历史设计中曾存在 `do <body> in <expr>` 形式（返回 `<expr>` 类型的值）。新设计中此形式不再使用——返回值的多语句块一律用 `let <body> in <expr>`，仅 `do <body>`（返回 `Unit`）保留为 `let <body> in ()` 的语法糖。

```kun
// ❌ 不再使用：do in
do
  users = DB.query all
in
  users

// ✅ 返回值用 let in
let
  users = DB.query all
in
  users

// ✅ 返回 Unit 用 do（语法糖）
do
  IO.println "start"
  IO.println "done"
```

## Case 表达式（模式匹配）

```kun
case expr of
  pattern1 -> result1
  pattern2 -> result2
  _        -> default
```

### Unbound/Bound 分支规则

单表达式统一后，分支包裹规则按 unbound/bound 区分：

1. **Unbound 分支**（结果未被值绑定，不作为返回值）：继承外层 `do`/`let in` 效应上下文，分支内可直接写多语句，结果视为 `Unit`
2. **Bound 分支**（结果被值绑定或作为返回值）：多语句返回 `Unit` 用 `do`；多语句返回非 `Unit` 用 `let in`；单语句直接书写

```kun
// unbound 分支（在 do 块内，结果未消费）
do
  case File.read path of
    Ok text -> do
      IO.println "processing"        // 继承外层效应上下文
      process text
    Err _ ->
      IO.println "error"
  IO.println "done"

// bound 分支（结果被绑定）
result =
  case File.read path of
    Ok text ->
      let                              // 多语句返回非 Unit 须 let in 包裹
        parsed = parse text
        Log.info "parsed"
      in
        Some parsed
    Err _ -> Nil
```

模式类型：

### 变体模式

```kun
case parse "42" of
  Ok n  -> process n    // 变体模式 + 变量绑定
  Err _ -> handleError  // 通配忽略
```

### List 模式

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

### List 模式穷举规则

编译器对 List 类型的穷举检查遵循以下规则：

- `[]` 覆盖长度 0 的列表（空列表）
- `[..rest]` 覆盖任意长度的列表（`rest` 为空列表时等同于 `[]` 匹配）：单独使用即穷举
- `[a, ..rest]` 覆盖长度 ≥ 1 的列表
- `[]` + `[a, ..rest]` 覆盖所有长度：`[]` → len=0，`[a, ..rest]` → len ≥ 1
- `[a]` + `[a, b, ..rest]` 覆盖长度 1 和 ≥2，但缺少长度 0——检查器报告缺失 `[]` 分支
- `[a, b]` + `[a, b, c, ..rest]` 覆盖长度 2 和 ≥3，但缺少长度 0 和 1——检查器报告缺失 `[]` 和 `[a]` 分支

List 类型**强制穷举**——缺少分支时产生编译错误，错误信息列出未覆盖的长度范围（如「长度 1 的列表未被覆盖」）。

### 元组模式

```kun
case tuple of
  (1, y) -> 1 + y
  (x, 2) -> 2 * x
  _      -> 0
```

### Record 模式

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

### 守卫子句

```kun
case n of
  m if m > 0 && m <= 10  -> "small"
  m if m > 10            -> "large"
  _                        -> "other"
```

守卫子句使用 `if` 关键字（与 if 表达式复用同一关键字；上下文区分：在 `case` 模式后为守卫，在表达式位置为 if 表达式）。守卫的 `condition` 不影响分支体语义——`->` 后的分支体仍可单表达式或多语句，规则同无守卫分支。

### 通配模式

`_` 作为通配符（位置占位符），匹配任意值但不绑定：

```kun
case result of
  Ok _  -> "success"    // 忽略 Ok 内部的值
  Err _ -> "failed"     // 忽略 Err 内部的值
```

### Or 模式（多模式匹配）

多个变体或字面量共享同一分支体时，使用 `|` 连接：

```kun
case level of
  Info | Success  -> "good"
  Warning         -> "warn"
  Failure | Rollback -> "danger"
```

`|` 的语义是逻辑或——从左到右依次尝试每个子模式，首个匹配即进入该分支。

`|` 连接的子模式共享同一分支体，分支体支持多语句序列，规则同单模式分支。

`if` 守卫作用于整个 or 模式（而非仅最后一个子模式）：

```kun
case color of
  Red | Blue if darkMode -> "dark accent"
  Red | Blue               -> "accent"
  Green                    -> "secondary"
```

上例中 `Red | Blue if darkMode` 等价于 `Red if darkMode -> "dark accent"` 和 `Blue if darkMode -> "dark accent"` 两个独立分支的简写。

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

`if` 是表达式，必有返回值。`else` 分支**可省略**——省略时隐式类型为 `Unit`。在 bound 位置（结果被值绑定或作为函数返回值）省略 `else` 时，`then` 分支也必须返回 `Unit`，否则分支类型不一致导致编译错误。

`if` 分支体遵循与 `case` 相同的 [unbound / bound 规则](#unboundbound-分支规则)：

- **Unbound**（结果未被消费，处于外层 `do`/`let in` 上下文）：分支内可直接书写多语句，结果视为 `Unit`，无需显式包裹
- **Bound/Returned**（结果被值绑定或作为函数返回值）：多语句返回 `Unit` 用 `do`；多语句返回非 `Unit` 用 `let in`；单语句直接书写。各分支结果类型必须相同（可为 `Unit`）

`if` 分支体内可包含 `case` 表达式，其嵌套分支边界由 `else if`/`else` 定界，不受 `case` 内部 `pattern ->` 影响。

### 三元表达式

```kun
condition ? expr1 : expr2
```

三元表达式是 `if condition then expr1 else expr2` 的简洁形式，适用于简单条件。

## 管道操作符

```kun
list |> map (\x -> x * 2)
```

将左侧表达式的值作为最后一个参数传入右侧函数。**`|>` 是纯管道操作符**，统一类型 `a -> (a -> b) -> b`——不再隐式触发 Command 执行。

### 合法用法

```kun
// Command 修饰（Command -> Command）
cmd ... |> Cmd.withWorkDir p"/build"
cmd ... |> Cmd.mergeStderr
cmd ... |> Cmd.withoutDash

// Command 执行（Command -> 其他类型，显式调用执行函数）
cmd ... |> Cmd.exec        // 执行，丢弃输出
cmd ... |> Cmd.execSafe    // 执行，返回 Result
cmd ... |> Cmd.stream      // 执行，返回 Stream

// Stream 管道（Stream -> Stream）
stream |> Stream.lines
stream |> Stream.filter pred
stream |> Stream.toList

// 通用管道（任意类型）
list |> map (\x -> x * 2) |> filter (\x -> x > 5)
```

### 不再合法的用法

```kun
// ❌ 非法：|> 左侧 Command，右侧期望 Stream（类型不匹配）
cmd ls { a } [ "/tmp" ] |> Stream.lines
// 编译错误：Command 不匹配 Stream String
// Hint: 使用 Cmd.stream 执行命令获取输出流：
//       cmd ... |> Cmd.stream |> Stream.lines
```

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

## defer 资源清理

`defer expr` 在 `do`/`let in` 块内注册资源清理操作。`defer` 绑定到**最近 `do`/`let in` 块**，块退出时（正常返回或 panic unwind）按 LIFO 逆序执行。

```kun
do
  case File.createTemp! of
    Ok tmp -> do
      defer (File.remove tmp)
      cmd ffmpeg {} [ "input.mp4", tmp ] |> Cmd.exec
      // defer (File.remove tmp) 在此 do 块退出时执行
    Err _ -> IO.println "failed to create temp file"
```

### `defer` 与 `do`/`let in` 块的关系

`defer` 作用域 = **所在 `do`/`let in` 块**，嵌套时各层独立管理：

```kun
do                                   // 外层 do
  defer (cleanupOuter)            // 外层 defer
  result =
    let                               // 内层 let
      defer (cleanupInner)        // 内层 defer
      value = compute
    in
      value
  // 内层 defer 在此执行（cleanupInner）
  IO.println "outer continues"
// 外层 defer 在此执行（cleanupOuter）
```

### 规则

1. `defer expr` 中 `expr` 在所在 `do`/`let in` 块退出时执行
2. 多个 `defer` 按 LIFO 逆序执行
3. panic 时仍执行 `defer`（unwind 语义）
4. `defer` 仅在 `do`/`let in` 块内有效（不可在纯表达式顶层）
5. `defer` 的 `expr` 效应并入所在 `do`/`let in` 块
6. `defer` 表达式本身不返回值（类型为 `Unit`）

## Record 操作

```kun
{ name = "Kun", version = "0.1" }    // 创建
record.name                           // 字段访问
{ record | version = "0.2" }          // 更新（不可变复制+修改）
{a, ..rest} = config                  // 解构，剩余字段作为 Record 绑定到 rest
{a, .._} = config                    // 解构，丢弃剩余字段

{x as x1, y as y1} = point            // 解构带别名
```

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
  |> Stream.filter (String.contains "ERROR")
  |> Stream.map (String.slice 0 100)
  |> Stream.iter IO.println
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

每个函数体为独立 scope，单表达式规则从头应用：

- **返回 `Unit` 的多语句函数**：函数体用 `do`（可紧跟 `->`），无论单语句还是多语句：
  ```kun
  main : List String -> Unit ! {IO}
  main = \_ -> do
    content = File.read p"/tmp/foo"
    case content of
      Ok text -> IO.print text
      Err _   -> IO.println "failed"
  ```
- **返回非 `Unit` 的多语句函数**：函数体用 `let in`：
  ```kun
  add : Int -> Int -> Int
  add = \x y ->
    x + y                           // 单语句，直接书写

  sumAndFloor : List Int -> Int
  sumAndFloor = \items ->
    let
      total = List.sum items
    in
      toInt (toFloat total / 3.0)    // 多语句返回非 Unit，须用 let in
  ```
- `main` 签名为 `List String -> Unit ! {IO, File, Cmd, ...}`，退出码通过 `Process.exit n` 返回或 panic 退出码规则

顶层函数建议标注类型签名。局部函数可省略：

```kun
main = \_ -> do
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

## 效应声明 `effect`

`effect` 关键字声明代数效应，Record 风格：

```kun
effect <Name> =
  { <op1> : <signature>
  , <op2> : <signature>
  , ...
  }
```

操作签名是函数类型，效应隐含为 `<Name>`。

### 内置效应声明（标准库）

内置效应的签名在标准库中以普通 `effect` 声明，与用户效应形式完全一致：

```kun
// <runtime>/lib/kun/IO.kun
export (IO)

effect IO =
  { println : String -> Unit
  , readln  : String
  , eprintln : String -> Unit
  }

// <runtime>/lib/kun/Cmd.kun
export (Cmd, pipe, cmd, withEnv, withStdin, withStdinFile, mergeStderr, withWorkDir, withRunAs, withoutDash, andThen, orElse, timeout, retry)

effect Cmd =
  { exec     : Command -> Unit
  , execSafe : Command -> Result (Stream String) CommandError
  , stream   : Command -> Stream String
  , which    : String -> ?Path
  }
```

handler 实现在编译器源码（Zig）中，签名与实现彻底分离。

### 用户自定义效应

```kun
// DB.kun
export (DB)

effect DB =
  { query   : Query -> Result Rows DbError
  , execute : Statement -> Result Unit DbError
  }

// Log.kun
export (Log)

effect Log =
  { info  : String -> Unit
  , warn  : String -> Unit
  , error : String -> Unit
  }
```

### 操作调用

```kun
<Effect>.<op> <args>
```

例：

```kun
let
  users = DB.query allUsers          // 调用 DB.query
  Log.info "fetched"                 // 调用 Log.info
  result = Cmd.execSafe c            // 调用 Cmd.execSafe
in
  result
```

## Handler 声明 `handler`

`handler` 关键字声明效应的消解器，case of 风格：

```kun
<handlerName> : Handler {<Effect>} a ! {<handlerEffects>}
<handlerName> =
  handler <Effect> of
    <op1> <args> -> <impl>
    <op2> <args> -> <impl>
    ...
```

**`handler X of`** 形式，显式标注消解的效应。

### 用户效应 Handler

```kun
// DB/PostgresHandler.kun
export (postgreHandler)

import DB (DB)
import Cmd (Cmd, cmd)

postgreHandler : Handler {DB} a ! {Cmd, IO}
postgreHandler =
  handler DB of
    query q ->
      let
        sql = Query.toSql q
        result =
          cmd "psql" {} [ sql ]
            |> Cmd.execSafe
      in
        case result of
          Ok stream ->
            let
              output = Stream.toList stream |> String.join "\n"
            in
              parseRows output
          Err e ->
            Err (IoError e)
    execute s ->
      let
        sql = Statement.toSql s

        cmd "psql" {} [ sql ] |> Cmd.exec
      in
        Ok ()
```

### Mock Handler（测试用）

```kun
// lib/MockHandlers.kun
import DB (DB)
import Log (Log)

mockDbHandler : Handler {DB} a
mockDbHandler =
  handler DB of
    query _ -> Ok [Row {id="1", name="alice"}]
    execute _ -> Ok ()

mockLogHandler : Handler {Log} a
mockLogHandler =
  handler Log of
    info _ -> ()
    warn _ -> ()
    error _ -> ()
```

> Mock handler 用于 `Test.with` 模块函数设置 `TestCase.with` 字段消解用户效应（声明式效应隔离），详见 [单元测试设计 - Handler 组合实现效应隔离](testing.md#handler-组合实现效应隔离)。

### 多效应 Handler

```kun
composedHandler : Handler {DB, Log} a ! {Cmd, IO}
composedHandler =
  handler {DB, Log} of
    DB.query q -> ...
    DB.execute s -> ...
    Log.info msg -> ...
    Log.error msg -> ...
```

操作名需显式限定（`DB.query`）避免歧义。**多效应 handler 操作名限定规则**：

- 单效应 handler：操作名**可不限定**（`query` 即可）
- 多效应 handler：操作名**必须限定**（`DB.query`），避免同名操作歧义

### `continue` 与 `abort` 控制流原语

`continue` 和 `abort` 是**控制流原语**（非函数），不可作为值传递，不可嵌套在 lambda 中。

**`continue` 语义**：

- 立即求值参数，委托外层/默认 handler
- 返回委托结果，控制流回到当前 handler 分支
- 不可作为值传递（不可绑定到变量、不可作为函数参数）
- 每分支恰好一次

**`abort` 语义**：

- 立即终止当前 handler，返回指定值
- 不执行后续代码，不调用 `continue`
- 返回值类型须与 handler 产出类型 `a` 一致
- 与 `continue` 二选一

**编译器检查**：

- 每条 handler 分支路径必须有且仅有一次 `continue` 或 `abort`
- `continue`/`abort` 不可嵌套在 lambda 中（必须在 handler 分支顶层路径）

```kun
// ✅ 合法：continue 在顶层路径
handler DB of
  query q ->
    let
      IO.println "querying"
      result = continue (DB.query q)
    in
      result

// ❌ 非法：continue 在 lambda 中
handler DB of
  query q ->
    let
      f = \x -> continue (DB.query q)   // 编译错误：continue 不可在 lambda 中
    in
      f ()

// ❌ 非法：continue 作为值传递
handler DB of
  query q ->
    let
      cont = continue                   // 编译错误：continue 不可作为值
    in
      ...
```

### continue/abort 示例

```kun
// continue 示例：委托默认
loggingDb : Handler {DB} a ! {IO}
loggingDb =
  handler DB of
    query q ->
      let
        IO.println "querying"
        result = continue (DB.query q)    // 委托外层/默认 DB handler
      in
        result
    execute s ->
      continue (DB.execute s)

// continue 传不同参数：变换查询
rewritingDb : Handler {DB} a ! {DB}
rewritingDb =
  handler DB of
    query q ->
      continue (DB.query (optimizeQuery q))   // 用优化后的查询委托

// abort 示例：dry-run，不执行真实操作
dryRunDb : Handler {DB} a
dryRunDb =
  handler DB of
    query _ -> abort (Ok [])               // 不调用 continue，返回空结果
    execute _ -> abort (Ok ())

// abort 示例：提前终止
shortCircuitDb : Handler {DB} a ! {IO}
shortCircuitDb =
  handler DB of
    query q ->
      let
        cached = Cache.get q
      in
        case cached of
          Some result -> abort result       // 缓存命中，提前返回，不查库
          Nil -> continue (DB.query q)      // 缓存未命中，委托真实查询
```

### Handler 组合

```kun
(>>) : Handler {e1} a ! e11 -> Handler {e2} a ! e21 -> Handler {e1, e2} a ! {e11, e21}
```

```kun
composedHandler : Handler {DB, Log} a ! {Cmd, IO}
composedHandler =
  postgreHandler >> journaldLog
```

## `handle with` 表达式

`handle with` 表达式消解效应集，**仅在 `main` 函数与 `TestCase` 值的 `body` 字段内可用**：

```kun
handle
  <expr>
with
  <handler>
```

### 入口级上下文

| 上下文 | 可用 `handle` | 说明 |
|---|---|---|
| `main` | ✅ | 程序入口 |
| `TestCase.body` | ✅ | `TestCase` 类型值的 `body` 字段，由 `kun test` 运行器在入口级上下文执行（详见 [测试与 `Test` 效应](#测试与-test-效应)、[单元测试设计](testing.md)） |
| 其他业务函数 | ❌ | 只声明效应，不消解 |

**识别机制**：`main` 函数名 + `TestCase` 类型值的 `body` 字段（运行器提供入口级上下文）。编译器对 `main` 与 `TestCase.body` 统一处理，允许其内 `handle`。

### 业务函数的效应流向

业务函数声明效应 → 冒泡到调用者 → 最终到 `main`（或 `TestCase.body`）→ 入口级上下文内 `handle` 消解。

**未消解效应的处理**：

- 内置效应（IO/File/Cmd/FFI 等）：运行时自动注入默认 handler
- 用户效应（DB/Log 等）：编译错误，必须显式 `handle`


例：

```kun
handle
  let
    users = DB.query allUsers
    Log.info "fetched"
  in
    users
with
  postgreHandler >> journaldLog
```

### main 函数示例

```kun
main : List String -> Unit ! {Cmd, IO}
main = \args ->
  handle
    do
      result = fetchUser (UserId "1")
      case result of
        Ok user -> do
          IO.println f"found: {user.name}"
          updateUser user
        Err _ ->
          IO.println "not found"
  with
    postgreHandler >> journaldLog
```

## 测试与 `Test` 效应

测试用例是 `<module>_test.kun` 文件中**导出的 `TestCase` 类型值**（而非 `test*` 前缀函数）。`assert`/`fail`/`skip` 是 `Test` 效应的操作，通过 `abort` 终止测试（不再使用 panic）。

> 完整设计（`TestCase` 类型 Record、`Test` 效应、`Test` 模块（`test`/`Test.with`/`Test.timeout`/`Test.describe`）、`testHandler`、执行模型、并行隔离、生命周期、报告格式、`kun test` 命令选项）详见 [单元测试设计](testing.md)。本节仅描述语法层面要点。

### `TestCase` 类型与 `Test` 效应

```kun
type TestCase =
  TestCase
    { name : String
    , description : ?String
    , timeout : ?Duration
    , body : Unit ! {Test, e}
    , with : ?(Handler {e} Unit ! {r})
    }

effect Test =
  { assert : Bool -> Unit        // assert cond；cond=false → abort (Fail "assertion failed")
  , fail : String -> Unit        // 显式失败 → abort (Fail msg)
  , skip : String -> Unit        // 跳过 → abort (Skip reason)
  }
```

- `Test` 是**标准库效应**（非保留名——与 `DB`/`Log` 等用户效应同构）也是**标准库模块**（`test`/`Test.with`/`Test.timeout`/`Test.describe`，同名消歧）；`testHandler : Handler {Test} TestResult ! {IO}` 是 `kun` 二进制内置 handler（运行器提供，与 IO/File 等内置效应默认 handler 同级）；`TestCase` 是测试用例 Record 类型
- `assert`/`fail`/`skip` 是 `Test` 效应的操作，可在**任何效应集含 `Test` 的函数**中使用（不限 `TestCase.body`）；通过 `abort` 终止当前测试——**没有 panic 黑魔法**，与普通 handler 的 `abort` 语义完全一致
- `Test.with` 模块函数：设置 `TestCase.with` 字段，指定消解 `body` 用户效应 `e` 的 handler；多个用户效应通过 `>>` 组合为单一 handler；`Test.with = Nil`（省略）表示 `e` 必须为空或仅含内置效应（由运行时沙箱消解）

### `Test` 模块——`test` 构造器与链式函数

`Test` 模块提供便捷构造器与链式字段设置函数（均为纯函数，返回新 `TestCase`）：

```kun
import Test (Test, TestCase, test, assert, fail, skip)
// Test.with / Test.timeout / Test.describe 全名使用

test : String -> (Unit ! {Test, e}) -> TestCase
Test.with     : Handler {e} Unit ! {r} -> TestCase -> TestCase
Test.timeout  : Duration -> TestCase -> TestCase
Test.describe : String -> TestCase -> TestCase
```

`test` 构造 `TestCase` 默认填 `Nil`；链式函数 `|>` 管道设置字段：

```kun
// 等价：test "foo" (...) |> Test.timeout 5s  ≡  TestCase { name = "foo", ..., timeout = Some 5s, ... }
```

### `TestResult` 类型

```kun
type TestResult =
  Pass
  | Fail String      // 失败原因
  | Skip String      // 跳过原因
```

`TestResult` 仅由 `testHandler` 产出（不再由测试函数显式返回）；`Pass` 对应 `body` 正常返回，`Fail`/`Skip` 对应 `Test` 效应的 `abort`。

### 测试用例示例

```kun
// lib/UserService_test.kun
import UserService (fetchUser)
import User (UserId)
import Test (Test, TestCase, test, assert, fail)
import DB.Mock (mockDbHandler)
import Log.Mock (mockLogHandler)

export (testFetchUser)   // ← 仅导出的 TestCase 值才会被运行

testFetchUser : TestCase =
  test "fetchUser returns user"
    (\ -> do
      result = fetchUser (UserId "1")
      case result of
        Ok user -> assert (user.name == "alice")
        Err _ -> fail "expected Ok, got Err"
    )
  |> Test.describe "Uses mock DB and Log handlers"
  |> Test.with (mockDbHandler >> mockLogHandler)
  //  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  //  DB/Log 被消解为确定性 mock 行为，剩余 IO 由沙箱消解
  |> Test.timeout 10s
```

**`kun test` 运行器**：

- 扫描 `lib/` 下所有 `*_test.kun` 文件（递归），收集 `export` 列表中的 `TestCase` 类型值
- 对每个 `TestCase` 值：包装 `body!` → 用 `TestCase.with` 消解用户效应 → 用 `testHandler` 消解 `Test` 效应 → 产出 `TestResult`
- 支持 `--filter`（glob 匹配 `TestCase.name`）/`--timeout`/`--parallel`/`--fail-fast`/`--report text|json` 选项
- 无 `beforeAll`/`afterAll`/`beforeEach`/`afterEach` 隐式全局钩子；Setup/teardown 通过 `defer`（在 `Test` 效应 `abort` 路径下也会执行）+ handler 组合显式表达

### 入口级 `handle with` 与 `TestCase.body`

`handle with` 表达式**仅在 `main` 函数与 `TestCase` 值的 `body` 字段内可用**（详见 [`handle with` 表达式](#handle-with-表达式)）。`kun test` 运行器在入口级上下文执行 `TestCase.body`（包装 → `TestCase.with` 消解用户效应 → `testHandler` 消解 `Test` 效应），因此 `body` 内可使用 `handle with`；用户效应通常通过 `Test.with` 模块函数声明式消解。

> **旧 `test*` 前缀函数已废弃**（2026.07.16）：测试用例不再以 `test` 前缀命名 + 签名过滤识别；旧的 `assert : Bool -> Unit`（panic 失败）替换为 `Test` 效应的 `assert` 操作（abort 失败）。详见 [与现有设计的关系](testing.md#与现有设计的关系)。

## `extern` 块（FFI）

`extern` 关键字声明外部 C 库绑定，自动产生独立效应，自动生成默认 handler 委托 `FFI.call`：

```kun
extern <EffectName> from "<lib>" =
  { <func1> : <signature>
  , <func2> : <signature>
  , ...
  }
```

与 `effect`/`type` 形式一致：`<keyword> <Name> [修饰] = { <fields> }`。`from "lib"` 是必要修饰（库绑定）。

### 库加载规则（仅 Linux）

- `<lib>` 为基础名，运行时按 Linux 规则查找：`lib<lib>.so` → `lib<lib>.so.X` → `<lib>.so`
- 搜索路径：`LD_LIBRARY_PATH` → `/lib` → `/usr/lib` → `/usr/local/lib`
- 加载方式：`dlopen(lib, RTLD_LAZY)`，首次调用时加载，结果缓存
- 非 Linux 平台：`extern` 声明编译错误（FFI 不跨平台）

### 示例

```kun
// Libc.kun
export (Libc)

extern Libc from "libc" =
  { strlen : String -> Int
  , fopen : String -> String -> ?(Opaque File)
  , fclose : Opaque File -> Int
  , fread : FfiBuffer -> Int -> Int -> Opaque File -> Int
  }

// Curl.kun
export (Curl)

extern Curl from "libcurl" =
  { easy_init : ?(Opaque Curl)
  , easy_setopt : Opaque Curl -> Int -> String -> Int
  , easy_perform : Opaque Curl -> Int
  , easy_cleanup : Opaque Curl -> Unit
  }
```

### 语法细节规则

1. 库名必须字符串字面量，不可用变量：
   ```kun
   extern Libc from libVar = { ... }        // ❌ 编译错误
   extern Libc from "libc" = { ... }        // ✅ 合法
   ```

2. `extern` 块不可嵌套：
   ```kun
   extern Outer from "liba" =
     { extern Inner from "libb" = { ... } }  // ❌ 编译错误
   ```

3. 签名不可含效应标注（效应隐含为库名）：
   ```kun
   extern Libc from "libc" =
     { strlen : String -> Int ! {Libc} }     // ❌ 编译错误
     { strlen : String -> Int }              // ✅ 合法
   ```

4. `extern` 块内至少一个函数：
   ```kun
   extern Empty from "libc" = {}             // ❌ 编译错误
   ```

5. 同一效应名不可重复声明（与 `effect` 共享命名空间）：
   ```kun
   effect Libc = { customOp : String -> String }
   extern Libc from "libc" = { strlen : String -> Int }
   // ❌ 编译错误：Libc 重复声明
   ```

### 调用形式

```kun
<EffectName>.<func> <args>
```

调用产生 `! {<EffectName>}`，**无需 `unsafe`**（效应名已标注 FFI 来源，签名保证类型安全）：

```kun
let
  len = Libc.strlen "hello"           // ! {Libc}，无 unsafe
  fp = Libc.fopen "/etc" "r"          // ! {Libc}
  n = Libc.fread buf 1 1024 fp        // ! {Libc}
  Libc.fclose fp                      // ! {Libc}
in
  n
```

### `FfiBuffer` 不逃逸（编译器内置规则）

`FfiBuffer` 是编译器内置的特殊类型，其不逃逸规则由**编译器硬编码**强制，不采用属性标注形式：

```kun
// ✅ 合法：拷贝后逃逸
let
  buf = Ffi.alloc 1024
  content = Ffi.toBytes buf 1024    // content : Bytes（普通类型）
in
  content                           // 合法：content 非 FfiBuffer

// ❌ 编译错误：FfiBuffer 不可逃逸
let
  buf = Ffi.alloc 1024
in
  buf                               // 错误：FfiBuffer 不可作为返回值
```

详见 [类型系统 - FFI 系统](type-system.md#ffi-系统)。

### `Opaque` 类型

不透明指针，幻影类型，Kun 不可解引用，仅传递给其他 FFI 函数：

```kun
type Opaque a    // a 是指向的类型，Opaque 表示完全未知
```

`Opaque File` 与 `Opaque Curl` 是**不同类型**，编译期区分，运行时均为 `void*`。需手动释放的 `Opaque`，用 `defer` 配合释放函数保证释放：

```kun
let
  fp = Libc.fopen "/etc/hosts" "r"     // fp : ?(Opaque File)
in
  case fp of
    Nil -> Err "open failed"
    Some handle ->
      let
        defer (Libc.fclose handle)  // 保证关闭

        buf = Ffi.alloc 4096
        n = Libc.fread buf 1 4096 handle
        content = Ffi.toString buf n
      in
        Ok content
// defer 在 let in 块退出时执行 fclose
```

## `cmd` 字面量

`cmd` 关键字构造 Command ADT 值（纯操作，不立即执行），四段式固定结构：

```
cmd <命令> <子命令>* <选项>? <位置参数>?
```

- 命令：字符串或标识符（必填）
- 子命令：字符串或标识符（零或多个）
- 选项：Record `{ ... }`（可省略，缺省 `{}`）
- 位置参数：List `[ ... ]`（可省略，缺省 `[]`）

```kun
cmd docker run { d = true, name = "my-web" } [ "nginx" ]
```

### 选项映射规则

#### 键形式

| 键形式 | 示例 | 映射规则 |
|---|---|---|
| 标识符单字符 | `a`, `l`, `p` | 补 `-` 前缀 |
| 标识符多字符 | `maxCount`, `verbose` | 补 `--` 前缀 + camelCase→kebab-case |
| 字符串键 | `"-Xmx"`, `"/user"`, `"-2"` | 原样使用，不补前缀 |
| 简写（任何键） | `a`, `"-2"`, `"--readOnly"` | ≡ `= true` |

#### 值类型

| 值类型 | 生成 argv |
|---|---|
| `Bool = true` | 旗标（无值） |
| `Bool = false` / `Nil` | 省略 |
| 单值（String/Int/Float/Path/Char） | flag + 值 |
| `List` | 重复 flag + 各值 |

#### 完整映射表

| 键 | 值 | 生成 argv |
|---|---|---|
| `a`（标识符单字符） | `true` | `-a` |
| `a` | `false`/`Nil` | （省略） |
| `a` | `"value"` | `-a value` |
| `a` | `[ "v1","v2" ]` | `-a v1 -a v2` |
| `a`（简写） | — | `-a` |
| `maxCount` | `true` | `--max-count` |
| `maxCount` | `50` | `--max-count 50` |
| `maxCount` | `[ "50","100" ]` | `--max-count 50 --max-count 100` |
| `verbose`（全小写） | `true` | `--verbose` |
| `"-Xmx"` | `"1024m"` | `-Xmx 1024m` |
| `"/user"` | `"admin"` | `/user admin` |
| `"-2"`（简写） | — | `-2` |
| `"-read-only"` | `true` | `-read-only` |

### argv 生成顺序

```
argv = [命令名] + [子命令...] + [选项 flags（按 Record 声明顺序）] + [ "--" if 有位置参数且 useDash] + [位置参数]
```

### `--` 分隔符

**默认**：有位置参数时自动插入 `--`。

**关闭**：`Cmd.withoutDash` 纯函数：

```kun
// 设置 useDash = false
Cmd.withoutDash : Command -> Command

// argv = [ "echo", "hello", "world" ]   // 无 --
cmd echo {} [ "hello", "world" ] |> Cmd.withoutDash
```

### `cmd` 字面量示例

```kun
// 基本命令
cmd date {} []
cmd ls { a, l } [ p"/tmp" ]

// 子命令
cmd docker run { d = true, name = "my-web" } [ "nginx" ]
cmd git log { "-2", pretty = "format:%h" } [ "master" ]

// 字符串命令名
cmd "@vue/cli" create {} [ "my-app" ]
cmd "./build.sh" { verbose = true } [ "prod-env" ]
cmd "g++" { o = "a.out", "-Wall" = true, "-O2" = true } [ "main.cpp" ]

// 字符串子命令
cmd git "log" { ... } [ "master" ]

// 非标准 flag
cmd java { "-Xmx" = "1024m", "-jar" = p"app.jar" } []
cmd net { "/user" = "administrator", "/active" = "yes" } []

// 多值选项
cmd docker run
  { p = [ "80:80", "443:443" ]
  , v = [ "/host:/container" ]
  }
  [ "nginx" ]

// 简写
cmd ls { a, l, h } [ p"/tmp" ]

// 关闭 --
cmd echo {} [ "hello", "world" ] |> Cmd.withoutDash
```

### Command 执行

`cmd` 字面量构造 `Command` ADT 值，**纯操作不立即执行**。执行必须显式调用执行函数：

```kun
// Cmd 效应操作
Cmd.exec     : Command -> Unit ! {Cmd}                                // 执行，丢弃 stdout，失败 panic
Cmd.execSafe : Command -> Result (Stream String) CommandError ! {Cmd} // 执行，返回 Result
Cmd.stream   : Command -> Stream String ! {Cmd}                       // 执行，返回 Stream，失败 panic
Cmd.which    : String -> ?Path ! {Cmd}                                // PATH 查找
```

详见 [OS 命令调用机制](command-system.md)。

### 管道：`pipe` 纯函数

仅保留纯函数 `pipe`，构造 `Pipe` ADT 变体：

```kun
pipe : List Command -> Command
```

**嵌套深度限制**：`pipe` 命令列表最多 16 个命令，超过 → 编译错误。理由：OS pipe 缓冲区与 fd 数量限制，16 层足够覆盖真实场景。若需更深，拆分为多个 `pipe` + 中间文件。

**空列表处理**：`pipe` 的参数列表若为字面量空列表 `[]`，编译错误；若为变量（编译期未知是否空），运行时检查，空列表 panic。

```kun
// ❌ 编译错误
pipe []

// ❌ 编译错误
pipe [c1, c2, ..., c17]   // 超过 16 层

// ✅ 合法
pipe [c1, ..., c16]
```

`pipe` 构造 `Pipe` ADT 变体，是纯函数。执行需显式调用 `Cmd.exec`/`Cmd.execSafe`/`Cmd.stream`：

```kun
// 管道执行（错误处理）
// result : Result (Stream String) CommandError ! {Cmd}
result =
  pipe
    [ cmd ps { a } []
    , cmd grep { pattern = "nginx" } []
    ]
    |> Cmd.execSafe

// 管道执行（输出流处理）
pipe
  [ cmd ps { a } []
  , cmd grep { pattern = "nginx" } []
  ]
  |> Cmd.stream
  |> Stream.lines
  |> Stream.toList
```

### 修饰函数

纯函数，返回新 Command：

```kun
Cmd.withEnv       : Map String String -> Command -> Command
Cmd.withStdin     : String -> Command -> Command
Cmd.withStdin     : Stream Bytes -> Command -> Command
Cmd.withStdinFile : Path -> Command -> Command
Cmd.withWorkDir   : Path -> Command -> Command
Cmd.withRunAs     : String -> Command -> Command
Cmd.mergeStderr   : Command -> Command
Cmd.withoutDash   : Command -> Command
Cmd.andThen       : Command -> Command -> Command
Cmd.orElse        : Command -> Command -> Command
Cmd.timeout       : Duration -> Command -> Command
Cmd.retry         : Int -> Duration -> Command -> Command
```

### 典型用法

```kun
// 仅副作用
cmd mkdir { p = true } [ "/tmp/build" ]
  |> Cmd.exec

// 错误处理
do
  result =
    cmd cat {} [ p"/etc/maybe_missing" ]
      |> Cmd.execSafe

  case result of
    Ok stream ->
      Stream.iter IO.println stream
    Err e ->
      IO.println "not found"

// 输出流处理
let
  lines =
    cmd ls { a } [ "/tmp" ]
      |> Cmd.stream
      |> Stream.lines
      |> Stream.filter (String.contains "log")
      |> Stream.toList
in
  lines

// 修饰 + 执行
do
  c = cmd tar { c = true, f = "backup.tar" } [ "." ]
    |> Cmd.withWorkDir p"/build"
    |> Cmd.withEnv #{ "TZ" = "UTC" }
    |> Cmd.withoutDash

  Cmd.exec c                         // 显式执行
```

## 运算符与优先级

### 运算符列表

| 类别 | 运算符 | 结合性 | 说明 |
|------|--------|--------|------|
| 表达式分组 | `(expr)` | — | |
| 成员访问 | `.` | 左结合 | |
| 函数应用 | (空格) | 左结合 | |
| 一元 | `-`, `not` | 右结合 | |
| 移位 | `shl`/`shr`/`ushr` | 左结合 | `Int` 位运算 |
| 按位与 | `&` | 左结合 | `Int` 位运算 |
| 按位异或 | `^` | 左结合 | `Int` 位运算 |
| 按位或 | `\|` | 左结合 | `Int` 位运算 |
| 乘除 | `*`, `/`, `%` | 左结合 | |
| 加减 | `+`, `-` | 左结合 | |
| 拼接 | `++` | 左结合，适用于 `String`（`"a" ++ "b"`）、`Bytes`（`0x01 ++ 0x02`）、`Path`（`p"/etc" ++ p"config"`） |
| 比较 | `==`, `/=`, `<`, `>`, `<=`, `>=` | 无结合 | `==` 浅比较 |
| 逻辑与 | `&&` | 左结合（短路） |
| 逻辑或 | `\|\|` | 左结合（短路） |
| 函数组合 | `>>`, `<<` | 左结合 |
| 正向管道 | `\|>` | 左结合 | 纯管道，不隐式触发执行 |
| 反向管道 | `<\|` | 右结合 | |
| 三元 | `? :` | 右结合 | |
| 绑定 | `=` | 右结合 | |
| 效应集引导 | `!` | — | 函数类型中引导效应集 `! {E}` |

`Nil` 和 `Some` 为编译器内置 ADT `Nilable a` 的两个变体，始终缺省可用。`Nil` 是无 payload 变体（类似 `true`/`false` 的语法角色），`Some` 是带 payload 变体。二者在 `case` 模式匹配中使用。`Nil` 在表达式和模式中统一通过 ADT 变体查找路径处理，非特殊字面量关键字。详见 [类型系统](type-system.md#nilable-类型-nilable-a--t)。

### 优先级（从高到低）

```
最高:
  .
  (expr)
  函数应用
  -        not
  shl      shr       ushr
  &
  ^
  |
  *        /        %
  +        -        ++
  ==       /=       <      >      <=      >=
  &&
  ||
  >>       <<
  ? :
  if/case/let-in/do
  |>       <|
最低:  =     !
```

- **函数应用** `f a b` 优先级高于所有运算符：`f a b + c` → `(f a b) + c`；`f a |> g` → `(f a) |> g`
- **`if`/`case`/`let-in`/`do`** 优先级高于管道操作符：`if a then b else c |> f` → `(if a then b else c) |> f`；`case x of A -> y |> z` → `(case x of A -> y) |> z`
- **位运算** 优先级：`shl`/`shr`/`ushr` > `&` > `^` > `|`，均为左结合

### 位运算示例

```kun
// 优先级示例
a & b | c       // 等价 (a & b) | c
a ^ b & c       // 等价 a ^ (b & c)
a shl 2 | b     // 等价 (a shl 2) | b

// 文件权限
mode = 0o644
mode1 = mode | 0o100    // 添加 owner execute
mode2 = mode1 & 0o777  // 掩码

// 信号位掩码
sigMask = (1 shl 2) | (1 shl 15)   // SIGINT | SIGTERM
```

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

### 模块系统规则

1. **默认可见性**：无 `export` 的绑定私有，仅 `export` 列出的符号公开

2. **Re-export**：`export` 列出的符号无需本模块定义，可来自 `import`：
   ```kun
   export (DB, postgreHandler)   // re-export postgreHandler

   import DB.PostgresHandler (postgreHandler)
   ```

3. **不支持 wildcard 导入**（避免冲突与隐式）：
   ```kun
   import DB.*                   // ❌ 编译错误
   import DB (DB, query, execute) // ✅ 显式导入
   ```

4. **导入冲突需别名解决**：
   ```kun
   import DB (query)
   import Cache (query)          // ❌ 编译错误：query 重名
   // 解决：别名
   import DB (query as dbQuery)
   import Cache (query as cacheQuery)
   ```

5. **模块选择性导入与全名引用**：
   ```kun
   import DB (query, execute)    // 选择性导入，支持直接用 query 或全名引用 DB.query
   ```

6. **模块别名 + 选择性导入**：
   ```kun
   import DB as D (query, execute)    // 支持直接用 query 或别名引用 D.query
   ```

### 效应与模块同名

效应名与模块名可共享同一标识符（如 `Cmd` 既是效应又是模块），二者分属**类型命名空间**与**值命名空间**，语法位置天然不重叠，同名合法。编译器按使用上下文自动消歧，无需额外语法。

**命名空间分离**：

| 标识符 `Cmd` 的角色 | 出现位置 | 命名空间 |
|---|---|---|
| 效应名（类型层） | 函数效应集 `! {Cmd}`、`Handler {Cmd} a`、`handle ... with h`、`effect Cmd = {...}` | 类型命名空间 |
| 模块名（值层） | `import Cmd (...)`、`Cmd.exec`、`Cmd.withEnv`、`Cmd/` 目录 | 值命名空间 |

效应名只出现在类型标注的效应集位置（类型上下文），模块名只出现在表达式/导入位置（值上下文），二者不冲突。

**`Cmd.<name>` 的解析**：同一限定前缀下，效应操作与模块函数按签名归属区分：

| 调用 | 归属 | 判定 |
|---|---|---|
| `Cmd.exec`/`Cmd.execSafe`/`Cmd.stream`/`Cmd.which` | **效应操作** | 签名在 `effect Cmd = {...}` 中声明，调用产生 `! {Cmd}` |
| `Cmd.withEnv`/`Cmd.withoutDash`/`Cmd.andThen` 等 | **模块纯函数** | 模块顶层绑定，无效应集（`! {}`），不属任何 `effect` 记录 |

编译器维护**效应操作表**（来自 `effect` 声明）与**模块符号表**（来自模块绑定）两张表。`Cmd.exec` 查效应表命中，`Cmd.withEnv` 查模块表命中。效应集检查进一步区分：效应操作在纯函数体内调用 → 编译错误；模块纯函数调用 → 合法。

**消歧规则**（避免歧义）：

1. **效应操作必须全名调用**：效应操作不支持选择性导入裸名，必须以 `EffectName.op` 形式调用。`import Cmd (exec)` ❌ 编译错误（效应操作不可裸名导入）；`Cmd.exec c` ✅。
2. **模块纯函数可选择性导入裸名**：`import Cmd (withEnv)` ✅，可直接用 `withEnv env c`。
3. **效应操作不可被模块函数遮蔽**：`effect Cmd` 声明后，同模块内不可再定义同名 `exec`/`execSafe`/`stream`/`which` 绑定（编译错误，避免 `Cmd.exec` 歧义）。
4. **解析优先级**：`EffectName.<op>` 先查效应操作表，再查模块符号表。若模块函数与效应操作重名，效应操作优先（但规则 3 已禁止此情况，故实际不会发生）。
5. **`continue`/`abort` 内的限定**：handler 内 `continue (Cmd.exec c)` 委托的永远是效应操作（查效应表），模块函数不参与 handler 委托。

**视觉区分**：带 `EffectName.` 前缀且名为该效应声明的操作（如 `Cmd.exec`/`Cmd.execSafe`/`Cmd.stream`/`Cmd.which`）的是效应操作；其余 `EffectName.<xxx>` 或选择性导入裸名的是模块函数。

```kun
// Cmd 既是效应又是模块，同名合法
import Cmd (Cmd, pipe, cmd, withEnv, withoutDash)   // 模块函数可选择性导入

fetchUser : UserId -> Result User ! {Cmd, IO}        // Cmd 作为效应名（类型层）

main : List String -> Unit ! {Cmd, IO} =
  \args -> do
    c = cmd docker run { d = true } [ "nginx" ]
      |> withEnv (Map.fromList [ ("TZ", "UTC") ])   // withEnv 模块函数（裸名）
      |> withoutDash                                // withoutDash 模块函数（裸名）
    result = Cmd.execSafe c                         // Cmd.execSafe 效应操作（全名，产生 ! {Cmd}）
    case result of
      Ok stream -> Stream.iter IO.println stream
      Err e     -> IO.println "failed"
```

> **保留名**：7 个内置效应名（`IO`/`File`/`Cmd`/`Random`/`DateTime`/`Signal`/`FFI`）为编译器保留名，用户不可定义同名 `effect`。内置效应名与对应标准库模块同名（如 `IO` 效应与 `IO` 模块），遵循上述同名规则。用户自定义效应（如 `DB`/`Log`）若与用户模块同名，同样适用。

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

### `effect` / `extern` 导出规则

- 仅支持以 `export (EffectName)` 形式导出效应名，不支持单独导出效应操作
- `extern` 产生的效应通过 `export (Libc)` 导出，与 `effect` 相同

```kun
// ✅ 合法：只导出效应名（通过 DB.query、DB.execute 调用其操作）
export (DB)

// ❌ 不支持单独导出效应操作
// export (DB, query)  // query 不单独导出
```

### 导入

导入有三种互斥风格：

```kun
// 风格一：模块别名 — 通过别名限定访问
import List                            // 直接通过 List.map 访问
import List as L                       // 通过 L.map 访问（短别名）
import DB as D (query, execute)        // 模块别名 + 选择性导入

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

Stream 是**惰性拉取序列**（lazy pull-based sequence），不绑定 IO。元素在消费时按需求值，适用于大文件处理、无限序列、数据流管道。Stream 是显式惰性特区之一（另一个是 `Lazy` 模块）。

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
Stream.toList  : Stream a -> List a                       // 终端
Stream.iter    : (a -> Unit ! e) -> Stream a -> Unit ! e  // 终端
Stream.fold    : (b -> a -> b) -> b -> Stream a -> b      // 终端
Stream.string  : Stream String -> String                  // 终端：全文收集
Stream.bytes   : Stream a -> Bytes                        // 终端：二进制读取
```

Stream 必须由终端操作消费——未被消费的 Stream 导致子进程变为僵尸和 fd 泄漏。**Stream 消费检查的作用域为单个 `do`/`let in` 块**：块内构造的 Stream 必须在本块内消费；跨块传递（作为函数参数/返回值/绑定到外层）视为已消费。详见 [类型系统 - Stream 消费检查](type-system.md#stream-消费检查)。

## 与语法分析器的交互

语法设计需与类型检查器协调：

1. **类型标注与值定义可同行或分离**：解析器支持两种形式——同行 `name : Type = expr`（识别 `:` 后为类型，`=` 后为表达式，同行解析）与分两行 `name : Type` + `name = expr`。两种形式语义等价，按可读性选择
2. **泛型空格分隔**：`List Int` 中 `List` 和 `Int` 以空格分隔，解析器通过上下文（类型位置 vs 表达式位置）和首字母大小写区分类型标识符与变量
3. **前缀字面量**：`p"..."`、`r"..."`、`f"..."` 三种前缀 + 双引号的字面量，解析器根据前缀字母区分，内容按原始字符串处理
4. **`cmd` 字面量**：四段式固定结构，解析器按 `cmd` 关键字引导，依次解析命令/子命令/选项 Record/位置参数 List
5. **`effect`/`extern`/`type`/`handler` Record 风格**：`<keyword> <Name> [修饰] = { <fields> }`，解析器统一处理
6. **`?` 在类型中的角色**：`?T` 为 `Nilable T` 的语法糖；`??T` 嵌套为编译错误；`? :` 为三元
7. **`!` 在函数类型与表达式中的角色**：`! {E}` 引导效应集；`! e` 效应多态变量；无 `!` ≡ `! {}`；`T ! {E}`（无 `->`）为零参效应函数类型；`Name!` 后缀执行零参函数（与已废弃的 Command 断言执行 `!` 是不同特性）

### 解析歧义消解规则

以下场景存在 token 级别的解析歧义，解析器按以下规则确定性处理：

#### 类型构造器 vs 函数调用

| 上下文 | `List Int` 的语义 | 解析规则 |
|--------|-----------------|---------|
| 类型标注行（`x : ...`） | 类型构造器应用 `List<Int>` | 大写标识符后跟空格 → 类型构造器 |
| 表达式行（`x = ...`） | 编译期错误——类型名不可作为值 | 大写标识符在表达式位置报错 |
| `import` 中的 `as` 别名 | 模块别名（`import List as L`） | `as` 后标识符保留为模块别名 |

解析器通过上下文（`:` 后为类型位置，`=` 后为表达式位置）和首字母大小写区分类型构造器与函数调用。

#### 点号 `.` 的语义消歧

| 模式 | 语义 | 解析规则 |
|------|------|---------|
| `X.y`（X 大写，在导入表） | 模块限定函数调用 | 导入表查找 `X` → 模块名 |
| `x.y`（x 小写） | Record 字段访问 | 产生 `recordAccess` AST 节点 |
| `tuple.0`（数字后缀） | Tuple 索引 | `.` 后为数字字面量 |
| `.name`（高阶参数位置） | 字段访问速记 | 仅在 `map .name`、`filter .size` 等位置有效；其他位置为语法错误 |

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
2. `.` 右侧为数字起始 → 元组索引（`tuple.0`）
3. `.` 为 Lambda 参数的显式字段访问速记（`.name`）→ 在函数参数位置
4. 其余情况 → Record 字段访问（`record.field`）

#### `cmd` 字面量解析

`cmd` 关键字后依次解析：

1. **命令**：字符串字面量或标识符（必填）
2. **子命令**：零或多个字符串字面量或标识符（直到遇到 `{` 或 `[`）
3. **选项**：Record `{ ... }` 或缺省 `{}`（直到遇到 `[` 或下一语句）
4. **位置参数**：List `[ ... ]` 或缺省 `[]`

`cmd` 字面量构造 `Command` ADT 值，是纯表达式。

