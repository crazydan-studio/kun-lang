# 命令签名系统设计

## 定位

命令签名系统是 Kun 将 Linux 命令抽象为类型安全函数的桥梁。命令函数的本质是**获取结构化结果**，而非执行特定命令。`ls p"/tmp"` 的语义是"获取 /tmp 目录下的文件列表（名称、类型、大小、时间）"，而非"执行带有这些参数的 ls"。

调用命令函数时，运行时会自动处理输出的结构化和反序列化——用户通过 CDF（Command Description File，命令描述文件）声明的返回类型操作结果，不直接接触原始文本输出。

## `run` — 命令入口

所有命令的执行统一通过 `run` 内置语法：

```kun
run"kubectl" ["get", "pods", "-n", "default"]
// → Stream String（T4 默认）
// → 有审计日志 + 沙箱隔离
// → 无结构化输出，无参数校验
```

`run` 是命令执行的唯一入口。它返回 `Stream String`，由 `process.run` 能力控制授权。用户无需做任何前置工作——写出来就能跑。

### `process.run` 能力

`run` 命令由 `process.run` 能力控制，白名单机制，默认拒绝：

```kun
with caps
  process.run = ["kubectl", "docker", "curl"]

main =
  run"kubectl" ["get", "pods"]          // ✅
  run"docker" ["ps"]                    // ✅
  run"ssh" ["user@host"]                // ❌ 不在白名单
```

| 规则 | 说明 |
|------|------|
| basename 精确匹配 | `process.run = ["kubectl"]` 匹配 `kubectl` |
| `[]` 通配 | `process.run = []` 匹配任何命令（慎用） |
| 默认 | 空列表——无 `run` 权限 |

## 升级路径：从 `run` 到 CDF

`run` 是起点。运行时自动尝试为每个 `run` 调用升级到更好的路径：

```
run"kubectl" ["get", "pods"]（首次调用）
  │
  ├── T1：有内置签名？
  │   └── 是 → 自动升级为内建 Primitive，精确结构化返回
  │
  ├── T2：有 CDF 文件（项目级/用户级/内置库）？
  │   └── 是 → 自动升级为 CDF 命令函数，类型安全
  │
  ├── T3：auto-infer 成功？
  │   ├── 是 → 生成 CDF 草稿并缓存到 ~/.kun/cdf/
  │   │   ├── 本次按 T3 级别执行（seccomp + 沙箱，无签名）
  │   │   └── 下次调用自动升级为 T2
  │   └── 否 → 留在 run 模式（T4）
  │       ├── 基础沙箱隔离
  │       ├── 强制审计日志
  │       └── seccomp 通用白名单
  │
  └── 运行时提示：kubectl 的 CDF 草稿已缓存到 ~/.kun/cdf/kubectl.cdf
```

### 四种执行级别

| 级别 | 触发条件 | 返回值类型 | 安全检查 |
|------|---------|-----------|---------|
| **T1 内建** | 运行时内置 Primitive | `Result (Stream T) IOError`（精确结构化） | 完整沙箱 + seccomp |
| **T2 CDF** | 有 `.cdf` 文件 | `Result (Stream T) IOError`（精确结构化） | 完整沙箱 + seccomp + 签名验证 |
| **T3 自动推断** | auto-infer 成功，无签名 | `Result (Stream T) IOError`（T 可能为 `String`） | seccomp + 沙箱，无签名 |
| **T4 `run`** | 默认级别，无升级路径匹配 | `Stream String` | 基础沙箱 + 审计日志 |

用户在所有级别使用相同的 `run""` 语法。升级是透明的：

```kun
// 第一次写时：T4，返回 Stream String
// 缓存 CDF 后：T2，返回 Result (Stream StatusEntry) IOError
// 用户代码不需要改——编译器根据 T 级别处理返回值
let output = run"kubectl" ["get", "pods"]
// T4 时：output : Stream String
// T2 时：output : Result (Stream PodEntry) IOError
```

### 设计原则

1. **`run` 优先**：所有命令都能跑，零前置工作。CDF 是逐步升级的合同，不是准入门槛
2. **自动升级**：运行时在后台自动推断并缓存 CDF，用户无需手动干预
3. **渐进安全**：T4 基础隔离 → T3 中等 → T2 完整。用户在便利和安全之间逐步选择
4. **来源可信**：CDF 文件通过密码学签名建立信任链

## `run` 的沙箱与安全

`run` 的子进程在受限沙箱中执行：

| 机制 | 默认策略 |
|------|---------|
| PID namespace | 启用，子进程不可见其他进程 |
| Mount namespace | 启用（只读 `/usr` + `/lib`） |
| Network namespace | 启用，默认无网络。通过 `net.*` 能力放行 |
| seccomp | 通用白名单：brk/mmap/munmap/exit_group/read/write/openat/fstat/close |
| 审计日志 | 始终强制，不可绕过 |
| 参数校验 | 无（CDF 升级后才有） |

网络示例：

```kun
with caps
  process.run = ["curl"]
  net.https = ["api.example.com"]   // 同时也为 run 的子进程放行网络

main =
  run"curl" ["https://api.example.com/data"]
```

## CDF → Kun 代码生成

## CDF → Kun 代码生成

CDF 不再是运行时解析的描述文件，而是**编译期代码生成源**——CDF 在编译时被转译为 Kun 模块代码，生成完整的 Options Record 类型、命令函数签名、argv 构造逻辑和输出解析器调用。

### 文件位置

```
~/.kun/cdf/<command>.cdf        # 用户级
<project>/.kun/cdf/<command>.cdf # 项目级（提交到版本控制）
<runtime>/cdf/                   # 内置签名库
```

### CDF 语法

#### CDF 形式化语法（EBNF）

以下 EBNF 定义 CDF 文件格式（v1）。终端符用单引号包裹，可选用 `[ ]`，零次或多次用 `{ }`，分组用 `( )`。

```ebnf
cdf_file    = version_header , { validator_decl | parser_decl } , command_decl ;
comment     = '//' , { character } , newline ;

version_header = '//' , 'kun-cdf-v1' ;

(* 验证器 *)
validator_decl = 'validator' , identifier , '=' , expression ;
expression     = identifier                           (* 引用其他验证器 *)
               | identifier , { expression }          (* 函数应用：all [...] *)
               | string_literal | number              (* 字面量 *)
               | '\\' , identifier , '->' , expression (* lambda *)
               | '[' , [ expression , { expression } ] , ']'  (* 列表 *)
               ;

(* 解析器 *)
parser_decl    = 'parser' , identifier , ':' , stream_type , '=' , module_ref ;
stream_type    = 'Stream' , '(' , 'Result' , type_name , type_name , ')' ;
module_ref     = identifier , '.' , identifier ;

(* 命令声明 *)
command_decl   = 'command' , identifier , [ string_literal ] , newline
                 , indent , command_body , dedent ;
subcommand_decl = 'subcommand' , identifier , [ string_literal ] , newline
                  , indent , command_body , dedent ;
command_body   = { option_decl | param_decl | output_decl | bin_decl | exitcode_decl | subcommand_decl } ;

(* 退出码声明 *)
exitcode_decl  = 'exitcode' , ( '*' | number ) , '=' , ( 'Ok' [ 'empty' ] | 'Err' , expression ) ;

(* 选项 *)
option_decl    = 'option' , identifier , flag_string , ':' , type_expr
                 , [ '!' ] , [ 'with' , '(' , expression ')' ] ;
flag_string    = '"-' , flag_char , { flag_char } , '"'         (* 短名：-v *)
               | '"--' , identifier , '"'                       (* 长名：--verbose *)
               ;
flag_char      = letter | digit | '_' ;

(* 位置参数 *)
param_decl     = 'param' , ( '*' | natural ) , ':' , type_expr
                 , [ 'with' , '(' , expression ')' ] ;

(* 输出声明 *)
output_decl    = 'output' , ( identifier [ '-doc' ] | 'default' | 'json' | 'text-doc' | 'json-doc' ) ;

(* 命令路径 *)
bin_decl       = 'bin' , path_literal ;

(* 类型 *)
type_expr      = type_name | 'List' , type_name ;
type_name      = 'Bool' | 'Int' | 'Nat' | 'Float' | 'String' | 'Path' | identifier ;
path_literal   = 'p"' , { character } , '"' ;
string_literal = '"' , { character } , '"' ;
number         = digit , { digit } ;
natural        = digit , { digit } ;
identifier     = ( letter | '_' ) , { letter | digit | '_' } ;
```

**语义约束**（解析器必须在语法分析后额外检查）：

| # | 约束 | 违规处理 |
|---|------|---------|
| 1 | `param <N>` 的编号 `N` 必须严格递增，不可跳跃（如先 `param 1` 后 `param 0`） | 编译期报错：参数编号顺序错误 |
| 2 | `param *` 必须出现在所有 `param <N>` 之后，且每个 `command_body` 中最多一个 `param *` | 编译期报错：param * 位置错误 |
| 3 | `!` 标记仅适用于非 `Bool` 非 `List` 类型的 `option`。`Bool` 或 `List T` 后出现 `!` 为编译期警告并忽略 | 编译期警告：Bool/List 类型不支持 ! 标记 |
| 3a | `option` 声明 `List T` 时，`Kun` 字段类型为 `List T`，表示此标志可重复出现（0..N 次）。运行时 argv 构造为每个元素重复展开一次标志 | — |
| 4 | `output` 引用 `identifier` 时，该标识符必须在文件前面的 `parser_decl` 中已定义 | 编译期报错：引用了未定义的解析器 |
| 5 | `output default` 和 `output json` 为关键字，不可用作自定义 `parser` 名称 | 编译期报错：default/json 为保留标识符 |
| 6 | `bin` 的相对路径（`p"./..."` 开头）不可超出 CDF 所在目录（`../` 不允许） | 编译期报错：bin 路径超出 CDF 目录 |

**词法规定**：
- CDF 使用缩进（空格/制表符）表示 `command`/`subcommand` 的嵌套层级
- `//` 为行注释，注释内不解析其他语法
- `identifier` 区分大小写，不能以数字开头
- `flag_string` 的短名形式限制为 `"-` + ASCII 字母数字 + `"`，不支持 `-abc` 合并短名（合并由运行时 argv 解析器处理，CDF 只声明单字符短名）

#### 校验器和解析器（根命令层级，无缩进）

```kun-cdf
// 校验器——纯函数，仅对值本身做校验（格式、范围、正则等）
// 不可涉及 IO（如文件存在性检查）
validator portRange = all [range 1 65535, not (\p -> p == 666)]
validator nonEmpty = all [length 1 255]
validator branchName = regex r"^[a-zA-Z0-9_/.-]+$"
validator nameCheck = MyModule.validateName     // 引用模块函数

// 解析器——纯函数，输入始终为 Stream String（命令原始 stdout）
// 返回值 Stream (Result EntryType String)，每行独立成功/失败
parser statusFormat : Stream (Result StatusEntry String) = MyParser.parseStatus
parser logFormat    : Stream (Result CommitEntry String) = MyParser.parseLog
```

#### `option`——命令选项

```
option <name> "<flag>" : <type>[!] [with (<validator>)]
```

| 部分 | 说明 |
|------|------|
| `<name>` | 函数 Options Record 的字段名，不加引号 |
| `"<flag>"` | 命令的选项名，`-v`（短名，单字符）或 `--verbose`（长名），二选其一。解析器通过 `--` 前缀区分长短名 |
| `<type>` | 选项值类型。支持 `T`、`T!`、`List T` 三种形式 |
| `[!]` | 可选标记。`T!` 表示必填（`String!` → Kun 类型 `String`）。缺省为可选（`String` → Kun 类型 `?String`）。**`Bool` 和 `List T` 不受 `!` 影响**——编译期检查到 `Bool!` 或 `List T!` 时发出警告并忽略 `!` |
| `[with (<validator>)]` | 可选验证器，可以是已定义的 `validator` 名称，也可以是**内联表达式** |

**`List T` 类型**：声明选项可重复出现任意次。生成的 Kun 字段类型为 `List T`。运行时 argv 构造为每个元素展开一次标志：

```kun-cdf
option env "-e" : String                   // -e 出现 0 或 1 次 → env : ?String
option env "-e" : List String              // -e 出现 0..N 次 → env : List String
```

调用示例：

```kun
// docker run --env DB_HOST=prod --env DB_USER=admin
docker.run { env = ["DB_HOST=prod", "DB_USER=admin"], detach = true }
// → docker run --detach --env DB_HOST=prod --env DB_USER=admin
```

**内联验证器**：`with` 子句中的 `<validator>` 可以是已声明的 `validator` 名称，也可以是直接写在括号内的表达式——省去先定义后引用的步骤：

```kun-cdf
option port "-p" : Int with (range 1 65535)          // 内联：无需事先声明 validator
option format "-f" : String with (include ["json", "csv"])
option branch "-b" : String with (regex r"^[a-z]+$")
```

**长短名区分规则**：`"<flag>"` 以 `--` 开头为长名，以 `-` 开头为短名。短名必须是单字符（`-a` 合法，`-abc` 不合法）。合并短名（如 `-abc` 展开为 `-a -b -c`）由运行时 argv 解析器处理，不在 CDF 声明范围内。

```kun-cdf
option verbose "-v" : Bool                   // Bool → Bool，缺省 false
option config "-c" : Path                    // 可选 → ?Path
option name "-n" : String!                   // 必填 → String
option port "-p" : Int with (portRange)       // 可选 + 引用已定义验证器
option format "-f" : String with (include ["json", "csv"])
option type "--type" : String                  // 字段名 type 合法
```

#### `param`——位置参数

```
param <N> : <type>                           // 确定位置，始终必填
param * : List <type>                        // 剩余参数，集合类型
```

- `param <N>` 顺序对应函数参数位置，按顺序依次存在——不支持前一个不存在而后一个存在的情况
- `param <N>` 的编号 `N` 必须严格递增（如 `param 0` → `param 1` → `param 2`，不可跳跃或逆序）
- 确定位置的参数始终必填，不支持 `!` 标记
- `param *` 必须出现在所有 `param <N>` 之后，每个 `command_body` 中最多出现一次
- `param * : List T` 显式写出 `List`，语义为零个或多个相同类型的参数
- 不同类型的位置参数必须分别映射为 `param <N>`，`param *` 要求所有元素同类型

```kun-cdf
param 0 : Path                          // 函数第 2 个参数（Options 后第 1 个），Path
param 1 : String                        // 函数第 3 个参数，String
param 2 : String with (regex r"^v\d+") // 函数第 4 个参数，带内联验证器
param * : List String                   // 函数最后一个参数，List String
```

参数映射关系：

```
函数参数顺序 = [Options Record] + [param 0] + [param 1] + ... + [param *]
      位置:          1             2           3             最后
```

#### `param *` 的类型为 `List Path`

```kun-cdf
param * : List Path      // ✅ 正确：显式 List
param * : Path           // ❌ 错误：param * 必须显式 List
param 0 : Path           // ✅ 正确：确定位置，无需 List
param 0 : Path!          // ❌ 错误：确定位置不使用 ! 标记
```

#### `List <type>` 在 CDF 中的语义

CDF 中的 `List` 直接映射为 Kun 的 `List` 类型，无独立 CDF 类型系统：
- `param * : List Path` → 生成的 Kun 函数最后一个参数类型为 `List Path`
- CDF 不声明嵌套集合类型（如 `List (List String)`）

#### `output`——输出解析器引用

```kun-cdf
output <parser_name>           // 行流模式：引用已定义的 parser，类型为 Stream (Result T String)
output default                 // 行流模式：默认解析器，返回 Stream String
output json                    // 行流模式：逐行 JSON 解析器，返回 Stream JsonValue
output text-doc                // 文档模式：完整输出为 String
output json-doc                // 文档模式：整个输出解析为一个 JsonValue
output <parser_name>-doc       // 文档模式：自定义文档解析器，parser 签名需为 String -> Result T String
```

`output` 引用的 `parser_name` 必须在文件前面的 `parser_decl` 中已定义，否则编译期报错。`default` 和 `json` 为保留关键字，不可用作自定义 `parser` 名称。`-doc` 后缀标记文档模式——parser 接收的入参是完整的 stdout 字符串，而非逐行。Parser 的签名须与 output 模式匹配：

| `output` 声明 | Parser 签名 | 收集策略 |
|-------------|------------|---------|
| `output <name>` | `Stream String -> Stream (Result T String)` | 逐行喂给 parser |
| `output <name>-doc` | `String -> Result T String` | 收集完整 stdout，一次传给 parser |

#### `exitcode`——退出码语义

```
exitcode <N> = Ok                    // 退出码 N → Ok (Stream T)
exitcode <N> = Ok empty              // 退出码 N → Ok Stream.empty
exitcode <N> = Err <expr>            // 退出码 N → Err <expr>
exitcode * = Err <expr>              // 通配：其他未声明码
```

缺省行为：`0 = Ok`，非零 = `Err (IOError.Other "exit N")`。详见[退出码声明](#exitcode--退出码声明)节。

#### `bin`——命令路径

```kun-cdf
command myTool "my-tool"                    // 函数名 myTool，二进制 my-tool
  bin p"/usr/local/bin/my-tool"             // 绝对路径
  bin p"./tools/my-tool"                    // 相对路径（相对于 CDF 所在目录，不可超出）

command git                                 // 函数名 = 二进制名 = "git"
  // 缺省不写 bin，按函数名搜索 PATH
```

相对路径不可超出 CDF 所在目录（`../` 不允许）。

#### 版本号声明

CDF 文件必须以版本注释开头，用于格式兼容性识别：

```kun-cdf
// kun-cdf-v1
```

格式变更时：解析器向下兼容旧版格式，运行时检测到旧版时输出升级建议。

#### 完整 CDF 示例

```kun-cdf
// kun-cdf-v1
// git.cdf
parser statusFormat : Stream (Result StatusEntry String) = MyParser.parseStatus
parser logFormat    : Stream (Result CommitEntry String) = MyParser.parseLog

command git
  output default
  param * : List String

subcommand status
  output statusFormat
  option short "-s" : Bool

subcommand log
  output logFormat
  option maxCount "-n" : Int with (range 1 1000)   // 内联验证器
  param 0 : String with (regex r"^[a-zA-Z0-9_/.-]+$")  // 内联验证器

subcommand remote
  output default
  option verbose "-v" : Bool

  subcommand add
    option fetch "-f" : Bool
    param 0 : String
    param 1 : String with (regex r"^https?://")     // 内联验证器

subcommand config
  output default
  option global "--global" : Bool

  subcommand get
    option type "--type" : String with (include ["int", "bool", "path"])
    param 0 : String

// 文档模式解析器：整个输出作为 JSON 处理
parser podInfo : Result PodInfo String = ParsePodInfo.parseAll

subcommand get-pod
  output podInfo-doc
  param 0 : String

// 退出码声明
exitcode 0 = Ok
exitcode 1 = Ok empty       // 如 grep 无匹配
exitcode * = Err (IOError.Other "exit {code}")
```

### CDF 与 Kun 的边界

CDF 是编译期 DSL，不是 Kun 语言的子集。各元素的来源和解析策略：

| CDF 元素 | 来源 | 说明 |
|---------|------|------|
| 基本类型 `Bool`/`Int`/`String`/`Path` | 借用 Kun 类型名 | 编译期直接映射为 Kun 对应类型 |
| `validator <name> = <expr>` 中的 `<expr>` | **CDF 自有表达式** | 独立解析，不经过 Kun 解析器 |
| `MyModule.validateName` 引用 | 引用 Kun 模块函数 | CDF 编译器需理解 Kun 的模块路径解析 |
| `p"/path"` 字面量 | 借用 Kun 语法 | CDF 编译期求值为 Path 常量 |
| `r"^regex$"` 字面量 | 借用 Kun 语法 | CDF 编译期求值为 Regex 常量 |

#### 生成的 Kun 模块

```kun
// 代码生成器将 CDF 层级映射为嵌套模块结构。
// 内部函数名使用 _ 连接层级（git_remote_add），
// 对外调用通过模块路径语法（git.remote.add）。

module Git export
  ( git
  , git_status    as git.status
  , git_log       as git.log
  , git_remote    as git.remote
  , git_remote_add as git.remote.add
  , git_config    as git.config
  , git_config_get as git.config.get
  )

// 解析器返回类型
type StatusEntry = { file : Path, status : String }
type CommitEntry = { hash : String, author : String, message : String }

// Options Record（代码生成，runAs 自动注入）
type GitOptions = { runAs : ?RunAs }
type GitStatusOptions = { short : Bool, runAs : ?RunAs }
type GitLogOptions = { maxCount : ?Int, runAs : ?RunAs }

// 根命令（参数顺序：Options → param *）
git : GitOptions -> List String -> IO
  (Result (Stream String) IOError)

// 一级子命令
git_status : GitStatusOptions -> IO
  (Result (Stream StatusEntry) IOError)

git_log : GitLogOptions -> String -> IO
  (Result (Stream CommitEntry) IOError)

// 嵌套子命令
git_remote : GitRemoteOptions -> IO
  (Result (Stream String) IOError)

git_remote_add : GitRemoteAddOptions -> String -> String -> IO
  (Result (Stream String) IOError)

git_config : GitConfigOptions -> IO
  (Result (Stream String) IOError)

git_config_get : GitConfigGetOptions -> String -> IO
  (Result (Stream ConfigEntry) IOError)
```

#### 调用示例

```kun
// 根命令
git {} ["status"]
// → git status

// status 子命令
git.status { short = true }
// → git status -s

// remote add 子命令
git.remote.add { fetch = true } "origin" "https://github.com/user/repo.git"
// → git remote add --fetch origin https://github.com/user/repo.git

// config get 子命令（内联字符串参数，无需单独声明 validator）
git.config.get { type = Just "bool" } "core.autocrlf"
// → git config get --type bool core.autocrlf
```

### `exitcode` — 退出码声明

退出码是 POSIX 进程级协议，命令函数在内部消化，不暴露给调用方。CDF 通过 `exitcode` 声明每个退出码的语义：

```cdf
exitcode 0  = Ok                               // 成功 → Ok
exitcode 1  = Ok empty                          // 同成功但无输出（如 grep 无匹配）
exitcode 2  = Err (IOError.NotFound "{file}")   // 出错 → Err
exitcode *  = Err (IOError.Other "{stderr}")    // 默认：其他非零码 → Err
```

| 规则 | 说明 |
|------|------|
| `exitcode <N> = Ok` | 退出码 `N` → `Ok (Stream T)` |
| `exitcode <N> = Ok empty` | 退出码 `N` → `Ok Stream.empty`（空流，非错误） |
| `exitcode <N> = Err <expr>` | 退出码 `N` → `Err <expr>` |
| `exitcode * = ...` | 通配规则，匹配其他所有未声明的退出码 |

缺省行为（未声明任何 `exitcode` 时）：

```
退出码 0 → Ok (Stream T)
退出码 ≠ 0 → Err (IOError.Other "command exited with code N")
```

#### 代码生成包装逻辑

```
子进程退出，exit code = N
  │
  ├── N 有显式 exitcode 声明？
  │     ├── Ok → 返回 Ok，调用 CmdResult.stdout（已去除）
  │     ├── Ok empty → 返回 Ok Stream.empty
  │     └── Err expr → 返回 Err expr
  │
  └── N 无显式 & 无通配？
        ├── N == 0 → Ok
        └── N ≠ 0 → Err (IOError.Other "exit N")
```

### 行流 vs 文档模式

命令输出有两种消费模式，由 `output` 声明选择：

| 模式 | 适用场景 | `output` 声明 | 返回类型 |
|------|---------|--------------|---------|
| **行流** | 每行是一条独立记录（日志、JSON Lines、`grep` 结果） | `output <name>` / `default` / `json` | `IO (Result (Stream T) IOError)` |
| **文档** | 整个输出是一个结构化整体（`kubectl get -o json`、`curl` API 响应） | `output <name>-doc` / `text-doc` / `json-doc` | `IO (Result T IOError)` |

区别在于运行时对命令 stdout 的喂给策略：

```
行流模式：
  stdout 逐行剪裁 → 每行独立喂给 parser → 产出一个 Stream 元素
  命令长时间运行时可边输出边处理

文档模式：
  stdout 完整收集 → 等命令退出后一次喂给 parser → 产出一个完整结果
  命令输出必须是自包含的完整文档
```

#### 行流命令函数返回类型

```kun
IO (Result (Stream T) IOError)
```

#### 文档模式命令函数返回类型

```kun
IO (Result T IOError)
```

示例：

```kun
// 行流：逐行处理日志
kubectl.logs {} ["pod-1"]        // output json → Stream JsonValue
  |> iter (\line -> process line)

// 文档：完整 JSON 对象
pod <-? kubectl.get.pods { output = "json" }   // output json-doc → JsonValue
nodeCount = pod["items"] |> length
```

`CmdResult` 已移除。退出码在内部处理，调用方只看到有意义的业务结果。

调用方示例：

```kun
// grep 找到匹配 → Ok (Stream ["line1", "line2"])
lines <-? grep {} ["pattern", "/etc/passwd"]
lines |> iter print

// grep 无匹配 → Ok Stream.empty（不是错误）
lines <-? grep {} ["nonexistent", "/etc/passwd"]
lines |> iter print    // 输出空

// grep 文件不存在 → Err (IOError.NotFound "/nonexistent")
Err e <-? grep {} ["pattern", "/nonexistent"]
// e = NotFound "/nonexistent"

// 命令不存在 → Err (IOError.Other "command not found")
```

### 代码生成规则

| CDF 声明 | 生成产物 |
|---------|---------|
| `command <name>` | 函数 `<name>`，Record `<Name>Options` |
| `subcommand <name>` | 内部函数 `<main>_<name>`，调用语法 `<main>.<name>`（多层嵌套 `<main>.<sub1>.<sub2>`） |
| `option x "-x" : Bool` | 字段 `x : Bool`，argv 构造展开为 `-x` |
| `option x "-x" : T` | 字段 `x : ?T` |
| `option x "-x" : T!` | 字段 `x : T` |
| `option x "-x" : List T` | 字段 `x : List T`，argv 构造 `-x v1 -x v2 -x v3` |
| `param <N> : T` | 函数第 N+1 个参数（Options 后），类型 `T` |
| `param * : List T` | 函数最后一个参数，类型 `List T` |
| `validator <name> = <expr>` | 常量 `name : Validator T`，编译期展开 |
| `parser <name> : Stream (Result T S) = M.f` | 注入 `M.f` 到命令函数实现 |
| `output <name>` | 行流模式。Parser 入参 `Stream String`，返回 `Result (Stream T) IOError` |
| `output default` / `output json` | 行流模式。`T` = `String` / `JsonValue` |
| `output text-doc` | 文档模式。收集全部 stdout 为 String，返回 `Result String IOError` |
| `output json-doc` | 文档模式。整个输出解析为 JsonValue，返回 `Result JsonValue IOError` |
| `output <name>-doc` | 文档模式。parser 签名 `String -> Result T String`，返回 `Result T IOError` |
| `output` 内置标识符 | `default`、`json`、`text-doc`、`json-doc` 为保留标识符，自定义 `parser` 不可同名 |
| `runAs` | 自动注入到 Options Record 作为`runAs : ?RunAs` |
| `option type`等关键字名 | Record 字段名直接使用关键字，不受限制 |
| `exitcode N = Ok` | 退出码 N → `Ok (Stream T)` |
| `exitcode N = Ok empty` | 退出码 N → `Ok Stream.empty` |
| `exitcode N = Err <expr>` | 退出码 N → `Err <expr>` |
| `exitcode * = ...` | 通配规则，无对应声明时由缺省行为处理 |

### 隐式字段注入

代码生成器自动在所有 Options Record 中注入以下字段。CDF 中声明同名 `option` 均编译期报错：

`FdSpec` 类型定义：

```kun
type FdSpec
  = ReadFromPath Path        // fd < path：从文件读取
  | WriteToPath Path         // fd > path：写入文件
  | ReadFromStr String       // fd <<< "str"：从字符串读取（heredoc 等效）
  | InheritFrom Int          // fd <& N：继承自另一 fd
  | RedirectTo Int           // fd >& N：重定向到另一 fd
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `runAs` | `?RunAs` | 命令函数的执行用户身份，控制通过 `process.run-as` 能力 |
| `env` | `Map String String` | 子进程环境变量，缺省继承当前进程环境。非 CLI 参数，不传递给 argv |
| `stdin` | `?(Fd OrPath)` | 子进程标准输入来源（文件路径或现有 fd） |
| `stdout` | `?(Fd OrPath)` | 子进程标准输出目标 |
| `stderr` | `?(Fd OrPath OrStdioMode)` | 子进程标准错误目标，支持 `Pipe`/`Inherit` 模式 |
| `fd` | `Map Int FdSpec` | 额外文件描述符重定向，键为 fd 编号，值为 `FdSpec` 类型 |

调用示例：

```kun
// 带环境变量注入和输出重定向的命令
git.log { env = Map.fromList [("GIT_DIR", "/repo/.git")]
        , stdout = Just (Path p"/tmp/git.log")
        , maxCount = Just 50 }
// → GIT_DIR=/repo/.git git log -n 50 > /tmp/git.log

// 管道模式
git.log { stderr = Just StdioMode.Pipe, maxCount = Just 10 }
  |> handleStderr
// → git log -n 10 2>&1 管道到 handleStderr

// 进程替换 / fd 重定向
diff { fd = Map.fromList
         [ (3, FdSpec.ReadFromPath p"/tmp/a")
         , (4, FdSpec.ReadFromPath p"/tmp/b") ] }
// → diff 3< /tmp/a 4< /tmp/b

// heredoc 等效：fd 读取字符串
diff { fd = Map.fromList [(3, FdSpec.ReadFromStr "content a\ncontent b")] }
```

隐式字段的 argv 映射：

```
env    → 不在 argv 中，通过 setenv/pre-exec 注入
stdin  → 不在 argv 中，通过 dup2/重定向实现
stdout → 不在 argv 中，通过 dup2/重定向实现
stderr → 不在 argv 中，通过 dup2/重定向实现
runAs  → 不在 argv 中，通过 setuid 切换实现
```

## seccomp 规则自动推导

seccomp-BPF 过滤规则由命令的参数类型和名称自动推导，不再依赖独立的 behavior 声明：

| 参数模式 | 允许的系统调用 | 说明 |
|---------|--------------|------|
| `Path` 类型参数 | `openat`、`read`、`pread64`、`fstat`、`close`、`lseek` | 文件读取 |
| 输出/写入语义参数 | `openat`、`write`、`pwrite64`、`ftruncate`、`fsync`、`close` | 文件写入 |
| 网络/URL 类型参数 | `socket`、`connect`、`sendto`、`recvfrom`、`close` | 网络请求 |
| 子进程相关参数 | `clone`、`execve`、`waitid`、`exit_group` | 进程管理 |
| 无匹配参数 | `brk`、`mmap`、`munmap`、`exit_group` | 仅内存操作 |

## 命令函数实现方式

### 实现策略

命令函数有两种实现方式，根据命令复杂度选择：

| 实现方式 | 适用条件 | 运行时机制 | 工作量和风险 |
|---------|---------|-----------|------------|
| **内建 Primitive**（Zig 实现） | 实现简单、功能单一、有直接内核 API 支持、或有更优的内置替代实现 | 进程内函数调用，无子进程开销 | 每命令 50-600 行，低风险 |
| **CDF 映射**（外部命令） | 功能复杂、网络交互、需要完整的外部工具链 | 通过子进程执行，CDF 声明签名和输出类型，运行时自动解析 | CDF 编写 + 文本解析 |

Kun 已内建 `Regex` 类型和正则引擎，因此文本搜索类命令（`grep`、`find`）可选用内建 Primitive 实现（复用正则引擎），避免子进程文本回传开销。

### 覆盖范围

| 类别 | 命令 | 实现方式 | 输出类型 | 理由 |
|------|------|---------|---------|------|
| 文件信息 | `ls`、`stat`、`du`、`df` | **内建 Primitive** | 结构化 | 直接调用 `getdents()`/`statx()`/`statvfs()`/`fts_open()`，内核 API 稳定 |
| 文件操作 | `cp`、`mv`、`rm`、`mkdir`、`touch` | **内建 Primitive** | 仅退出码 | `sendfile()`/`rename()`/`unlinkat()`/`mkdirat()`，能力集成价值高 |
| 权限操作 | `chmod`、`chown`、`ln`、`readlink`、`realpath`、`umask` | **内建 Primitive** | 仅退出码 | `fchmodat()`/`fchownat()`/`linkat()`/`readlinkat()`，直接系统调用 |
| 归档包 | `zip`、`unzip` | CDF 映射 | 仅退出码 | 无内核支持，需外部库 |
| 压缩 | `gzip`、`gunzip`、`xz`、`zstd` | CDF 映射 | 仅退出码 | 无内核支持，需外部库 |
| 内容搜索 | `grep` | **内建 Primitive** | 结构化 | 复用内建正则引擎，避免子进程 pipe |
| 目录遍历 | `walkDir` | **内建 Primitive（标准库）** | 结构化 | `fts_open()` 树遍历，返回 `Stream DirEntry`；过滤在外部通过 `filter` 完成 |
| — | `find` | **不映射**（由 `walkDir` + `filter` 替代） | — | `walkDir` 的 `filter` 组合覆盖所有 `find` 用例（-name/-type/-size 等） |
| 数据库检索 | `locate` | **内建 Primitive** | 结构化 | 直接读取 mlocate.db 二进制格式 |
| 进程信息 | `ps` | **内建 Primitive** | 结构化 | 读取 `/proc/[pid]/*` 直接返回结构化类型 |
| 系统信息 | `free`、`uname`、`lscpu`、`uptime` | **内建 Primitive** | 结构化 | `sysinfo()`/`uname()` 等直接系统调用 |
| 网络连接信息 | `ss` | CDF 映射 | 结构化 | netlink 协议实现复杂度中等，保持外部命令 |
| 网络交互 | `curl`、`wget`、`dig`、`ping` | CDF 映射 | 结构化 | HTTP/TLS/ICMP 栈复杂度极高 |
| 远程同步 | `rsync`、`scp` | CDF 映射 | 结构化/仅退出码 | 复杂协议，无法内建 |
| 归档内容 | `tar` | CDF 映射 | 结构化 | 归档格式解析复杂度高 |

**不映射**（由 Kun 标准库和语言特性覆盖）：`sed`、`awk`、`sort`、`uniq`、`cut`、`tr`、`head`、`tail`、`cat`、`wc`、`tee`

### `walkDir` 的设计

`walkDir` 负责目录树遍历，过滤在外部通过 `filter` 完成——职责清晰，避免内建谓词语法：

```kun
// 系统 find: find /var/log -name "*.log" -type f -size +100M
// Kun walkDir + filter:
walkDir { root = p"/var/log" }
  |> filter (\e -> e.name |> endsWith ".log")
  |> filter (\e -> e.fileType == RegularFile)
  |> filter (\e -> e.size > 100 * MB)
```

```kun
// walkDir 的签名
type DirEntry = { path : Path, fileType : FileType, size : Int, mtime : DateTime }

walkDir : { root : Path, depth : ?Int
          , followSymlinks : Bool = false
          , runAs : ?RunAs
           } -> IO (Result (Stream DirEntry) IOError)
```

### 管道与参数展开（xargs 模式）

Kun 的 `|>` 管道和 `Stream.toList` 组合自然支持 xargs 风格的模式，无需独立 `xargs` 命令：

```kun
// Shell: pip freeze | xargs pip install
// Kun: 先取包列表，再作为参数传给安装命令
packages = pip.freeze {} []
  |> filter (\line -> line |> contains "==")
  |> toList

pip.install {} packages
// → pip install package1==1.0 package2==2.0
```

`Stream.toList` 将惰性流消费为 `List String`，直接作为 `param *` 传入下一命令。对于需要逐个参数处理的场景（如并行调用），使用 `Stream.iter` 实现：

```kun
// 逐个安装（非 xargs 批量）
pip.freeze {} []
  |> filter (\line -> line |> contains "==")
  |> iter (\pkg -> pip.install {} [pkg])
```

### 内置签名的存储

内置签名编译在 Kun 运行时二进制中，以 Zig 静态数组形式存在：

```zig
// Zig 伪代码：内置签名条目
const BUILTIN_SIGNATURES = [_]SignatureEntry{
    .{ .name = "ls",  .cdf_data = @embedFile("cdf/ls.cdf") },
    .{ .name = "cat", .cdf_data = @embedFile("cdf/cat.cdf") },
    // ... 更多
};
```

## 签名自动推断

### 推断策略

每次 `run""` 调用自动触发签名查找流程：

```
run"kubectl" ["get", "pods"]
  │
  ├── T1：内置签名库命中 → 升级为内建 Primitive
  ├── T2：项目级 CDF → 用户级 CDF 命中 → 升级为 CDF 命令函数
  └── 以上均未命中 → 启动 auto-infer
      ├── man 手册解析（首选，信息最详尽）
      ├── --help/-h 解析（回退，信息有限）
      └── 默认签名（无信息可用：无 flag/positional，output default）
```

### man 手册解析

```
man 页面
  │
  ▼
提取 OPTIONS / ARGUMENTS / DESCRIPTION 段落
  │
  ├── 解析短标志: -v, -o file, -n NUM
  ├── 解析长标志: --verbose, --output=file
  ├── 解析参数类型: file, num, string, path
  ├── 解析枚举值: r|w|x
  └── 解析默认值: (default: 42)
  │
  ▼
生成 CDF 片段 → 合并 → 签名
```

### 子命令检测

```
命令 --help 输出
  │
  ▼
检测 "Usage: <cmd> <subcommand>" 模式
  │
  ▼
对每个子命令递归获取帮助
  ├── man <cmd>-<subcommand>      # 优先：如 git-commit
  ├── man <cmd> <subcommand>      # 回退：如 man git commit
  └── <cmd> <subcommand> --help   # 最终回退
  │
  ▼
每个子命令独立签名
```

### AI 辅助整理

当自动推断结果不够精确时，运行时输出整理提示词：

```
// 运行时输出的 CDF 草稿
// 请人工审核后保存到 ~/.kun/cdf/<command>.cdf

command "<command>"
  // 自动推断结果（可能需要人工修正）
  flag "verbose" 'v' : Bool                     // 置信度: 高
  option "output" 'o' : String                  // 置信度: 中（类型不确定）
  positional 0 : String                         // 置信度: 低（位置参数含义未知）
```

### 自动 CDF 生成

`run""` 调用时自动触发 auto-infer，无需用户干预：

```bash
kun run script.kun
# script.kun 中有 run"kubectl" ["get", "pods"]
# → T1/T2 未命中
# → 自动触发 --help/man 解析
# → 生成 CDF 草稿并缓存到 ~/.kun/cdf/kubectl.cdf
# → 本次按 T3 级别执行
# → 下次调用自动升级为 T2
```

用户也可手动 `kun cdf init <command>` 从命令的 `--help`/man 页面预生成 CDF 骨架，或审核 auto-infer 生成的草稿后添加签名。

## CDF 生命周期

### 获取（auto-infer 自动完成）

```
run"kubectl"（首次）
  → auto-infer 触发
  → CDF 草稿缓存到 ~/.kun/cdf/kubectl.cdf
  → 下次调用自动升级为 T2
```

### 编写（可选，审核自动生成的草稿）

```
审核 auto-infer 生成的 CDF 草稿
  → 修正类型推断不准确的部分
  → 添加 parser 输出声明
  → 签名 → 部署
```

### 签名

```
CDF 文件
  │
  ▼
Ed25519 签名（private key）
  │
  ▼
CDF + .sig 文件 → 分发
```

### 验证缓存

运行时缓存 CDF 解析结果以提升性能：

```
~/.kun/cache/
├── cdf_parsed/          # 解析后的 CDF（二进制格式）
│   ├── ls.cdf.cache
│   └── git.cdf.cache
├── man_parsed/          # 解析后的 man 页面
│   └── rsync.man.cache
└── signatures/          # 验证过的 CDF 签名
    └── custom-tool.sig.cache
```

缓存失效策略：
- 源 CDF 文件 mtime 更新 → 重新解析
- 签名有效期过期 → 重新验证
- 缓存目录超过 30 天未使用 → 自动清理

### 版本兼容性

CDF 版本号声明方式见[版本号声明](#版本号声明)节。格式变更策略：
- 向下兼容：解析器支持旧版格式
- 升级提示：运行时检测到旧版 CDF 时输出建议
- 强制升级：仅当旧版格式存在安全漏洞时

## 运行时集成

### `run` 加载流程

```
run"kubectl" ["get", "pods"]
  │
  ├── process.run 检查
  │   ├── "kubectl" 在白名单中 → 继续
  │   └── 拒绝 → PermissionError
  │
  ├── 签名查找：内置 → 项目级 CDF → 用户级 CDF → auto-infer
  │   │
  │   ├── T1/T2 命中 → 升级为命令函数，走 CDF 加载流程
  │   ├── T3 auto-infer 成功 → 缓存 CDF 草稿 + 本次 T3 级别执行
  │   └── T4 均未命中 → 留在 run 模式
  │       │
  │       ├── 1. 强制审计日志记录
  │       ├── 2. 配置沙箱（PID/mount/network namespace）
  │       │   └── 网络 namespace 根据 net.* 能力放行
  │       ├── 3. 应用通用 seccomp 白名单
  │       ├── 4. fork-exec 加载子进程
  │       └── 5. 返回 Stream String
```

### 超长参数自动分片

`List String` 类型的 `param *` 或 `option x "-x" : List T` 在运行时可能产生超出 OS `execve` 限制（通常 2MB）的 argv。运行时自动处理：

```
param * : List String 传入 100 万条目
  │
  ├── 计算总 argv 长度
  │
  ├── 长度 < 内核限制（2MB） → 一次 exec
  │
  └── 长度 ≥ 内核限制
      │
      ├── 自动分片：将 List 切分为 N 个子列表
      ├── 依次 exec 每个分片（共享 stdin/stdout/stderr 配置）
      └── 隐式合并所有分片的 stdout Stream
          └── 用户感知为一次完整的调用
```

分片对用户完全透明，`Stream` 元素顺序与不分裂时一致。

仅在 `List String` 或 `List T` 类型的参数上触发。单个 `String`/`Int` 等标量参数不会超出限制。

### 参数验证器运行时

参数验证器在序列化参数前执行：

```kun-cdf
option "port" 'p' : Int with (range 1 65535)
// 用户传入 -p 99999
// → 验证失败：ValidationError { validator: "range", constraint: "1..65535", actual: "99999" }
// → 阻止执行，报告错误
```

## 与运行时架构的关系

命令签名系统与运行时的接口定义在 `系统基线文档` 中：

| 运行时组件 | CDF 交互点 |
|-----------|-----------|
| 命令加载器 | 根据 CDF 决定加载策略（dlopen/ptrace/fork-exec） |
| 参数序列化器 | 根据 CDF 参数定义确定序列化格式 |
| seccomp 管理器 | 根据命令参数类型和名称生成 seccomp-BPF 规则 |
| 结果反序列化器 | 根据 CDF output 定义解析返回值 |



## CDF 源代码管理

### git 集成

CDF 文件和加密密钥建议按以下方式管理：

```
.kun/                       # 项目根目录下的 Kun 配置目录
├── cdf/                    # 项目级 CDF 定义
│   ├── custom-tool.cdf
│   └── deploy-tool.cdf
└── trusted-keys/           # 项目信任的公钥
    ├── maintainer-1.pub
    └── maintainer-2.pub
```

- `cdf/` 提交到版本控制
- `trusted-keys/` 提交到版本控制
- 私钥永不提交，通过安全渠道管理

## CDF 注册中心

社区贡献的 CDF 文件通过注册中心分发，降低每个用户自写 CDF 的成本：

### 安装

```bash
kun cdf install kubectl                   # 安装最新版本
kun cdf install kubectl@1.28              # 安装指定版本
kun cdf search kubectl                    # 搜索注册中心
kun cdf list                              # 列出已安装的 CDF
```

### 分发格式

注册中心中的每个 CDF 包包含：

```
kubectl/
├── kubectl.cdf           # CDF 定义
├── kubectl.cdf.sig       # Ed25519 签名
└── metadata.toml         # 版本、作者、依赖等信息
```

### 信任链

- 注册中心对所有提交进行自动化验证（语法检查 + 安全审计）
- 用户可配置信任的公钥列表（`~/.kun/trusted-keys/`）
- 项目级 `trusted-keys/` 覆盖个人配置
- 未签名的 CDF 包被拒绝安装

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 0.2.0 | 2026-06-04 | 分级可用性模型（T1-T4）、内联验证器、`.` 分隔子命令调用、CDF 注册中心、自动生成工具 |
| 0.1.0 | 2026-05-31 | CDF 文件格式、参数定义、输出类型、行为声明、签名自动推断、内置签名库、运行时集成 |

