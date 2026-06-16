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
| `Type -> Type` | 类型构造器（接受一个类型参数返回具体类型） | `List`、`Set`、`Stream` |
| `Map` | `Type -> Type -> Type` | 接收键类型和值类型，返回具体字典类型 |

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

├── Standard Library Types (compiler-supported)
│   ├── Decimal    (mantissa + exponent)
│   ├── Command    (opaque, Cmd.\<bin\>)
│   └── DateTime   (Int newtype)
```

> `DateTime`、`Decimal`、`Command` 为标准库类型——由编译器提供 TypeEnv 变体和运行时表示支持，但非语言内置基础类型。`DateTime` 为 `Int` 的 newtype，`Decimal` 为尾数+指数二元组，`Command` 为不透明值。

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
| 嵌套 `? ?T` | **编译期报错**。`Nil` 已表示"不存在"，嵌套 Nilable 不增加表达能力——`? ?T` 的取值空间与 `?T` 完全相同（值级折叠）。`Nil` 字面量在 `? ?T` 上下文中不可区分"外层 Nil"与"外层存在但内层 Nil" |

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
  s   -> s             // 此分支 s 收窄为非 Nil 的 String（安全）

if x /= Nil then
  String.length x         // 此分支 x 收窄为非 Nil 的 String（安全）
```

#### 表达式 scrutinee 收窄

`case` 的 scrutinee 可以是任意表达式（非仅变量）。编译器对表达式 scrutinee 引入隐式临时绑定：

```kun
case someFunc() of          // someFunc : -> ?String
  Nil -> "absent"
  s   -> String.length s    // s 收窄为 String
```

收窄作用于模式绑定的变量——`Nil` 分支中无绑定，`s` 分支中 `s` 的类型收窄为 `String`。每个分支对 scrutinee 的求值次数为一次（编译器插入临时绑定保证）。

#### 复合模式收窄

元组和 Record 模式中，每个子模式独立收窄：

```kun
case (x, y) of              // x : ?Int, y : ?String
  (Nil, Nil) -> "both absent"
  (a, Nil)   -> Int.neg a   // a : Int（收窄），第二项仍为 Nil
  (Nil, b)   -> b           // b : String（收窄），第一项为 Nil
  (a, b)     ->             // a : Int, b : String（均收窄）
    Int.toString a ++ b
```

规则：
- 元组模式 `(p1, p2, ...)`：每个位置根据该位置的值类型独立收窄。`Nil` 子模式收窄对应位置为 `Nil`；变量子模式在非 `Nil` 分支中收窄为 `T`
- Record 模式 `{f1 = p1, f2 = p2, ...}`：每个字段根据其子模式独立收窄，规则同元组
- 守卫子句中的变量类型为 scrutinee 原始类型（不收窄）

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
| `Path` | 文件系统路径（不保证 UTF-8） | `p"/tmp/foo"`, `p"./foo"` | `[]u8` | 与 `String` 语义区分；内部可为任意非 NUL 字节 |

### 类型详述

#### `Int`

- 固定 64 位有符号整数（i64），补码表示。字面量支持十进制、`0x`、`0o`、`0b` 及 `_` 分隔
- `Int` 的四则运算（`+`/`-`/`*`/`/`）在安全模式（Debug/ReleaseSafe）下溢出时 panic。ReleaseFast 和 ReleaseSmall 模式下溢出检测关闭——行为为 Zig 的默认行为（二进制补码回绕，wrapping）。需要精确溢出控制的代码使用 wrapping 运算符（`+%`、`-%`、`*%` 等，wrapping 语义）或将操作数提升为 `Float` 后计算再截断。若后续引入饱和运算需求，可在标准库中补充 `Int.saturatingAdd` 等函数。

`Int` 除零（`x / 0` 或 `x % 0`）在任何构建模式下均为 panic——不可通过模式关闭。`Float` 除零返回 `±Infinity` 或 `NaN`（见上方特殊浮点值表）。

#### `Float`

- IEEE 754 双精度浮点数（f64）。与 `Int` 混合运算需显式转换
- 操作函数及容差比较见 [`Float` 模块](standard-library.md#float-浮点操作)

#### 特殊浮点值

`Float` 遵循 IEEE 754 语义：

| 值 | 产生方式 | 行为 |
|----|---------|------|
| `NaN` | `0.0 / 0.0`、`sqrt(-1.0)` | 通过所有操作传播；`NaN == NaN` 始终为 `false`（IEEE 754 规定）；使用 `approxEqual` 检测 NaN 参数时返回 `false`；`toString NaN` → `"NaN"` |
| `+Infinity` | `1.0 / 0.0` | `Infinity + 1.0` → `Infinity`；`toString Infinity` → `"Infinity"` |
| `-Infinity` | `-1.0 / 0.0` | 同理；`toString -Infinity` → `"-Infinity"` |
| `0.0` / `-0.0` | 正零和负零 | `-0.0 == 0.0` 为 `true`（IEEE 754）；`toString` 均为 `"0.0"` |

**精度局限**：二进制浮点无法精确表示大多数十进制小数（如 `0.1` + `0.2` ≠ `0.3`）。Kun 从两个层面缓解：

1. `toString` 输出时默认舍入到 15 位有效数字，消除显示噪音
2. `Float.approxEqual` 提供容差比较，避免直接用 `==` 比较浮点值

需要精确十进制计算的场景应使用标准库 [`Decimal` 类型](standard-library.md#decimal-十进制精确数值)。

#### `Bool`

- 仅两个值：`true`、`false`。支持 `&&`、`||`、`not`，前两者短路求值

#### `String`

- 不可变 UTF-8 编码文本。操作函数见 [`String` 模块](standard-library.md#string-字符串操作)
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

### 复合类型

#### `List t`

不可变同质列表，运行时表示为 `{ptr, len, cap}` 数组。元素类型必须一致。

#### `Map k v`

不可变键值字典。键类型必须可哈希（`Int`、`String`、`Bool`、`Char`、`Path`、`Duration`）。运行时表示为开地址哈希表。

#### `Set t`

不可变无序集合。元素类型同 `Map` 的键类型约束——必须可哈希。

#### `Stream t`

惰性序列。元素按需拉取，运行时表示为 Zig tagged union（`cmd`/`mapped`/`filtered`/`taken`/`dropped`/`lines`/`parse_mapped`/`parse_mapped_keep`）。`Stream` 的消费必须在创建其的 Arena 销毁前完成——编译器对未被消费的 `Stream` 进行流敏感检测。

#### `Command`

`Cmd.<bin>` 构造的延迟执行值。`Command` 为不透明类型——编译器内置，不可用 Kun 代码构造。`Cmd.exec : Command -> Unit` 显式执行并丢弃输出；`|>` 管道左侧为 `Command` 时隐式触发执行，输出 `Stream String`；`?` 后缀立即执行，返回 `Result (Stream String) CommandError`。未被消费的 `Command` 值是编译错误。

## 效应跟踪

> **编译器内置**：效应跟踪通过编译器 AST 标记 + 类型签名中的 `!` 标注实现。`do` 块和效应命名空间（`Cmd.*`、`IO.*` 等）由编译器直接识别和处理。

### 效应函数自动推断

Kun 通过 AST 扫描自动推断函数的效应性：

- 含 `do` 块的函数自动标记为效应函数
- 以下命名空间的所有函数均为效应函数：`IO.*`、`File.*`、`Env.*`、`Process.*`、`Sys.*`、`Task.*`、`Random.*`；`Signal.on` 为效应函数（`Signal` 模块其余函数为纯函数）
- `Cmd.<bin>` 构造 `Command` 值及 `Cmd` 装饰函数（`Cmd.pipe`、`Cmd.withEnv` 等，接收并返回 `Command`）为纯操作，可在 `do` 块外使用
- `Cmd.<bin>?`、`Cmd.pipe?`、`Cmd.timeout`、`Cmd.retry`、`Cmd.execSafe`、`Cmd.stdoutToString`、`Cmd.stderrToString`（立即执行并返回 `Result`）为效应函数
- `Cmd.exec : Command -> Unit` 执行 Command 值，为效应函数
- `Cmd.which : String -> ?Path` PATH 查找，为效应函数
- 纯函数（无 `do` 块、无 `!` 参数声明）不能调用效应函数——编译期拒绝。`(a -> b)!` 参数使函数自身成为效应函数。
- 函数名不添加效应标记，效应性由编译器推断、文档生成（`kun doc`）和 IDE/LSP 提供可见性

> **注**：在 MVP（v0.1）中，下列命名空间/函数虽被效应检查器识别，但无运行时实现：`Sys.ps`、`Sys.free`、`Sys.df`、`Task.*`、`Random.*`、`Signal.on`、`Cmd.timeout`、`Cmd.retry`、`Cmd.withRunAs`。效应检查器对它们的守卫不影响编译——调用这些函数在 MVP 中因 Primitive 表无绑定而报"未定义函数"错误。后续版本中逐一激活。

### 效应回调标记 `!`

在函数类型签名中，`(a -> b)!` 标注**效应回调参数**——该参数**必须是**效应函数，不能传入纯函数：

```kun
// iter 的回调参数标注为效应回调
iter : (a -> Unit)! -> List a -> Unit

// 调用时：传入效应函数
do
  List.iter IO.println files       // ✅ IO.println 是效应函数

// 传入纯函数 → 编译错误
purePrint = \s -> ()              // 纯函数
List.iter purePrint files          // ❌ 编译错误：期望效应函数，传入了纯函数
```

`!` 标注的规则：

| 规则 | 说明 |
|------|------|
| `!` 位置 | `!` 紧跟在被标注的**函数类型参数**之后：`(a -> b)!` |
| 回调约束 | 含 `!` 标注的参数**必须传入效应函数**，纯函数传入是编译错误 |
| 效应传播 | 声明了 `!` 参数的函数**自身是效应函数**（必须在 `do` 块中调用） |
| 纯函数限制 | **纯函数不能声明 `!` 参数**——编译期拒绝 |
| 多参数 | 可在一个签名中标注多个 `!` 参数：`(a -> Unit)! -> b -> (c -> Unit)! -> d` |

### `!` 的内部类型表示

`(a -> b)!` 在编译器内部退糖为独立的类型构造器 `EffectFn(a, b)`，与普通函数类型 `Fn(a, b)` 在**结构等价下不兼容**——`EffectFn(a, b)` 和 `Fn(a, b)` 不会合一。这意味着：

- `identity : a -> a` 实例化为 `identity : EffectFn(Int, Unit) -> EffectFn(Int, Unit)` 时，`a` 被代换为 `EffectFn(Int, Unit)`，`!` 约束不会丢失
- `List.map : (a -> b) -> List a -> List b` **不能**接收 `EffectFn` 类型的参数——因为 `EffectFn(a, b)` 无法与 `Fn(a, b)` 合一
- 别名绑定（如 `f = List.iter`）保留 `EffectFn` 类型，效应约束通过类型传递而非 AST 标记

嵌套 `!` 类型 `((a -> b)! -> c)!` 表示为 `EffectFn(EffectFn(a, b), c)`——外层 `!` 使参数类型为 `EffectFn(...)`，内层 `!` 嵌入在该 EffectFn 的第一个参数中。

> 注：含 `do` 块或效应命名空间调用的用户定义函数，编译器在约束生成阶段自动为其赋予 `EffectFn` 内部类型（而非 `Fn`）。这意味着用户定义的效应函数**可以**传入 `!` 标注的参数（二者同为 `EffectFn`），但**不能**传入普通高阶函数的非 `!` 回调参数（如 `List.map`，其参数类型为 `Fn(a, b)`，与 `EffectFn` 不兼容）。用户无需在函数签名中书写 `!`——`->` 语法保持不变，编译器根据函数体自动选择 `Fn` 或 `EffectFn` 内部表示。

无约束类型变量 `a` 可与 `EffectFn(Int, Unit)` 合一（类型变量接受任何类型）。因此 `List.map : (a -> b) -> List a -> List b` 在实例化为 `a = Int, b = Unit` 时可接受 `EffectFn(Int, Unit)` 作为参数——因为 `a -> b` 是 `Fn(a, b)` 的语法糖，`a` 可被合一为 `EffectFn(Int, Unit)`，但 `EffectFn(Int, Unit)` 与 `Fn(Int, Unit)` 不可合一——前者是类型变量的绑定，后者是结构等价的比较。简言之：类型变量可绑定到任何类型，包括 `EffectFn`；两个具体类型的合一遵循结构等价规则，`EffectFn` 与 `Fn` 结构不同。

`!` 标注在标准库中包含以下函数：

```kun
List.iter  : (a -> Unit)! -> List a -> Unit
Stream.iter : (a -> Unit)! -> Stream a -> Unit
Signal.on   : Signal -> (Signal -> Unit)! -> Unit
Task.spawn  : Int -> List Command -> ... (内部效应，无回调参数)
```

`List.map`、`List.filter`、`List.fold`、`Stream.map`、`Stream.filter`、`Stream.fold` 等其余高阶函数**不包含 `!` 标注**——它们的回调必须是纯函数。需要逐元素执行副作用时使用 `List.iter` 或 `Stream.iter`。

### 效应检查

在类型合一的同时，效应检查器（Effect Checker）执行以下验证：

- 识别含 `do` 块的函数，标记为效应函数
- 识别签名中声明了 `!` 参数的函数，标记为效应函数
- 验证纯函数体中无效应函数调用
- 验证纯函数签名中无 `!` 参数声明
- 验证 `do` 块内未被消费的 `Command` 值（未被 `Cmd.exec`、`|>` 或 `?` 消费的 `Command` 是编译错误）
- 验证 `do` 块内未被消费的 `Stream`（未被 `toList`/`iter`/`fold`/`string`/`bytes` 等终端操作消费的 `Stream` 是编译错误，防止子进程变为僵尸和 fd 泄漏）
- `do` 块内条件消费路径的所有分支均需消费 `Stream`；`Cmd.timeout : Duration -> Command -> Result (Stream String) CommandError` 返回 `Result`，其 `Ok` 分支的 `Stream` 仍须消费
- 验证 `!` 参数的传入实参为效应函数（含 `do` 块或效应命名空间函数）
- 验证 `do` 块外的代码无效应命名空间函数调用
- 验证 `Cmd.<bin>?`、`Cmd.pipe?`、`Cmd.timeout`、`Cmd.retry`、`Cmd.which`、`Cmd.exec`、`Cmd.execSafe`、`Cmd.stdoutToString`、`Cmd.stderrToString` 仅在 `do` 块内使用
- 验证 `|>` 管道操作符的左侧为 `Command` 类型时仅在 `do` 块内出现——`do` 块外的 `|>` 收到 `Command` 值时编译期报错（提示："Command pipe requires a do block; use Cmd.<bin>? instead if you need immediate execution in pure context"）。`|>` 左侧为 `Stream` 或其他非 Command 类型时不受此限
- Lambda 含有效应函数调用时，要求该 lambda 在 `do` 块内定义

效应检查失败产生 `TypeError`，纳入统一的错误报告。

> **注意**：`let ... in` 绑定、`defer` 资源清理和 f-string 插值均有类型检查级语义：
> - `let ... in` 绑定表达式必须为纯（不得含 `do` 块或效应调用），绑定采用延迟求值
> - `do in` 形式在副作用执行后返回纯值——`in` 之后的表达式处于纯上下文，不需 `do` 块
> - `defer expr` 的类型为 `Unit`，不影响所在 `do` 块的类型
> - f-string 插值表达式的编译期 `toString` 展开（所有类型均通过编译器缺省「类型名 + 负载数据」格式生成字符串；显式定义的 `toString` 优先）——编译期完成全部校验，无运行时 panic

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
- 编译器对递归 `type` 别名的展开有深度上限（默认 256 层），防止无限展开。达到上限时产生编译错误（`TypeError`），错误信息报告展开路径（`A → B → A → B → ... → B`）和涉及的别名列表。交叉递归（A 引用 B，B 引用 A）中各别名的展开均计入同一深度计数器
- 交叉递归（A 引用 B，B 引用 A）同样通过别名机制支持

occurs check 在合一过程中检测类型变量自引用：
- **默认启用**：`a ~ List a` → 拒绝（无限类型错误）
- **对 `type` 别名关闭**：`type Tree = { value : Int, children : List Tree }` 中的 `Tree` 在自身定义内出现时，occurs check 不阻止合一——编译器将此类循环识别为等递归类型别名
- **带类型参数的递归别名**同样关闭 occurs check：`type Tree a = { value : a, children : List (Tree a) }`

### 无子类型

Kun 类型系统**不包含子类型关系**：

- `Int` 无子类型关系
- Record 无宽度子类型化和深度子类型化
- 函数类型无逆变/协变

选择不引入子类型的理由：子类型（尤其是 Record 宽度子类型）会显著增加类型检查器的复杂度（需引入子类型约束与合一的交互、协变/逆变位置计算），且与 HM 推断的合一算法存在根本性张力。对于配置传递场景（从大 Record 中提取部分字段传给子函数），结构等价的方案是通过 Record 更新语法构造精确匹配的子集，而非依赖子类型自动忽略多余字段。`.name` 字段访问速记是此策略的唯一例外——其脱糖为 `\x -> x.name`，`x` 的具体 Record 类型由调用点 HM 上下文确定，不要求 Record 宽度子类型。这是以少量样板代码换取类型系统简单性和编译期性能的权衡。

**性能权衡**：结构等价在大型模块图（50+ 模块）中，类型比较需要逐字段展开深层嵌套结构，性能低于名义等价的 O(1) 名称比较。Kun 的缓解措施包括：(1) 合一结果缓存，避免重复比较；(2) 编译期索引缓存，减少跨模块类型检查次数；(3) 对等递归类型展开深度上限（256 层），防止不终止。若后续性能成为瓶颈，可考虑在保持外部结构等价的前提下，为内部类型表示引入指针等价优化。

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

类型检查采用 HM（Hindley-Milner）推断，两阶段流程（约束生成 + 合一），详细实现见[系统基线](../architecture/system-baseline.md#类型检查算法）。

#### Let 多态与递归绑定

`let` 绑定支持递归——`let f = \x -> ... f (x - 1) ... in f 5` 中，`f` 的类型在 `let` 体中被泛化后实例化到 `f` 自身的引用位置。递归 `let` 的类型推断分两阶段：(1) 为 `f` 分配类型变量 `a`；(2) 在合一 `f` 的引用时将 `a` 实例化为新变量，与函数体推断出的类型合一。

互递归函数通过相互引用的 `let` 绑定处理：`let even = \x -> ...; odd = \y -> ... in ...`——两个绑定的类型先在各自作用域内泛化，然后在对方的引用处实例化。`let` 绑定组中所有函数的类型变量同时泛化，形成多态递归绑定组。

### 错误信息设计

HM 推断器产生的原始合一错误（如 "cannot unify `a -> b` with `Int`"）对目标用户（Linux 运维/DevOps）不可理解。编译器将原始合一错误转化为面向运维的结构化错误消息，包含：源位置、期望类型、实际类型、错误原因、修复建议。

#### 错误溯源

类型检查器在约束生成阶段记录类型变量的**来源位置**：

- 函数参数的绑定点（参数名 + 行号）
- `let` 绑定的值表达式（绑定名 + 行号）
- `case` 分支的 scrutinee（表达式 + 行号）
- Record 字段的构造/访问点（字段名 + 行号）

错误消息中的类型引用使用用户可见的类型名（如 `String`），而非内部类型 ID。模板中使用 `{expected}`、`{found}`、`{source}`、`{hint}` 占位符。

> **i18n**：以下模板为中文 locale（zh_CN）的展示格式。英文 locale（en）下，模板标题和字段标签使用英文 msgid（如 `"Type Mismatch"`、`"Expected"`），提示文本替换为对应的英文翻译。消息的 msgid 体系、`.po` 文件管理与运行时 locale 检测见 [i18n 子系统](../architecture/i18n.md)。
>
> 模板中 msgid 与中文翻译的对应关系：
>
> | msgid | zh_CN |
> |-------|-------|
> | `Type Mismatch` | 类型不匹配 |
> | `Argument Type Mismatch` | 函数参数类型不匹配 |
> | `Branch Type Mismatch` | 分支类型不一致 |
> | `Not A Function` | 非函数调用 |
> | `Too Many Arguments` | 参数过多 |
> | `Effect Callback Required` | 效应回调必需 |
> | `Nil For Non-Nilable` | Nil 赋值给非 Nilable |
> | `Nilable Used As Non-Nilable` | ?T 用于非 Nilable 位置 |
> | `Non-Exhaustive Pattern` | 模式匹配非穷举 |
> | `Redundant Pattern` | 冗余模式 |
> | `Unknown Field` | 未知字段 |
> | `Missing Field` | 缺少字段 |
> | `Tuple Index Out Of Range` | 元组索引越界 |
> | `Effect In Pure Function` | 纯函数调用效应函数 |
> | `Command Not Consumed` | Command 未消费 |
> | `Stream Not Consumed` | Stream 未消费 |
> | `Unbound Variable` | 未定义变量 |
> | `Unbound Type` | 未定义类型 |
> | `Infinite Type` | 无限类型 |
> | `Recursive Type Expansion Limit` | 递归展开超限 |
> | `Expected` | 期望 |
> | `Found` | 发现 |
> | `Hint` | 提示 |
> | `Reason` | 原因 |

#### 错误消息模板（20 个最常见场景）

**基础类型不匹配**

1. **`Mismatch`**（值类型不匹配）
   ```
   Error: Type Mismatch ─── src/main.kun:{line}:{col}
     Expected: {expected}
     Found:    {found}
     ──┤ {context_line}
     Hint: {source} 的类型为 {found}，但此处需要 {expected}
   ```

2. **`FunctionApplyArg`**（函数参数类型不匹配）
   ```
   Error: Argument Type Mismatch ─── src/main.kun:{line}:{col}
     Function: {func_name} : {func_type}
     Expected: {expected}
     Found:    {found}
     ──┤ {context_line}
     Hint: 第 {arg_index} 个参数应为 {expected}，但传入值为 {found}
   ```

3. **`IfBranchMismatch`**（if 分支类型不一致）
   ```
   Error: Branch Type Mismatch ─── src/main.kun:{line}:{col}
     then: {then_type}
     else: {else_type}
     ──┤ {context_line}
     Hint: if 表达式的两个分支必须返回相同类型
   ```

**函数类型**

4. **`NotAFunction`**（将非函数值作为函数调用）
   ```
   Error: Not A Function ─── src/main.kun:{line}:{col}
     Value type: {found}
     ──┤ {context_line}
     Hint: {found} 不是函数类型，无法进行函数调用。是否拼写错误？
   ```

5. **`TooManyArgs`**（函数参数过多）
   ```
   Error: Too Many Arguments ─── src/main.kun:{line}:{col}
     Function: {func_type}
     Extra argument type: {extra_type}
     ──┤ {context_line}
     Hint: 函数已接收所有参数后仍有额外参数。Kun 使用柯里化——你是否需要括号调整调用顺序？
   ```

6. **`EffectCallbackMismatch`**（`!` 参数传入纯函数）
   ```
   Error: Effect Callback Required ─── src/main.kun:{line}:{col}
     Expected: EffectFn({param}, {result})
     Found:    Fn({param}, {result})
     ──┤ {context_line}
     Hint: 标记了 ! 的参数必须传入效应函数（含 do 块或调用 IO/File/Cmd 等）。传入的函数 {name} 为纯函数
   ```

**Nilable 类型**

7. **`NilAssignedToT`**（Nil 赋值给非 Nilable 类型）
   ```
   Error: Nil For Non-Nilable ─── src/main.kun:{line}:{col}
     Type: {expected} (not nilable)
     ──┤ {context_line}
     Hint: {expected} 不可为 Nil。使用 ?{expected} 标注为可选类型，或提供非 Nil 值
   ```

8. **`NilableUsedAsT`**（?T 用于期望 T 的位置）
   ```
   Error: Nilable Used As Non-Nilable ─── src/main.kun:{line}:{col}
     Expected: {expected}
     Found:    ?{inner_type}
     ──┤ {context_line}
     Hint: 值可能为 Nil。使用 case 模式匹配收窄、{var} ?? default 提供默认值、或 {var} ?. 可选链安全访问
   ```

**ADT / 模式匹配**

9. **`NonExhaustive`**（模式匹配非穷举）
   ```
   Error: Non-Exhaustive Pattern ─── src/main.kun:{line}:{col}
     Type: {adt_name}
     Missing: {missing_variants}
     ──┤ {context_line}
     Hint: 类型 {adt_name} 有 {total} 个变体，当前仅覆盖 {covered} 个。添加缺失的 {missing_name} 分支
   ```

10. **`RedundantPattern`**（冗余模式分支）
    ```
    Error: Redundant Pattern ─── src/main.kun:{line}:{col}
      Pattern: {pattern} (不会被执行)
      ──┤ {context_line}
      Hint: 此分支之前已有通配模式覆盖了所有剩余情况，此分支永不会到达
    ```

**Record / Tuple**

11. **`UnknownField`**（Record 中不存在的字段）
    ```
    Error: Unknown Field ─── src/main.kun:{line}:{col}
      Record: {record_type}
      Field:  {field_name}
      ──┤ {context_line}
      Hint: {record_type} 不包含字段 {field_name}。可用字段：{available_fields}
    ```

12. **`MissingField`**（Record 构造缺少字段）
    ```
    Error: Missing Field ─── src/main.kun:{line}:{col}
      Record: {record_type}
      Missing: {missing_fields}
      ──┤ {context_line}
      Hint: {record_type} 要求以下字段：{required_fields}
    ```

13. **`TupleIndexOutOfRange`**（Tuple 索引越界）
    ```
    Error: Tuple Index Out Of Range ─── src/main.kun:{line}:{col}
      Tuple: ({elements})
      Index: {index}
      ──┤ {context_line}
      Hint: Tuple 有 {len} 个元素（索引 0-{len_minus_1}），但访问了索引 {index}
    ```

**效应系统**

14. **`EffectInPure`**（纯函数调用效应函数）
    ```
    Error: Effect In Pure Function ─── src/main.kun:{line}:{col}
      Effect call: {called_func} (效应函数)
      ──┤ {context_line}
      Hint: 纯函数不能调用效应函数 {called_func}。将函数体放入 do 块，或使用 ! 参数注入效应回调
    ```

15. **`CommandNotConsumed`**（Command 值未被消费）
    ```
    Error: Command Not Consumed ─── src/main.kun:{line}:{col}
      Command: {cmd_name}
      ──┤ {context_line}
      Hint: Command 值未被消费——子进程不会启动。使用 |> 管道触发、Cmd.exec 显式执行、或 ? 后缀立即执行
    ```

16. **`StreamNotConsumed`**（Stream 未被消费）
    ```
    Error: Stream Not Consumed ─── src/main.kun:{line}:{col}
      ──┤ {context_line}
      Hint: Stream 未被终端操作消费，子进程可能变为僵尸进程。使用 Stream.toList / Stream.iter / Stream.fold 消费
    ```

**Unbound / 作用域**

17. **`UnboundVariable`**（未定义变量）
    ```
    Error: Unbound Variable ─── src/main.kun:{line}:{col}
      Name: {var_name}
      ──┤ {context_line}
      Hint: 变量 {var_name} 未定义。是否拼写错误？是否缺少 import？
    ```

18. **`UnboundType`**（未定义类型）
    ```
    Error: Unbound Type ─── src/main.kun:{line}:{col}
      Name: {type_name}
      ──┤ {context_line}
      Hint: 类型 {type_name} 未定义。类型名必须以大写字母开头。是否拼写错误？是否缺少 import？
    ```

**泛型 / 递归**

19. **`InfiniteType`**（无限类型——occurs check 失败）
    ```
    Error: Infinite Type ─── src/main.kun:{line}:{col}
      Type: {var} 出现在自身定义中
      ──┤ {context_line}
      Hint: 类型变量 {var} 引用自身，需要 type 别名来定义递归类型。匿名类型中不能直接引用自身
    ```

20. **`RecursiveAliasDepth`**（递归别名展开达到上限）
    ```
    Error: Recursive Type Expansion Limit ─── src/main.kun:{line}:{col}
      Expansion path: {path}
      ──┤ {context_line}
      Hint: 递归 type 别名展开超过 256 层限制。展开路径：{path}。检查是否存在意外的循环引用
    ```

#### 验证标准

类型检查器的正确性通过以下验收标准确认（具体测试用例留到实现阶段编写）：

1. 每个错误消息模板至少对应一个正例（通过类型检查的合法程序）和一个反例（产生该模板中指定错误的非法程序）
2. HM 推断的回归测试覆盖以下关键场景：Let 多态、递归 let 绑定、互递归函数、泛型 ADT、嵌套 Nilable、EffectFn/Fn 结构不相容
3. 效应检查器验证：纯函数内包含效应调用时精确报告 `Effect In Pure Function`；`do` 块内未消费的 Stream 精确报告 `Stream Not Consumed`；`do` 块外 `|>` 收到 Command 时精确报告类型错误
4. 错误恢复：单文件内多个独立类型错误全部报告（非遇第一个停止）

测试基础架构见 `standard-library.md` 的 `Test` 模块（推迟 v1.0）。

#### 错误级别

| 级别 | 含义 | 行为 |
|------|------|------|
| Error | 类型不匹配，程序无法安全执行 | 拒绝编译，退出码 1 |
| Warning | 潜在问题（冗余模式、未消费 Stream） | 输出警告，编译通过 |

#### 错误恢复

类型错误不阻断后续检查。类型检查器在遇到类型不匹配时：
1. 为失败节点分配一个特殊占位类型 `TypeError`（仅用于继续检查，不暴露给用户）
2. 依赖该节点类型的后续节点使用 `TypeError` 进行约束生成（避免级联报错）
3. 最终报告所有独立错误（每个错误对应一个根本原因），过滤掉以 `TypeError` 为依赖的派生错误

#### 实现原则

1. **用户导向**：错误消息使用运维人员可理解的术语（「类型不匹配」「字段不存在」），避免内部术语（「合一失败」「代换冲突」）
2. **位置精确**：错误指向源码中的精确行和列，附带上下文代码行
3. **建议可操作**：Hint 提供具体的修复代码示例（非仅描述问题）
4. **累积报告**：一次编译报告所有类型错误（非遇到第一个就停止），在 Typed AST 上继续检查非阻塞错误

### 编译期类型内省 API

编译器向标准库中的 Primitive 函数提供以下编译期类型内省接口（基于 Zig `comptime` + `@typeInfo` 实现）：

```zig
/// 返回给定 TypeId 的用户可见类型名称
fn getTypeName(env: *TypeEnv, ty: TypeId) []const u8;

/// 返回 Record 类型的字段信息列表（字段名 + 字段 TypeId + 偏移量）
fn getRecordFields(env: *TypeEnv, ty: TypeId) []const RecordFieldInfo;

/// 返回 ADT 类型的变体信息列表（变体名 + 变体 tag 值 + 各变体的字段类型）
fn getADTVariants(env: *TypeEnv, ty: TypeId) []const ADTVariantInfo;

/// 返回指定 Record 字段的编译期偏移量（字节）
fn getFieldOffset(env: *TypeEnv, ty: TypeId, field_name: []const u8) usize;
```

这些函数仅在编译期（`comptime`）可用，由 `Cli.parse`（v0.5）、`Parser.Record.fromJson`（v0.5）和 `toString` 泛型分发等 Primitive 函数调用。API 在 `TypeEnv` 已完全构造（类型检查完成后）方可使用。

> **Kun TypeId ↔ Zig comptime type 映射**：`TypeId` 是 `TypeEnv.types` 数组的索引。在类型检查完成（Typed AST 构建后）的 `comptime` 上下文中，编译器通过 `@typeInfo(TypeEnv.types[id])` 获取 Zig 类型结构信息。此映射仅在编译期为有效——运行时 `TypeEnv` 中的类型表示为值，不可用作 Zig 类型。`getTypeName` 等 API 函数在 `comptime` 环境中通过此映射返回类型信息供 `Cli.parse`（v0.5）和 `Parser.Record.fromJson`（v0.5）使用。

## 类型表示与运行时

类型在编译后的运行时表示及 C ABI 映射见[系统基线](../architecture/system-baseline.md#类型运行时表示)。类型系统专注于编译期语义，运行时内存布局属于架构实现细节。

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.15 | 审计修复三轮：Int 溢出/ Float NaN 语义文档化；除零行为明确（Int panic / Float IEEE）；递归 let 与互递归 HM 类型推断；错误恢复占位类型机制；occurs check 选择性启用规则；EffectFn 与泛型变量合一澄清 |
| 2026.06.15 | 审计修复二轮：效应检查器新增 `\|>` 管道执行守卫（do 块外拒绝 Command 类型）；新增编译器类型内省 API 定义 |
| 2026.06.15 | 审计修复：补全 DateTime/Map/Set/Stream/Command 类型定义；纯函数定义统一；let in/do in/defer/f-string 类型检查引用；kind 表补充 Map/Stream |
| 2026.06.14 | 效应跟踪修正：用户定义含 `do` 块的函数自动获取 `EffectFn` 内部类型（而非 `Fn`），可传入 `!` 参数；`Signal.*` 效应规则缩小为 `Signal.on` |
| 2026.06.14 | `(a -> b)!` 退糖为 `EffectFn(a, b)` 独立类型构造器——与 `Fn(a, b)` 在结构等价下不兼容；补充嵌套 `!` 语义说明、别名保留规则 |
| 2026.06.14 | 新增效应回调标记 `(a -> b)!`——标注参数必须为效应函数；含 `!` 参数的函数自身为效应函数；纯函数禁止声明 `!` 参数；新增 `Cmd.exec` 效应函数（Command 显式执行） |
| 2026.06.13 | `Cmd` 效应分类细化（装饰函数为纯操作/立即执行为效应）；效应跟踪提升为独立 H2；锚点规范化 |
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
