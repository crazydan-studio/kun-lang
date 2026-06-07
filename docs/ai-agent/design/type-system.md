# 类型系统设计

## 设计目标与原则

### 核心目标

Kun 的类型系统服务于一门面向 Linux 的函数式脚本语言。其设计围绕以下目标展开：

- **类型安全**：所有类型检查在编译期完成，消除运行时类型错误
- **推断优先**：用户无需为局部变量和绝大多数函数参数提供类型标注
- **实用至上**：为脚本场景做务实取舍，不追求理论完备性
- **显式错误**：通过和类型（`Result`）将错误处理纳入类型系统，禁止隐式异常。可选值通过 `?T`（nilable 类型）表达
- **运行时对齐**：类型表示与 C ABI 兼容，保障 dlopen 直接加载命令二进制

### 设计原则

1. **无子类型**：所有类型间无隐式转换关系，`Nat` 与 `Int` 为独立类型
2. **结构等价**：类型等价基于结构而非名称
3. **穷举检查**：模式匹配必须覆盖所有分支（对和类型强制）
4. **纯度标记**：类型系统区分纯表达式与带 IO 副作用的表达式
5. **不可变默认**：所有数据默认不可变，类型系统对此做静态保证

## 类型宇宙与种类系统

### 种类（Kind）

Kun 采用两级种类系统：

| 种类 | 含义 | 示例 |
|------|------|------|
| `Type` | 具体类型（值可居留其中） | `Int`、`Bool`、`String` |
| `Type -> Type` | 类型构造器（接受一个类型参数返回具体类型） | `List`、`Set` |

所有完整应用的类型构造器（如 `List Int`）归约到种类 `Type`。

#### 幻影类型（Phantom Type）

幻影类型是没有变体和值的 ADT，仅用作类型参数标记。它在运行时零开销——没有值可以被创建，纯粹在编译期用于类型级标记。

```kun
type Stream       // 零变体 ADT，不能创建运行时值
type Document     // 同上

type Command mode a =
  { parser : String -> Result a String
  , args : List CmdArg
  , ...
  }

// 不同幻影类型标记不同的"模式"
asStream  : (String -> Result a String) -> Command Stream a
asDocument : (String -> Result a String) -> Command Document a

// Builder 函数对所有 mode 通用（幻影类型参数不参与运行时）
withArg : String -> Command mode a -> Command mode a
```

幻影类型与普通类型参数的区别：

| 维度 | 普通类型参数 | 幻影类型参数 |
|------|------------|-------------|
| 用途 | 承载运行时值 | 编译期标记 |
| 参与值定义 | 是（如 `List a` 中 `a` 是元素类型） | 否（`Command mode a` 中 `mode` 不影响字段） |
| 运行时表示 | 类型擦除后仍有值层信息 | 完全零开销——无值可创建 |
| 典型应用 | 泛型容器 | 类型级状态机、标记模式（如行流/文档） |

使用注意：
- 幻影类型声明 `type X` 是无变体 ADT，**不能**通过 `X { ... }` 或 `X value` 创建值。如果误用 `type X = X Int`（带变体），它就不再是幻影类型，而是一个普通的 newtype
- 幻影类型在 `case` 模式匹配中不需要穷举——因为没有变体可以匹配
- 编译器通过函数签名中的具体幻影类型（`Command Stream a` vs `Command Document a`）做编译期分支选择，无运行时开销
- 与积类型（Record）的关系：幻影类型不是积类型，它不包含任何字段。积类型是 `{ name : String, ... }` 结构。当幻影类型作为 `Command mode a` 的 `mode` 参数时，它仅出现在类型参数位置，不影响 `Command` 的字段定义

#### 幻影类型的导入、导出与模式匹配

**导出**：幻影类型本质上是一个零变体 ADT，导出规则与普通类型一致：

```kun
module Command export
  ( Command
  , Stream, Document   // 作为类型名导出，供外部在类型标注中使用
  , asStream, asDocument
  , ...
  )
```

`Stream(..)` 或 `Stream(StreamVariant)` 在此处无意义——因为幻影类型没有变体可以导出。`Stream`（仅类型名）导入方可引用该类型名即可用于类型标注：

```kun
// 导入方仅引用类型名，用于函数签名
import Command with
  ( Command, Stream, Document
  , asStream, ...
  )

makeStreamCmd : (String -> Result a String) -> Command Stream a
```

**模式匹配**：幻影类型没有变体，因此**不能**在 `case` 中匹配其值。以下代码是编译错误：

```kun
// ❌ 编译错误：Stream 没有变体，无法 case 匹配
case mode of
  _ -> ...
```

幻影类型的"分支选择"通过**类型签名**在编译期完成，而非运行时的模式匹配：

```kun
// ✅ 编译期分支：编译器通过函数签名中的具体类型选择实现
//   函数签名用 Command Stream a → 编译器选择行流处理路径
//   函数签名用 Command Document a → 编译器选择文档处理路径
run1 : String -> { ... } -> Command Stream a -> IO (Stream (Result a String))
run2 : String -> { ... } -> Command Document a -> IO (Result a IOError)
```

编译器在处理调用时，根据实参类型的具体幻影类型 `Stream`/`Document`，在生成的代码中选择 `run1` 或 `run2`。这与重载解析类似——但通过类型参数选择而非函数名选择。

**零变体 ADT 的特殊性**：`type X` 声明了一个没有构造器的类型。在 Kun 中：
- `case x of ...` — **不允许**，因为没有变体可以匹配
- `let x : X = ...` — 无法赋值，因为没有值可以创建
- `f : X -> Int` — 函数无法被调用（无法传入参数），但可用于类型参数位置
- `f : List X -> Int` — 列表恒为空，可作为零值标记

因此，幻影类型的使用被自然限制在类型参数位置，不可能被误用为运行时值。

### 通用场景示例

#### 标记单位（防止类型混淆）

```kun
type Meters
type Seconds

type Distance = ?Meters              // ❌ 错误：Meters 没有值，Distance 永远为 Nil
type Velocity = ?(Meters, Seconds)   // ❌ 错误：同上

// ✅ 正确用法：作为类型参数标记
type Measurement a = { value : Float, unit : a }
//                       ↑ 运行时值   ↑ 编译期标记

// 构造不同单位的测量值
dist  : Measurement Meters
dist  = { value = 100.0, unit = ??? }    // ❌ 不能给 unit 赋值（Meters 无值）

// ✅ 正确做法：unit 不作为 Record 字段，仅通过类型参数标记
type Measurement a = { value : Float }

dist : Measurement Meters
dist = { value = 100.0 }                 // ✅ Meters 仅用于类型签名

time : Measurement Seconds
time = { value = 9.58 }

// 对比：不同类型的测量值在函数签名中区分
addDist : Measurement Meters -> Measurement Meters -> Measurement Meters
addDist = \x y -> { value = x.value + y.value }

// ✅ 以下会编译报错，防止单位混淆：
// addDist dist time   ❌ Seconds 不能传给期望 Meters 的参数
```

#### 标记序列格式

```kun
type JsonString
type XmlString

parseJson : String -> Result JsonString String
parseXml  : String -> Result XmlString String

// 对不同格式的字符串应用不同的处理
processJson : JsonString -> IO Unit
processXml  : XmlString -> IO Unit

// 类型系统确保不会混淆格式
// processJson (parseXml content)  ❌ 编译错误：XmlString ≠ JsonString
// processXml (parseJson content)  ❌ 编译错误
```

#### 何时使用幻影类型 vs ADT

幻影类型适合"只影响类型安全、不影响运行时行为"的场景。如果需要**运行时根据标记做不同处理**，应使用 ADT：

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| 防止单位混淆（Meters vs Feet） | 幻影类型 | 运行时行为相同，只是数值 |
| 标记模式（行流 vs 文档） | 幻影类型 | 编译器在生成代码时根据类型选择处理路径 |
| 需要运行时分支（OK vs Error） | ADT（`Result`） | 需要在 `case` 中匹配变体 |
| 需要不同的字段结构 | ADT（变体可带不同字段） | 每个变体可以有独立的 Record 字段 |

**规律**：如果两个"变体"共享相同的字段结构，但你想在类型层面区分它们 → 用幻影类型。如果字段结构不同，或需要运行时 `case` 匹配 → 用 ADT。

### 类型分类

```
Type Universe
├── Base Types         (Int, Nat, Float, Bool, String, Bytes, Char, Regex, Duration, Unit, Path)
├── Compound Types     (List, Map, Set, Stream, Tuple)
├── Product Types      (Record/Tuple)
├── Sum Types / ADTs   (custom sum types, Result)
├── Nilable Types      (?T — Nil or T)
├── Function Types     (pure functions, command functions)
├── Effect Types       (IO)
└── Type Variables     (a, b, etc. — for generics)
```

### Nilable 类型（`?T`）

类型 `?T` 表示值可能存在（`T`），也可能不存在（`Nil`）。这是语言内置类型构造器，非 ADT。

| 规则 | 说明 |
|------|------|
| `T`（无 `?`） | **不可**为 Nil。`let x : String = Nil` 编译期报错 |
| `?T` | **可**为 Nil。`let x : ?String = Nil` 合法 |
| `?(T1 T2)` | 对多词类型使用括号包裹，如 `?(Result T E)` 表示 `Result T E` 可为 Nil。**不支持 `?Result T E` 形式**——`?` 的作用域不明确 |
| `Nil` 字面量 | 唯一值为 `Nil`，类型为 `?a`（多态） |
| Record 字段 | 未提供的字段自动为 `Nil` |
| 和类型字段 | 字段类型默认不可 Nil，`?` 需显式标注 |
| 函数参数 | 默认不可 Nil。`?` 标注时可为 Nil |

操作符：

| 操作符 | 语义 | 示例 |
|-------|------|------|
| `x ?? default` | Nil 合并：`x` 为 `Nil` 时返回 `default`，否则返回 `x` | `name ?? "guest"` |
| `x ?. f` | 可选链：`x` 为 `Nil` 时返回 `Nil`，否则调用 `f(x)` | `getConfig "port" ?. parseInt` |

模式匹配收窄：

```kun
x : ?String
x = someFunctionReturningOptional

case x of
  Nil -> "none"        // Nil 分支
  s   -> s             // 此分支 s 收窄为 !String（安全）

if x /= Nil then
  print x              // 此分支 x 收窄为 !String（安全）
```

## 基础类型

### 概览

| 类型 | 值域 | 字面量示例 | 运行时表示 | 说明 |
|------|------|-----------|-----------|------|
| `Int` | `-2^63 .. 2^63-1` | `42`, `-3`, `0xFF` | i64 | 固定宽度有符号整数 |
| `Nat` | `0 .. 2^63-1` | `42u`, `0u` | i64 (非负约束) | 非负整数，独立于 `Int` |
| `Float` | IEEE 754 双精度 | `3.14`, `-2.5e10` | f64 | 浮点数 |
| `Bool` | `true` / `false` | `true`, `false` | u1 (或 u8) | 布尔值 |
| `String` | UTF-8 编码文本 | `"hello"`, `""` | `[]u8` (切片) | 不可变 UTF-8 字符串 |
| `Bytes` | 任意二进制数据 | `0x48656C6C6F` | `[]u8` | 与 `String` 明确区分 |
| `Char` | Unicode 标量值 | `'A'`, `'\n'` | u32 | Unicode 标量值 |
| `Regex` | 编译后正则 | `r"[0-9]+"` | 内部编译表示 | 编译期验证 |
| `Duration` | 纳秒精度时间段 | `5s`, `100ms`, `2h` | i64 (纳秒) | 时间跨度 |
| `Unit` | 单元类型 | `()` | void | 表示无返回值 |
| `Path` | 文件系统路径 | `p"/tmp/foo"`, `p"./foo"` | `[]u8` | 与 `String` 语义区分 |

### 类型详述

#### `Int`

- 固定 64 位有符号整数，补码表示
- 四则运算溢出为运行时 Panic（`debug` 模式检测，`release` 模式可关闭检查）。注意：关闭检查后溢出行为为静默回绕（wraparound），与 i64 的补码表示一致。这是否属于"运行时类型错误"的争议——溢出是值域问题而非类型问题，不影响类型系统关于"消除运行时类型不匹配错误"的保证
- 字面量支持十进制、十六进制 `0x`、八进制 `0o`、二进制 `0b`，以及下划线分隔 `1_000_000`
- 支持操作：`+`, `-`, `*`, `/` (截断除法), `%` (模), `neg`, `abs`
- 比较操作返回 `Bool`：`==`, `/=`, `<`, `>`, `<=`, `>=`

#### `Nat`

- 非负整数，值域 `0 .. 2^63-1`
- 与 `Int` **无子类型关系**，是独立类型
- 字面量后缀 `u` 区分：`42` 为 `Int`，`42u` 为 `Nat`；支持下划线分隔 `20_000u`
- `Nat` 计算结果可能为负时编译期报错（如 `0u - 1u` 编译期拒绝）
- 与 `Int` 的互转通过显式内置函数：`toInt : Nat -> Int`、`toNat : Int -> Nat`（负数→运行时 Panic）
- 语义场景：文件描述符、进程 ID、端口号、文件大小、权限掩码

#### `Float`

- IEEE 754 双精度浮点数
- 支持操作：`+`, `-`, `*`, `/`, `neg`, `abs`, `floor`, `ceil`, `round`, `sqrt`
- 与 `Int`/`Nat` 的混合运算需显式转换：`toFloat`, `toInt`, `toNat`

#### `Bool`

- 仅两个值：`true`, `false`
- 支持操作：`&&`, `||`, `not`
- 短路求值：`&&` 和 `||` 具有短路语义

#### `String`

- 不可变 UTF-8 编码文本
- 支持操作（通过 `String` 模块调用）：`++` (拼接), `length`, `slice`, `contains`, `startsWith`, `endsWith`, `split`, `join`, `trim`, `toUpper`, `toLower`, `replace`
- 索引访问：`str[i]` 返回 `Char`
- 使用双引号 `"..."`，支持转义序列；多行字符串用 `"""` 包裹
- 插值字符串使用 `f"..."` 前缀
- **外部输入编码策略**：从文件/网络读取的外部字节序列转换为 `String` 时（`Bytes -> String`），若包含非法 UTF-8 序列则运行时 Panic。需要处理非 UTF-8 数据的场景应使用 `Bytes` 类型，而非强制转为 `String`

#### `Bytes`

- 不可变二进制数据，与 `String` 语义上严格区分
- 字面量使用 `0x` 前缀后接十六进制字节：`0x48656C6C6F`
- 支持操作：`++` (拼接), `length`, `slice`, `at`
- 转换：`toBytes : String -> Bytes`、`toString : Bytes -> String` (假定 UTF-8)

#### `Char`

- Unicode 标量值（U+0000 到 U+10FFFF）
- 使用单引号字面量：`'A'`, `'\n'`, `'好'`
- 支持操作：`isDigit`, `isLetter`, `isWhitespace`, `toUpper`, `toLower`

#### `Regex`

- 编译期验证的正则表达式
- 字面量使用 `r"..."` 前缀：`r"(?i)[a-z]+"`

  ```kun
  r"(?i)[a-z]+"       // 忽略大小写
  r"(?m)^foo"         // 多行模式（^/$ 匹配行边界）
  r"(?s).+"           // DotAll（. 匹配换行符）
  r"(?u)\w+"          // Unicode 模式
  r"(?im)[a-z]+"      // 多标志组合：忽略大小写 + 多行
  r"(?i-m)[a-z]+"     // 开启 i，关闭 m
  ```

- 支持修饰符：

  | 内联语法 | 名称 | 语义 |
  |---------|------|------|
  | `(?i)` | IgnoreCase | 大小写不敏感匹配 |
  | `(?m)` | Multiline | `^`/`$` 匹配每行的起始和结束 |
  | `(?s)` | DotAll | `.` 元字符匹配包括换行符在内的所有字符 |
  | `(?u)` | Unicode | 启用 Unicode 属性转义（`\p{...}`） |
  | `(?x)` | Extended | 忽略模式中的空白和注释 |

- 修饰符作用域：出现在模式开头则作用于整个模式，出现在中间则仅影响后续部分
- 支持修饰符开关：`(?i)` 开启，`(?-i)` 关闭
- 编译期对正则语法进行验证，语法错误为编译期错误
- 修饰符在编译期编码到正则中，运行时不可变更
- 支持操作：`match : Regex -> String -> ?String`、`matchAll : Regex -> String -> List String`、`contains : Regex -> String -> Bool`、`split : Regex -> String -> List String`、`replace : Regex -> String -> String -> String`、`replaceAll : Regex -> String -> String -> String`
- 捕获组支持：`captures : Regex -> String -> ?(List (?String))`（返回所有捕获组，每组可能为 null）

#### `Duration`

- 表示纳秒精度的时间段
- 运行时表示为 i64（纳秒数）
- 字面量：`5s`, `100ms`, `2h`, `30m`, `1d`, `500us`, `200ns`
- 支持操作：`+`, `-`, 比较, `toSecs`, `toMillis`, `toNanos`
- 可与 `Int` 进行标量乘除：`5s * 3`

#### `Unit`

- 单值类型，只有一个值 `()`
- 用于表示无返回值的函数
- 对应 C 的 `void`

#### `Path`

- 表示文件系统路径
- 与 `String` 语义上区分（但运行时同用 `[]u8`）
- 字面量使用 `p"..."` 前缀：`p"/tmp/foo"`、`p"./foo"`
- 支持操作：`++` (拼接)，`p"/etc" ++ p"kun" ++ p"config"` → `p"/etc/kun/config"`（自动处理分隔符）
- 支持操作：`parent : Path -> Path`、`fileName : Path -> String`

```kun
// 路径操作是纯字符串语义，不依赖文件类型
p = p"/tmp/foo"
```

运行时查询函数：

### `IO`——效应类型

独立 `IO t` 效应类型解决三个核心问题：

| 问题 | Shell 脚本现状 | Kun 的解决方案 |
|------|---------------|---------------|
| 副作用不可见 | 任何函数都可能偷偷写文件、发网络请求，调用者无从知晓 | `IO t` 让类型签名直观承诺"此函数有副作用"，纯函数（无 `IO`）编译期保证无副作用 |
| 执行顺序不可控 | 管道和进程隐式顺序依赖，纯函数式求值策略不确定 | `do` 记法 + `IO` 类型提供显式顺序组合语法，保证副作用按源码顺序执行 |
| 职责混叠 | 权限检查与执行逻辑杂糅 | IO 效应只回答"有没有副作用"（编译期），能力安全系统回答"允许哪些具体副作用"（运行时），分层解耦 |

决策依据：

1. **脚本场景的务实选择**——不做完整 effect system（如 algebraic effects），仅标记 IO 边界。用户不需要追踪"文件写入"vs"网络请求"vs"随机数"等细粒度效应，只需区分"纯"与"不纯"
2. **最小侵入**——`IO t` 是极简包装类型，不影响 HM 类型推断，不引入效应多态（effect polymorphism），编译器实现负担低
3. **与能力安全互补**——无 IO 边界的纯函数静态保证不触发任何系统调用，作为安全基线的第一道防线
4. **`do` 记法对齐主流实践**——借鉴 Haskell 的 `do` 记法，脚本语言用户仅需理解"`<-` 从 IO 中解包"这一概念，学习成本可控

### 效应传播规则

1. 调用任何带 `IO` 效应的函数，调用者自动获得 `IO` 效应
2. 纯函数不能调用标记 `IO` 的函数
3. `do` 表达式用于按顺序组合 IO 操作
4. IO Stream 的构造和消费分别标记 IO 边界：`<-` 解包获得 `Stream t`，消费时逐元素按需执行

#### 嵌套 IO 类型

`IO t` 中的 `t` 可以是任意类型，包括 `IO` 自身。`f : IO (IO String)` 在 `do` 块中需要两次 `<-` 解包：

```kun
x <- f           // x : IO String（解包外层 IO）
y <- x           // y : String（解包内层 IO）
```

这是 HM 类型构造器的自然结果，无需特殊语言支持。

### 与能力安全的关系

- 类型系统仅回答"是否有副作用"（IO 边界标记）
- 能力安全系统回答"允许哪些具体的副作用"（文件 / 网络 / 进程等）
- 两套机制互补：类型系统在编译期确保正确性，能力系统在运行时控制权限
- `capability_check` 发生在运行时 IO 原语内部（`readFile`、`httpGet` 等），而非类型检查期间。纯函数（无 `IO t`）编译期保证不会到达 `capability_check` 检查点，因此永远不触发能力检查

## 类型等价与类型关系

### 等价规则

类型等价基于结构等价（Structural Equivalence）：

- 两个类型当且仅当其结构完全相同时被视为等价
- 名称别名（在导入时指定的别名）展开后参与比较
- 泛型类型在应用相同类型参数后结构等价

### 无子类型

Kun 类型系统**不包含子类型关系**：

- `Nat` 与 `Int` 为独立类型，无隐式转换
- `List Nat` 与 `List Int` 为不同类型
- Record 无宽度子类型化和深度子类型化
- 函数类型无逆变/协变

### 扩展积类型（Extensible Records）

基于已有 Record 类型声明扩展类型，编译期展开为完整字段：

```kun
type CmdOptions = { runAs : ?RunAs }

type GitCommitOptions =
  { CmdOptions
  | message : String
  }
// 编译期等价于：{ runAs : ?RunAs, message : String }
```

约束：
- 基类型必须是有名 Record 类型（`type T = { ... }`）
- 字段名冲突时扩展字段覆盖基类型字段
- 不支持多继承
- 扩展积类型仅用于类型定义，不可用于行变量（无 `{ a | name : String }` 语法）

#### Record 类型与函数

函数接受 Record 参数时，必须使用精确的 Record 类型（不支持"只要包含某些字段"的泛化）：

```kun
getName : { name : String } -> String
getName = \{ name } ->
  name

// 需要精确匹配
getName { name = "Kun" }                    // → "Kun"
// getName { name = "Kun", version = "0.1" }  // ❌ 编译错误：类型不匹配
```

如需在函数间传递包含额外字段的 Record，使用扩展积类型预先定义：

```kun
type Base = { name : String }
type NamedWithVersion = { Base | version : String }

getName : Base -> String
getName = \{ name } -> name

process : NamedWithVersion -> String
process = \r ->
  let
    name = getName r   // ✅ OK：Base 在 NamedWithVersion 中完整包含
  in
    f"{name} v{r.version}"
```

#### Record 更新

Record 更新要求操作数具有精确已知的 Record 类型：

```kun
updateName : { name : String } -> { name : String }
updateName = \r ->
  { r | name = "new name" }
```

### 显式类型转换

跨类型转换必须通过显式内置函数：

| 转换 | 函数 | 安全性 |
|------|------|--------|
| `Nat -> Int` | `toInt : Nat -> Int` | 始终安全（值域子集） |
| `Int -> Nat` | `toNat : Int -> Nat` | 负数运行时 Panic |
| `Int -> Float` | `toFloat : Int -> Float` | 大整数可能精度损失 |
| `Float -> Int` | `toInt : Float -> Int` | 截断，小数部分丢失 |
| `String -> Bytes` | `toBytes : String -> Bytes` | 始终安全 |
| `Bytes -> String` | `toString : Bytes -> String` | UTF-8 非法序列运行时 Panic |

## 类型检查算法

### 两阶段流程

```
阶段 1: 约束生成（Constraint Generation）
  AST → 遍历生成类型约束等式

阶段 2: 合一（Unification）
  约束等式 → 求解 → 类型替换 → 最终类型
```

### 阶段 1: 约束生成

对 AST 的每个节点，根据其种类生成对应的类型约束：

| AST 节点 | 生成的约束 |
|----------|-----------|
| 整数字面量 | `τ = Int` |
| Bool 字面量 | `τ = Bool` |
| 变量引用 | `τ = lookup(env, var)` |
| 函数应用 | `τ_fn = (τ_arg) -> τ_res` |
| Lambda | `τ = (τ_param) -> τ_body` |
| Let 绑定 | 泛型实例化，let-多态 |
| 模式匹配 | 穷举性检查，分支类型合一 |
| If 表达式 | 条件必须为 `Bool`，分支类型合一 |
| Record 字面量 | `τ = { f1: τ1, f2: τ2, ... }`，提取字段类型 |
| 字段访问 `.name` | `τ_record` 必须包含 `name` 字段，`τ_res` 为该字段类型 |
| Record 更新 `{ r \| f = v }` | `τ_input` 与 `τ_output` 结构相同，仅字段 `f` 类型为 `τ_val` |

### 阶段 2: 合一

标准 Martelli-Montanari 合一算法：

1. 从约束集中取一条等式 `τ₁ = τ₂`
2. 应用当前替换到 `τ₁` 和 `τ₂`
3. 尝试合一化简后的类型
4. 发生冲突 → 生成类型错误报告
5. 成功 → 将新替换加入到全局替换
6. 重复直到约束集为空

Record 类型的合一是结构化的：两个 Record 类型当且仅当字段名集合相同且对应字段类型可合一时才可合一。扩展积类型在参与合一前已编译期展开为完整字段集。

### 类型错误报告

类型错误报告包含：

- **错误位置**：文件名 + 行号 + 列号
- **期望类型**：上下文期望的类型
- **实际类型**：表达式推断出的类型
- **错误原因**：可读的中文解释
- **修改建议**：针对常见错误的修复提示

错误消息模板：

```
类型错误 [E001]: 类型不匹配
  ┌─ script.kun:12:5
  │
12  │  42 + "hello"
  │  ───┬───
  │     ╰── String 类型不能与 Int 进行 + 运算
  │
  提示：字符串拼接请使用 ++ 操作符
```

## 类型表示与运行时

### 运行时类型表示

- 基础类型在运行时表示为对应的 C ABI 类型（`i64`、`f64`、`u8` 等）
- 禁止运行时类型擦除 —— 仅在必要时保留类型标签（如 ADT 变体标记）
- 和类型运行时采用带标记的联合体（Tagged Union）：

  ```zig
  struct Nilable_Int64 {
    uint8_t is_nil;    // 0 = 有值, 1 = Nil
    int64_t value;     // 仅 is_nil==0 时有意义
  };
  ```

### 与 dlopen 的对齐

- 函数参数的传递使用 C ABI 兼容的结构体
- ADT 变体标记使用 `uint8_t`
- 字符串使用 `{ ptr : *u8, len : usize }` 切片表示

## 版本与演进

### Record 构造默认对象

Kun 语言本身**不**支持为积类型字段绑定缺省值语法。需要使用缺省值的场景，由类型模块导出的构造默认对象的函数实现：

```kun
type Config
  = { host : String
    , port : Int
    , debug : Bool
    }

defaultConfig : Config
defaultConfig = { host = "localhost", port = 8080, debug = false }
```

使用者可通过 `update` 语法覆盖部分字段：

```kun
cfg = { defaultConfig | port = 9090 }   // host="localhost", port=9090, debug=false
```

此模式与不可变性一致，不需要语言层面增加缺省值语法，不增加类型系统的复杂度。

| 版本 | 变更 |
|------|------|
| 0.2.1 | 扩展积类型 `{ Base \| field : T }`，移除行变量（`{ a \| name : String }`）以降低类型检查器实现复杂度 |
| 0.2.0 | Nilable 类型 `?T` 替代 `Maybe`，新增 `?.` 可选链和 `??` Nil 合并操作符 |
| 0.1.0 | MVP 基础类型 + `Maybe`/`Result` + HM 推断 + 简单参数化多态 + `IO` 效应标记 |

## 参考

- [应用概览](app-overview.md) — Kun 语言功能全景
- [功能清单](feature-inventory.md) — 功能实现状态追踪
- [系统基线](../architecture/system-baseline.md) — 运行时与类型系统概览
- [模块边界](../architecture/module-boundaries.md) — 类型检查器在架构中的位置
