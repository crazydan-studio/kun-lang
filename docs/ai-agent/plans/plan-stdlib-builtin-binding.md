# 执行计划：标准库内置函数绑定机制设计

## 背景与目标

当前 `design/standard-library.md` 定义了 30+ 模块的完整 API，`architecture/system-baseline.md` 将标准库实现分为两类（纯 Kun 实现 / Primitive 实现），但对以下关键细节未定义：

1. 无逐函数级别的实现类别标注，无法区分混合模块（如 `File.readString` 是 Primitive，`File.copy` 是纯 Kun）
2. Primitive 函数表的存储结构、初始化流程、绑定机制未定义
3. 用户代码隐式覆盖受保护模块名的防护机制缺失（当前搜索路径 `lib/` > `$KUN_PATH` > `<runtime>/lib/kun/` 反而赋予用户代码最高优先级）
4. "可用 Kun 代码实现"的决策标准不明确

目标：在不改变现有 API 设计的前提下，补全标准库函数与解释器内置逻辑的绑定机制设计，确保安全性（防同名覆盖、防篡改）的同时保持模块系统对用户的透明性。

## 变更范围

### 修改文件

| 文件 | 变更内容 | 预估行数 |
|------|---------|---------|
| `architecture/system-baseline.md` | 新增"Primitive 函数表与模块绑定"章节，定义表结构、初始化流程、模块加载时的绑定时序、安全防护规则 | ~170 行 |
| `design/standard-library.md` | 为每个函数签名标注实现类别（`[Primitive]` / `[PureKun]`）；新增全局分类说明段落 | ~100 行 |
| `architecture/module-boundaries.md` | 标准库模块列表补充实现类别标注，依赖图中标注 Primitive 绑定接口 | ~25 行 |
| `plans/index.md` | 新增本计划条目 | ~5 行 |
| `context/project-context.md` | 活跃工作更新 | ~5 行 |

### 不修改的文件

- `design/type-system.md` — 类型定义不变
- `design/syntax.md` — 语法不变
- `design/command-system.md` — 命令系统不变
- `requirements/mvp.md` — MVP 范围不变

## 实施步骤

### Step 1: 扩展 `architecture/system-baseline.md` — Primitive 函数表与模块绑定

**前置依赖**：无

新增章节 `## Primitive 函数表与模块绑定`，包含以下子章节：

#### 1.1 Primitive 函数表结构

定义 Primitive 函数表在 Zig 中的数据结构：

- 键：模块名 + "." + 函数名（如 `"IO.println"`、`"File.readString"`）
- 值：Zig 函数指针，签名为 `*const fn (env: *RuntimeEnv, args: *const Value) Value`
- 存储：编译期常量表（`comptime` 生成的静态数组），运行时无分配开销
- 生命周期：全局堆分配，初始化后不可变（`const` 语义）

#### 1.2 初始化流程

在运行时初始化阶段（`system-baseline.md` 第 37-40 行）细化：

```
运行时环境建立
  ├── 创建 Arena 分配器
  ├── 设置全局求值环境
  └── 注册 Primitive 函数表
        ├── 编译期常量表直接载入
        ├── 表标记为只读（const 指针）
        └── 记录受保护模块名集合 {IO, File, Env, Process, Cmd, Random, Stream, Signal}
```

#### 1.3 模块加载时的绑定规则

定义模块加载器在解析 `import` 时的行为：

```
import M
  │
  ├── 1. M 在受保护模块名集合中？
  │     ├── 是 → 跳过文件系统搜索
  │     │       ├── 加载 <runtime>/lib/kun/M.kun（仅用于获取签名和文档）
  │     │       ├── 对每个 export 函数：若 Primitive 表中有 M.f 绑定 → 函数体替换为 Zig 实现
  │     │       └── 若用户在 lib/M.kun 或 $KUN_PATH/M.kun 定义了同名模块 → 编译警告 "module M is a protected built-in; user definition is ignored"
  │     └── 否 → 走常规文件系统搜索路径（lib/ → $KUN_PATH → <runtime>/lib/kun/）
  │
  └── 2. 函数名冲突检测：
        └── 同一模块内，Primitive 绑定的函数名不可被同模块 Kun 代码覆盖
            └── 签名声明可以（文档用途），但函数体以 Primitive 为准
```

#### 1.4 安全防护规则

| 攻击面 | 防护机制 |
|--------|---------|
| 用户定义 `lib/IO.kun` 覆盖内置模块 | 受保护模块名跳过文件搜索，用户定义不生效（编译警告） |
| 运行时修改 Primitive 表 | 编译期常量表，运行时无修改入口（`const` + 无 setter API） |
| 用户在同模块内定义与 Primitive 同名的函数 | 编译错误："function `f` is a protected built-in; cannot be redefined in module M" |
| 用户 `import` 后 `=` 重新绑定 | 模块导出不可变；`IO = { println = myPrintln }` 仅创建当前作用域新绑定，不影响模块系统 |
| 恶意 Kun 文件以受保护模块名命名 | 受保护模块名集合白名单，不受文件系统内容影响 |

### Step 2: 标注 `design/standard-library.md` — 实现类别

**前置依赖**：Step 1

为每个函数的签名行追加实现类别标注。标注格式：在函数签名注释中追加 `[Primitive]` 或 `[PureKun]`。

#### 2.1 分类标准

| 条件 | 类别 | 标注 |
|------|------|------|
| 需要系统调用（fork/exec/read/write/stat/getenv/signalfd 等） | Primitive | `[Primitive]` |
| 需要编译期类型内省（`toString`、`Cli.parse` 等） | Primitive | `[Primitive]` |
| 需要直接操作内存布局（哈希表插入、列表扩容、切片指针操作） | Primitive | `[Primitive]` |
| 纯数据变换/组合子（无副作用、无指针操作） | PureKun | `[PureKun]` |
| 编译器级语法（`Cmd.<bin>`、`do`、`defer`、`case` 等） | 不标注 — 这些是语法而非函数 |

#### 2.2 各模块标注概览

| 模块 | Primitive 函数 | PureKun 函数 | 备注 |
|------|---------------|-------------|------|
| `Int` | 无（运算符 `+`/`-`/`*`/`/` 是编译器内置语法） | `neg`、`abs`、`fromString`、`toFloat`、`toString` | 基础运算符由编译器直接处理 |
| `Float` | 无 | `neg`、`abs`、`floor`、`ceil`、`round`、`sqrt`、`approxEqual`、`fromString`、`toInt`、`toString` | `sqrt` 依赖 `sqrt` 运算符（编译器内置） |
| `String` | `length`、`slice` | `(++)`、`contains`、`startsWith`、`endsWith`、`split`、`join`、`trim`、`toUpper`、`toLower`、`replace`、`replaceAll`、`toString` | `length` 需直接读取 `Slice.len`；`slice` 需直接操作指针 |
| `Bytes` | 无 | `fromHex`、`toHex`、`fromString`、`toString` | |
| `Char` | 无 | `of`、`fromInt`、`isDigit`、`isAlpha`、`isUpper`、`isLower`、`isWhitespace`、`isControl`、`toUpper`、`toLower`、`toInt` | 字符分类依赖 Unicode 码表查找，但可用纯 Kun 模式匹配实现 |
| `Regex` | `isMatch`、`firstMatch`、`allMatches`、`replace`、`replaceAll`、`split` | `fromString` | 正则引擎本身是 C 库（PCRE2/regexec），必须 Primitive |
| `Math` | 无 | 全部为 PureKun | 依赖编译器内置算术运算符 |
| `Function` | 无 | `identity`、`always`、`<\|`、`\|>`、`<<`、`>>` | |
| `List` | `length`、`head`、`last`、`get`、`append`、`reverse`、`sort`、`slice`、`take`、`drop` | `map`、`filter`、`filterMap`、`fold`、`reduce`、`iter`、`all`、`any` | 结构操作需直接操作 `Array.length`/`ptr`；高阶函数可用 Kun 表达 |
| `Map` | `get`、`keys`、`values`、`size`、`insert`、`remove` | `update`、`fromList`、`toList`、`merge` | 哈希表操作需直接操作桶数组 |
| `Set` | `size`、`isEmpty`、`contains`、`insert`、`remove` | `union`、`intersect`、`diff`、`toList`、`fromList` | 同上 |
| `Result` | 无 | `map`、`mapError`、`andThen`、`withDefault`、`ok`、`isOk`、`isErr` | |
| `Nil` | 无 | `withDefault`、`map`、`orElse`、`toResult`、`andThen` | `Nil` 变体本身是编译器内置 |
| `Stream` | `fromList`、`range`、`lines`、`linesMax`、`string`、`bytes`、`toList`、`iter`、`fold` | `map`、`filter`、`take`、`drop`、`parseMap`、`parseMapKeep` | tagged union 构造/消费需 Primitive |
| `IO` | `print`、`println`、`readln` | 无 | 全部需要 `write`/`read` syscall |
| `File` | `list`、`mkdir`、`mkdirAll`、`exists`、`readString`、`writeString`、`readBytes`、`writeBytes`、`stat`、`touch`、`remove`、`removeDir`、`createTempFile`、`createTempDir`、`rename`、`glob` | `copy` | `copy` 可用 `readString`+`writeString` 组合 |
| `Env` | `getenv` | 无 | 需要环境变量 syscall |
| `Cmd` | `exec`、`exec?`、`pipe`、`pipe?`、`which`、`timeout`、`retry` | `withEnv`、`withStdin`、`mergeStderr`、`withCwd`、`withRunAs`、`withRawOpt`、`andThen`、`orElse`、`xargs` | 装饰函数为纯 Command 值变换 |
| `Process` | `exit`、`pid`、`uid`、`gid`、`kill`、`wait`、`sleep` | 无 | |
| `Random` | `int`、`bytes`、`float`、`shuffle` | 无 | 需要 `getrandom` syscall |
| `Path` | 无 | `cwd`、`parent`、`fileName`、`extension`、`join`、`(++)`、`fromString`、`fromBytes`、`component`、`toString`、`toBytes` | 路径是 `[]u8` 切片，字符串操作即可 |
| `Duration` | 无 | 全部为 PureKun | 运行时表示为 i64，算术即可 |
| `DateTime` | `format`、`parse` | `of`、`fromUnixSecs`、`toUnixSecs`、字段访问、算术 | `format`/`parse` 需要时区数据处理 |
| `Pid`、`Signal`、`FileType`、`FileMode`、`FileStat`、`ExitCode`、`Uid`、`Gid` | 无 | 全部为 PureKun | 这些是 newtype/enum/record，构造函数和访问器无需系统调用 |
| `IOError`、`CommandError` | 无 | 全部为 PureKun | ADT 构造和模式匹配 |
| `Validator` | 无 | `oneOf`、`range`、`nonEmpty`、`regex` | |
| `Decimal` | 无 | 全部为 PureKun | 基于 `Int` 尾数和指数的精确十进制 |
| `Cli` | `parse`、`show` | `flag`、`option`、`count`、`arg`、`withDefault`、`withRequires`、`withNegation`、`withEnvVar`、`withValidator`、`oneOf` | `parse` 需要编译期代码展开（v0.5）；声明器为纯值构造 |
| `Parser` | `fromJson`、`fromRecord` | 无 | 需要编译期代码展开（v0.5） |
| `Test` | 无 | `equal`、`ok`、`panics` | |
| `Task` | `spawn`、`all` | 无 | 需要 `fork`/线程（v0.5） |

#### 2.3 标注格式示例

在 `standard-library.md` 的函数签名中追加注释（仅标注，不改变签名或文档结构）：

```kun
// 取反
neg : Int -> Int                   // [PureKun]

// 从 String 转换为 Int（可能失败）
fromString : String -> Result Int String  // [PureKun]
```

对 Primitive 函数使用独立注释行说明为何不可用纯 Kun：

```kun
// 读取文件全部内容为 String
// [Primitive] — 需要 read(2) 系统调用
readString : Path -> Result String IOError
```

### Step 3: 更新 `architecture/module-boundaries.md`

**前置依赖**：Step 1, Step 2

- 标准库模块列表补充实现类别标注
- 依赖图中标注"运行时 → 标准库 (Primitive 绑定接口)"
- 模块职责说明中标准库部分补充绑定规则引用

### Step 4: 更新元数据文件

**前置依赖**：Step 1, Step 2, Step 3

- `plans/index.md`：新增本计划条目
- `context/project-context.md`：更新活跃工作与任务路由记录

## 验证方法

1. **构建验证**：`cd docs && pnpm lint && pnpm build`
2. **一致性审查**：逐文件检查变更未引入与其他文档（`type-system.md`、`syntax.md`、`command-system.md`）的矛盾
3. **分类完整性**：对照 `standard-library.md` 的每个函数，确认均有实现类别标注
4. **安全覆盖**：逐项验证安全防护规则覆盖了所有攻击面
5. **搜索路径验证**：确认受保护模块绑定规则与现有搜索路径设计不冲突

## 风险评估

| 风险 | 缓解措施 |
|------|---------|
| Primitive/PureKun 分类争议（某些函数处于灰色地带） | 以"保守内置"为原则——不确定时标记为 `[Primitive]`，后续可按需从 Primitive 降级到 PureKun（方向可逆，反之不可） |
| 受保护模块列表未来扩展时忘记更新绑定表 | 绑定表与受保护模块名集合来自同一编译期常量定义，编译器自动确保一致性 |
| 标注格式在后续大规模重写时被遗漏 | 在 `standard-library.md` 首部新增约定说明段落，声明标注为设计契约的一部分 |
| 与后续泛型/类型类设计冲突 | 当前标注基于 v0.1.0 无类型类的假设；若后续引入 `Hashable` 类型类，`Map`/`Set` 的 PureKun 函数可自然迁移 |

## 审计要点

1. Primitive 函数表的结构是否与 Zig 编译期能力兼容
2. 受保护模块绑定规则是否与模块搜索路径逻辑一致
3. 安全防护规则是否覆盖了已知攻击面（同名覆盖、运行时篡改、模块重绑定）
4. 每个模块的 Primitive/PureKun 分类是否正确反映了"必须内置"与"可用 Kun 表达"的边界
5. 标注格式不改变已有 API 签名

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.15 | 初始版本 |
