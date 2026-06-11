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
| `Bool` | `true` / `false` | `true`, `false` | u1 (或 u8) | 布尔值 |
| `String` | UTF-8 编码文本 | `"hello"`, `""` | `[]u8` (切片) | 不可变 UTF-8 字符串 |
| `Bytes` | 任意二进制数据 | `0x48656C6C6F` | `[]u8` | 与 `String` 明确区分 |
| `Char` | Unicode 标量值 | `'A'`, `'\n'` | u32 | Unicode 标量值 |
| `Regex` | 编译后正则 | `r"[0-9]+"` | 内部编译表示 | 编译期验证 |
| `Duration` | 纳秒精度时间段 | `5s`, `100ms`, `2h` | i64 (纳秒) | 时间跨度 |
| `Unit` | 零宽度类型 | 无（编译器隐式值） | void | 无返回值标记，不可作为参数类型 |
| `Path` | 文件系统路径 | `p"/tmp/foo"`, `p"./foo"` | `[]u8` | 与 `String` 语义区分 |

### 类型详述

#### `Int`

- 固定 64 位有符号整数，补码表示
- 四则运算溢出为运行时 Panic（`debug` 模式检测，`release` 模式可关闭检查）。注意：关闭检查后溢出行为为静默回绕（wraparound），与 i64 的补码表示一致。这是否属于"运行时类型错误"的争议——溢出是值域问题而非类型问题，不影响类型系统关于"消除运行时类型不匹配错误"的保证
- 字面量支持十进制、十六进制 `0x`、八进制 `0o`、二进制 `0b`，以及下划线分隔 `1_000_000`
- 支持操作：`+`, `-`, `*`, `/` (截断除法), `%` (模), `neg`, `abs`
- 比较操作返回 `Bool`：`==`, `/=`, `<`, `>`, `<=`, `>=`

#### `Float`

- IEEE 754 双精度浮点数
- 支持操作：`+`, `-`, `*`, `/`, `neg`, `abs`, `floor`, `ceil`, `round`, `sqrt`
- 与 `Int` 的混合运算需显式转换：`toFloat`, `toInt`

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
- 支持操作：`match : Regex -> String -> ?String`、`matchAll : Regex -> String -> List String`、`contains : Regex -> String -> Bool`、`split : Regex -> String -> List String`、`replace : Regex -> String -> String -> String`、`replaceAll : Regex -> String -> String -> String`
- 捕获组支持：`captures : Regex -> String -> ?(List (?String))`（返回所有捕获组，每组可能为 null）

#### `Duration`

- 表示纳秒精度的时间段
- 运行时表示为 i64（纳秒数）
- 字面量：`5s`, `100ms`, `2h`, `30m`, `1d`, `500us`, `200ns`
- 支持操作：`+`, `-`, 比较, `toSecs`, `toMillis`, `toNanos`
- 可与 `Int` 进行标量乘除：`5s * 3`

#### `Unit`

- 零宽度类型（运行时 0 字节，等价 C `void`）
- **无程序员可访问的字面量**——编译器在需要 `Unit` 值的位置插入唯一的隐式值
- 仅用作**返回类型**（`T -> Unit`，标记无有意义返回值），**不可作为参数类型**
- 对应 C 的 `void`
- 泛型实例化中 `b = Unit` 时，编译器隐式填充唯一值；`Result Unit E` 的 `Ok` 变体由编译器隐式产生载荷

#### 零参函数类型 `-> T`

零参函数类型 `-> T` 表示不接受任何参数、返回类型 `T` 的函数：

```kun
-> DateTime          // 零参函数，返回 DateTime
-> Result Path Error  // 零参函数，返回 Result
```

规则：
- `-> T` 与 `a -> T` 是**不同元数的函数类型**——HM 合一时元数必须相同，否则合一失败
- 零参函数**仅允许用于 IO 效应函数**（函数体含 `do` 块）。纯零参函数退化为常量，应使用 `let` 绑定
- 对应的 Lambda 语法为 `\ -> expr`
- 调用零参函数时裸名即为调用：`Time.now`（不可传参）

```kun
now : -> DateTime
now = \ ->
  do
    Time.now

getPid : -> Pid
getPid = \ ->
  do
    Process.pid
```

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

### 效应跟踪

Kun 采用 AST 标记方案替代 `IO T` 类型包装器：

- 含 `do` 块的函数自动标记为效应函数
- 以下命名空间的所有函数均为效应函数：`Cmd.*`、`IO.*`、`File.*`、`Env.*`、`Process.*`、`Time.*`、`Signal.*`、`Sys.*`、`TempFile.*`
- 纯函数（无 `do` 块）不能调用效应函数——编译期拒绝
- 效应性不扩散到类型签名——函数签名中不出现 `IO` 标记
- Lambda 含有效应函数调用时，该 lambda 必须在 `do` 块内定义

## 类型等价与类型关系

### 等价规则

类型等价基于结构等价（Structural Equivalence）：

- 两个类型当且仅当其结构完全相同时被视为等价
- 名称别名（在导入时指定的别名）展开后参与比较
- 泛型类型在应用相同类型参数后结构等价

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

### 显式类型转换

跨类型转换必须通过显式内置函数：

| 转换 | 函数 | 安全性 |
|------|------|--------|
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
|---|---|
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

Record 类型的合一是结构化的：两个 Record 类型当且仅当字段名集合相同且对应字段类型可合一时才可合一。

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
| 0.3.0 | 移除 `Nat`、`IO T` 效应类型、幻影类型、扩展积类型（`{ Base \| field : T }`）；效应跟踪改为 AST 标记方案 |
| 0.2.1 | 扩展积类型 `{ Base \| field : T }`，移除行变量以降低类型检查器实现复杂度 |
| 0.2.0 | Nilable 类型 `?T` 替代 `Maybe`，新增 `?.` 可选链和 `??` Nil 合并操作符 |
| 0.1.0 | MVP 基础类型 + `Maybe`/`Result` + HM 推断 + 简单参数化多态 + `IO` 效应标记 |

## 参考

- [应用概览](app-overview.md) — Kun 语言功能全景
- [功能清单](feature-inventory.md) — 功能实现状态追踪
- [系统基线](../architecture/system-baseline.md) — 运行时与类型系统概览
- [模块边界](../architecture/module-boundaries.md) — 类型检查器在架构中的位置
