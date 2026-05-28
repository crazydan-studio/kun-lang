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

所有完整应用的类型构造器（如 `List<Int>`、`Maybe<String>`）归约到种类 `Type`。

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
| `Regex` | 编译后正则 | `` regex`[0-9]+` `` | 内部编译表示 | 编译期验证 |
| `Duration` | 纳秒精度时间段 | `5s`, `100ms`, `2h` | i64 (纳秒) | 时间跨度 |
| `Unit` | 单元类型 | `()` | void | 表示无返回值 |
| `Path` | 文件系统路径 | `path"/tmp/foo"`, `."/foo"` | `[]u8` | 与 `String` 语义区分 |

### 类型详述

#### `Int`

- 固定 64 位有符号整数，补码表示
- 四则运算溢出为运行时 Panic（`debug` 模式检测，`release` 模式可关闭检查）
- 字面量支持十进制、十六进制 `0x`、八进制 `0o`、二进制 `0b`
- 支持操作：`+`, `-`, `*`, `/` (截断除法), `%` (模), `neg`, `abs`
- 比较操作返回 `Bool`：`==`, `!=`, `<`, `>`, `<=`, `>=`

#### `Nat`

- 非负整数，值域 `0 .. 2^63-1`
- 与 `Int` **无子类型关系**，是独立类型
- 字面量后缀 `u` 区分：`42` 为 `Int`，`42u` 为 `Nat`
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
- 使用双引号 `"..."`，支持转义序列

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
- 字面量使用反引号包裹并以 `regex` 前缀标记：`` regex`[0-9]+` ``
- 修饰符通过 **PCRE 内联语法**嵌入到模式中：

  ```
  regex`(?i)[a-z]+`       -- 忽略大小写
  regex`(?m)^foo`         -- 多行模式（^/$ 匹配行边界）
  regex`(?s).+`           -- DotAll（. 匹配换行符）
  regex`(?u)\w+`          -- Unicode 模式
  regex`(?im)[a-z]+`      -- 多标志组合：忽略大小写 + 多行
  regex`(?i-m)[a-z]+`     -- 开启 i，关闭 m
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
- 支持操作：`match : Regex -> String -> Maybe<String>`、`matchAll : Regex -> String -> List<String>`、`contains : Regex -> String -> Bool`、`split : Regex -> String -> List<String>`、`replace : Regex -> String -> String -> String`、`replaceAll : Regex -> String -> String -> String`
- 捕获组支持：`captures : Regex -> String -> Maybe<List<Maybe<String>>>`（返回所有捕获组，每组可能为 null）

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
- 字面量使用 `path` 前缀：`path"/tmp/foo"`、`path"./foo"`
- 支持操作：`join : Path -> Path -> Path`、`parent : Path -> Path`、`filename : Path -> String`、`extension : Path -> String`、`exists : Path -> Bool`
- 支持 `.` 操作符：`path"/tmp".join("foo")`

### Path 与文件类型

`Path` 是**不透明类型**，不内嵌文件类型信息。文件类型（`FileType`）是运行时属性，由 `stat` 系统调用确定，且可能在检查和使用的间隙发生变化（TOCTOU 问题）。`FileType`、`IOError` 等关联类型由[标准库](standard-library.md)定义。

```kun
-- 路径操作是纯字符串语义，不依赖文件类型
p = path"/tmp/foo"
parent = p.parent()
name   = p.filename()
ext    = p.extension()
```

运行时查询函数：

```
fileType : Path -> IO<Result<FileType, IOError>>
```

使用场景：

```kun
case fileType(p) of
  Ok RegularFile -> readFile(p)
  Ok Directory   -> listDir(p)
  Ok _           -> fail("不支持的输入类型")
  Err err        -> fail("无法访问: " ++ err)
```

命令签名系统（CDF）可在参数级别标注预期文件类型，在运行时验证而非类型系统撒谎：

```
-- CDF 声明示例
readFile : Path -> IO<String>       -- 运行时检查参数为 RegularFile
listDir  : Path -> IO<List<Path>>    -- 运行时检查参数为 Directory
```

设计依据：

1. **路径操作本质是字符串操作**——`join`、`parent`、`extension` 等不依赖文件类型，强加类型标签反而让这些纯操作为难
2. **文件类型是运行时属性**——类型系统无法静态保证 `stat` 调用结果在后续操作中仍然有效
3. **TOCTOU 固有风险**——即便在检查点获取了类型，也不能阻止竞态条件下路径被替换，兜底运行时检查不可避免
4. **命令兼容性**——`rm`、`chmod`、`ls`、`mv` 等命令大多接受所有文件类型，强制穷举匹配不符实用主义原则

## 复合类型

### `List<T>`

- 不可变顺序序列，支持索引访问和模式匹配解构
- 运行时使用 **Rope（绳索）** 作为底层数据结构，支持高效的拼接、切片和索引访问
- 字面量：`[1, 2, 3]`
- 索引访问：`list[i]` 返回 `Maybe<T>`（越界时返回 `None`）
- 模式匹配支持空列表 `[]` 和 `head :: tail` 解构
- 支持操作：`length`, `isEmpty`, `head`, `tail`, `map`, `filter`, `fold`, `reduce`, `append`, `reverse`, `take`, `drop`, `slice`

#### List 与 Array 合并的设计决策

Kun 不提供独立的 `Array<T>` 类型，有序序列由 `List<T>`（Rope 实现）统一表达。

**合并动机：**

1. **单一概念**：用户只需记住"有序序列 = List"，无需在不同序列类型间选择和转换
2. **Rope 兼具两端优势**：Rope（平衡二叉树）作为底层实现，兼顾 O(log n) 索引访问和 O(log n) 拼接/切片，同时保持模式匹配所需的头尾解构能力
3. **消除转换摩擦**：无 `toList`/`fromArray` 转换，所有序列操作在同一类型上链式完成

**未采用独立 Array 的理由：**

| 维度 | 独立 Array | Rope List |
|------|-----------|-----------|
| 索引访问 | O(1) | O(log n) |
| 内存密度 | 连续，零开销 | 树节点，每元素 ~2 指针开销 |
| 缓存友好性 | 顺序遍历缓存友好 | 节点跳转 |
| C ABI 兼容 | 天然 `*T + len` | 需序列化为连续 buffer |

这些差异在运行时层是可管理的：List 在需要 C ABI 传递时由运行时**透明地摊平**为连续 buffer，无需暴露为独立类型。脚本语言的优先级是概念简洁，而非微基准。

如果未来确实需要连续内存语义（如 mmap 映射文件为元素数组），可通过 `List` 的特化视图（如 `MappedList<T>`）在运行时层处理，不引入新类型。

**参考：** Python 同样仅暴露单一的 `list` 类型（动态数组），且在大数据量场景（如 `numpy`）使用库级特化而非语言内置新类型。

### `Map<K, V>`

- 不可变平衡树映射（`K` 需支持 `Ord` 约束）
- 字面量：`#{ "name" => "Kun", "version" => "0.1" }`
- 支持操作：`get`, `insert`, `remove`, `contains`, `keys`, `values`, `map`, `fold`, `merge`, `size`, `isEmpty`
- 模式匹配支持基于键的模式

### `Set<T>`

- 不可变集合，元素唯一且无序
- 字面量：`#[1, 2, 3]`
- 支持操作：`insert`, `remove`, `contains`, `size`, `isEmpty`, `toList`, `union`, `intersect`, `diff`
- 元素类型需支持相等比较（内建 `Eq`，由运行时内置而非类型系统表达）

### `Stream<T>`

- 惰性求值序列
- 通过 `stream` 表达式创建，或从文件/网络资源构造
- 支持惰性操作：`map`, `filter`, `take`, `drop`, `fold`
- 支持 mmap 和分块读取大文件
- 非阻塞 IO 操作返回带 `IO` 效应的 `Stream`

### `Tuple`

- 异质、定长序列
- 字面量：`(1, "hello", true)`
- 类型：`(Int, String, Bool)`
- 模式匹配解构：`let (x, y, z) = tuple`
- 索引访问：`tuple.0`, `tuple.1`

## 积类型（Product Types）

### Record

- 具名字段的积类型
- 字面量：`{ name = "Kun", version = "0.1" }`
- 类型：`{ name : String, version : String }`
- 字段访问：`record.name`
- 更新语法（不可变）：`{ record | version = "0.2" }`
- 模式匹配解构：

  ```
  let { name, version } = record
  ```

## 和类型 / ADT

### 自定义和类型

声明语法（借鉴 Elm）：

```
type Color
  = Red
  | Green
  | Blue
  | Rgb { r : Int, g : Int, b : Int }
```

- 每个变体可携带 0 个或多个字段
- 变体名称必须以大写字母开头
- 变体字段可以是无名（元组风格）或具名（Record 风格）

### 内建和类型

#### `Maybe<T>`

```
type Maybe<T>
  = Just T
  | None
```

- 表示值可能存在或不存在
- 典型用法：安全索引、查找操作、可能失败但不需错误信息的操作

#### `Result<T, E>`

```
type Result<T, E>
  = Ok T
  | Err E
```

- 表示操作可能成功（`Ok`）或失败（`Err`）
- 错误类型 `E` 通常为 `String` 或自定义错误类型
- 支持 `?` 操作符自动解包 `Ok` 并传播 `Err`（早返回）

### 穷举检查

- 对和类型的模式匹配必须覆盖所有变体
- 编译器静态检查穷举性
- 可使用 `_` 通配分支覆盖剩余变体
- 当新增变体时，所有已有匹配将触发编译期穷举检查错误，确保代码同步更新

## 函数类型

### 函数类型签名

```
(T1, T2, ...) -> T
```

- `T1, T2, ...` 为参数类型（多个参数用逗号分隔）
- `T` 为返回类型
- 无参数函数：`() -> T`

### 纯函数与命令函数

#### 纯函数

- 无副作用，返回值仅由参数决定
- 模式匹配和递归是主要控制流
- 类型签名：`(Int) -> Int`

#### 命令函数

- 对 Linux 命令的函数式抽象
- 具有确定的参数签名和输出类型
- 类型签名包含命令的精确参数信息（由 CDF 或自动推断提供）
- 执行命令隐含 IO 效应（见下节）

#### 高阶函数

- 函数可作为参数传递和作为返回值
- 内置高阶函数：`map : (a -> b) -> List<a> -> List<b>`
- 支持匿名函数（Lambda）：

  ```
  list |> map (\x -> x * 2)
  ```

### 闭包捕获

- 闭包通过值捕获外部变量（不可变引用）
- 捕获值在闭包创建时冻结
- 闭包类型携带捕获环境的信息

## 类型推断

### 算法

采用 **Hindley-Milner（算法 W）** 作为类型推断核心：

- 基于约束生成与合一（Unification）
- 全程序推断，用户无需为局部变量提供类型标注
- 顶层函数建议标注类型签名（可选，但作为公开 API 建议标注）

### Let-多态

```
identity = \x -> x
-- identity : a -> a

n = identity 42       -- n : Int
s = identity "hello"  -- s : String
```

- `let` 绑定引入的泛型表达式可针对每次使用实例化不同的类型
- 实现了参数化多态而不要求用户显式编写类型签名

### 标注语法

```
add : (Int, Int) -> Int
add = \(x, y) -> x + y
```

- 类型标注在函数名后以 `:` 引导
- 类型标注与实现分离（与 Parser 解析顺序相适应）
- 编译器会验证标注与实现的一致性

## 模式匹配类型规则

### 可反驳性

| 模式类型 | 可反驳性 | 示例 |
|---------|---------|------|
| 字面量模式 | 可反驳 | `0`, `true`, `"hello"` |
| 通配模式 | 不可反驳 | `_` |
| 变量绑定 | 不可反驳 | `x` |
| 变体模式 | 可反驳 | `Just x`, `Ok v` |
| List 模式 | 可反驳 | `[]`, `x :: xs` |

### 穷举性规则

1. 对自定义和类型（包括 `Maybe`、`Result`）：所有变体必须被覆盖
2. 对 `Bool`：`true` 和 `false` 必须同时覆盖
3. 对 `List`：`[]` 和 `x :: xs` 建议覆盖（缺少时编译器发出 warning）
4. 通配模式 `_` 可替代任何未列举的变体
5. 守卫子句（`when` 条件）不影响穷举性判断

### 类型收窄

在模式匹配的每个分支中，模式变量具有更精确的类型：

```
parse : String -> Result<Int, String>

case parse("42") of
  Ok n  -> -- 此处 n : Int
  Err _ -> -- 此处错误信息已知
```

## 泛型

### 简单参数化多态

Kun 采用无约束的参数化多态（类似 Elm，无 Typeclass/Trait）：

```
identity : a -> a
identity = \x -> x

map : (a -> b) -> List<a> -> List<b>
map = \f, list -> ...
```

- 类型变量 `a`, `b`, `c` 等由类型推断自动推导
- 隐式全称量化：`identity : a -> a` 等价于 `identity : forall a . a -> a`
- 无类型约束机制（无 Typeclass、无 Trait、无接口）

### 限制

- 泛型参数的使用受限：只能作为值传递、存储、返回
- 不能对泛型参数执行类型特定操作（无 `show`、无 `eq` 等）
- `Map<K, V>` 的 `K` 要求 `Ord` 约束，`Set<T>` 的 `T` 要求 `Eq` 约束——但这些由**运行时内置**提供而非类型系统表达。编译器生成对这些内置操作的调用，不涉及类型级约束求解。这是"无约束泛型"原则的例外边界：内置容器类型享有特权，用户定义类型不可自定义约束
- 此设计的权衡：表达力降低但实现简洁、推断稳定、错误消息清晰

## 效应类型

### IO 效应

Kun 在类型系统中标记副作用边界：

```
-- 纯函数
add : (Int, Int) -> Int

-- 有 IO 效应的函数
readFile : Path -> IO<String>

-- 组合
main : IO<Unit>
main = do
  content <- readFile(path"/tmp/foo")
  print(content)
```

### 效应传播规则

1. 调用任何带 `IO` 效应的函数，调用者自动获得 `IO` 效应
2. 纯函数不能调用标记 `IO` 的函数
3. `do` 表达式用于按顺序组合 IO 操作
4. 惰性求值与 IO 的交互：`Stream<T>` 的构造和消费分别标记 IO 边界

### 与能力安全的关系

- 类型系统仅回答"是否有副作用"（IO 边界标记）
- 能力安全系统回答"允许哪些具体的副作用"（文件 / 网络 / 进程等）
- 两套机制互补：类型系统在编译期确保正确性，能力系统在运行时控制权限

## 类型等价与类型关系

### 等价规则

类型等价基于结构等价（Structural Equivalence）：

- 两个类型当且仅当其结构完全相同时被视为等价
- 名称别名（type alias）展开后参与比较
- 泛型类型在应用相同类型参数后结构等价

### 无子类型

Kun 类型系统**不包含子类型关系**：

- `Nat` 与 `Int` 为独立类型，无隐式转换
- `List<Nat>` 与 `List<Int>` 为不同类型
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
  ┌─ script.ku:12:5
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
