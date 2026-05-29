# 语法设计

## 设计原则

1. **表达式导向**：所有语句均为表达式，具有返回值
2. **简洁一致**：借鉴 Elm（为主）、Haskell 和 Rust，避免冗余关键字
3. **声明与实现分离**：类型标注与值定义为独立行，便于读取
4. **显式边界**：副作用（IO）、错误处理（Result）、权限（capability）均有显式语法标记
5. **最小惊喜**：优先采用 Shell 用户熟悉的符号约定

## 注释

```
-- 行注释：双横线开头，直到行尾
```

仅支持行注释。无块注释。

## 字面量

| 类型 | 语法 | 示例 |
|------|------|------|
| Int | 十进制、`0x`/`0o`/`0b` 前缀 | `42`, `-3`, `0xFF`, `0o77`, `0b1010` |
| Nat | Int 字面量加后缀 `u` | `42u`, `0u` |
| Float | 十进制浮点或科学计数法 | `3.14`, `-2.5e10` |
| Bool | 关键字 | `true`, `false` |
| String | 双引号包裹，支持转义序列 | `"hello"`, `"line1\nline2"` |
| String (插值) | `f` 前缀 + 双引号，`{expr}` 嵌入表达式，可选 `:` 格式说明 | `` f`count: {n}` ``, `` f`pi: {3.14:.2f}` `` |
| Bytes | `0x` 前缀后接十六进制字节序列 | `0x48656C6C6F` |
| Char | 单引号包裹 | `'A'`, `'\n'`, `'好'` |
| Regex | `` regex`...` `` 前缀 + 反引号 | `` regex`[0-9]+` `` |
| Duration | 整数 + 单位后缀 | `5s`, `100ms`, `2h`, `30m`, `1d`, `500us`, `200ns` |
| Unit | 空圆括号 | `()` |
| Path | `path"..."` 前缀 + 双引号 | `path"/tmp/foo"`, `path"./foo"` |

各类型选用最符合其内容的引用风格：
- **双引号**：String、Path、f-string — 需要转义序列和插值支持
- **反引号**：Regex — 避免反斜杠转义地狱

容器字面量：

```
[1, 2, 3]              -- List
#{ "a" => 1 }          -- Map
#[1, 2, 3]             -- Set
(1, "hello", true)     -- Tuple
{ name = "Kun" }       -- Record
```

## 字符串插值与格式化

### 语法

以 `f` 为前缀的字符串字面量支持嵌入表达式和格式化说明：

```
f"count: {n}"                     -- 变量插值，自动 toString(n)
f"result: {a + b}"                -- 任意表达式
f"pi = {3.14159:.2f}"             -- 带格式说明
f"{name:>10}"                     -- 字符串对齐
f"hex: {255:x} / {255:X}"         -- 整数进制
```

嵌入表达式使用大括号 `{expr}` 包裹，可在其中任意位置出现。`f` 前缀与双引号之间无空格。

### 自动 toString

未指定格式说明时，`{expr}` 等价于 `toString(expr)`：

```
n = 42
f"answer is {n}"          -- → "answer is 42"
f"answer is " ++ toString(n)  -- 等价
```

对 `String` 类型，`toString` 直接返回自身。对 `Path`、`IpAddress` 等标准库类型，`toString` 返回其可读表示。

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
f"{42:#>6}"     → "####42"          -- `#` 填充，右对齐
f"{42:0>6}"     → "000042"          -- `0` 填充，右对齐
```

#### DateTime

`DateTime` 类型支持 `%` 格式符，委托到 `strftime`：

```
f"{now:%Y-%m-%d %H:%M:%S}"    -- → "2026-05-29 14:30:00"
f"{now:%F}"                    -- → "2026-05-29"
```

### 转义

| 需要输出 | 写法 | 说明 |
|---------|------|------|
| 字面量 `{` | `\{` | 大括号转义 |
| 字面量 `}` | `\}` | 大括号转义 |
| 字面量 `\` | `\\` | 反斜杠转义 |
| 字面量 `f` | `f` | 仅在 `f"` 前缀中和字符串前导位置无歧义 |

示例：

```
f"brace: \{hello\}"    → "brace: {hello}"
f"backslash: \\"       → "backslash: \"
```

### 嵌套

f-string 中嵌入的表达式本身可包含字符串字面量，但不支持嵌套 f-string（不可写 `f"outer {f"inner"}"`）：

```
f"list: {join(", ", names)}"       -- 函数调用，参数为普通字符串
f"path: {path"/etc/hosts"}"        -- 嵌入 Path 字面量
```

### 与普通字符串的关系

- `"..."` — 普通字符串，不支持插值，`{` 无特殊含义
- `f"..."` — 插值字符串，`{expr}` 被求值并格式化，`\{` 转义输出字面量 `{`
- 运行时类型：两者均为 `String`，插值在编译期展开为 `toString`/格式化调用链

设计依据：

1. **`f` 前缀与现有约定一致**——`path"..."`、``regex`...` `` 均已采用前缀标记不同字面量类型，`f"..."` 延续此模式，不引入新引用符号
2. **普通字符串不受影响**——无需在非插值字符串中转义 `{`，仅 `f"..."` 内大括号有特殊含义
3. **Python 对齐**——格式说明语法与 Python 3 的格式规范微型语言（Format Specification Mini-Language）保持一致，降低学习成本
4. **编译期展开无运行时开销**——插值在编译期展开为 `++` 和 `toString`/格式化函数调用，与手写等价

## 标识符与命名

| 类别 | 规则 | 示例 |
|------|------|------|
| 变量/函数 | 小写字母或下划线开头 | `map`, `identity`, `_temp` |
| 类型/变体 | 大写字母开头 | `Int`, `Maybe`, `Just`, `Ok` |
| 类型变量 | 小写字母，单字优先 | `a`, `b`, `key`, `value` |
| 模块 | 大写字母开头 | `List`, `Path`, `System` |

## 类型声明

### ADT（和类型）

```
type Color
  = Red
  | Green
  | Blue

type Maybe<T>
  = Just T
  | None

type Result<T, E>
  = Ok T
  | Err E

type SocketAddr
  = Tcp IpAddress Port
  | Udp IpAddress Port
```

变体字段支持三种形式：

```
type IpAddress
  = Ipv4 (Nat, Nat, Nat, Nat)     -- 无名字段（元组风格）
  | Ipv6 (Nat, Nat, Nat, Nat, Nat, Nat, Nat, Nat)

type Error
  = NotFound Path                   -- 无名字段（空格分隔）
  | PermissionDenied Path

type Color
  = Rgb { r : Int, g : Int, b : Int }   -- 具名字段（Record 风格）
```

### Newtype

单变体 ADT 为 newtype：

```
type UserName = UserName String
type Uid = Uid Nat
```

### 类型别名

```
type alias IOError = ...   -- 待定
```

（当前设计直接使用 ADT 而非别名，后续按需引入。）

### 类型标注

类型标注为独立声明行，与值定义分离：

```
add : (Int, Int) -> Int
add = \(x, y) -> x + y

identity : a -> a
identity = \x -> x

main : IO<Unit>
main = do
  content <- readFile(path"/tmp/foo")
  print(content)
```

函数类型语法：

```
T1 -> T2 -> T3           -- 柯里化函数
(T1, T2) -> T3           -- 元组参数
(T1, T2) -> T3 -> T4     -- 元组参数 + 柯里化返回
() -> T                  -- 无参数
IO<T>                    -- IO 包装
```

单参数免除圆括号：`Int -> Int` 而非 `(Int) -> Int`。`(Int) -> Int` 视为合法但不推荐。

泛型参数使用尖括号：

```
List<Int>
Maybe<String>
IO<Result<FileType, IOError>>
```

Record 类型：

```
{ name : String, version : String }
```

## 表达式

### 变量引用与字面量

```
42                           -- Int 字面量
"hello"                      -- String 字面量
[1, 2, 3]                    -- List 字面量
myVariable                   -- 变量引用
```

### Lambda

```
\x -> x + 1                  -- 单参数
\x, y -> x + y               -- 多参数（语法糖，脱糖为 \x -> \y -> x + y）
\(x, y) -> x + y             -- 元组解构（单参数，匹配 (T1, T2) -> T 类型）
```

### 函数应用

函数应用通过空格分隔：

```
identity 42
map (\x -> x * 2) list
readFile(path"/tmp/foo")          -- 圆括号消除歧义
pid(1234)                         -- 构造器调用
```

### Let 绑定

```
name = value                     -- 简单绑定
p = path"/tmp/foo"

let (x, y, z) = tuple            -- 元组解构
let { name, version } = record   -- Record 解构
```

### Case 表达式（模式匹配）

```
case expr of
  pattern1 -> result1
  pattern2 -> result2
  _        -> default
```

模式类型：

```
case parse("42") of
  Ok n  -> process(n)        -- 变体模式 + 变量绑定
  Err _ -> handleError()     -- 通配忽略

case list of
  []        -> "empty"
  x :: xs   -> "cons"        -- List cons 模式

case color of
  Red   -> 0
  Green -> 1
  Blue  -> 2

case expr of
  value when condition -> ...   -- 守卫子句（when）
  _                    -> ...
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
main : IO<Unit>
main = do
  content <- readFile(path"/tmp/foo")
  print(content)
```

`<-` 从 IO 操作中解包值。纯表达式直接写。

### Record 操作

```
{ name = "Kun", version = "0.1" }    -- 创建
record.name                            -- 字段访问
{ record | version = "0.2" }           -- 更新（不可变复制+修改）
```

### 索引访问

```
list[i]          -- List 索引，返回 Maybe<T>
str[i]           -- String 索引，返回 Char
tuple.0          -- Tuple 索引（0-based）
tuple.1
```

### 点调用语法

点号后接标识符可选带圆括号调用：

```
p.parent()                    -- 方法调用
record.name                   -- 字段访问（无括号）
```

点调用是通用语法，适用于所有类型。无括号时视为字段投影，有括号时视为函数调用。

### ? 操作符

```
readConfig : Path -> IO<Result<Config, String>>
config = readConfig(path"/etc/app.toml")?    -- 解包 Ok，传播 Err
```

在返回 `Result<T, E>` 的上下文中，`?` 解包 `Ok` 变体取得 `T` 值；若为 `Err`，将错误传播到调用者。

## 函数定义

函数定义由可选的类型标注行和值定义行组成：

```
add : (Int, Int) -> Int
add = \(x, y) -> x + y

-- 或匿名函数绑定
increment = \x -> x + 1
```

顶层函数建议标注类型签名。局部函数可省略：

```
main = do
  let double = \x -> x * 2
  print(double(21))
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

### 导入

```
import List                     -- 导入模块，公开符号可直接使用
import List as L                -- 限定别名
import List (map, filter)       -- 限定导入特定符号
```

### 导出

符号默认私有。使用 `pub` 关键字公开：

```
pub add : (Int, Int) -> Int
add = \(x, y) -> x + y

helper = \x -> x * 2            -- 私有
```

## 权限声明

### 脚本级声明

```
capability fs.read("/etc"), fs.read("/var/log"), net.http("api.example.com")
```

### 单命令注解

```
cat(path"/etc/nginx/nginx.conf") with capabilities fs.read("/etc")
```

### 作用域级权限

```
with capability net.http("api.example.com") {
  let response = curl(url"https://api.example.com/data")
  process(response)
}
```

`with capability`（单数）引入一个权限作用域块。`with capabilities`（复数）在单命令注解中列举多个权限。

## Stream 表达式

```
stream expr                        -- 从表达式创建惰性流

stream readFile(path"/tmp/large.log")
  |> filter (\line -> contains(line, "ERROR"))
  |> map parseLine
```

`stream` 关键字将表达式的求值延迟到消费时，适用于大文件处理和惰性管道。

## 语法优先级规则总结

1. 函数应用（空格）优先级高于所有中缀运算符
2. 管道 `|>` 优先级低于比较运算符
3. `?` 优先级最低，确保结果传播在完整表达式后
4. 使用圆括号消除歧义：`map (\x -> x + 1) list`

## 与语法分析器的交互

语法设计需与类型检查器协调：

1. **类型标注与值定义分离**：解析器先识别 `name : type` 行，再识别 `name = expr` 行
2. **泛型尖括号 `<...>`**：解析器需区分比较运算符 `<` 与泛型括号（通过上下文：类型位置 vs 表达式位置）
3. **自定义运算符**：当前设计无自定义运算符（保持简洁）

## 一致性决议

本设计统一如下不一致：

| 原不一致 | 决议 |
|---------|------|
| lambda 三种写法 | `\x ->` 单参数；`\x, y ->` 多参数糖；`\(x, y) ->` 元组解构 |
| 单参类型圆括号 | `Int -> Int` 规范形式，`(Int) -> Int` 兼容但不推荐 |
| 类型标注为声明 vs 注释 | 类型标注为真实声明行；文档中的注释风格仅供教学 |
| 字面量引用风格 | `path"..."` 双引号 / `` regex`...` `` 反引号 / `f"..."` 双引号各有场景 |
| 字符串插值 | `f"..."` 前缀 + 大括号嵌入 + `:` 格式说明，编译期展开为 `toString`/格式化链 |
| `capability` 单复 | `with capability` 作用域（单数）；`with capabilities` 列举（复数） |
| 点调用语义 | 无括号=字段投影，有括号=方法调用，通用语法 |
| `Stream` 构造 | `stream expr` 关键字语法 |
| 常量访问 | `ExitCode.success` = 模块路径（按惯例归属于类型模块） |
