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
let x : ?String = ...

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
- 支持操作：`++` (拼接), `length`, `slice`, `contains`, `startsWith`, `endsWith`, `split`, `join`, `trim`, `toUpper`, `toLower`, `replace`
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

### 行多态（Row Polymorphism）

Kun 通过**行多态**实现 Record 类型的泛化，允许函数接受"至少包含某些字段"的 Record。行多态不是子类型——它是参数化多态在 Record 字段上的应用。

#### 基本语法

```kun
getName : { a | name : String } -> String
getName = \{ name } ->
  name

// 调用：接受任何包含 name: String 的 Record
getName { name = "Kun" }                    // → "Kun"
getName { name = "Kun", version = "0.1" }   // → "Kun"
```

`{ a | name : String }` 读作"一个 Record 类型，包含 `name : String` 字段，剩余字段的类型变量为 `a`"。

#### 与无子类型原则的关系

| 维度 | 子类型 | 行多态 |
|------|--------|--------|
| 机制 | 隐式向上转型 | 类型变量替换 |
| 安全性 | 协变/逆变问题 | 类型安全，无变体问题 |
| 推断 | 需单独的子类型约束求解 | 标准合一扩展 |
| 运行时 | 可能需要类型擦除/装箱 | 零开销 |

行多态通过类型变量在调用点被具体类型替换，是编译期的精确匹配——而非隐式向上转型。因此行多态不与"无子类型"原则冲突。

#### 扩展积类型

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
- 基类型必须是有名 Record 类型（`type T = { ... }`），不可为行变量
- 字段名冲突时扩展字段覆盖基类型字段
- 不支持多继承

#### 与 Record 更新的交互

行多态保证输入 Record 的剩余字段类型不变地传递到输出：

```kun
updateName : { a | name : String } -> { a | name : String }
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
| 字段访问 `.name` | `τ_record = { name: τ_res \| a }`，引入行变量 |
| Record 更新 `{ r \| f = v }` | `τ_input = { f: τ_val \| a }` 且 `τ_output = { f: τ_val \| a }`，行变量贯穿 |

### 阶段 2: 合一

标准 Martelli-Montanari 合一算法，扩展支持**行合一**（row unification）：

1. 从约束集中取一条等式 `τ₁ = τ₂`
2. 应用当前替换到 `τ₁` 和 `τ₂`
3. 尝试合一化简后的类型
4. 发生冲突 → 生成类型错误报告
5. 成功 → 将新替换加入到全局替换
6. 重复直到约束集为空

行合一是标准合一的扩展，处理 Record 类型与行变量的合一：

```kun
// 调用 getName : { a | name : String } -> String
getName { name = "Kun", version = "0.1" }

// 生成约束：{ a | name : String } = { name : String, version : String }
// 行合一后：a = { version : String }
```

行合一的核心规则：

| 左侧类型 | 右侧类型 | 合一结果 |
|---------|---------|---------|
| `{ f: τ_f \| a }` | `{ f: τ_f, g: τ_g \| b }` | `a = { g: τ_g \| b }`（提取匹配字段，剩余归入行变量） |
| `{ f: τ_1 \| a }` | `{ f: τ_2 \| b }` | 先合一 `τ_1 = τ_2`，再合一 `a = b` |
| `{ \| a }`（空） | 任意 Record | `a =` 该 Record 类型 |
| `{ \| a }` | `{ \| b }` | `a = b` |

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
| 0.3.0 | 行多态：行变量、行合一、`{ a \| name : String }` 语法、扩展积类型 `{ Base \| field : T }` |
| 0.2.0 | Nilable 类型 `?T` 替代 `Maybe`，新增 `?.` 可选链和 `??` Nil 合并操作符 |
| 0.1.0 | MVP 基础类型 + `Maybe`/`Result` + HM 推断 + 简单参数化多态 + `IO` 效应标记 |

## 参考

- [应用概览](app-overview.md) — Kun 语言功能全景
- [功能清单](feature-inventory.md) — 功能实现状态追踪
- [系统基线](../architecture/system-baseline.md) — 运行时与类型系统概览
- [模块边界](../architecture/module-boundaries.md) — 类型检查器在架构中的位置
