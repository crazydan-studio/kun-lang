# ~~命令签名系统设计~~ 已废弃

> **本设计已废弃**。CDF（Command Description File）方案已被 `.cmd.kun` + Builder API 方案完全替代。
> 新设计见 `command-function-system.md`。本文件保留仅作历史参考，不应用于新开发。

## 定位

命令签名系统是 Kun 将 Linux 命令抽象为类型安全函数的桥梁。核心原则是**映射能力（Capability），而非形式（Form）**。命令函数的本质是**获取结构化结果**，而非执行特定命令。`ls p"/tmp"` 的语义是"获取 /tmp 目录下的文件列表（名称、类型、大小、时间）"，而非"执行带有这些参数的 ls"。

设计者不应问"这个命令有哪些 flags？"，而应问"用户通过这个命令想要获得什么能力？"。CLI 的 flags、子命令、参数格式是能力的历史载体，而非能力本身。详见[能力映射指南](capability-mapping-guide.md)。

调用命令函数时，运行时会自动处理输出的结构化和反序列化——用户通过 CDF（Command Description File，命令描述文件）声明的返回类型操作结果，不直接接触原始文本输出。

## `run` — 命令入口

所有命令的执行统一通过 `run` 内置语法：

```kun
run"kubectl" ["get", "pods", "-n", "default"]
// → Stream String（T4 默认）
// → 有审计日志 + 沙箱隔离
// → 无结构化输出，无参数校验
```

`run` 是命令执行的唯一入口。它返回 `Stream String`，由 `process.run` 能力控制授权。命令默认不可执行，必须在 `process.run` 白名单中显式声明才可使用。

### `process.run` 能力

`run` 命令由 `process.run` 能力控制，白名单机制，默认拒绝：

```kun
with caps
  process.run = ["kubectl", "docker", "curl"]

main =
  do
    run"kubectl" ["get", "pods"]          // ✅
    run"docker" ["ps"]                    // ✅
    run"ssh" ["user@host"]                // ❌ 不在白名单
```

| 规则 | 说明 |
|------|------|
| basename 精确匹配 | `process.run = ["kubectl"]` 匹配 `kubectl` |
| `[]` 通配 | `process.run = []` 放行所有在白名单场景确有必要时使用 |
| 默认 | 空列表——无 `run` 权限。任何命令都不可执行 |

注意：`process.run` 白名单仅控制 `run` 语法（T4 原始模式）。升级到 T1/T2 的命令函数不受此限制——CDF 存在即授权。

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
| **T4 `run`** | `process.run` 白名单允许 + 无升级路径匹配 | `Stream String` | `process.run` 白名单 + 基础沙箱 + 审计日志 |

用户在所有级别使用相同的 `run""` 语法。升级是透明的：

```kun
// 第一次写时：T4，返回 Stream String
// 缓存 CDF 后：T2，返回 Result (Stream StatusEntry) IOError
// 用户代码不需要改——编译器根据 T 级别处理返回值
output = run"kubectl" ["get", "pods"]
// T4 时：output : Stream String
// T2 时：output : Result (Stream PodEntry) IOError
```

### 设计原则

1. **能力优先**：函数签名表达用户想要的能力，而非命令的 CLI 形式。参数只映射影响"返回什么"的要素
2. **自动升级**：`run` 调用自动触发签名查找 + auto-infer，T4 → T3 → T2 逐级透明升级
3. **渐进安全**：T4 白名单 + 基础隔离 → T3 中等 → T2 完整
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
command_body   = { param_decl | output_decl | bin_decl | exitcode_decl | subcommand_decl } ;

(* 退出码声明 *)
exitcode_decl  = 'exitcode' , ( '*' | number ) , '=' , ( 'Ok' [ 'empty' ] | 'Err' , expression ) ;

(* 能力参数（替代旧 option + param 合并声明） *)
param_decl    = 'param' , identifier , ':' , type_expr , 'with' , '(' , category , [ ',' , cli_spec ] , [ ',' , validator_call ] , ')' ;
category      = 'essential' | 'filter' | 'behavior' ;
cli_spec      = 'cli:' , ( string_literal | cli_cases | 'positional' , ( natural | '*' ) ) ;
cli_cases     = 'case' , type_name , 'of' , newline
                , indent , { cli_case } , dedent ;
cli_case      = identifier , '->' , ( string_literal | '[' , string_literal , { ',' , string_literal } , ']' ) ;
validator_call = expression ;

(* 输出声明 *)
output_decl    = 'output' , ( identifier [ '-doc' ] | 'default' | 'json' | 'text-doc' | 'json-doc' ) ;

(* 命令路径 *)
bin_decl       = 'bin' , path_literal ;

(* 类型 *)
type_expr      = type_name | 'List' , type_name | 'Map' , type_name , type_name ;
type_name      = 'Bool' | 'Int' | 'Nat' | 'Float' | 'String' | 'Path' | 'Map' | identifier ;
path_literal   = 'p"' , { character } , '"' ;
string_literal = '"' , { character } , '"' ;
number         = digit , { digit } ;
natural        = digit , { digit } ;
identifier     = ( letter | '_' ) , { letter | digit | '_' } ;
```

**语义约束**（解析器必须在语法分析后额外检查）：

| # | 约束 | 违规处理 |
|---|------|---------|
| 1 | `param` 的 `identifier` 在同一 `command_body` 中不可重复 | 编译期报错：参数名重复 |
| 2 | `cli_spec` 中 `positional` 的编号 `N` 必须严格递增 | 编译期报错：位置参数编号顺序错误 |
| 3 | `cli_spec` 中 `positional *` 最多出现一次 | 编译期报错：positional * 重复 |
| 4 | `param` 声明 `List T` 时，`cli:` 标记为可重复标志，argvc 构造为每个元素展开一次标志 | — |
| 5 | `param` 声明 `Map K V` 时，`cli:` 标记格式为 `<k>=<v>` 模式 | — |
| 6 | `output` 引用 `identifier` 时，该标识符必须在文件前面的 `parser_decl` 中已定义 | 编译期报错：引用了未定义的解析器 |
| 7 | `output default` 和 `output json` 为关键字，不可用作自定义 `parser` 名称 | 编译期报错：default/json 为保留标识符 |
| 8 | `bin` 的相对路径（`p"./..."` 开头）不可超出 CDF 所在目录（`../` 不允许） | 编译期报错：bin 路径超出 CDF 目录 |

**词法规定**：
- CDF 使用缩进（空格/制表符）表示 `command`/`subcommand` 的嵌套层级
- `//` 为行注释，注释内不解析其他语法
- `identifier` 区分大小写，不能以数字开头

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

#### `param`——能力参数声明

`param` 是 CDF 的核心声明，表达用户通过命令函数表达的能力参数。每个 `param` 声明包含：
1. 参数名（Kun Record 字段名）
2. 类型（Kun 类型）
3. 分类（essential / filter / behavior）
4. CLI 映射（可选，编译期实现细节）
5. 验证器（可选）

```
param <name> : <type> with (<category> [, cli: <cli-spec>] [, <validator>])
```

| 部分 | 说明 |
|------|------|
| `<name>` | 函数参数 Record 的字段名，不加引号 |
| `<type>` | 参数类型。支持 `T`、`?T`（可选）、`List T`（重复）、`Map K V`（KV 映射） |
| `<category>` | 参数分类：`essential`（核心定位参数）、`filter`（筛选参数）、`behavior`（行为参数）。见[能力映射指南](capability-mapping-guide.md) |
| `<cli-spec>` | CLI 映射规范（可选），编译期/运行时据此构造 argv。可省略——运行时 auto-infer 自动决定 |
| `<validator>` | 可选验证器（同旧 `with` 语法） |

**分类语义**：
- `essential`：核心参数，决定操作的目标。函数生成时为此参数生成必填字段
- `filter`：影响结果集的参数。函数生成时为此参数生成 `?T` 或带默认值的字段
- `behavior`：改变执行方式的参数。函数生成时为此参数生成 `?T` 或带默认值的字段

**CLI 映射规范**：

```cdf
// 直接 flag
param all : Bool with (filter, cli: "-a")
param verbose : Bool with (behavior, cli: "--verbose")

// 带值 flag
param output : Path with (filter, cli: {"-o", <value>})
param maxCount : Int with (filter, cli: {"--max-count", <value>})

// 位置参数
param path : Path with (essential, cli: positional 0)
param pattern : String with (essential, cli: positional 0)

// 可变位置参数
param args : List String with (essential, cli: positional *)

// 条件 CLI 映射（不同值映射不同的 flag）
param sortBy : SortBy with (filter, cli: case SortBy of
                                Name -> "--sort=name"
                                Size -> "--sort=size"
                                Time -> "--sort=time")

// 重复 flag（List T）
param env : Map String String with (behavior, cli: {"-e", <k>=<v>})
param port : List PortMapping with (behavior, cli: {"-p", <src>:<dst>})

// 无 CLI 映射（运行时 auto-infer 自动决定）
param all : Bool with (filter)    // cli 省略，auto-infer 发现 -a
```

**CLI 映射是可选实现细节**。参数的能力语义不依赖于 CLI 映射的存在——即使不写 `cli:`，运行时 auto-infer 也会自动发现合适的 CLI 对应关系。

**注意**：`cli:` 中的 flag 字符串（如 `"-a"`、`"--verbose"`）是编译期/运行时的实现细节，不暴露给 Kun 语言用户。用户通过 Record 字段名操作参数。

**`List T` 与 `Map K V` 类型**：

```cdf
param env : List String with (behavior, cli: {"-e", <value>})
// → List String，argv 展开为 -e v1 -e v2 -e v3

param env : Map String String with (behavior, cli: {"-e", <k>=<v>})
// → Map String String，argv 展开为 -e k1=v1 -e k2=v2
```

调用示例：

```kun
// docker run --detach --restart=always -e DB_HOST=prod -p 80:8080 nginx
docker.run { image = "nginx", detach = true,
             restart = Restart.Always,
             env = Map.fromList [("DB_HOST", "prod")],
             port = [PortMapping { host = 80, container = 8080 }] }
```

**内联验证器**：

```kun-cdf
param port : Int with (behavior, cli: {"-p", <value>}, range 1 65535)
param format : String with (filter, cli: {"-f", <value>}, include ["json", "csv"])
param branch : String with (filter, cli: positional 0, regex r"^[a-z]+$")
```

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
  param args : List String with (essential, cli: positional *)

subcommand status
  output statusFormat
  // status 的核心能力是获取工作区状态——无多余参数
  // 运行时自动选择最佳输出格式（porcelain/json 等）用于解析

subcommand log
  output logFormat
  param maxCount : ?Int with (filter, cli: {"-n", <value>}, range 1 1000)
  param branch   : ?String with (filter, cli: positional 0, regex r"^[a-zA-Z0-9_/.-]+$")

subcommand remote
  output default

  subcommand add
    param name : String with (essential, cli: positional 0)
    param url  : String with (essential, cli: positional 1, regex r"^https?://")

subcommand config
  output default

  subcommand get
    param key   : String with (essential, cli: positional 0)
    param scope : ?ConfigScope with (filter, cli: case ConfigScope of
                                           Local -> "--local"
                                           Global -> "--global"
                                           System -> "--system")

// 文档模式解析器：整个输出作为 JSON 处理
parser podInfo : Result PodInfo String = ParsePodInfo.parseAll

subcommand get-pod
  output podInfo-doc
  param name : String with (essential, cli: positional 0)

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
  ( git, git_status, git_log
  , git_remote, git_remote_add
  , git_config, git_config_get
  )

// 解析器返回类型
type StatusEntry = { file : Path, status : String }
type CommitEntry = { hash : String, author : String, message : String }

// Options Record（代码生成，runAs 自动注入）
// 每个 param 对应一个 Record 字段，分类决定其类型：
//   essential → 普通字段
//   filter    → ?T 字段（可选）
//   behavior  → ?T 字段（可选）
type GitOptions = { runAs : ?RunAs, args : List String }
type GitStatusOptions = { runAs : ?RunAs }               // 无 filter/behavior 参数
type GitLogOptions = { maxCount : ?Int, branch : ?String, runAs : ?RunAs }

// 根命令（参数顺序：Options 单 Record）
git : GitOptions -> IO (Result (Stream String) IOError)

// 一级子命令
git_status : GitStatusOptions -> IO (Result (Stream StatusEntry) IOError)

git_log : GitLogOptions -> IO (Result (Stream CommitEntry) IOError)

// 嵌套子命令
git_remote : GitRemoteOptions -> IO (Result (Stream String) IOError)

git_remote_add : GitRemoteAddOptions -> String -> String -> IO
  (Result (Stream StatusEntry) IOError)

git_config : GitConfigOptions -> IO (Result (Stream String) IOError)

git_config_get : GitConfigGetOptions -> String -> IO
  (Result (Stream ConfigEntry) IOError)
```

#### 调用示例

```kun
// 根命令（传递 raw args）
git { args = ["status"] }
// → git status

// status 子命令——始终返回结构化 StatusEntry
// 无 short/long 参数——结构化输出本身就是规范形式
git.status {}
// → Stream StatusEntry  ← 始终结构化
//   CLI 运行时选择最佳输出格式（porcelain/json/long）用于解析

// remote add 子命令
git.remote.add { } "origin" "https://github.com/user/repo.git"
// → git remote add origin https://github.com/user/repo.git
//   无 --fetch 映射——fetch 属于 behavior 分类，只在必要时声明

// log 子命令——只映射影响结果集的参数
git.log { maxCount = 50, branch = "main" }
// → git log -n 50 main
//   无 --oneline/--graph/--format/--decorate——显示格式不映射
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
pod <-! kubectl.get.pods { output = "json" }   // output json-doc → JsonValue
nodeCount = pod["items"] |> length
```

`CmdResult` 已移除。退出码在内部处理，调用方只看到有意义的业务结果。

调用方示例：

```kun
// grep 找到匹配 → Ok (Stream ["line1", "line2"])
lines <-! grep {} ["pattern", "/etc/passwd"]
lines |> iter print

// grep 无匹配 → Ok Stream.empty（不是错误）
lines <-! grep {} ["nonexistent", "/etc/passwd"]
lines |> iter print    // 输出空

// grep 文件不存在 → Err (IOError.NotFound "/nonexistent")
Err e <-! grep {} ["pattern", "/nonexistent"]
// e = NotFound "/nonexistent"

// 命令不存在 → Err (IOError.Other "command not found")
```

### 代码生成规则

| CDF 声明 | 生成产物 |
|---------|---------|
| `command <name>` | 函数 `<name>`，Record `<Name>Options` |
| `subcommand <name>` | 内部函数 `<main>_<name>`，调用语法 `<main>.<name>`（多层嵌套 `<main>.<sub1>.<sub2>`） |
| `param x : T with (essential, ...)` | 字段 `x : T`（必填） |
| `param x : ?T with (filter, ...)` | 字段 `x : ?T`（可选筛选条件） |
| `param x : ?T with (behavior, ...)` | 字段 `x : ?T`（可选行为参数） |
| `param x : Bool with (filter/behavior, ...)` | 字段 `x : Bool` |
| `param x : List T with (cli: {"-x", <value>})` | 字段 `x : List T`，argv 构造 `-x v1 -x v2 -x v3` |
| `param x : Map K V with (cli: {"-x", <k>=<v>})` | 字段 `x : Map K V`，argv 构造 `-x k1=v1 -x k2=v2` |
| `param x : T with (cli: positional N)` | 字段 `x : T`（Options Record 中的必填字段） |
| `param x : List T with (cli: positional *)` | 字段 `x : List T`（Options Record 中的字段，收集所有剩余参数） |
| `cli: case ... of` | 编译期生成值到 argv 的映射表 |
| 无 `cli:` 的参数 | 运行时 auto-infer 发现合适的 CLI flag |
| `validator <name> = <expr>` | 常量 `name : Validator T`，编译期展开 |
| `parser <name> : Stream (Result T S) = M.f` | 注入 `M.f` 到命令函数实现 |
| `output <name>` | 行流模式。Parser 入参 `Stream String`，返回 `Result (Stream T) IOError` |
| `output default` / `output json` | 行流模式。`T` = `String` / `JsonValue` |
| `output text-doc` | 文档模式。收集全部 stdout 为 String，返回 `Result String IOError` |
| `output json-doc` | 文档模式。整个输出解析为 JsonValue，返回 `Result JsonValue IOError` |
| `output <name>-doc` | 文档模式。parser 签名 `String -> Result T String`，返回 `Result T IOError` |
| `output` 内置标识符 | `default`、`json`、`text-doc`、`json-doc` 为保留标识符，自定义 `parser` 不可同名 |
| `runAs` | 自动注入到 Options Record 作为`runAs : ?RunAs` |
| `param` 名使用关键字 | Record 字段名直接使用关键字，不受限制 |
| `exitcode N = Ok` | 退出码 N → `Ok (Stream T)` |
| `exitcode N = Ok empty` | 退出码 N → `Ok Stream.empty` |
| `exitcode N = Err <expr>` | 退出码 N → `Err <expr>` |
| `exitcode * = ...` | 通配规则，无对应声明时由缺省行为处理 |

### 隐式字段注入

代码生成器自动在所有 Options Record 中注入以下字段。CDF 中声明同名 `param` 均编译期报错：

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
| `stdin` | `?OrPath` | 子进程标准输入来源（文件路径或现有 fd） |
| `stdout` | `?OrPath` | 子进程标准输出目标 |
| `stderr` | `?OrStdioMode` | 子进程标准错误目标，支持 `Pipe`/`Inherit` 模式 |
| `fd` | `Map Int FdSpec` | 额外文件描述符重定向，键为 fd 编号，值为 `FdSpec` 类型 |

其中 `Fd`、`OrPath`、`OrStdioMode` 类型定义：

```kun
type Fd = Fd Int                         // 文件描述符编号

type OrPath
  = FdSource Fd                          // 使用现有 fd
  | PathSource Path                       // 从路径打开

type OrStdioMode
  = OrPathMode OrPath                    // 文件路径或现有 fd
  | Pipe                                  // 通过管道捕获
  | Inherit                               // 继承父进程 fd
```

调用示例：

```kun
// 带环境变量注入和输出重定向的命令
git.log { env = Map.fromList [("GIT_DIR", "/repo/.git")]
        , stdout = Path p"/tmp/git.log"
        , maxCount = 50 }
// → GIT_DIR=/repo/.git git log -n 50 > /tmp/git.log

// 管道模式
git.log { stderr = StdioMode.Pipe, maxCount = 10 }
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

### 覆盖范围（能力导向）

命令的实现方式选择基于能力复杂度和集成价值：

| 类别 | 命令 | 实现方式 | 映射参数 | 不映射参数 | 理由 |
|------|------|---------|---------|-----------|------|
| 文件信息 | `ls` | **内建 Primitive** | `path`、`all`、`recursive`、`sortBy` | `--color`、`-l`、`-h`、`--format` | 直接 `getdents()`/`statx()` 内核 API |
| 文件信息 | `stat` | **内建 Primitive** | `path` | 所有格式参数 | 直接 `statx()` 系统调用 |
| 文件信息 | `du` | **内建 Primitive** | `path`、`maxDepth`、`apparentSize` | `-h`、`--si`、`-c` | 直接 `fts_open()` 遍历 |
| 文件信息 | `df` | **内建 Primitive** | `path`、`type` | `-h`、`-T`、`--sync` | 直接 `statvfs()` 系统调用 |
| 文件操作 | `cp`/`mv`/`rm`/`mkdir` | **内建 Primitive** | 核心参数 + 行为参数 | `-v`、`-i`、`--backup` | `sendfile()`/`rename()`/`unlinkat()`/`mkdirat()` |
| 权限操作 | `chmod`/`chown`/`ln`/`readlink`/`realpath` | **内建 Primitive** | 核心参数 + 行为参数 | 显示和回显类参数 | `fchmodat()`/`fchownat()`/`linkat()`/`readlinkat()` |
| 系统信息 | `ps` | **内建 Primitive** | `all`、`user`、`pid` | `-o`、`-f`、`--sort`、`--forest` | 读取 `/proc` 直接结构化 |
| 系统信息 | `free`/`uname`/`uptime`/`lscpu` | **内建 Primitive** | 无参数 | 所有格式参数 | `sysinfo()`/`uname()` 直接系统调用 |
| 内容搜索 | `grep` | **内建 Primitive** | `pattern`、`path`、`recursive`、`caseInsensitive`、`invert`、`maxCount` | `--color`、`-n`、`-l`、`-H` | 复用内建正则引擎，避免子进程 pipe |
| 数据库检索 | `locate` | **内建 Primitive** | `pattern` | `-i`、`-c`、`-l`、`-q`、`--regex` | 直接读取 mlocate.db 二进制格式 |
| 目录遍历 | `walkDir` | **内建 Primitive** | `root`、`depth`、`followSymlinks` | — | `fts_open()` 树遍历，过滤在外部用 `filter` |
| 目录遍历 | `find` | **不映射** | — | — | `walkDir` + `filter` 覆盖 |
| 归档压缩 | `tar` | **CDF 映射** | `mode`、`archive`、`files`、`compress`、`strip` | `-v`、`--checkpoint`、`--exclude-vcs` | 归档格式复杂度高 |
| 压缩 | `gzip`/`xz`/`zstd` | **CDF 映射** | `mode`、`target`、`level` | `-v`、`-k`、`-f`、`-c` | 无内核支持，需外部库 |
| 归档包 | `zip`/`unzip` | **CDF 映射** | `mode`、`archive`、`files`、`password` | `-q`、`-v`、`-T`、`-X` | 无内核支持，需外部库 |
| 网络连接信息 | `ss` | **CDF 映射** | `tcp`、`udp`、`listening`、`process` | `-a`、`-l`、`-p`、`-e`、`-i` | netlink 协议复杂 |
| 网络交互 | `curl`/`wget` | **CDF 映射** | 优先标准库 `Http` 模块 | 大量格式/输出参数 | HTTP/TLS 栈复杂度极高 |
| DNS | `dig` | **CDF 映射** | `domain`、`type`、`server` | `+short`、`+stats`、`-4`、`-6` | DNS 协议实现复杂 |
| 网络连通性 | `ping` | **CDF 映射** | `host`、`count`、`interval`、`timeout` | `-4`、`-6`、`-D`、`-n`、`-q` | ICMP 协议实现复杂 |
| 远程同步 | `rsync`/`scp` | **CDF 映射** | `source`、`destination`、`recursive`、`compress` | `-v`、`-P`、`--progress`、`-h` | 复杂协议，无法内建 |
| 版本控制 | `git` | **CDF 映射** | 子命令各自核心 + 筛选参数 | `--oneline`、`--graph`、`--format` | 复杂的子命令树，高频命令独立映射 |
| 容器 | `docker` | **CDF 映射** | 子命令各自核心 + 行为参数 | `--format`、`--no-trunc`、`-q` | REST API，高复杂度 |
| 容器编排 | `kubectl` | **CDF 映射** | `resource`、`name`、`namespace`、`label` | `-o`、`-w`、`--sort-by`、`--show-labels` | REST API，高复杂度 |

**不映射**（由 Kun 标准库和语言特性覆盖）：`sed`、`awk`、`sort`、`uniq`、`cut`、`tr`、`head`、`tail`、`cat`、`wc`、`tee`、`echo`、`printf`、`xargs`、`which`、`cd`、`sudo`、`su`

> 完整的能力映射分析见[能力映射指南](capability-mapping-guide.md)。

### `walkDir` 的设计

`walkDir` 负责目录树遍历，过滤在外部通过 `filter` 完成——职责清晰，避免内建谓词语法：

```kun
// 系统 find: find /var/log -name "*.log" -type f -size +100M
// Kun walkDir + filter:
walkDir { root = p"/var/log" }
  |> filter (\e -> toString e.path |> endsWith ".log")
  |> filter (\e -> e.type == Regular)
  |> filter (\e -> e.size > 100 * MB)
```

```kun
// walkDir 的签名
type DirEntry = { path : Path, type : FileType, size : Int, mtime : DateTime }

walkDir : { root : Path, depth : ?Int
          , followSymlinks : Bool
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

## 签名自动推断（能力导向）

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
      └── 默认签名（仅 output default）
```

### 能力推断（核心变更）

Auto-inference 的目标**不是捕获所有 CLI flags**，而是识别出高价值的**能力参数**：

```
man 页面 / --help
  │
  ▼
提取 OPTIONS / ARGUMENTS 段落
  │
  ├── 能力筛选：
  │   ├── 结果影响参数 → 保留（-a, -n, -r 等）
  │   ├── 显示格式参数 → 丢弃（--color, -h, --format 等）
  │   └── 内部行为参数 → 丢弃（--verbose, --dry-run 等）
  │
  ├── 参数分类：
  │   ├── essential：路径、目标、模式等核心定位参数
  │   ├── filter：-a, -n, -r 等筛选参数
  │   └── behavior：--recursive, --force 等行为参数
  │
  ├── 类型推断：
  │   ├── 枚举值 → 生成和类型（如 sort=name|size|time）
  │   └── 数值 → Int/Nat/Float
  │
  └── 语义提升：
      ├── 多个相关 flag → 合并为枚举（如 -H/-a/-N → all: Bool）
      └── flag 组合 → 单一能力参数（如 -r -i -l → search: SearchMode）
  │
  ▼
生成 CDF 片段（仅能力参数，无格式化参数）→ 签名
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
每个子命令独立进行能力推断
```

### 人类审核辅助

Auto-inference 生成的 CDF 草稿标注置信度和建议分类：

```
// 运行时输出的 CDF 草稿（能力导向）
// 请人工审核后保存到 ~/.kun/cdf/<command>.cdf

command "<command>"
  // 自动推断的能力参数（按分类排列）
  // [essential]
  param <name> : Path with (essential)         // 置信度: 高
  // [filter]
  param <name> : Bool with (filter)             // 置信度: 高
  // [behavior]
  param <name> : Int with (behavior)            // 置信度: 中（类型不确定）
  // [未分类 — 建议人工检查]
  // --verbose, --color, --format 等已自动排除
```

### 自动 CDF 生成

`run""` 调用时自动触发 auto-infer：

```bash
kun run script.kun
# script.kun 中有 run"kubectl" ["get", "pods"]
# → T1/T2 未命中
# → 自动触发 --help/man 解析
# → 能力筛选 + 参数分类
# → 生成 CDF 草稿（仅能力参数）并缓存到 ~/.kun/cdf/kubectl.cdf
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
  │   └── T4 均未命中 → 仅当 process.run 白名单允许时执行
  │       │
  │       ├── 1. 强制审计日志记录
  │       ├── 2. 配置沙箱（PID/mount/network namespace）
  │       │   └── 网络 namespace 根据 net.* 能力放行
  │       ├── 3. 应用通用 seccomp 白名单
  │       ├── 4. fork-exec 加载子进程
  │       └── 5. 返回 Stream String
  │
  └── process.run 白名单为空 → 命令不可执行 → PermissionError
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

分片对用户基本透明，`Stream` 元素顺序与不分裂时一致。

**部分失败语义**：某分片执行失败（退出码非零或信号终止）时：
1. 后续分片**不再执行**（类似 Shell `set -e` 行为）
2. 已成功分片的 stdout 视为有效，通过 Stream 正常传递
3. `Err` 包含失败分片信息和已处理分片计数：`Err (IOError.Other "shard N/M failed: exit code X")`

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
| 0.3.0 | 2026-06-04 | **能力导向重构**：CDF 格式从 CLI 选项声明（`option x "-x" : T`）重构为能力参数声明（`param x : T with (cli: "-x")`），CLI 映射下移为可选实现细节；新增参数分类系统（essential/filter/behavior）；auto-inference 只推断能力参数；`process.run` 白名单默认拒绝；新增[能力映射指南](capability-mapping-guide.md) |
| 0.2.0 | 2026-06-04 | 分级可用性模型（T1-T4）、内联验证器、`.` 分隔子命令调用、CDF 注册中心、自动生成工具 |
| 0.1.0 | 2026-05-31 | CDF 文件格式、参数定义、输出类型、行为声明、签名自动推断、内置签名库、运行时集成 |
