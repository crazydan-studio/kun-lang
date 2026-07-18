# 类型系统设计

## 设计目标与原则

### 核心目标

Kun 的类型系统服务于一门面向 Linux 的函数式脚本语言。其设计围绕以下目标展开：

- **类型安全**：所有类型检查在编译期完成，消除运行时类型错误
- **推断优先**：用户无需为局部变量和绝大多数函数参数提供类型标注
- **实用至上**：为脚本场景做务实取舍，不追求理论完备性
- **显式错误**：通过和类型（`Result`）将错误处理纳入类型系统，禁止隐式异常。可选值通过 `?T`（nilable 类型）表达
- **运行时对齐**：类型表示与 C ABI 兼容
- **副作用即类型**：函数类型显式标注效应集 `a -> b ! E`，纯函数是效应空集 `! {}` 的特例

### 设计原则

1. **无子类型**：所有类型间无隐式转换关系
2. **`alias`/`type` 分离**：`alias` 别名结构等价（无屏障），`type` ADT 名义等价（有屏障，**不做 tag 擦除**）
3. **穷举检查**：模式匹配必须覆盖所有分支（对和类型强制）
4. **效应即类型**：函数类型含效应集，纯函数 `! {}` 不能调用 `! E`（E 非空）函数
5. **不可变默认**：所有数据默认不可变，类型系统对此做静态保证
6. **立即求值**：所有表达式立即求值，`let in` 绑定立即；`Lazy`/`Stream` 为显式惰性特区
7. **`==` 浅比较**：结构浅比较，深比较显式使用 `Equal` 模块函数
8. **不支持 typeclass**：效应抽象靠 `effect`/`handler`，非 typeclass
9. **不支持行多态**：效应集为闭集 + 单效应变量 `e`

## 类型宇宙与种类系统

### 种类（Kind）

Kun 采用以下种类系统：

| 种类 | 含义 | 示例 |
|------|------|------|
| `Type` | 具体类型（值可居留其中） | `Int`、`Bool`、`String` |
| `Type -> Type` | 类型构造器（接受一个类型参数返回具体类型） | `List`、`Set`、`Stream`、`Nilable` |
| `Type -> Type -> Type` | 多参类型构造器 | `Map`、`Result` |
| `Effect` | 效应种类（一个具体的效应，如 `IO`/`File`/`DB`） | `IO`、`File`、`Cmd` |
| `EffectSet` | 效应集种类（效应的集合） | `{}`、`{IO}`、`{IO, File}`、`e` |

所有完整应用的类型构造器（如 `List Int`）归约到种类 `Type`。函数类型 `a -> b ! E` 中，`a`/`b` 为 `Type`，`E` 为 `EffectSet`。

### 类型分类

```
Type Universe
├── Base Types         (Int, Float, Bool, String, Bytes, Char, Regex, Duration, Unit, Path)
├── Compound Types     (List, Map, Set, Stream, Tuple)
├── Product Types      (Record/Tuple)
├── Sum Types / ADTs   (custom via `type`, Result, Nilable)
├── Function Types     (a -> b ! E, pure = ! {})
├── Handler Types      (Handler {e} a ! {handlerEffects})
├── FFI Types          (Opaque a, FfiBuffer, FfiValue)
├── Standard Library Types (compiler-supported)
│   ├── Decimal    (mantissa + exponent)
│   ├── Command    (ADT: Simple | Pipe)
│   ├── DateTime   (built-in effect)
│   └── TestResult (ADT: Pass | Fail String | Skip String)
└── Type Variables     (a, b, e — for generics and effect polymorphism)
```

> `DateTime`、`Decimal`、`Command`、`TestResult` 为标准库类型——由编译器提供 TypeEnv 变体和运行时表示支持，但非语言内置基础类型。`Command` 为 ADT（`type Command = Simple SimpleCommand | Pipe (List Command)`），`TestResult` 为 ADT（`type TestResult = Pass | Fail String | Skip String`）。

## 函数类型

### 函数类型语法

```kun
<param> -> <result> ! <effectSet>
```

- `param`：参数类型
- `result`：返回值类型
- `effectSet`：效应集

### 效应集语法

| 写法 | 含义 |
|---|---|
| `! {}` | 纯（效应空集） |
| `! {IO}` | 单效应 |
| `! {IO, File}` | 多效应并集 |
| `! e` | 效应多态（单变量 `e`） |
| `! {IO, e}` | 至少 IO + 可能更多 |
| 无 `!` | 等价 `! {}`（纯） |

效应集为**无序集合**：`{IO, File} ≡ {File, IO}`，类型检查、`==` 比较、handler 匹配均按无序集合处理；编译器内部维护效应集为排序后的规范形式。

### 纯函数

**纯函数 = 效应空集的函数**，无独立概念：

```kun
add : Int -> Int -> Int          // 等价 add : Int -> Int -> Int ! {}
add = \x y -> x + y

fetchUser : UserId -> Result User ! {DB, Log}
fetchUser = \uid -> ...
```

类型检查规则：

- `! {}` 函数体内不可调用 `! E`（E 非空）函数
- `! {}` 函数体内 `let in` 不可含效应语句
- `! E`（E 非空）函数体内可调用任意函数（效应并入 E）

### 零参效应函数类型 `T ! {E}`

零参效应函数声明为 `Name : RetType ! {Effects}`——结果类型直接跟在 `:` 后，**无 `->` / `Unit ->` 前缀**。`! {E}` 存在且无 `->` 即标识零参效应函数：

```kun
now : DateTime ! {DateTime}             // 零参效应函数，返回 DateTime
createTemp : Result Path IOError ! {File} // 零参效应函数，返回 Result
```

规则：

- 零参效应函数的类型为 `T ! {E}`（无 `->`）；带参函数类型为 `A -> T ! {E}`，二者元数不同——HM 合一时元数必须相同，否则合一失败
- 零参函数**仅允许用于效应函数**（函数体含效应调用）。纯零参函数退化为常量，应使用 `let` 绑定
- 纯函数返回类型不可为 `Unit`——返回 `Unit` 的纯计算无输出也无副作用，退化为无操作（no-op），编译期报错。效应函数可返回 `Unit`（`Test` 效应的 `assert : Bool -> Unit ! {Test}` 是测试专用例外，由 `testHandler` 消解为 `TestResult`）
- 对应的 Lambda 语法为 `\ -> expr`（无参数占位符，无 `_`）
- **调用约定**：`Name!` 后缀执行零参函数（如 `DateTime.now!`）；`Name`（无 `!`）为函数引用，可作为一等值传递给高阶函数（参数类型为 `T ! {E}` 时接收零参效应函数引用）
- **带参函数的柯里化调用**：参数完整时正常执行；参数不完整时返回柯里化形式（仍是函数值，不执行）
- **`!` 后缀语义**：`!` 为后缀执行运算符，优先级高于函数应用，仅作用于零参函数。**此 `!` 与已废弃的 Command 断言执行 `!`（旧 `c!` → 现 `Cmd.exec c`）是不同的特性**——后者已废弃，前者是新的零参函数执行运算符
- **零参函数类型作参数须括号化**：当零参效应函数类型作为参数时需用括号包裹，如 `runThunk : (Unit ! {IO}) -> Unit ! {IO}` 的参数为零参回调（接收一个零参效应函数引用，体内 `f!` 执行）

```kun
now : DateTime ! {DateTime}
now = \ ->
  let
    t = DateTime.now!
  in
    t

getPid : Pid ! {Process}
getPid = \ ->
  let
    p = Process.pid!
  in
    p

// 函数引用：将零参函数作为值传递给高阶函数
runAll : List (Unit ! {IO}) -> Unit ! {IO}
runAll = \fs -> List.iter (\f -> f!) fs
```

> **「零参效应函数」与「取 `Unit` 的纯函数」的区分**：二者形式不同，须严格区分：
>
> | 形式 | 类型 | 元数 | 用途 | 调用 |
> |------|------|------|------|------|
> | 零参效应函数 | `T ! {E}`（无 `->`，有 `! {E}`） | 0 | 表示无输入但含效应的计算 | `Name!` |
> | 取 `Unit` 的纯函数 | `Unit -> T`（有 `->`，无 `! {E}`） | 1 | 显式 thunk 标记（如 `Lazy.lazy` 接收的延迟求值体） | `f ()` |
>
> 判别准则：**有 `! {E}` 且无 `->` 即零参效应函数；有 `->` 即带参函数（无论参数是否为 `Unit`）**。零参效应函数用 `!` 后缀执行，不能用 `()` 调用；取 `Unit` 的纯函数用 `f ()` 应用，不能用 `!` 后缀。
>
> **关于 `Lazy.lazy : (Unit -> a) -> Lazy a`**：此处参数 `Unit -> a` 是 **1 参纯函数**（有 `->`，无 `! {E}`），**不是零参函数**——它显式接收 `Unit` 占位以标记 thunk（延迟求值的封装体）。`Lazy` 是求值策略例外特区（与 `Stream` 同），需要 1 参纯函数类型作为 thunk 标记，故不适用"零参函数仅允许用于效应函数"的规则。
>
> 纯零参函数（无 `->` 且无 `! {E}`）会退化为常量，应使用 `let` 绑定——故 `Unit -> T`（纯）总是意味着"1 参函数取 `Unit`"，不存在歧义。

## Nilable 类型（`Nilable a` / `?T`）

`Nilable a` 是编译器内置的 ADT，表示值可能存在（`Some a`），也可能不存在（`Nil`）。`?T` 为 `Nilable T` 的语法糖——用户可在类型标注中任选其一。

> **编译器内置**：`type Nilable a = Some a | Nil` 是编译器预定义的和类型，等效于用户定义的 ADT。`Some` 和 `Nil` 两个变体始终缺省可用（无需 `import` 即可在 `case` 模式匹配中使用）。`Nilable` 模块（需导入）提供组合子函数。

### `?T` 语法糖

`?T` 在语法分析阶段脱糖为 `Nilable T`：

| 写法 | 脱糖后 | 说明 |
|------|--------|------|
| `?T` | `Nilable T` | 如 `?String` → `Nilable String` |
| `?(T1 T2)` | `Nilable (T1 T2)` | 多词类型须括号包裹，**不**支持 `?Result T E`（作用域不明确） |

`?T` 与 `Nilable T` 在类型系统中完全等价，可在类型标注中互用。模块函数签名**统一使用 `?a`** 以保持简洁。

### 嵌套禁止（关键简化）

**禁止嵌套 Nilable**：`?T` 的 `T` 不可为 `?T'`，`Nilable (Nilable T)` → 编译错误。

理由：`Nil` 在嵌套上下文中不可区分外层与内层，语义模糊。

```kun
// ❌ 编译错误
x : ??Int
x = Some (Some 1)

// Error: Nested Nilable
//   Hint: Nilable 不可嵌套。用 Result (?Int) Error 或自定义 ADT。
```

需表达"可能缺席的可选值"时，用 `Result (?T) Error` 或自定义 ADT。

### 规则

| 规则 | 说明 |
|------|------|
| `T`（无 `?`） | **不可**为 Nil。`x : String = Nil` 编译期报错 |
| `?T` | **可**为 Nil。`x : ?String = Nil` 合法 |
| `Nil` | `Nilable` ADT 的 `Nil` 变体，类型为多态 `?a`，与上下文合一确定具体类型——非特殊字面量，与 `Some` 同为缺省可用变体 |
| 和类型字段 | 默认不可 Nil，`?` 需显式标注 |
| 嵌套 `? ?T` | **编译错误**（Nested Nilable）。`Nil` 在嵌套上下文中不可区分外层与内层 |
| `if x /= Nil` | **不**支持流敏感收窄，使用 `case` 显式匹配 |

### 模式匹配

```kun
x : ?String
x = someFunctionReturningOptional

case x of
  Some s -> String.length s   // 显式 Some，s 收窄为 String
  Nil    -> 0
```

`case` 匹配 `Nilable` 时必须显式使用 `Some` 和 `Nil` 变体——编译器不做裸变量糖化。

### 复合模式

```kun
case (x, y) of              // x : ?Int, y : ?String
  (Some a, Some b) -> Int.toString a ++ b
  (Some a, Nil)    -> Int.toString a
  (Nil, Some b)    -> b
  (Nil, Nil)       -> "both absent"
```

## 基础类型

### 概览

| 类型 | 值域 | 字面量示例 | 运行时表示 | 说明 |
|------|------|-----------|-----------|------|
| `Int` | `-2^63 .. 2^63-1` | `42`, `-3`, `0xFF`, `0o644` | i64 | 固定宽度有符号整数 |
| `Float` | IEEE 754 双精度 | `3.14`, `-2.5e10` | f64 | 浮点数 |
| `Bool` | `true` / `false` | `true`, `false` | u8 | 布尔值 |
| `String` | UTF-8 编码文本 | `"hello"`, `""` | `[]u8` (切片) | 不可变 UTF-8 字符串 |
| `Bytes` | 任意二进制数据 | `0x48656C6C6F` | `[]u8` | 与 `String` 明确区分 |
| `Char` | Unicode 标量值 | `'A'`, `'\n'` | u32 | Unicode 标量值 |
| `Regex` | 编译后正则 | `r"[0-9]+"` | 内部编译表示 | 编译期验证 |
| `Duration` | 纳秒精度时间段 | `5s`, `100ms`, `2h` | i64 (纳秒) | 时间跨度 |
| `Unit` | 零宽度类型 | 无（编译器隐式值） | void | 无返回值标记；不可作为参数类型；作为返回类型仅限效应函数 |
| `Path` | 文件系统路径（不保证 UTF-8） | `p"/tmp/foo"`, `p"./foo"` | `[]u8` | 与 `String` 语义区分；内部可为任意非 NUL 字节 |

### 类型详述

#### `Int`

- 固定 64 位有符号整数（i64），补码表示。字面量支持十进制、`0x`、`0o`、`0b` 及 `_` 分隔
- `Int` 的四则运算（`+`/`-`/`*`/`/`）在安全模式（Debug/ReleaseSafe）下溢出时 panic。ReleaseFast 和 ReleaseSmall 模式下溢出检测关闭——行为为 Zig 的默认行为（二进制补码回绕，wrapping）。需要精确溢出控制的代码使用 wrapping 运算符（`+%`、`-%`、`*%` 等，wrapping 语义）或将操作数提升为 `Float` 后计算再截断。若后续引入饱和运算需求，可在标准库中补充 `Int.saturatingAdd` 等函数。

`Int` 除零（`x / 0` 或 `x % 0`）在任何构建模式下均为 panic——不可通过模式关闭。`Float` 除零返回 `±Infinity` 或 `NaN`（见下方特殊浮点值表）。

#### `Int` 位运算

`Int` 模块扩展位运算，满足系统脚本场景（权限位掩码、信号位、flag 组合）：

```kun
// 位运算
(&)   : Int -> Int -> Int      // 按位与
(|)   : Int -> Int -> Int      // 按位或
(^)   : Int -> Int -> Int      // 按位异或
not     : Int -> Int             // 按位取反
shl     : Int -> Int -> Int      // 左移
shr     : Int -> Int -> Int      // 右移（算术）
ushr    : Int -> Int -> Int      // 右移（逻辑）

// 位操作工具
popCount : Int -> Int            // 位计数
leadingZeros : Int -> Int        // 前导零
trailingZeros : Int -> Int       // 后续零
```

**优先级**（从高到低）：

| 优先级 | 运算符 | 说明 |
|---|---|---|
| 1 | `shl`/`shr`/`ushr` | 移位 |
| 2 | `&` | 按位与 |
| 3 | `^` | 按位异或 |
| 4 | `\|` | 按位或 |

均为左结合。

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

#### `Float`

- IEEE 754 双精度浮点数（f64）。与 `Int` 混合运算需显式转换
- 操作函数及容差比较见 [`Float` 模块](standard-library.md#float-浮点操作与数学函数)
- `Float.approxEqual` 签名 `Float -> Float -> Float -> Bool`，语义 `|a - b| < epsilon`，参数顺序为 `a b epsilon`

```kun
Float.approxEqual (0.1 + 0.2) 0.3 1e-10    // ✅ 正确
// Float.approxEqual 1e-10 (0.1 + 0.2) 0.3  // ❌ 参数顺序错误
```

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

- 修饰符作用域：出现在模式开头则作用于整个模式，出现在中间则仅影响后续部分；未显式指定修饰符时，正则引擎使用默认行为（大小写敏感、`^`/`$` 仅匹配文本首尾、`.` 不匹配换行符）
- 支持修饰符开关：`(?i)` 开启，`(?-i)` 关闭
- 编译期验证正则语法。操作函数见标准库 `Regex` 类型

#### `Duration`

- 纳秒精度时间段，运行时表示为 i64（纳秒）。字面量：`5s`、`100ms`、`2h`、`30m`、`1d`、`500us`、`200ns`
- 操作函数见标准库

#### `Unit`

- 零宽度类型（C `void`），编译器隐式值。不可作为参数类型

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

不可变键值字典。键类型仅限内置可哈希类型（`Int`/`String`/`Bool`/`Char`/`Path`/`Duration`）。运行时表示为开地址哈希表。用户自定义类型作键，用 `Map.fromHashFn` 传入哈希函数：

```kun
// 用户自定义哈希
users : Map Int User
users = Map.fromHashFn (\(UserId i) -> i) Map.empty
```

不引入 typeclass，用运行时哈希函数替代。

#### `Set t`

不可变无序集合。元素类型同 `Map` 的键类型约束——必须可哈希。

#### `Stream t`

惰性序列（显式惰性特区）。元素按需拉取，运行时表示为 Zig tagged union。`Stream` 的消费必须在创建其的 `let in` 块内完成——编译器对未被消费的 `Stream` 进行流敏感检测。

#### `Command`

`type Command = Simple SimpleCommand | Pipe (List Command)` ADT，由 `cmd` 字面量构造（纯操作）。`Command` 为编译器内置类型，执行通过 `Cmd.exec`/`Cmd.execSafe`/`Cmd.stream` 显式触发，无 Command 的 `?`/`!` 后缀糖（注：零参函数执行的 `!` 后缀是独立特性，见[零参效应函数类型](#零参效应函数类型-t-e)），无 `|>` 隐式触发。

## 相等比较（`==`）语义

`==` 采用**结构浅比较**，不递归嵌套容器/ADT。

### 规则

| 类型 | `==` 行为 |
|---|---|
| `Int`/`Bool`/`Char`/`Duration` | 值比较 |
| `Float` | 值比较；`NaN == NaN` → `false`（IEEE 754） |
| `String`/`Bytes`/`Path` | 内容比较（首层） |
| `List`/`Map`/`Set` | **引用比较**（不递归元素） |
| `Record`/`Tuple` | **引用比较**（不递归字段） |
| ADT | **引用比较**（不比较 tag 与 payload） |
| `Closure`/`Opaque`/`Stream` | 引用比较 |

### 浅比较的语义

```kun
// 基础类型：值比较
1 == 1                              // true
"hello" == "hello"                  // true（内容相同）
NaN == NaN                          // false（IEEE 754）

// 容器/复合类型：引用比较（浅）
[1, 2] == [1, 2]                    // false（不同 List 实例）
{ x = 1, y = 2 } == { x = 1, y = 2 }  // false（不同 Record 实例）
(Ok 1) == (Ok 1)                    // false（不同 ADT 实例）

// 同一引用：true
xs = [1, 2]
xs == xs                            // true（同一实例）
```

### 深比较需求

若需深比较，用 `Equal` 模块提供的 `equal` 函数，显式递归：

```kun
// Equal 模块（深比较）
List.equal : (a -> a -> Bool) -> List a -> List a -> Bool
Map.equal : (k -> k -> Bool) -> (v -> v -> Bool) -> Map k v -> Map k v -> Bool
Set.equal : (a -> a -> Bool) -> Set a -> Set a -> Bool

// 使用
List.equal (==) [1, 2] [1, 2]                          // true（元素浅比较）
List.equal (List.equal (==)) [[1], [2]] [[1], [2]]     // true（嵌套深比较）
```

### 设计理由

- 浅比较是 O(1)，性能可预测
- 深比较在不可变语言中语义复杂（嵌套循环引用、大结构性能）
- 显式 `equal` 函数让深比较成为用户选择，非默认行为
- 不引入 typeclass，用模块函数替代

### Map 键的哈希

Map 键仅限内置可哈希类型（`Int`/`String`/`Bool`/`Char`/`Path`/`Duration`）。用户自定义类型作键，用 `Map.fromHashFn` 传入哈希函数。

不引入 typeclass，用运行时哈希函数替代。

## 类型声明体系：`alias` 与 `type` 分离

Kun 采用 `alias` 与 `type` 两个关键字，覆盖别名定义与 ADT 定义（含单变体包装与多变体和类型）。

### `alias`：别名定义

`alias` 定义任意类型（含 Record）的**透明别名**，编译期展开为底层类型，无运行时存在，结构等价，无抽象屏障。

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

// Point 与匿名 Record 等价
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
type Result a e = Ok a | Err e
type Color = Red | Green | Blue
type Tree a = Leaf | Node a (Tree a) (Tree a)
```

- 名义等价
- 多构造器，穷举性检查
- 有 tag

### 单变体与多变体的一致性

单变体 `type User = User { ... }` 与多变体 `type Result a e = Ok a | Err e` 都是 ADT，运行时均为 tagged union。**不做 tag 擦除优化**，保持 ADT 语义统一。单变体可自然演化为多变体（添加变体），无需改变运行时表示或编译器处理。

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

### 基础类型包装

```kun
type UserId = UserId Int
type Email = Email String

// 构造
uid : UserId = UserId 42
email : Email = Email "alice@example.com"

// 解构
case uid of
  UserId i -> Int.toString i

case email of
  Email s -> s

// 不可与底层类型互换
uid : UserId = UserId 1
id : Int = uid   // ❌ 编译错误（UserId ≠ Int）

// 显式转换
id : Int =
  case uid of
    UserId i -> i   // ✅
```

### 三态对照

| 场景 | 关键字 | 等价性 | 运行时 | 构造器 | 用途 |
|---|---|---|---|---|---|
| `alias X = T` | `alias` | 结构等价 | 同 T（展开） | 无 | 别名/缩写 |
| `type X = X T` | `type` | 名义等价 | tagged union | 有（`X`） | 包装类型，抽象屏障 |
| `type X = A \| B` | `type` | 名义等价 | tagged union | 有（`A`/`B`） | 和类型 |

**选择指南**：

- 需要类型缩写，不需屏障 → `alias`
- 需要抽象屏障，包装 Record/基础类型 → `type X = X T`（单变体 ADT）
- 需要和类型，多分支 → `type X = A | B`（多变体 ADT）

### 完整示例

```kun
// alias：别名（结构等价）
alias Point = { x : Float, y : Float }
alias Config = { host : String, port : Int }

// type 单变体：包装类型（名义等价，有屏障）
type User = User { name : String, id : Int }
type Session = Session { name : String, id : Int, token : String }
type UserId = UserId Int
type Email = Email String

// type 多变体：和类型
type Result a e = Ok a | Err e
type Color = Red | Green | Blue

// 使用
p : Point
p = { x = 1.0, y = 2.0 }   // alias，匿名 Record 直接赋值

user : User
user = User { name = "alice", id = 1 }   // type，用构造器
name =
  case user of
    User r -> r.name

session : Session = user   // ❌ 编译错误（User ≠ Session）

result : Result Int String = Ok 42
case result of
  Ok v -> Int.toString v
  Err e -> e

uid : UserId = UserId 1
fetchUser uid   // ✅ 接受 UserId，不接受 Int
// fetchUser 1   // ❌ 编译错误
```

### 设计理由

1. **`alias` 与 `type` 分离**：别名（无屏障）与类型定义（有屏障）意图明确，无歧义
2. **单变体与多变体统一**：都是 ADT，都有 tag，编译器处理一致，单变体可自然演化为多变体
3. **不做 tag 擦除**：保持 ADT 语义统一，避免编译器优化复杂度与不确定性
4. **tag 开销可接受**：`type UserId = UserId Int` 的 tag 开销在脚本场景可忽略；若需大量值包装，用 `alias`（结构等价，零开销）

## 递归类型

Kun 支持 **等递归类型（Equi-recursive Types）**。在合一算法中，对 `type` 声明的别名关闭 occurs check——允许类型定义中引用自身，通过别名的结构展开实现。

```kun
// 等递归类型示例：clispec 通过 subs 引用自身
type CliSpec =
  { subs : ?(Map String CliSpec) }
```

### 递归类型深度限制

等递归类型展开深度上限 **256 层**，达到上限 → **编译错误**（非静默截断）：

```kun
// 递归类型展开达到 256 层
// Error: Recursive Type Expansion Limit
//   Expansion path: Tree → TreeNode → Tree → ... → TreeNode (256 layers)
//   Hint: 检查循环引用，或用 Opaque 包装。
```

深度可通过环境变量 `KUN_MAX_TYPE_DEPTH` 覆盖（0 表示无限制）。

### 递归类型的关键约束

- 递归必须通过 `type` 别名间接发生——直接在匿名 Record 中引用自身会被 occurs check 拒绝（匿名类型无别名可供展开）
- 编译器对递归 `type` 别名的展开有深度上限（默认 256 层），防止无限展开。达到上限时产生编译错误（`TypeError`），错误信息报告展开路径（`A → B → A → B → ... → B`）和涉及的别名列表
- 交叉递归（A 引用 B，B 引用 A）同样通过别名机制支持

occurs check 在合一过程中检测类型变量自引用：

- **默认启用**：`a ~ List a` → 拒绝（无限类型错误）
- **对 `type` 别名关闭**：`type Tree = { value : Int, children : List Tree }` 中的 `Tree` 在自身定义内出现时，occurs check 不阻止合一——编译器将此类循环识别为等递归类型别名
- **带类型参数的递归别名**同样关闭 occurs check：`type Tree a = { value : a, children : List (Tree a) }`

## 类型等价与类型关系

### 等价规则

Kun 采用**混合等价**策略：

- **`alias` 结构等价**：`alias` 定义的别名编译期展开为底层类型，结构完全相同即等价
- **`type` 名义等价**：`type` 定义的 ADT 仅当声明为同一名称时才等价，即使结构相同也不兼容

**结构等价**适用于：基础类型、复合类型（`List`/`Map`/`Set`/`Stream`/`Tuple`）、Record、函数类型、`alias` 别名。泛型类型在应用相同类型参数后结构等价。

**名义等价**适用于：`type` 定义的 ADT。`type User = User { name, id }` 与 `type Session = Session { name, id }` 是不同的类型，即使底层 Record 结构相同。

选择混合等价的理由：

1. **与 HM 推断天然契合**。HM 合一算法直接产出结构等式，结构等价无需在合一之外额外维护全局名称映射
2. **Kun 无子类型，名义等价优势场景不存在**
3. **脚本场景追求零声明成本**。`{ x: Int, y: Int }` 自然就是坐标类型，无需先声明 `type Point = ...` 才能传递。用户按需使用 Record 字面量即可获得类型安全
4. **需要语义隔离时用 `type` 单变体 ADT**。`type UserId = UserId Int` 提供精确的名义边界——同名 ADT 互相兼容，不同名的即使包装相同底层类型也不兼容

### 无子类型

Kun 类型系统**不包含子类型关系**：

- `Int` 无子类型关系
- Record 无宽度子类型化和深度子类型化
- 函数类型无逆变/协变

选择不引入子类型的理由：子类型（尤其是 Record 宽度子类型）会显著增加类型检查器的复杂度（需引入子类型约束与合一的交互、协变/逆变位置计算），且与 HM 推断的合一算法存在根本性张力。对于配置传递场景（从大 Record 中提取部分字段传给子函数），结构等价的方案是通过 Record 更新语法构造精确匹配的子集，而非依赖子类型自动忽略多余字段。`.name` 字段访问速记是此策略的唯一例外——其脱糖为 `\x -> x.name`，`x` 的具体 Record 类型由调用点 HM 上下文确定，不要求 Record 宽度子类型。这是以少量样板代码换取类型系统简单性和编译期性能的权衡。

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

## 代数效应系统

### 内置效应

7 个内置效应（含 `FFI`）：

| 效应 | 含义 | 触发来源 |
|---|---|---|
| `IO` | 控制台 IO | `IO.println`/`IO.readln` |
| `File` | 文件系统 | `File.read`/`File.write` |
| `Cmd` | 子进程执行 | `Cmd.exec`/`Cmd.execSafe`/`Cmd.stream` |
| `Random` | CSPRNG | `Random.int`/`Random.bytes` |
| `DateTime` | 系统时间 | `DateTime.now` |
| `Signal` | 信号处理 | `Signal.on` |
| `FFI` | 外部 C 库调用 | `FFI.call`（由 `extern` 块默认 handler 委托） |

**保留名**：以上 7 个效应名为编译器保留名，用户不可定义同名 `effect`。防伪造机制见 [FFI 防欺骗](#ffi-防欺骗机制)。

> **效应名与模块名同名**：7 个内置效应名与对应标准库模块同名（如 `IO` 效应与 `IO` 模块、`Cmd` 效应与 `Cmd` 模块）。效应名属类型命名空间（出现在 `! {E}`、`Handler {E}` 等类型位置），模块名属值命名空间（出现在 `import`、`Module.func` 等值位置），二者语法位置不重叠，同名合法。效应操作（如 `Cmd.exec`）必须全名调用且不可裸名导入，模块纯函数（如 `Cmd.withEnv`）可选择性导入裸名；详见 [语法设计 - 效应与模块同名](syntax.md#效应与模块同名)。

### 效应声明语法

```kun
effect <Name> =
  { <op1> : <signature>
  , <op2> : <signature>
  , ...
  }
```

**Record 风格**，操作签名是函数类型，效应隐含为 `<Name>`。

### 内置效应声明（标准库）

内置效应的**签名**在标准库中以普通 `effect` 声明（无特权关键字），与用户效应形式完全一致。**handler 实现**在编译器源码（Zig）中，编译进 `kun` 二进制，用户不可见、不可改。

```kun
// <runtime>/lib/kun/IO.kun
export (IO)

effect IO =
  { println : String -> Unit
  , readln  : String
  , eprintln : String -> Unit
  }

// <runtime>/lib/kun/File.kun
export (File)

effect File =
  { read        : Path -> Result String IOError
  , write       : Path -> String -> Result Unit IOError
  , remove      : Path -> Result Unit IOError
  , exists      : Path -> Bool
  , createTemp  : Result Path IOError
  }

// <runtime>/lib/kun/Cmd.kun
export (Cmd, pipe, cmd, withEnv, withStdin, withStdinFile, mergeStderr, withWorkDir, withRunAs, withoutDash, andThen, orElse, timeout, retry)

effect Cmd =
  { exec     : Command -> Unit
  , execSafe : Command -> Result (Stream String) CommandError
  , stream   : Command -> Stream String
  , which    : String -> ?Path
  }

// <runtime>/lib/kun/FFI.kun
export (FFI, FfiBuffer, alloc, toBytes, toString)

effect FFI =
  { call : String -> String -> List FfiValue -> FfiValue
  }
```

**handler 实现（Zig，编译器源码内）**：

```zig
// src/builtin_handlers.zig（编译进 kun 二进制）
fn io_println(env: *Env, args: []const Value) -> Value {
  std.debug.print("{s}\n", .{args[0].string});
  return .unit;
}
fn ffi_call(env: *Env, args: []const Value) -> Value {
  // dlopen/dlsym + C ABI 调用
  ...
}

// 内置 handler 注册表（编译期生成，加载标准库时校验完整性）
const builtin_handler_table = std.ComptimeStringMap(HandlerEntry, .{
  .{ "IO.println", .{ .fn_ptr = io_println, .is_effect = true } },
  .{ "FFI.call", .{ .fn_ptr = ffi_call, .is_effect = true } },
  // ...
});
```

**签名与实现的绑定**：编译器加载标准库 `effect IO` 时，校验每个操作在注册表有对应 Zig 实现，缺失则编译错误。

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

### 效应集推导

函数效应集 = 体内所有效应调用的并集：

```kun
fetchUser : UserId -> Result User ! {DB, Log}
fetchUser = \uid ->
  let
    Log.info f"fetching {uid}"       // {Log}
    result = DB.query (selectUser uid)  // {DB}
  in
    case result of
      Ok [row] -> Ok (User row)
      _ -> Err NotFound
// 效应集：{DB, Log}
```

### 调用约束

**调用者效应集必须包含被调用者效应集**：

```kun
// 合法：fetchUser 的 {DB, Log} ⊇ DB.query 的 {DB}
fetchUser = \uid ->
  let
    result = DB.query q        // DB.query : ... ! {DB}
  in
    ...

// 非法：纯函数调用效应函数
pureHelper : Int -> Int
pureHelper = \n ->
  let
    result = DB.query q        // ❌ 编译错误：纯函数调用效应函数
  in
    ...
```

### 效应多态（单变量）

```kun
map : (a -> b ! e) -> List a -> List b ! e
```

`e` 是单效应变量，表示"回调的效应集"。调用时实例化：

```kun
let
  // result : List (Result Rows) ! {DB}
  result = map DB.query queries    // e := {DB}
in
  result
```

### Let 泛化与值限制

`let` 绑定泛化时同时泛化效应变量。采用**值限制**（value restriction，OCaml 风格）：

**规则**：

1. `let` 绑定的右侧为**语法值**（lambda/字面量/ADT 构造）→ 泛化类型变量与效应变量
2. `let` 绑定的右侧为函数应用/效应调用 → 不泛化，效应集固定
3. 递归 `let`：先分配效应变量，函数体检查后泛化

```kun
// 函数是值 → 泛化
let
  id = \x -> x                    // id : a -> a ! e，泛化 e
in
  ...                              // id 可在不同效应上下文使用

// 函数应用非值 → 不泛化
let
  result = DB.query q             // result : Result Rows ! {DB}，不泛化
in
  ...                              // result 固定效应集
```

**设计理由**：值限制避免多态引用破坏类型安全（经典 ML value restriction 问题），简单且可靠。

### HM 合一规则（效应集）

效应集合一：

| 约束 | 结果 |
|---|---|
| `! IO ~ ! IO` | 成立 |
| `! IO ~ ! {IO, File}` | 失败 |
| `! e ~ ! IO` | 成立，`e := {IO}` |
| `! e ~ ! {}` | 成立，`e := {}` |
| `! {IO, e} ~ ! {IO, File}` | 成立，`e := {File}` |
| `! e ~ ! {IO, e}` | 失败（occurs check） |

### 效应集有序性

效应集为**无序集合**：`{IO, File} ≡ {File, IO}`，合一时按排序后比较。

**规则**：

- 类型检查、`==` 比较、handler 匹配均按无序集合处理
- 编译器内部维护效应集为排序后的规范形式（如按字母序）
- HM 合一时 `{IO, e} ~ {File, e'}` 解为 `e := {File}`, `e' := {IO}`（顺序无关）

## Handler 系统

### Handler 类型

```kun
// Handler e a：消解效应集 e，产出类型 a
Handler : EffectSet -> Type -> Type
```

`Handler {DB} a` 表示"消解 DB 效应、产出 a 的 handler"。

### Handler 声明语法

```kun
<handlerName> : Handler {<Effect>} a ! {<handlerEffects>}
<handlerName> =
  handler <Effect> of
    <op1> <args> -> <impl>
    <op2> <args> -> <impl>
    ...
```

**`handler X of`** 形式，显式标注消解的效应。

### 内置效应 Handler

内置效应的 handler 实现于编译器源码（Zig），编译进 `kun` 二进制。用户不可定义内置效应的默认 handler，但可在 `main`/`TestCase.body` 内用自定义 handler 包装（通过 `continue` 委托默认）。`Test` 标准库效应的默认 handler `testHandler` 同样由运行器内置（与 IO/File 等内置效应默认 handler 同级），详见 [单元测试设计](testing.md)。

内置 handler 注册表在编译期生成，加载标准库 `effect` 声明时校验完整性。

### 用户效应 Handler

用户效应无默认 handler，必须显式 handle：

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

### `continue` 委托与 `abort` 提前终止

handler 内用 `continue` 委托外层或默认实现，用 `abort` 提前终止。

**`continue` 与 `abort` 是控制流原语**（非函数），不可作为值传递，不可嵌套在 lambda 中。

**`continue` 规则**：

| 操作 | 允许 | 说明 |
|---|---|---|
| `continue` 调用一次 | ✅ | 委托默认/外层 handler |
| `continue` 传不同参数 | ✅ | 允许参数变换 |
| `continue` 多次调用 | ❌ | 编译错误（不支持非确定性） |
| 既不 `continue` 也不 `abort` | ❌ | 编译错误（必须二选一） |
| `continue` 在 lambda 中 | ❌ | 编译错误 |
| `continue` 作为值传递 | ❌ | 编译错误 |

**`abort` 规则**：

`abort value` 提前终止 handler，返回 `value`（类型须与 handler 产出类型 `a` 一致）。不调用 `continue`，剩余计算不执行。

**编译器检查**：每条 handler 分支路径必须有且仅有一次 `continue` 或 `abort`。

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

**设计理由**：

- 不支持 `continue` 多次调用 → 排除非确定性（Kun 脚本场景不需要）
- 支持 `abort` → 提供 dry-run/缓存/提前终止能力
- 强制 `continue` 或 `abort` 二选一 → 保证 handler 语义完整
- 编译期静态分析 → 无运行时开销

### Handler 组合

```kun
(>>) : Handler {e1} a ! e11 -> Handler {e2} a ! e21 -> Handler {e1, e2} a ! {e11, e21}
```

```kun
composedHandler : Handler {DB, Log} a ! {Cmd, IO}
composedHandler =
  postgreHandler >> journaldLog
```

### `handle` 表达式（限入口函数）

**`handle with` 仅在 `main` 函数与 `TestCase` 值的 `body` 字段内可用**，业务函数不可使用。

```kun
handle
  <expr>
with
  <handler>
```

**入口级上下文**：

| 上下文 | 可用 `handle` | 说明 |
|---|---|---|
| `main` | ✅ | 程序入口 |
| `TestCase.body` | ✅ | `TestCase` 类型值的 `body` 字段，由 `kun test` 运行器在入口级上下文执行（详见 [单元测试设计](testing.md)） |
| 其他业务函数 | ❌ | 只声明效应，不消解 |

**识别机制**：`main` 函数名 + `TestCase` 类型值的 `body` 字段（运行器提供入口级上下文）。编译器对 `main` 与 `TestCase.body` 统一处理，允许其内 `handle`。

**测试用例识别规则**：

1. 文件命名：`<module>_test.kun`，与被测模块同目录共置（如 `lib/List.kun` 对应 `lib/List_test.kun`）；不识别 `tests/` 目录、不识别 `test-*.kun` 命名
2. 用例载体：导出的 `TestCase` 类型值（`type TestCase = TestCase { name, description, timeout, body, with }`），而非 `test*` 前缀函数
3. 收集规则：仅 `export` 列表中的 `TestCase` 类型值会被收集执行；未导出的 `TestCase` 类型绑定视为辅助构造（fixture、参数化模板），不参与执行
4. `body` 字段：零参效应函数 `Unit ! {Test, e}`，效应集必须含 `Test`，可选含用户效应 `e`

```kun
// lib/List_test.kun
import List (reverse)
import Test (Test, TestCase, test, assert)

export (testReverse)   // ← 仅导出的 TestCase 值才会被运行

testReverse : TestCase =
  test "reverse preserves elements" (\ ->
    let
      result = reverse [1, 2, 3]
      assert (result == [3, 2, 1])
    in
      ()
  )
```

> `TestCase` 类型、`Test` 效应、`testHandler`、`Test` 模块（`test`/`Test.with`/`Test.timeout`/`Test.describe`）的完整定义见 [标准库 Test 模块](standard-library.md#test-测试断言与结果)；完整测试设计见 [单元测试设计](testing.md)。

**业务函数的效应流向**：业务函数声明效应 → 冒泡到调用者 → 最终到 `main`（或 `TestCase.body`）→ 入口级上下文内 `handle` 消解。

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

测试用例示例（`Test.with` 模块函数声明式消解用户效应）：

```kun
// lib/UserService_test.kun
testFetchUser : TestCase =
  test "fetchUser returns user" (\ ->
    let
      result = fetchUser (UserId "1")
      case result of
        Ok user -> assert (user.name == "alice")
        Err _ -> fail "expected Ok, got Err"
    in
      ()
  )
  |> Test.with (mockDbHandler >> mockLogHandler)
```

> `kun test` 运行器在入口级上下文执行 `TestCase.body`：包装 `body!` → 用 `TestCase.with` 消解用户效应 → 用 `testHandler` 消解 `Test` 效应 → 产出 `TestResult`。因此 `body` 内可使用 `handle with`（与 `main` 同级）。

### Handler 效应变换

handler 实现内可调用其他效应，实现变换：

```kun
// DB 变换为 Cmd（用 psql 命令实现 DB）
postgreHandler : Handler {DB} a ! {Cmd, IO}
```

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

### 强制性保证

1. **编译期效应集追踪**：每个函数效应集由编译器推导
2. **调用经分发表**：效应调用 `X.op` 编译为分发表查找
3. **用户效应必须 handle**：未消解的用户效应冒泡到 `main`/`TestCase.body`，编译错误
4. **内置效应有默认**：未消解的内置效应运行时自动注入默认 Zig handler
5. **入口级 handle 限制**：`handle with` 仅 `main`/`TestCase.body` 可用，业务函数不可中途消解

### `main` 边界与效应集校验

**`main` 允许的效应**：

- 所有内置效应（`IO`/`File`/`Cmd`/`Random`/`DateTime`/`Signal`/`FFI`）
- 不允许用户效应（`DB`/`Log`/`Libc` 等），必须 `handle` 消解

**未消解效应的处理**：

- 内置效应：运行时自动注入默认 Zig handler
- 用户效应（含 `extern` 库效应）：编译错误，必须显式 `handle`
- `FFI` 效应到达 `main`：运行时检查 `--allow-ffi`

**错误消息模板**：

```
Error: Unhandled User Effect ─── src/main.kun:1:1
  Effect: DB
  In function: main
  Hint: 用户效应 DB 必须在 main 内 handle。
        添加：handle <expr> with dbHandler

Error: Unhandled Library Effect ─── src/main.kun:1:1
  Effect: Libc
  In function: main
  Hint: 库效应 Libc 未消解。
        选项 1：在 main 内 handle（自定义 handler）
        选项 2：不 handle，运行时自动注入默认（产生 FFI，需 --allow-ffi）
```

```kun
main : List String -> Unit ! {IO, File, Cmd, ...}
main = \args ->
  handle
    let
      result = fetchUser (UserId "1")
      ...
    in
      ()
  with
    postgreHandler >> journaldLog
  // 用户效应 DB/Log 被消解
  // 剩余 {Cmd, IO} 冒泡到 main，运行时自动注入默认 handler
```

### Stream 消费检查

**`let in` 统一后，Stream 消费检查的规则**：

1. **作用域**：检查粒度为单个 `let in` 块
2. **块内构造的 Stream**：必须在本块内消费（`toList`/`iter`/`fold`/`string`/`bytes`）
3. **跨块传递**：Stream 作为函数参数/返回值/绑定到外层 → 视为"已消费"，不追踪
4. **条件消费**：`case`/`if` 分支的所有分支均需消费，缺失分支编译错误
5. **`Cmd.timeout`/`retry` 交互**：返回 `Result (Stream String) CommandError`，`Ok` 分支 Stream 须消费，`Err` 分支豁免
6. **`defer` 交互**：`defer` 块内操作不计入消费分析

```kun
// ✅ 合法：块内消费
let
  stream = Cmd.stream (cmd ls { a } [ "/tmp" ])
  lines = stream |> Stream.lines |> Stream.toList
in
  lines

// ✅ 合法：跨块传递视为已消费
let
  stream = Cmd.stream (cmd ls { a } [ "/tmp" ])
in
  stream   // 传递给外层，视为已消费（外层负责）

// ❌ 编译错误：块内未消费
let
  stream = Cmd.stream (cmd ls { a } [ "/tmp" ])
  IO.println "got stream"
in
  ()   // stream 未消费
```

## FFI 系统

### 设计概要

FFI 采用**分层归属**设计：

- **底层 `FFI` 效应**：内置保留效应，所有 C 库调用最终产生 `! {FFI}`，受 `--allow-ffi` 控制
- **上层库效应**：每个 `extern` 块自动产生独立效应（如 `Libc`/`Curl`），可独立 handle/mock
- **自动桥接**：`extern` 块的默认 handler 自动生成，调用 `FFI.call`，用户无需手写桥接
- **仅 Linux 支持**：FFI 不做跨平台，专注 Linux `.so`/`dlopen`，不支持 Windows/macOS

### `extern` 块语法

```kun
extern <EffectName> from "<lib>" =
  { <func1> : <signature>
  , <func2> : <signature>
  , ...
  }
```

与 `effect`/`type` 形式一致：`<keyword> <Name> [修饰] = { <fields> }`。`from "lib"` 是必要修饰（库绑定）。

**库加载规则**（仅 Linux）：

- `<lib>` 为基础名，运行时按 Linux 规则查找：`lib<lib>.so` → `lib<lib>.so.X` → `<lib>.so`
- 搜索路径：`LD_LIBRARY_PATH` → `/lib` → `/usr/lib` → `/usr/local/lib`
- 加载方式：`dlopen(lib, RTLD_LAZY)`，首次调用时加载，结果缓存
- 非 Linux 平台：`extern` 声明编译错误（FFI 不跨平台）

**示例**：

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

**语法细节规则**：

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

### `extern` 块的语义

一个 `extern` 块自动完成三层：

1. **效应声明**：自动生成 `effect Libc = { strlen : ..., fopen : ..., ... }`
2. **库绑定**：记录 `Libc` 效应关联库 `"libc"`
3. **默认 handler**：编译器自动生成，每个操作调用 `FFI.call`，产生 `! {FFI}`

```kun
// 编译器为 extern Libc from "libc" { strlen : String -> Int } 自动生成：
effect Libc = { strlen : String -> Int }

// 默认 handler（不可见，编译器生成）
defaultLibcHandler : Handler {Libc} a ! {FFI}
defaultLibcHandler =
  handler Libc of
    strlen s ->
      unsafe (FFI.call "libc" "strlen" [StringVal s])
        |> ffiToInt
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

### `FFI.call` 与 `unsafe`

`FFI.call` 是直接调用 C 的底层接口，**类型擦除**（`List FfiValue -> FfiValue`），需 `unsafe`：

```kun
// 直接调用 FFI.call，需 unsafe（罕见，用户通常用 extern 块）
let
  len = unsafe (FFI.call "libc" "strlen" [StringVal "hello"]) |> ffiToInt
in
  len
```

**`FfiValue` 类型定义**：

```kun
type FfiValue =
  IntVal Int
  | FloatVal Float
  | BoolVal Bool
  | StringVal String
  | BytesVal Bytes
  | PathVal Path
  | OpaqueVal (Opaque Any)     // 完全不透明
  | BufferVal FfiBuffer           // FFI 内存缓冲区
  | UnitVal

// 解构函数（由编译器内置，extern 块默认 handler 使用）
ffiToInt : FfiValue -> Int
ffiToFloat : FfiValue -> Float
ffiToBool : FfiValue -> Bool
ffiToString : FfiValue -> String
ffiToBytes : FfiValue -> Bytes
ffiToPath : FfiValue -> Path
ffiToOpaque : FfiValue -> Opaque a
ffiToUnit : FfiValue -> Unit
```

**`unsafe` 的归属**：

| 调用形式 | 需 `unsafe` | 理由 |
|---|---|---|
| `Libc.strlen "hello"`（extern 块函数） | ❌ | 效应名标注风险，签名类型安全 |
| `FFI.call "libc" "strlen" [...]`（直接调用） | ✅ | 类型擦除，绕过类型安全 |
| `Opaque`/`FfiBuffer` 不安全操作 | ✅ | 绕过类型安全 |

常规 FFI 调用经 `extern` 块，不需 `unsafe`。`unsafe` 仅用于直接 `FFI.call` 等罕见场景。

**复杂 C 类型支持范围**：

MVP 仅支持：

- 基础类型：`Int`/`Float`/`Bool`/`String`/`Bytes`/`Path`/`Unit`
- `Opaque a`：不透明指针
- `?T`：可选（NULL 表示 Nil）
- `List T`：数组（自动转 `T*` + 长度）

MVP 不支持：

- C struct 按值传递（用 `Opaque` 包装 + FFI 函数访问字段）
- C union（不支持）
- 函数指针/回调（未来考虑）
- 变参函数（不支持）

### FFI 内存管理（`let in` 闭包自动释放）

`Ffi.alloc` 申请的内存绑定到**所在 `let in` 块**的生命周期，块结束（正常或 panic）自动释放：

```kun
let
  buf = Ffi.alloc 4096              // FFI 内存，绑定此 let in 块
  n = Libc.fread buf 1 4096 handle  // 使用 buf
  content = Ffi.toBytes buf n       // 拷贝到 Kun Bytes（可逃逸）
in
  content
// 块结束，buf 自动释放（无需手动 free）
```

### `FfiBuffer` 不逃逸（编译器内置规则）

`FfiBuffer` 是编译器内置的特殊类型，其不逃逸规则由**编译器硬编码**强制，不采用属性标注形式。

**编译器内置规则**：

1. `FfiBuffer` 类型的值绑定到**所在 `let in` 块**
2. 不可作为 `let in` 块的返回值（`in` 后表达式）
3. 不可赋值给外层 `let in` 块的绑定
4. 可作为参数传递给同块内的函数（但函数不可返回它）
5. 可通过 `Ffi.toBytes`/`Ffi.toString` 拷贝为普通类型后逃逸

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

// ❌ 编译错误：FfiBuffer 不可赋值给外层
let
  outer =                           // 外层绑定
    let
      inner = Ffi.alloc 1024        // inner : FfiBuffer（内层）
    in
      inner                         // 错误：FfiBuffer 不可逃逸到外层
in
  ...
```

**实现**：编译器类型检查阶段识别 `FfiBuffer` 类型（内置类型表），追踪其作用域，违反则编译错误。无需用户标注，规则硬编码在编译器中。

### `Opaque` 类型

不透明指针，Kun 不可解引用，仅传递给其他 FFI 函数：

```kun
type Opaque a    // a 是指向的类型，Opaque 表示完全未知
```

`Opaque a` 的 `a` 是**幻影类型**（phantom type）：

- `Opaque File` 与 `Opaque Curl` 是**不同类型**，编译期区分
- 运行时均为 `void*`，无运行时开销
- 不可解引用、不可算术，仅传递给其他 FFI 函数
- 类型参数 `a` 用于编译期类型安全，防止不同库的句柄误传

用于 C 库返回的句柄（`FILE*`/`curl*`/`sqlite3*` 等），由专门的 FFI 函数释放（如 `fclose`/`curl_easy_cleanup`）。

**`Opaque` 的内存管理**：

- C 库返回的 `Opaque`，其内存所有权由 C 库决定（需查 C 文档）
- 需手动释放的 `Opaque`，用 `defer` 配合释放函数保证释放
- `Opaque` 不可解引用、不可算术，仅传递

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

### 效应流向

**默认场景**（用户不 handle 库效应）：

```
Libc.strlen "hello" ! {Libc}
  → 冒泡到 main
  → 运行时自动注入 defaultLibcHandler
  → defaultLibcHandler 调用 FFI.call，产生 ! {FFI}
  → FFI 冒泡到 main
  → 运行时默认 FFI handler（Zig ffi_call）消解，需 --allow-ffi
```

**自定义 handler 场景**（main 内包装）：

```kun
loggingLibc : Handler {Libc} a ! {IO, Libc}
loggingLibc = handler Libc of
  strlen s ->
    let
      IO.println f"strlen({s})"
      result = continue (Libc.strlen s)   // 委托默认 Libc handler
    in
      result
  ...
```

效应流向：`Libc.strlen ! {Libc}` → `loggingLibc` 拦截 → `continue` 委托默认 → `FFI.call ! {FFI}` → 冒泡到 main。

**Mock 场景**（测试）：

```kun
mockLibc : Handler {Libc} a
mockLibc = handler Libc of
  strlen _ -> 5           // 不调用 continue，无 FFI
  fopen _ _ -> Nil
  ...

// lib/Libc_test.kun
testStrlen : TestCase =
  test "strlen returns length" (\ ->
    let
      len = Libc.strlen "hello"
      assert (len == 5)
    in
      ()
  )
  |> Test.with mockLibc    // Libc 被 mock，无 FFI 产生
```

测试中 `Libc` 被 mock，不触发真实 C 调用，可独立验证业务逻辑。Mock handler 通过 `Test.with` 模块函数注入（声明式效应隔离，设置 `TestCase.with` 字段），详见 [单元测试设计](testing.md)。

### FFI 防欺骗机制

`FFI` 是内置保留效应，其身份不可伪造。四层防护：

1. **保留名检查**：`IO`/`File`/`Cmd`/`Random`/`DateTime`/`Signal`/`FFI` 均为编译器保留名，用户不可定义同名 `effect`
2. **extern 调用强制产生内置 FFI**：`extern` 块的默认 handler 调用 `FFI.call`，编译器硬编码为内置 FFI 效应
3. **命名空间隔离**：内置效应在编译器内部命名空间，不查用户定义
4. **运行时 `--allow-ffi` 检查**：检查最终冒泡到 `main` 的 FFI 效应，未启用则拒绝执行

用户无法通过命名、定义、handler 等手段绕过 FFI 安全检查。`FFI` 效应身份与边界得到完整保护。

### 完整 FFI 示例

```kun
// Libc.kun
export (Libc)

extern Libc from "libc" =
  { strlen : String -> Int
  , fopen : String -> String -> ?(Opaque File)
  , fclose : Opaque File -> Int
  , fread : FfiBuffer -> Int -> Int -> Opaque File -> Int
  }

// FileReader.kun
export (readFileContent)
import Libc (Libc)
import Ffi (Ffi, FfiBuffer, alloc, toString)

readFileContent : Path -> Result String String ! {Libc}
readFileContent = \path ->
  let
    fp = Libc.fopen (Path.toString path) "r"
  in
    case fp of
      Nil -> Err "open failed"
      Some handle ->
        let
          defer (Libc.fclose handle)

          buf = Ffi.alloc 4096
          n = Libc.fread buf 1 4096 handle
          content = Ffi.toString buf n
        in
          Ok content

// main.kun
import FileReader (readFileContent)

main : List String -> Unit ! {Libc, IO}
main = \args ->
  let
    result = readFileContent (Path.fromString "/etc/hostname")

    case result of
      Ok content -> IO.println content
      Err e -> IO.println e
  // Libc 冒泡，运行时注入默认 Libc handler
  // 默认 handler 调用 FFI.call，产生 FFI
  // FFI 冒泡，运行时默认消解（需 --allow-ffi）
```

## 类型检查算法

类型检查采用 HM（Hindley-Milner）推断，两阶段流程（约束生成 + 合一），详细实现见[系统基线](../architecture/system-baseline.md#类型检查算法）。

### Let 多态与递归绑定

`let` 绑定支持递归——`let f = \x -> ... f (x - 1) ... in f 5` 中，`f` 的类型在 `let` 体中被泛化后实例化到 `f` 自身的引用位置。递归 `let` 的类型推断分两阶段：(1) 为 `f` 分配类型变量 `a`；(2) 在合一 `f` 的引用时将 `a` 实例化为新变量，与函数体推断出的类型合一。

互递归函数通过相互引用的 `let` 绑定处理：`let even = \x -> ...; odd = \y -> ... in ...`——两个绑定的类型先在各自作用域内泛化，然后在对方的引用处实例化。`let` 绑定组中所有函数的类型变量同时泛化，形成多态递归绑定组。

**值限制**：`let` 绑定的右侧为语法值（lambda/字面量/ADT 构造）时泛化类型与效应变量；右侧为函数应用/效应调用时不泛化。

## 错误信息设计

HM 推断器产生的原始合一错误（如 "cannot unify `a -> b` with `Int`"）对目标用户（Linux 运维/DevOps）不可理解。编译器将原始合一错误转化为面向运维的结构化错误消息，包含：源位置、期望类型、实际类型、错误原因、修复建议。

### 错误溯源

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
> | `Nil For Non-Nilable` | Nil 赋值给非 ?T 类型 |
> | `Nilable Used As Non-Nilable` | ?T 用于非 ?T 位置 |
> | `Nested Nilable` | Nilable 不可嵌套 |
> | `Non-Exhaustive Pattern` | 模式匹配非穷举 |
> | `Redundant Pattern` | 冗余模式 |
> | `Unknown Field` | 未知字段 |
> | `Missing Field` | 缺少字段 |
> | `Tuple Index Out Of Range` | 元组索引越界 |
> | `Effect In Pure Function` | 纯函数调用效应函数 |
> | `Pure Function Returns Unit` | 纯函数返回 Unit |
> | `Stream Not Consumed` | Stream 未消费 |
> | `Unhandled User Effect` | 未消解的用户效应 |
> | `Unhandled Library Effect` | 未消解的库效应 |
> | `Recursive Type Expansion Limit` | 递归展开超限 |
> | `Unbound Variable` | 未定义变量 |
> | `Unbound Type` | 未定义类型 |
> | `Infinite Type` | 无限类型 |
> | `Expected` | 期望 |
> | `Found` | 发现 |
> | `Hint` | 提示 |
> | `Reason` | 原因 |

### 错误消息模板（20 个最常见场景）

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
     Hint: if 表达式的所有分支必须返回相同类型
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

**Nilable 类型（`?T`）**

6. **`NilAssignedToT`**（Nil 赋值给非 `?T` 类型）
   ```
   Error: Nil For Non-Nilable ─── src/main.kun:{line}:{col}
     Type: {expected} (not nilable)
     ──┤ {context_line}
     Hint: {expected} 不可为 Nil。使用 ?{expected} 标注为可选类型，或提供非 Nil 值
   ```

7. **`NilableUsedAsT`**（?T 用于期望 T 的位置）
   ```
   Error: Nilable Used As Non-Nilable ─── src/main.kun:{line}:{col}
     Expected: {expected}
     Found:    ?{inner_type}
     ──┤ {context_line}
     Hint: 值可能为 Nil。使用 case 模式匹配收窄（Some x / Nil）
   ```

8. **`NestedNilable`**（嵌套 Nilable 禁止）
   ```
   Error: Nested Nilable ─── src/main.kun:{line}:{col}
     Type: ?{?{inner_type}}
     ──┤ {context_line}
     Hint: Nilable 不可嵌套。用 Result (?Int) Error 或自定义 ADT。
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
      Hint: 纯函数（! {}）不能调用效应函数 {called_func}。函数体声明效应集（! E）或移除效应调用
    ```

15. **`StreamNotConsumed`**（Stream 未被消费）
    ```
    Error: Stream Not Consumed ─── src/main.kun:{line}:{col}
      ──┤ {context_line}
      Hint: Stream 未被终端操作消费，子进程可能变为僵尸进程。使用 Stream.toList / Stream.iter / Stream.fold 消费
    ```

16. **`UnhandledUserEffect`**（未消解的用户效应冒泡到 main）
    ```
    Error: Unhandled User Effect ─── src/main.kun:{line}:{col}
      Effect: {effect_name}
      In function: main
      ──┤ {context_line}
      Hint: 用户效应 {effect_name} 必须在 main 内 handle。
            添加：handle <expr> with {effect_lower}Handler
    ```

17. **`UnhandledLibraryEffect`**（未消解的库效应）
    ```
    Error: Unhandled Library Effect ─── src/main.kun:{line}:{col}
      Effect: {effect_name}
      In function: main
      ──┤ {context_line}
      Hint: 库效应 {effect_name} 未消解。
            选项 1：在 main 内 handle（自定义 handler）
            选项 2：不 handle，运行时自动注入默认（产生 FFI，需 --allow-ffi）
    ```

**Unbound / 作用域**

18. **`UnboundVariable`**（未定义变量）
    ```
    Error: Unbound Variable ─── src/main.kun:{line}:{col}
      Name: {var_name}
      ──┤ {context_line}
      Hint: 变量 {var_name} 未定义。是否拼写错误？是否缺少 import？
    ```

19. **`UnboundType`**（未定义类型）
    ```
    Error: Unbound Type ─── src/main.kun:{line}:{col}
      Name: {type_name}
      ──┤ {context_line}
      Hint: 类型 {type_name} 未定义。类型名必须以大写字母开头。是否拼写错误？是否缺少 import？
    ```

**泛型 / 递归**

20. **`InfiniteType`**（无限类型——occurs check 失败）
    ```
    Error: Infinite Type ─── src/main.kun:{line}:{col}
      Type: {var} 出现在自身定义中
      ──┤ {context_line}
      Hint: 类型变量 {var} 引用自身，需要 type 别名来定义递归类型。匿名类型中不能直接引用自身
    ```

21. **`RecursiveAliasDepth`**（递归别名展开达到上限）
    ```
    Error: Recursive Type Expansion Limit ─── src/main.kun:{line}:{col}
      Expansion path: {path}
      ──┤ {context_line}
      Hint: 递归 type 别名展开超过 256 层限制。展开路径：{path}。检查是否存在意外的循环引用，或设置 KUN_MAX_TYPE_DEPTH 环境变量
    ```

**纯函数约束**

22. **`PureUnitReturn`**（纯函数返回 Unit）
    ```
    Error: Pure Function Returns Unit ─── src/main.kun:{line}:{col}
      Function: {func_name}
      Signature: {signature}
      ──┤ {context_line}
      Hint: 纯函数返回 `Unit` 无意义（无输出、无副作用）。声明效应集（如 `! {IO}`），或改为返回有效值
    ```

### 验证标准

类型检查器的正确性通过以下验收标准确认（具体测试用例留到实现阶段编写）：

1. 每个错误消息模板至少对应一个正例（通过类型检查的合法程序）和一个反例（产生该模板中指定错误的非法程序）
2. HM 推断的回归测试覆盖以下关键场景：Let 多态、递归 let 绑定、互递归函数、泛型 ADT、Nilable 嵌套禁止、效应集合一、效应多态单变量、值限制
3. 效应检查器验证：纯函数内包含效应调用时精确报告 `Effect In Pure Function`；`let in` 块内未消费的 Stream 精确报告 `Stream Not Consumed`；未消解用户效应冒泡到 `main` 精确报告 `Unhandled User Effect`
4. 错误恢复：单文件内多个独立类型错误全部报告（非遇第一个停止）

测试基础架构见 `standard-library.md` 的 `Test` 模块与 [单元测试设计](testing.md)。

### 错误级别

| 级别 | 含义 | 行为 |
|------|------|------|
| Error | 类型不匹配，程序无法安全执行 | 拒绝编译，退出码 1 |
| Warning | 潜在问题（冗余模式、未消费 Stream、纯表达式独立语句） | 输出警告，编译通过 |

### 错误恢复

类型错误不阻断后续检查。类型检查器在遇到类型不匹配时：

1. 为失败节点分配一个特殊占位类型 `TypeError`（仅用于继续检查，不暴露给用户）
2. 依赖该节点类型的后续节点使用 `TypeError` 进行约束生成（避免级联报错）
3. 最终报告所有独立错误（每个错误对应一个根本原因），过滤掉以 `TypeError` 为依赖的派生错误

### 实现原则

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

这些函数仅在编译期（`comptime`）可用，由 `Cli.parse`、`Parser.Record.fromJson` 和 `toString` 泛型分发等 Primitive 函数调用。API 在 `TypeEnv` 已完全构造（类型检查完成后）方可使用。

> **Kun TypeId ↔ Zig comptime type 映射**：`TypeId` 是 `TypeEnv.types` 数组的索引。在类型检查完成（Typed AST 构建后）的 `comptime` 上下文中，编译器通过 `@typeInfo(TypeEnv.types[id])` 获取 Zig 类型结构信息。此映射仅在编译期为有效——运行时 `TypeEnv` 中的类型表示为值，不可用作 Zig 类型。`getTypeName` 等 API 函数在 `comptime` 环境中通过此映射返回类型信息供 `Cli.parse` 和 `Parser.Record.fromJson` 使用。

## 类型表示与运行时

类型在编译后的运行时表示及 C ABI 映射见[系统基线](../architecture/system-baseline.md#类型运行时表示)。类型系统专注于编译期语义，运行时内存布局属于架构实现细节。

`type` 定义的 ADT 运行时为 tagged union（`{tag, payload}`），单变体与多变体一致，**不做 tag 擦除**。`alias` 编译期展开为底层类型，无运行时存在。

## 参考

- [应用概览](app-overview.md) — Kun 语言功能全景
- [功能清单](feature-inventory.md) — 功能实现状态追踪
- [语法设计](syntax.md) — `effect`/`handler`/`handle`/`extern`/`cmd` 字面量语法
- [OS 命令调用机制](command-system.md) — `cmd` 字面量与 Command 执行
- [标准库](standard-library.md) — `Lazy`/`Equal`/`FFI`/录制回放等模块
- [系统基线](../architecture/system-baseline.md) — 运行时与类型系统概览
- [模块边界](../architecture/module-boundaries.md) — 类型检查器在架构中的位置

