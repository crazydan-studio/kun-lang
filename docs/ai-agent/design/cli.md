# `Cli` — 命令行参数解析

## 设计定位

对标 Python `argparse`，以类型驱动的方式将 `main` 接收的 `List String` 解析为类型安
全的 Record。`Cli` 是纯标准库模块，不依赖编译器内置支持——其类型安全由 HM 推断 +
编译期代码展开实现，与 `Parser.Record.fromJson` 机制一致。

`Cli` 模块仅导出类型结构与声明器函数，不提供构造器或修饰器包装函数——用户直接操作
`CliSpec` 和 `CliMeta` 等 Record 数据，通过标准 Record 语法和 Map 字面量/更新语法
进行组装。

需显式导入：

```kun
import Cli
```

### 设计原则

- **默认严格**：未知选项报错并给出最接近的合法匹配（Did-you-mean）
- **类型即 schema**：Record 字段类型决定消费行为——`Bool` → flag，`?T` → 可选
  option，`List T` → 余量位置参数或可重复选项
- **声明即文档**：声明器携带的字符串既是解析规则，也是帮助文本——`--help` 始终自动
  生成；`--version` 同样自动可用
- **数据即接口**：`CliSpec` 和 `CliMeta` 为普通 Record 类型，用户通过标准 Record
  字面量构造、通过 `{ r | field = value }` 更新、通过 `Map` 模块操作子命令。不提供
  额外的包装函数
- **管道修饰**：`withDefault`、`withChoices`、`withRequires` 等修饰器通过 `|>` 链
  式应用
- **kebab-case → camelCase**：选项名、位置参数名和子命令名使用 kebab-case 书写，
  编译器在 `Cli.parse` 调用点自动映射为 Record 字段的 camelCase 名称

### 命名约定

声明器中的 `name` 参数（长选项名、位置参数名、子命令名）统一使用 **kebab-case**（
全小写，连字符分隔）。编译器在 `Cli.parse` 调用点自动将其转换为 **camelCase** 以匹
配 Record 字段名：

| 声明名 (kebab-case) | Record 字段名 (camelCase) |
| --------------------- | -------------------------- |
| `verbose` | `verbose` |
| `dry-run` | `dryRun` |
| `max-jobs` | `maxJobs` |
| `compiler-args` | `compilerArgs` |

转换规则：按 `-` 分割，首段保持原样，后续每段首字母大写。

短选项（`Char`）不受此规则影响——始终为单字符。若声明器不提供短选项，传 `Nil` 即可
（仅长选项）。

#### 输入验证

`name` 参数在声明器调用时（编译期）进行格式校验，必须满足：

- 仅含小写字母 `a-z`、数字 `0-9` 和连字符 `-`
- 不得以 `-` 开头或结尾
- 不得含连续 `--`
- 不得为空

违反上述规则时编译器直接报错，杜绝 `"a-"` 与 `"a"` 之类的映射碰撞。

### 选项值语法

选项值支持两种书写方式：

| 语法 | 示例 | 说明 |
| ----- | ---- | ---- |
| `--option VAL` | `--output dist/` | 空格分隔（POSIX 标准） |
| `--option=VAL` | `--output=dist/` | 等号分隔（GNU 扩展） |

两种形式等价，实现中统一处理：遇到 `--opt=val` 时按 `=` 拆分为选项名和值。短选项
同样支持 `-oVAL`（无空格）。

### 短标志组合

多个不取值 Boolean 短标志可以组合书写：

```
-xzvf archive.tar.gz  →  等价于 -x -z -v -f archive.tar.gz
```

展开规则：

1. 从左到右扫描短选项字符
2. 遇到取值型选项（`option`）时，该字符视为当前选项的短名，剩余字符及后续
   token 按正常规则解析。如 `-j8` 当 `-j` 为取值型选项时解析为 `-j 8`
3. 若取值型选项出现在组合中的非末位（如 `-jv`，`-j` 需值），则 `j` 之后的所有字
   符（即 `v`）作为 `-j` 的值

### 可重复选项

当 Record 字段类型为 `List T` 时，`option` 声明器自动变为可重复——每次出现均追加到
列表：

```kun
type RunConfig =
  { ports : List Int       // -p, --port（可重复）
  , image : String         // IMAGE（位置参数）
  }

// --port 8080 --port 443 nginx  →  ports = [8080, 443], image = "nginx"
```

列表元素按出现顺序排列。不出现时为空列表 `[]`。可重复选项的位置参数行为与单值选项
相同：必须有值 token。

### 选项依赖

使用 `withRequires` 修饰器声明选项间的依赖关系：

```kun
// --password 要求 --username 同时出现
Cli.option "password" 'p' "Password"
  |> Cli.withRequires "username"
```

若 `--password` 出现但 `--username` 未出现，解析报错。依赖链支持传递闭包。循环依赖
在编译期检测并报错。

### 类型结构

```kun
// 解析上下文元数据
// 所有字段均为可选（?T），省略的字段自动为 Nil
type CliMeta =
  { intro   : ?String    // 程序名称/简介（显示在 --help 第一行）
  , text    : ?String    // 详细描述（简介下方显示）
  , version : ?String    // 版本号（显示在 --version 输出中）；Nil 时输出「版本未设定」
  }

// 声明器种类
type CliArgKind
  = Flag
  | Option
  | Count
  | Positional

// 单个参数声明
// name 使用 kebab-case，编译期映射为 camelCase 字段名
// default 和 choices 存储为序列化字符串，运行期不做类型检查；
// 实际值在 Cli.parse 编译期展开阶段按目标字段类型反序列化
// 类型安全的门槛在 Cli.parse 调用点的编译期代码展开
type CliArg =
  { name       : String          // kebab-case 长选项名 / 位置参数名
  , short      : ?Char           // 短选项字符，Nil 表示仅长选项
  , help       : String          // 帮助文本
  , kind       : CliArgKind      // 声明器种类
  , default    : ?String         // 缺省值的字符串表示
  , choices    : ?(List String)  // 枚举约束的字符串列表
  , dependsOn  : ?String         // 依赖项名称（仅在 withRequires 修饰后设置）
  }

// 互斥组（at most one：最多允许一个出现）
type CliArgGroup
  = OneOf { name : String, args : List CliArg }

// 顶层解析描述
// 除 meta 外所有字段均为可选——省略时使用零值：
//   args=[]   groups=[]   subs=#{}   loose=false
// 无类型参数——目标 Record 类型由 Cli.parse 调用点 HM 推断
type CliSpec =
  { meta   : CliMeta
  , args   : ?(List CliArg)           // 位置参数和选项（可选，默认 Nil）
  , groups : ?(List CliArgGroup)      // 互斥组（可选，默认 Nil）
  , subs   : ?(Map String CliSpec)    // 子命令映射（可选，默认 Nil），key 为 kebab-case 子命令名
  , loose  : ?Bool                    // 透传模式（可选，默认 false）
  }

// 解析错误类型（结构化，支持程序化处理）
type CliError
  = UnknownOption { option : String, suggestion : ?String }
  | BadValue { name : String, expected : String, got : String }
  | MissingArg { name : String }
  | MissingOption { name : String }
  | BadChoice { name : String, got : String, choices : List String }
  | UnexpectedArg { arg : String }
  | MutexViolation { group : String, options : List String }
  | DependencyViolation { option : String, requires : String }
  | UnknownSubCmd { name : String, suggestion : ?String }
```

> **递归类型依赖**：`CliSpec` 通过 `subs : ?(Map String CliSpec)` 形成递归类型。这
> 要求 Kun 的类型系统支持 **等递归类型（equi-recursive types）**——即在合一算法中
> 对 `type` 别名关闭 occurs check，允许类型引用自身。此能力是 `CliSpec` 设计的硬
> 依赖，需在类型系统实现时予以支持。

### API

#### 声明器

```kun
// 布尔开关（--name / -c），不出现 → false
// short 为 Nil 表示仅长选项（适用于无自然短名的选项如 --amend）
// name 使用 kebab-case
flag : String -> ?Char -> String -> CliArg

// 带值选项（--name VAL / -c VAL）
//   字段为 ?T     → 不出现 → Nil
//   字段为 T      → 无缺省 → 必填；有 withDefault → 可选
//   字段为 List T → 可重复，不出现 → []
// short 为 Nil 表示仅长选项
// name 使用 kebab-case
option : String -> ?Char -> String -> CliArg

// 计数型标志（-c → 1，-ccc → 3），不出现 → 0
// short 为 Nil 表示仅长选项
// name 使用 kebab-case
count : String -> ?Char -> String -> CliArg

// 位置参数（按声明顺序消费 token）
//   字段为 T        → 必填（1 个 token）
//   字段为 ?T       → 可选（0 或 1 个 token）
//   字段为 List T   → 余量（0-N 个 token，仅可为末位）
// name 使用 kebab-case
arg : String -> String -> CliArg
```

#### 修饰器（管道应用）

```kun
// 设置缺省值（值在编译期序列化为 String 存入 default 字段，
// 在 Cli.parse 调用点按目标字段类型反序列化）
withDefault : a -> CliArg -> CliArg

// 设置枚举约束（值在编译期序列化为 List String 存入 choices 字段，
// 在 Cli.parse 调用点按目标字段类型反序列化并校验）
withChoices : List a -> CliArg -> CliArg

// 选项依赖：声明此选项要求另一选项同时出现
// 参数为所依赖选项的 kebab-case 名（编译期校验其存在性及无循环）
withRequires : String -> CliArg -> CliArg
```

#### 错误格式化

```kun
// 将解析错误转为人类可读字符串
show : CliError -> String
```

#### 互斥组

```kun
// 互斥组声明（at most one：最多允许一个参数出现）
// 组成员可以为 flag、option 或 count
oneOf : String -> List CliArg -> CliArgGroup
```

#### 解析

```kun
// 解析原始参数列表为目标 Record
// 类型 a 由调用点的变量类型声明驱动（HM 推断）
// 约束：调用处必须有显式类型标注（如 parseConfig : ... -> Result MyConfig CliError）
//       或通过后续使用使 a 被约束为具体类型
parse : CliSpec -> List String -> Result a CliError
```

### 声明器与字段类型对应

| 声明器 | 目标字段类型 | 行为 |
| -------- | ------------ | ------ |
| `flag "dry-run" 'd' "h"` | `Bool` | `--dry-run`/`-d` → true，不出现 → false |
| `flag "amend" Nil "h"` | `Bool` | `--amend` → true（仅长选项），不出现 → false |
| `count "verbosity" 'v' "h"` | `Int` | `-v` → 1，`-vvv` → 3，不出现 → 0 |
| `count "verbose" Nil "h"` | `Int` | `--verbose` → 1，每次出现 +1（仅长选项），不出现 → 0 |
| `option "output" 'o' "h"` | `?T` | `--output VAL`/`-o VAL` → 对应解析值，不出现 → Nil |
| `option "output" 'o' "h"` | `T` | `--output VAL`/`-o VAL` → 必填，不出现 → 错误 |
| `option "max-jobs" 'j' "h" \|> withDefault d` | `T` | 不出现 → `d` |
| `option "port" 'p' "h"` | `List T` | 可重复，`-p 80 -p 443` → `[80, 443]`，不出现 → `[]` |
| `option "config" Nil "h"` | `?T` / `T` / `List T` | 同 `option`，无短选项（仅 `--config VAL`） |
| `option "config" 'c' "h"`（无 default） | `T` | 必填，不出现 → 错误 |
| `arg "source-dir" "h"` | `T`（非 Bool/List） | 必填，1 个 token |
| `arg "output-dir" "h"` | `?T` | 可选，0 或 1 个 token |
| `arg "files" "h"` | `List T` | 0-N 个 token（仅可为最后一个位置参数） |

### 名字冲突与保留字

编译期检查以下冲突并报错：

- **同 spec 内重名**：长选项名（kebab-case）和短选项字符在同一个 `CliSpec` 内必须
  唯一
- **保留名 `help`**：声明器不得使用 `name = "help"`，`--help` 由框架自动生成
- **保留短选项 `h`**：声明器不得使用 `short = 'h'`，`-h` 为 `--help` 保留
- **保留名 `version`**：声明器不得使用 `name = "version"`，`--version` 由框架自动
  生成（显示 `meta.version`，Nil 时输出「版本未设定」）
- **保留短选项 `V`**：声明器不得使用 `short = 'V'`，`-V` 为 `--version` 保留
- **父/子命令同名**：子命令名（kebab-case）经过 camelCase 映射后若与父 Record 的
  其他字段名（选项或位置参数）冲突，编译期报错
- **父/子命令选项同名**：子命令 spec 内声明的选项名经过 camelCase 映射后若与父
  Record 的任何字段名相同，编译期报错——避免 `--verbose` 在父和子中归属歧义

### 互斥组

`oneOf` 语义为 **at most one**（最多允许一个出现）：组内声明的参数中，零个或一个可
以出现在命令行中；超过一个则解析报错。

```
Error: argument group 'config-source' allows at most one of: --global, --local
```

若需要"必须选一个"的强约束，在应用层对解析结果进行校验（所有成员均为
default/Nil/false 时拒绝）。这避免在框架层引入 `exactlyOne` 的额外复杂度。

### 子命令

#### 模型

子命令通过父 Record 的**可选字段**（`?T`）表达：每个子命令对应父 Record 中的一个
字段，字段名为子命令名的 camelCase 映射，字段类型为子命令解析结果的目标 Record 类
型。

子命令的 `CliSpec` 自身不含父命令的目标类型信息——类型约束全在 `Cli.parse` 调用点
的编译期展开阶段完成。

#### 组装方式

用户通过 Map 字面量直接将子命令 spec 写入父 spec 的 `subs` 字段。新建 spec 时使用
Map 字面量：

```kun
// 一次性声明全部子命令
{ meta = { intro = "deploy.kun" }
, args = [ Cli.flag "verbose" 'v' "Verbose output" ]
, subs = #{ "push" = pushSpec, "status" = statusSpec }
}
```

对已有 spec 追加子命令时，使用 Map 更新语法结合 `??`：

```kun
// 在管道中逐个子命令追加
parentSpec
  |> \s -> { s | subs = #{ s.subs ?? #{} | "push" = pushSpec } }
  |> \s -> { s | subs = #{ s.subs ?? #{} | "status" = statusSpec } }
```

`??` 是 Nil 合并操作符——当 `s.subs` 为 `Nil` 时返回空 Map `#{}`，否则返回已有 Map
。Map 字面量 `#{}` 和更新语法 `#{ old | key = val }` 是语言内置语法，无需
`import Map`。

#### 调度规则

- **子命令优先匹配**：解析器遇到位置 token 时，先检查是否匹配已注册的子命令名
  （kebab-case 比对），匹配则切换到该子命令的解析模式。若需将子命令名作为父命令位
  置参数的值传入，使用 `--` 分隔符：`deploy.kun -- push` 将 `"push"` 绑定到位置参
  数而非匹配子命令
- **父命令选项仅在前**：父命令声明的选项仅在子命令 token 之前被识别。一旦匹配到子
  命令，后续 token 由子命令的 spec 解析——子命令之后出现的父命令选项名将被视为未知
  选项（由子命令 spec 的 unknown-option 处理逻辑处理）
- **子命令接管位置参数**：一旦匹配到子命令，父命令的所有位置参数声明不再消费
  token——所有剩余位置 token 交由子命令的 spec 解析
- **无子命令时父命令正常解析**：若所有位置 token 均不匹配子命令名，父命令的位置参
  数按声明顺序正常绑定

```
输入: deploy.kun -v prod
→ "prod" 不匹配子命令名，父命令位置参数绑定: verbose=true, target="prod"

输入: deploy.kun -v push main dev
→ "push" 匹配子命令，父命令位置参数不绑定 → push spec 接管解析:
  verbose=true, push=PushConfig {force=false, remote="main", branch="dev"}

输入: deploy.kun push --verbose main dev
→ "push" 匹配子命令 → "--verbose" 由子命令 spec 解析（若子命令未声明则报未知选项）

输入: deploy.kun -- push
→ "--" 禁用子命令匹配，"push" 绑定到父命令第一个位置参数
```

#### 分发模式

子命令分发采用嵌套 `case` 模式。对于子命令较多的应用，可通过辅助函数减少嵌套深度
：

```kun
// 使用 Nil 合并链（??）配合 Result 组合
handleSubCmd : DeployConfig -> Unit
handleSubCmd cfg =
  case cfg.push of
    Nil ->
      case cfg.status of
        Nil -> IO.println "No subcommand"
        s   -> IO.println f"Status: short={s.short}"
    p -> IO.println f"Pushing to {p.remote}/{p.branch}"
```

当子命令数量超过 3 时，建议抽取独立的处理函数，将嵌套 `case` 限制在分发层，业务逻
辑放在各自处理函数中。

#### 多级嵌套

子命令的 spec 自身可含 `subs`，支持任意层级嵌套。每级子命令对应父 Record 中的一个
可选字段，字段类型为下一级子命令的配置 Record。组装方式同顶层——通过 Map 字面量或更新语法逐级嵌套。

#### 帮助

`--help` 自动列出所有已注册子命令。对特定子命令使用 `--help`（如
`deploy.kun push --help`）显示该子命令的详细帮助。子命令帮助文本取自子 spec 的
`meta.intro`。

`--version` 同样自动可用——显示 `meta.version`（若提供），否则输出「版本未设定」。

帮助输出中，参数名（选项名、位置参数名）的显示规则为：kebab-case 名全部大写，保留
原 `-` 分隔符。例如 `"source-dir"` → `SOURCE-DIR`，`"file-list"` → `FILE-LIST`。

### 编译期类型安全

`Cli.parse` 的泛型类型 `a` 由调用上下文推断。编译期流程：

0. **类型推断前提**：`Cli.parse` 的调用处必须有显式类型标注（如
   `parseConfig : List String -> Result MyConfig CliError`），或通过后续使用使
   `a` 被约束为具体 Record 类型。若 `a` 始终为自由类型变量（无约束），编译器报错
   ，提示需要类型标注
1. HM 推断 `a = MyConfig`（从标注或上下文合一得出）
2. 编译器展开 `MyConfig` 的字段类型
3. 对每个 `CliArg`：校验 `name` 的 kebab-case 格式，映射为 camelCase，在
   `MyConfig` 中查找对应字段，按字段类型验证 `kind` 兼容性。缺字段 → 编译错误，多
   余声明 → 编译错误
4. 对 `subs` 中的每个条目：将 kebab-case key 映射为 camelCase，在 `MyConfig` 中查
   找对应字段，验证其为 `?T` 类型，递归验证子 spec 与 `T` 的兼容性
5. 检查名字冲突：同 spec 内重名、保留名 `help`/`h`/`version`/`V`、父/子命令间的
   字段名冲突
6. 检查依赖关系：`withRequires` 的依赖目标存在且不形成循环
7. 为每个 `CliArg` 按对应字段类型生成特化的字符串→类型转换代码

`CliArg` 本身不带类型参数（`default` 和 `choices` 存储为 `String`），以避免不同字
段类型的 `CliArg` 无法放入同一 `List`。`CliSpec` 同样不带类型参数——子命令 spec 的
类型信息在构造时不绑定，仅在 `Cli.parse` 调用点通过编译期展开与目标 Record 结构进
行交叉验证。

`withDefault` 和 `withChoices` 在编译期将多态值序列化为 `String` 存入 `CliArg`
的 `default`/`choices` 字段。在 `Cli.parse` 展开阶段，编译器按目标字段类型将存储的
字符串反序列化，并校验反序列结果类型匹配且（对于 `withChoices`）值在允许列表内。此
机制与 `Parser.Record.fromJson` 的默认值处理一致。

> **编译期代码展开**：上述步骤 3-7 由编译器的通用代码展开设施执行——该设施允许标
> 准库函数在编译期根据已知类型参数内省 Record 结构并生成特化代码。此机制与
> `Parser.Record.fromJson` 共用同一基础设施，基于 Zig `comptime` + `@typeInfo` 实
> 现。`Cli.parse` 不要求编译器对其有特殊内置知识——它仅使用编译器提供的公开类型内
> 省 API。

---

## 示例

### 1. 基本用法

`kun build.kun -v -o dist/ --jobs 8 app`

```kun
import Cli
import IO

type BuildConfig =
  { verbose : Bool          // --verbose, -v
  , output  : ?Path         // --output, -o
  , jobs    : Int           // --jobs, -j
  , source  : String        // SOURCE（位置参数）
  }

parseConfig : List String -> Result BuildConfig CliError
parseConfig =
  Cli.parse
    { meta  = { intro  = "build.kun"
              , text   = "Compiles and packages."
              , version = Nil
              }
    , args =
        [ Cli.flag "verbose" 'v' "Enable verbose output"
        , Cli.option "output" 'o' "Output file path"
        , Cli.option "jobs" 'j' "Parallel jobs"
            |> Cli.withDefault 4
        , Cli.arg "source" "Source directory"
        ]
    }

main : List String -> Unit
main = \raw ->
  do
    case parseConfig raw of
      Ok cfg ->
        IO.println f"building {cfg.source} with {cfg.jobs} jobs"
      Err err ->
        IO.println (Cli.show err)
```

自动 `--help` 输出：

```
usage: build.kun [-v] [-o PATH] [-j N] SOURCE

build.kun

Compiles and packages.

Options:
  -v, --verbose       Enable verbose output
  -o, --output PATH   Output file path
  -j, --jobs N        Parallel jobs (default: 4)
  -h, --help          Show this help
  -V, --version       Show version

Arguments:
  SOURCE              Source directory
```

### 2. 子命令

`kun deploy.kun -v push --force origin main`

```kun
import Cli
import IO

type PushConfig =
  { force  : Bool
  , remote : String
  , branch : String
  }

type StatusConfig =
  { short : Bool }

// 父配置直接包含子命令字段（均为可选）
type DeployConfig =
  { verbose : Bool
  , push    : ?PushConfig
  , status  : ?StatusConfig
  }

pushSpec : CliSpec
pushSpec =
  { meta = { intro = "Deploy push action" }
  , args =
      [ Cli.flag "force" 'f' "Force push"
      , Cli.arg "remote" "Remote name"
      , Cli.arg "branch" "Branch name"
      ]
  }

statusSpec : CliSpec
statusSpec =
  { meta = { intro = "Deploy status action" }
  , args =
      [ Cli.flag "short" 's' "Short format"
      ]
  }

parseConfig : List String -> Result DeployConfig CliError
parseConfig =
  Cli.parse
    { meta =
        { intro = "deploy.kun"
        , text  = "Deploy management tool."
        }
    , args =
        [ Cli.flag "verbose" 'v' "Verbose output"
        ]
    , subs = #{ "push" = pushSpec, "status" = statusSpec }
    }

main : List String -> Unit
main = \raw ->
  do
    case parseConfig raw of
      Ok cfg ->
        case cfg.push of
          Nil ->
            case cfg.status of
              Nil -> IO.println "No subcommand specified"
              s   -> IO.println f"Status: short={s.short}"
          p -> IO.println f"Pushing to {p.remote}/{p.branch}"
      Err err ->
        IO.println (Cli.show err)
```

自动 `--help` 输出：

```
usage: deploy.kun [-v] [SUBCOMMAND]

deploy.kun

Deploy management tool.

Options:
  -v, --verbose       Verbose output
  -h, --help          Show this help
  -V, --version       Show version

Subcommands:
  push                Deploy push action
  status              Deploy status action
```

`deploy.kun push --help`：

```
usage: deploy.kun push [-f] REMOTE BRANCH

Deploy push action

Options:
  -f, --force         Force push
  -h, --help          Show this help

Arguments:
  REMOTE              Remote name
  BRANCH              Branch name
```

### 3. 子命令 + 父命令位置参数

父命令可同时声明位置参数——仅在无子命令匹配时才绑定：

```kun
type DeployConfig =
  { target  : ?String          // 仅无子命令时绑定
  , push    : ?PushConfig
  , status  : ?StatusConfig
  }

parseConfig : List String -> Result DeployConfig CliError
parseConfig =
  Cli.parse
    { meta  = { intro = "deploy.kun" }
    , args = [ Cli.arg "target" "Deployment target" ]
    , subs = #{ "push" = pushSpec, "status" = statusSpec }
    }

main : List String -> Unit
main = \raw ->
  do
    case parseConfig raw of
      Ok cfg ->
        case cfg.target of
          Nil ->
            case cfg.push of
              Nil ->
                case cfg.status of
                  Nil -> IO.println "No subcommand or target"
                  s   -> IO.println f"Status: short={s.short}"
              p -> IO.println f"Pushing to {p.remote}/{p.branch}"
          t -> IO.println f"Target: {t}"
      Err err ->
        IO.println (Cli.show err)
```

```bash
kun deploy.kun prod             → Target: prod
kun deploy.kun push main dev    → Pushing to main/dev
kun deploy.kun status           → Status: short=false
kun deploy.kun -- push          → Target: push
```

### 4. 多级子命令嵌套

```kun
type RemoteAddConfig =
  { name : String
  , url  : String
  }

type RemoteConfig =
  { add : ?RemoteAddConfig }

type DeployConfig =
  { remote : ?RemoteConfig
  , push   : ?PushConfig
  }

remoteAddSpec : CliSpec
remoteAddSpec =
  { meta = { intro = "Add remote" }
  , args =
      [ Cli.arg "name" "Remote name"
      , Cli.arg "url" "Remote URL"
      ]
  }

remoteSpec : CliSpec
remoteSpec =
  { meta = { intro = "Remote management" }
  , subs = #{ "add" = remoteAddSpec }
  }

parseConfig : List String -> Result DeployConfig CliError
parseConfig =
  Cli.parse
    { meta = { intro = "deploy.kun" }
    , subs = #{ "remote" = remoteSpec, "push" = pushSpec }
    }
```

### 5. kebab-case 选项映射示例

```kun
import Cli

type SyncConfig =
  { dryRun     : Bool          // --dry-run, -n
  , maxRetries : Int           // --max-retries, -r
  , sourceDir  : String        // SOURCE-DIR（位置参数）
  , fileList   : List String   // FILE-LIST（余量位置参数）
  }

parseSync : List String -> Result SyncConfig CliError
parseSync =
  Cli.parse
    { meta = { intro = "sync.kun" }
    , args =
        [ Cli.flag "dry-run" 'n' "Preview changes without applying"
        , Cli.option "max-retries" 'r' "Maximum retry attempts"
            |> Cli.withDefault 3
        , Cli.arg "source-dir" "Source directory"
        , Cli.arg "file-list" "Files to sync"
        ]
    }
```

自动 `--help` 输出：

```
usage: sync.kun [-n] [-r N] SOURCE-DIR [FILE-LIST...]

Options:
  -n, --dry-run       Preview changes without applying
  -r, --max-retries N Maximum retry attempts (default: 3)
  -h, --help          Show this help

Arguments:
  SOURCE-DIR          Source directory
  FILE-LIST           Files to sync
```

### 6. 可重复选项

`kun docker.kun -p 8080:80 -p 443:443 --rm nginx`

```kun
import Cli

type RunConfig =
  { ports  : List String     // --port / -p（可重复）
  , rm     : Bool            // --rm（仅长选项）
  , image  : String          // IMAGE（位置参数）
  }

parseRun : List String -> Result RunConfig CliError
parseRun =
  Cli.parse
    { meta = { intro = "kun-docker" }
    , args =
        [ Cli.option "port" 'p' "Publish port (host:container)"
        , Cli.flag "rm" Nil "Remove container after exit"
        , Cli.arg "image" "Container image"
        ]
    }
```

### 7. 选项依赖

```kun
import Cli

type LoginConfig =
  { username : String
  , password : ?String
  , host     : ?String
  }

parseLogin : List String -> Result LoginConfig CliError
parseLogin =
  Cli.parse
    { meta = { intro = "login.kun" }
    , args =
        [ Cli.option "username" 'u' "Username"
        , Cli.option "password" 'p' "Password"
            |> Cli.withRequires "username"
        , Cli.option "host" Nil "Server host" |> Cli.withDefault "localhost"
        ]
    }
```

`--password` 出现但 `--username` 未出现时：

```
Error: option '--password' requires '--username' to also be specified
```

### 8. 互斥组

```kun
import Cli

type MutexConfig = { global : Bool, local : Bool }

parseConfig : List String -> Result MutexConfig CliError
parseConfig =
  Cli.parse
    { meta = { intro = "mutex.kun" }
    , groups =
        [ Cli.oneOf "config-source"
            [ Cli.flag "global" 'g' "Use global config"
            , Cli.flag "local" 'l' "Use local config"
            ]
        ]
    }
```

`--global` 和 `--local` 同时指定时：

```
Error: argument group 'config-source' allows at most one of: --global, --local
```

两者均不指定时两者均为 `false`（at most one 允许零个）。

### 9. 枚举约束

```kun
import Cli

type ServerConfig =
  { host     : String
  , logLevel : ?String     // --log-level, -l
  }

parseConfig : List String -> Result ServerConfig CliError
parseConfig =
  Cli.parse
    { meta = { intro = "server.kun" }
    , args =
        [ Cli.option "host" Nil "Server host"
        , Cli.option "log-level" 'l' "Log level"
            |> Cli.withChoices ["debug", "info", "warn"]
        ]
    }
```

违规时：

```
Error: option '--log-level' must be one of: debug, info, warn
```

### 10. 透传模式

`kun gcc.kun -o a.out -Wall -O2 main.c`

```kun
import Cli

type CompileConfig =
  { output       : Path
  , compilerArgs : List String
  }

parseCompile : List String -> Result CompileConfig CliError
parseCompile =
  Cli.parse
    { meta  = { intro = "gcc.kun" }
    , loose = true
    , args =
        [ Cli.option "output" 'o' "Output file"
        , Cli.arg "compiler-args" "Compiler arguments"
        ]
    }
```

`output : Path` 无 `?` 无 default → 必填。`--o a.out` 之后所有 `-Wall`、`-O2`、
`main.c` 均流入 `compilerArgs`。

### 11. 多个位置参数

```kun
import Cli

type CpConfig =
  { source : String
  , dest   : String
  , target : Path
  }

parseCp : List String -> Result CpConfig CliError
parseCp =
  Cli.parse
    { meta = { intro = "cp.kun" }
    , args =
        [ Cli.arg "source" "Source file"
        , Cli.arg "dest"   "Destination file"
        , Cli.arg "target" "Target directory"
        ]
    }
```

```bash
kun cp.kun a.txt b.txt /tmp
```

按声明顺序消费：`a.txt` → `source`，`b.txt` → `dest`，`/tmp` → `target`。`--` 分
隔符遵循 POSIX 惯例：`--` 之后全部 token 视为位置参数。

### 12. 可选位置 + 余量位置

```kun
import Cli

type ToolConfig =
  { name  : ?String
  , files : List String
  }

parseTool : List String -> Result ToolConfig CliError
parseTool =
  Cli.parse
    { meta = { intro = "tool.kun" }
    , args =
        [ Cli.arg "name" "Optional name"
        , Cli.arg "files" "Input files"
        ]
    }
```

```bash
kun tool.kun                    → name = Nil, files = []
kun tool.kun hello              → name = "hello", files = []
kun tool.kun a.txt b.txt        → name = "a.txt", files = ["b.txt"]
kun tool.kun hello a.txt b.txt  → name = "hello", files = ["a.txt", "b.txt"]
```

位置参数消费策略为非贪婪：先尝试匹配前置的 `?T`（0 或 1 个），剩余全部进入
`List T`。`--` 之后全部 token 视为位置参数。

### 版本标志

`--version`/`-V` 由框架自动生成，输出 `meta.version`（若提供）：

```kun
// 指定版本号
{ meta = { intro = "deploy.kun", version = "2.1.0" } }

// $ kun deploy.kun --version
// deploy.kun 2.1.0

// 不指定版本号（version = Nil）→ 显示「版本未设定」
{ meta = { intro = "deploy.kun" } }

// $ kun deploy.kun --version
// deploy.kun — 版本未设定
```

### 完整 sub 字段说明示例

展示 `CliSpec` 所有字段及子命令的完整组装：

```kun
import Cli

type FullConfig =
  { verbose : Bool
  , output  : ?Path
  , deploy  : ?DeployConfig         // 子命令字段（可选）
  }

deploySpec : CliSpec
deploySpec =
  { meta   = { intro = "deploy", version = "3.0.0" }
  , args   = [ Cli.arg "target" "Deploy target" ]
  , groups = []
  , subs   = #{}
  , loose  = false
  }

parseConfig : List String -> Result FullConfig CliError
parseConfig =
  Cli.parse
    { meta   = { intro  = "full.kun"
               , text   = "Demonstrates all CliSpec fields."
               , version = "1.0.0"
               }
    , args   = [ Cli.flag "verbose" 'v' "Verbose output"
               , Cli.option "output" 'o' "Output path"
               ]
    , groups = [ Cli.oneOf "mode"
                   [ Cli.flag "dry-run" 'n' "Dry run"
                   , Cli.flag "force" 'f' "Force"
                   ]
               ]
    , subs   = #{ "deploy" = deploySpec }
    , loose  = false
    }
```

### 错误信息与程序化处理

`CliError` 为和类型，支持模式匹配实现程序化处理。使用 `Cli.show` 获取人类可读描述
：

```kun
case parseConfig raw of
  Ok cfg -> ...
  Err (UnknownOption { option = "verbse", suggestion = Some "verbose" }) ->
    // 自定义处理
    IO.println "did you mean --verbose?"
  Err err ->
    IO.println (Cli.show err)   // 通用回退
```

完整错误输出示例：

```
Error: unrecognized option '--verbse'. Did you mean '--verbose'?

Error: option '--jobs' expects an integer, got 'abc'

Error: required argument 'source' is missing

Error: required option '--config' is missing

Error: argument 'count' expects an integer, got 'abc'

Error: option '--log-level' must be one of: debug, info, warn

Error: unexpected argument 'c.txt'

Error: argument group 'config-source' allows at most one of: --global, --local

Error: option '--password' requires '--username' to also be specified

Error: unknown subcommand 'pussh'. Did you mean 'push'?

Try 'build.kun --help' for more information.
```

`--help`/`-h` 始终自动可用，不可禁用。`--version`/`-V` 同样自动可用。出现解析错误
时自动提示 `--help`。
