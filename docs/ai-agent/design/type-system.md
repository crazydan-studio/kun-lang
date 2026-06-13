# 类型系统设计

## 设计目标与原则

### 核心目标

Kun 的类型系统服务于一门面向 Linux 的函数式脚本语言。其设计围绕以下目标展开：

- **类型安全**：所有类型检查在编译期完成，消除运行时类型错误
- **推断优先**：用户无需为局部变量和绝大多数函数参数提供类型标注
- **实用至上**：为脚本场景做务实取舍，不追求理论完备性
- **显式错误**：通过和类型（`Result`）将错误处理纳入类型系统，禁止隐式异常。可选值通过 `?T`（nilable 类型）表达
- **运行时对齐**：类型表示与 C ABI 兼容

### 设计原则

1. **无子类型**：所有类型间无隐式转换关系
2. **结构等价**：类型等价基于结构而非名称
3. **穷举检查**：模式匹配必须覆盖所有分支（对和类型强制）
4. **效应标记**：含 `do` 块的函数通过 AST 标记为效应函数，纯函数不能调用效应函数
5. **不可变默认**：所有数据默认不可变，类型系统对此做静态保证

## 类型宇宙与种类系统

### 种类（Kind）

Kun 采用两级种类系统：

| 种类 | 含义 | 示例 |
|------|------|------|
| `Type` | 具体类型（值可居留其中） | `Int`、`Bool`、`String` |
| `Type -> Type` | 类型构造器（接受一个类型参数返回具体类型） | `List`、`Set` |

所有完整应用的类型构造器（如 `List Int`）归约到种类 `Type`。

### 类型分类

```
Type Universe
├── Base Types         (Int, Float, Bool, String, Bytes, Char, Regex, Duration, Unit, Path)
├── Compound Types     (List, Map, Set, Stream, Tuple)
├── Product Types      (Record/Tuple)
├── Sum Types / ADTs   (custom sum types, Result)
├── Nilable Types      (?T — Nil or T)
├── Function Types     (pure functions, command functions)
└── Type Variables     (a, b, etc. — for generics)
```

### Nilable 类型（`?T`）

> **编译器内置**：`?T` 是语言内置类型构造器，`Nil` 是编译器内置值，不可在纯 Kun 代码中定义等价物。操作符 `?.` 和 `??` 同样由编译器直接处理。

类型 `?T` 表示值可能存在（`T`），也可能不存在（`Nil`）。这是语言内置类型构造器，非 ADT。

| 规则 | 说明 |
|------|------|
| `T`（无 `?`） | **不可**为 Nil。`x : String = Nil` 编译期报错 |
| `?T` | **可**为 Nil。`x : ?String = Nil` 合法 |
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
  IO.print x              // 此分支 x 收窄为 !String（安全）
```

## 基础类型

### 概览

| 类型 | 值域 | 字面量示例 | 运行时表示 | 说明 |
|------|------|-----------|-----------|------|
| `Int` | `-2^63 .. 2^63-1` | `42`, `-3`, `0xFF` | i64 | 固定宽度有符号整数 |
| `Float` | IEEE 754 双精度 | `3.14`, `-2.5e10` | f64 | 浮点数 |
| `Bool` | `true` / `false` | `true`, `false` | u8 | 布尔值 |
| `String` | UTF-8 编码文本 | `"hello"`, `""` | `[]u8` (切片) | 不可变 UTF-8 字符串 |
| `Bytes` | 任意二进制数据 | `0x48656C6C6F` | `[]u8` | 与 `String` 明确区分 |
| `Char` | Unicode 标量值 | `'A'`, `'\n'` | u32 | Unicode 标量值 |
| `Regex` | 编译后正则 | `r"[0-9]+"` | 内部编译表示 | 编译期验证 |
| `Duration` | 纳秒精度时间段 | `5s`, `100ms`, `2h` | i64 (纳秒) | 时间跨度 |
| `Unit` | 零宽度类型 | 无（编译器隐式值） | void | 无返回值标记，不可作为参数类型 |
| `Path` | 文件系统路径 | `p"/tmp/foo"`, `p"./foo"` | `[]u8` | 与 `String` 语义区分 |

### 类型详述

#### `Int`

- 固定 64 位有符号整数（i64），补码表示。字面量支持十进制、`0x`、`0o`、`0b` 及 `_` 分隔
- 四则运算溢出时 panic（`release` 模式可关闭检测）。操作函数见 [`Int` 模块](standard-library.md#int--整数操作)

#### `Float`

- IEEE 754 双精度浮点数（f64）。与 `Int` 混合运算需显式转换
- 操作函数及容差比较见 [`Float` 模块](standard-library.md#float--浮点操作)

**精度局限**：二进制浮点无法精确表示大多数十进制小数（如 `0.1` + `0.2` ≠ `0.3`）。Kun 从两个层面缓解：

1. `toString` 输出时默认舍入到 15 位有效数字，消除显示噪音
2. `Float.approxEqual` 提供容差比较，避免直接用 `==` 比较浮点值

需要精确十进制计算的场景应使用标准库 [`Decimal` 类型](standard-library.md#decimal--十进制精确数值)。

#### `Bool`

- 仅两个值：`true`、`false`。支持 `&&`、`||`、`not`，前两者短路求值

#### `String`

- 不可变 UTF-8 编码文本。操作函数见 [`String` 模块](standard-library.md#string--字符串操作)
- 从外部输入转为 `String` 时，非法 UTF-8 序列运行时 Panic

#### `Bytes`

- 不可变二进制数据，与 `String` 语义严格区分。字面量 `0x` 前缀。转换函数见标准库

#### `Char`

- Unicode 标量值（u32）。操作函数见标准库

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
- 编译期验证正则语法。操作函数见标准库 `Regex` 类型

#### `Duration`

- 纳秒精度时间段，运行时表示为 i64（纳秒）。字面量：`5s`、`100ms`、`2h`、`30m`、`1d`、`500us`、`200ns`
- 操作函数见标准库

#### `Unit`

- 零宽度类型（C `void`），编译器隐式值。不可作为参数类型

#### 零参函数类型 `-> T`

零参函数类型 `-> T` 表示不接受任何参数、返回类型 `T` 的函数：

```kun
-> DateTime          // 零参函数，返回 DateTime
-> Result Path Error  // 零参函数，返回 Result
```

规则：
- `-> T` 与 `a -> T` 是**不同元数的函数类型**——HM 合一时元数必须相同，否则合一失败
- 零参函数**仅允许用于效应函数**（函数体含 `do` 块）。纯零参函数退化为常量，应使用 `let` 绑定
- 对应的 Lambda 语法为 `\ -> expr`
- 调用零参函数时裸名即为调用：`Sys.time`（不可传参）

```kun
now : -> DateTime
now = \ ->
  do
    Sys.time

getPid : -> Pid
getPid = \ ->
  do
    Process.pid
```

#### `Path`

- 文件系统路径，与 `String` 语义区分。字面量 `p"..."` 前缀。操作函数见 [`Path` 模块](standard-library.md#path)

```kun
// 路径操作是纯字符串语义，不依赖文件类型
p = p"/tmp/foo"
```

### 效应跟踪

> **编译器内置**：效应跟踪通过编译器 AST 标记实现，不可在纯 Kun 代码中模拟。`do` 块和效应命名空间（`Cmd.*`、`IO.*` 等）由编译器直接识别和处理。

Kun 采用 AST 标记方案替代 `IO T` 类型包装器：

- 含 `do` 块的函数自动标记为效应函数
- 以下命名空间的所有函数均为效应函数：`Cmd.*`、`IO.*`、`File.*`、`Env.*`、`Process.*`、`Signal.*`、`Sys.*`
- 纯函数（无 `do` 块）不能调用效应函数——编译期拒绝
- 效应性不扩散到类型签名——函数签名中不出现 `IO` 标记
- Lambda 含有效应函数调用时，该 lambda 必须在 `do` 块内定义

## 类型等价与类型关系

### 等价规则

Kun 采用**结构等价**（Structural Equivalence），而非名义等价（Nominal Equivalence）。

**结构等价**：两个类型当且仅当其结构完全相同时被视为等价。名称别名（导入时指定）展开后参与比较。泛型类型在应用相同类型参数后结构等价。结构等价适用于所有类型：基础类型、复合类型、Record、ADT、函数类型均基于其结构而非名称判断等价。

**名义等价**（未采用）：两个类型仅当声明为同一名称时才等价，即使结构相同也不兼容。如 `type A = { x: Int }` 与 `type B = { x: Int }` 在名义等价下是不同的类型。

选择结构等价的理由：

1. **与 HM 推断天然契合**。HM 合一算法直接产出结构等式，名义等价需要在合一之外额外维护全局名称映射并逐次查表展开，反而增加复杂度。

2. **Kun 无子类型，名义等价优势场景不存在**。名义等价的主要优势在于配合 nominal subtyping（如 Java 继承链），但 Kun 设计原则明确排除了子类型关系。

3. **脚本场景追求零声明成本**。`{ x: Int, y: Int }` 自然就是坐标类型，无需先声明 `type Point = ...` 才能传递。用户按需使用 Record 字面量即可获得类型安全。

4. **需要语义隔离时用 newtype**。`type UserId = UserId Int` 在结构等价系统中提供精确的名义边界——同名 newtype 互相兼容，不同名的即使包装相同底层类型也不兼容。这以最小成本在需要的地方获得名义等价的语义隔离能力，而不必全系统采用。

### 递归类型

Kun 支持 **等递归类型（Equi-recursive Types）**。在合一算法中，对 `type` 声明的别名关闭 occurs check——允许类型定义中引用自身，通过别名的结构展开实现。

```kun
// 等递归类型示例：clispec 通过 subs 引用自身
type CliSpec =
  { subs : ?(Map String CliSpec) }
```

递归类型的关键约束：

- 递归必须通过 `type` 别名间接发生——直接在匿名 Record 中引用自身会被 occurs check
  拒绝（匿名类型无别名可供展开）
- 编译器对递归 `type` 别名的展开有深度上限（默认 256 层），防止无限展开
- 交叉递归（A 引用 B，B 引用 A）同样通过别名机制支持

### 无子类型

Kun 类型系统**不包含子类型关系**：

- `Int` 无子类型关系
- Record 无宽度子类型化和深度子类型化
- 函数类型无逆变/协变

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

#### Record 更新

Record 更新要求操作数具有精确已知的 Record 类型：

```kun
updateName : { name : String } -> { name : String }
updateName = \r ->
  { r | name = "new name" }
```

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


### 显式类型转换

跨类型转换必须通过显式内置函数：

| 转换 | 函数 | 安全性 |
|------|------|--------|
| `Int -> Float` | `toFloat : Int -> Float` | 大整数可能精度损失 |
| `Float -> Int` | `toInt : Float -> Int` | 截断，小数部分丢失 |
| `String -> Bytes` | `toBytes : String -> Bytes` | 始终安全 |
| `Bytes -> String` | `toString : Bytes -> String` | UTF-8 非法序列运行时 Panic |

## 类型检查算法

类型检查采用 HM（Hindley-Milner）推断，两阶段流程（约束生成 + 合一），详细实现见[系统基线](../architecture/system-baseline.md)。

## 类型表示与运行时

类型在编译后的运行时表示及 C ABI 映射见[系统基线](../architecture/system-baseline.md#类型运行时表示)。类型系统专注于编译期语义，运行时内存布局属于架构实现细节。

## 版本与演进

| 版本 | 变更 |
|------|------|
| 2026.06.12 | 新增 `Float` 精度局限说明与 `toString` 截断语义；编译器内置标注（`Nil`/`?T`/效应跟踪）；新增 `Decimal` 精确十进制类型；`TempFile`/`TempDir` 整合为 `File.createTempFile`/`File.createTempDir` |
| 2026.06.10 | 移除 `Nat`、`IO T` 效应类型、幻影类型、扩展积类型（`{ Base \| field : T }`）；效应跟踪改为 AST 标记方案 |
| 2026.06.10 | 目录即命名空间模块系统：`export (...)` 替代 `module Xxx export (...)`；`import X (...)` 替代 `import X with (...)` |
| 2026.06.02 | 扩展积类型 `{ Base \| field : T }`，移除行变量以降低类型检查器实现复杂度 |
| 2026.06.02 | Nilable 类型 `?T` 替代 `Maybe`，新增 `?.` 可选链和 `??` Nil 合并操作符 |
| 2026.05.27 | MVP 基础类型 + `Maybe`/`Result` + HM 推断 + 简单参数化多态 + `IO` 效应标记 |

## 参考

- [应用概览](app-overview.md) — Kun 语言功能全景
- [功能清单](feature-inventory.md) — 功能实现状态追踪
- [系统基线](../architecture/system-baseline.md) — 运行时与类型系统概览
- [模块边界](../architecture/module-boundaries.md) — 类型检查器在架构中的位置
