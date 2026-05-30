# 类型系统设计

## 设计目标与原则

### 核心目标

Kun 的类型系统服务于一门面向 Linux 的函数式脚本语言。其设计围绕以下目标展开：

- **类型安全**：所有类型检查在编译期完成，消除运行时类型错误
- **推断优先**：用户无需为局部变量和绝大多数函数参数提供类型标注
- **实用至上**：为脚本场景做务实取舍，不追求理论完备性
- **显式错误**：通过和类型（`Result`、`Maybe`）将错误处理纳入类型系统，禁止隐式异常
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
| `Type -> Type` | 类型构造器（接受一个类型参数返回具体类型） | `List`、`Maybe`、`Set` |

所有完整应用的类型构造器（如 `List Int`、`Maybe String`）归约到种类 `Type`。

### 类型分类

```
Type Universe
├── Base Types         (Int, Nat, Float, Bool, String, Bytes, Char, Regex, Duration, Unit, Path)
├── Compound Types     (List, Map, Set, Stream, Tuple)
├── Product Types      (Record/Tuple)
├── Sum Types / ADTs   (custom sum types, Maybe, Result)
├── Function Types     (pure functions, command functions)
├── Effect Types       (IO)
└── Type Variables     (a, b, etc. — for generics)
```

```plantuml
@file:../diagrams/type-system-hierarchy.puml
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
- 四则运算溢出为运行时 Panic（`debug` 模式检测，`release` 模式可关闭检查）
- 字面量支持十进制、十六进制 `0x`、八进制 `0o`、二进制 `0b`，以及下划线分隔 `1_000_000`
- 支持操作：`+`, `-`, `*`, `/` (截断除法), `%` (模), `neg`, `abs`
- 比较操作返回 `Bool`：`==`, `!=`, `<`, `>`, `<=`, `>=`

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

  ```
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
- 支持操作：`match : Regex -> String -> Maybe String`、`matchAll : Regex -> String -> List String`、`contains : Regex -> String -> Bool`、`split : Regex -> String -> List String`、`replace : Regex -> String -> String -> String`、`replaceAll : Regex -> String -> String -> String`
- 捕获组支持：`captures : Regex -> String -> Maybe (List (Maybe String))`（返回所有捕获组，每组可能为 null）

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

```
// 路径操作是纯字符串语义，不依赖文件类型
p = p"/tmp/foo"
```

运行时查询函数：

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

#### 语法说明：为何 `IO t` 与和类型使用相同语法

`IO t` 与 `Maybe t`、`Result t e` 在类型标注中均写作 `Identifier args` 形式，但二者属不同类型分类：

```
Effect Types:     IO t           — 效应包装，标记副作用边界
Sum Types / ADTs: Maybe t        — 和类型，表达值可能落于多个变体之一
```

关键区别：

| 维度 | `Maybe t`（和类型） | `IO t`（效应类型） |
|------|---------------------|-------------------|
| 变体 | `Just t` / `None` 两个变体 | 无用户可见变体，单一包装 |
| 构造 | 用户显式调用 `Just x` / `None` | 由带副作用的函数返回类型隐式引入 |
| 语义 | "值可能是 x 或不存在" | "此操作有副作用，结果类型为 t" |

**选择相同语法的依据：**

1. **简化类型标注**——`IO String` 比引入一套全新效应标记语法（如 `String ! IO` 或 `String +IO`）更直观
2. **效应类型极简**——Kun 不做完整代数效应系统，`IO t` 只是一个"副作用边界标记"，不涉及效应多态或效应处理器
3. **Haskell 先例**——Haskell 的 `IO String` 与 `Maybe String` 写法完全一致

### 效应传播规则

1. 调用任何带 `IO` 效应的函数，调用者自动获得 `IO` 效应
2. 纯函数不能调用标记 `IO` 的函数
3. `do` 表达式用于按顺序组合 IO 操作
4. IO Stream 的构造和消费分别标记 IO 边界：`<-` 解包获得 `Stream t`，消费时逐元素按需执行

### 与能力安全的关系

- 类型系统仅回答"是否有副作用"（IO 边界标记）
- 能力安全系统回答"允许哪些具体的副作用"（文件 / 网络 / 进程等）
- 两套机制互补：类型系统在编译期确保正确性，能力系统在运行时控制权限

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

```plantuml
@file:../diagrams/type-checking-flow.puml
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

### 阶段 2: 合一

标准 Martelli-Montanari 合一算法：

1. 从约束集中取一条等式 `τ₁ = τ₂`
2. 应用当前替换到 `τ₁` 和 `τ₂`
3. 尝试合一化简后的类型
4. 发生冲突 → 生成类型错误报告
5. 成功 → 将新替换加入到全局替换
6. 重复直到约束集为空

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

  ```
  struct Maybe_Int {
    uint8_t tag;       // 0 = None, 1 = Just
    int64_t value;     // 仅 tag==1 时有意义
  };
  ```

### 与 dlopen 的对齐

- 函数参数的传递使用 C ABI 兼容的结构体
- ADT 变体标记使用 `uint8_t`
- 字符串使用 `{ ptr : *u8, len : usize }` 切片表示

## 版本与演进

| 版本 | 变更 |
|------|------|
| 0.1.0 | MVP 基础类型 + `Maybe`/`Result` + HM 推断 + 简单参数化多态 + `IO` 效应标记 |

## 参考

- [应用概览](app-overview.md) — Kun 语言功能全景
- [功能清单](feature-inventory.md) — 功能实现状态追踪
- [系统基线](../architecture/system-baseline.md) — 运行时与类型系统概览
- [模块边界](../architecture/module-boundaries.md) — 类型检查器在架构中的位置
