# `Cli` — 命令行参数解析

## 设计定位

对标 Python `argparse`，以类型驱动的方式将 `main` 接收的 `List String` 解析为类型安全的 Record。`Cli` 是纯标准库模块，不依赖编译器内置支持——其类型安全由 HM 推断 + 编译期代码展开实现，与 `Parser.Record.fromJson` 机制一致。

需显式导入：

```kun
import Cli
```

### 设计原则

- **默认严格**：未知选项报错并给出最接近的合法匹配（Did-you-mean）
- **类型即 schema**：Record 字段类型决定消费行为——`Bool` → flag，`?T` → 可选 option，`List T` → 余量位置参数
- **声明即文档**：声明器携带的字符串既是解析规则，也是帮助文本——`--help` 始终自动生成
- **管道修饰**：`withDefault`、`withChoices` 等修饰器是 `CliArg -> CliArg` 纯函数，通过 `|>` 链式应用

### 类型结构

```kun
// 解析上下文元数据
type CliMeta =
  { intro : ?String    // 程序名称/简介（显示在 --help 第一行）
  , text  : ?String    // 详细描述（简介下方显示）
  }

// 声明器种类
type CliArgKind
  = Flag
  | Option
  | Count
  | Positional

// 单个参数声明
// default 和 choices 存储为序列化字符串，运行期不做类型检查
// 类型安全的门槛在 Cli.parse 调用点的编译期代码展开
type CliArg =
  { name    : String          // 长选项名（也是 Record 字段名）
  , short   : ?Char           // 短选项字符
  , help    : String          // 帮助文本
  , kind    : CliArgKind      // 声明器种类
  , default : ?String         // 缺省值的字符串表示
  , choices : ?(List String)  // 枚举约束的字符串列表
  }

// 互斥组
type CliArgGroup
  = OneOf { name : String, args : List CliArg }

// 子命令（递归引用 CliSpec，a 约束父级类型，b 约束 handler 返回类型）
type CliSubCmd a b =
  { name    : String
  , help    : String
  , handler : ?(CliSpec b)      // 子命令的处理 spec
  }

// 顶层解析描述，a 为目标 Record 类型
type CliSpec a =
  { meta     : CliMeta
  , args     : ?(List CliArg)          // 位置参数和选项（可选）
  , groups   : ?(List CliArgGroup)    // 互斥组（可选）
  , levels   : ?(List (CliSubCmd a b))  // 子命令（可选），b 与 a 独立
  , loose    : ?Bool                    // 透传模式（可选，默认 false）
  }
```

### API

#### 构造器

```kun
// 零值元数据
meta : CliMeta        // 等价于 { intro = Nil, text = Nil }

// 设置 intro
intro : String -> CliMeta -> CliMeta

// 设置 text
text : String -> CliMeta -> CliMeta
```

#### 声明器

```kun
// 布尔开关（--name / -c），不出现 → false
flag : String -> Char -> String -> CliArg

// 带值选项（--name VAL / -c VAL）
//   字 段为 ?T  → 不出现 → Nil
//   字段为 T   → 无缺省 → 必填；有 withDefault → 可选
option : String -> Char -> String -> CliArg

// 计数型标志（-c → 1，-ccc → 3），不出现 → 0
count : String -> Char -> String -> CliArg

// 位置参数（按声明顺序消费 token）
//   字段为 T        → 必填（1 个 token）
//   字段为 ?T       → 可选（0 或 1 个 token）
//   字段为 List T   → 余量（0-N 个 token，仅可为末位）
arg : String -> String -> CliArg
```

#### 修饰器（管道应用，CliArg → CliArg）

```kun
// 设置缺省值
withDefault : a -> CliArg -> CliArg

// 设置枚举约束
withChoices : List a -> CliArg -> CliArg
```

#### 子命令

```kun
// 互斥组声明
oneOf : String -> List CliArg -> CliArgGroup

// 子命令声明
subCmd : String -> String -> CliSpec b -> CliSubCmd a b

// 解析原始参数列表为目标 Record
// 类型 a 由调用点的变量类型声明驱动
parse : CliSpec a -> List String -> Result a String
```

### 声明器与字段类型对应

| 声明器 | 目标字段类型 | 行为 |
|--------|------------|------|
| `flag "n" 'c' "h"` | `Bool` | `--n`/`-c` → true，不出现 → false |
| `count "n" 'c' "h"` | `Int` | `-c` → 1，`-ccc` → 3，不出现 → 0 |
| `option "n" 'c' "h"` | `?T` | `--n VAL` → Some，不出现 → Nil |
| `option "n" 'c' "h" \|> withDefault d` | `T` | 不出现 → `d` |
| `option "n" 'c' "h"`（无 default） | `T` | 必填，不出现 → 错误 |
| `arg "n" "h"` | `T`（非 Bool/List） | 必填，1 个 token |
| `arg "n" "h"` | `?T` | 可选，0 或 1 个 token |
| `arg "n" "h"` | `List T` | 0-N 个 token（仅可为最后一个位置参数） |

### 编译期类型安全

`Cli.parse` 的泛型类型 `a` 由调用上下文推断。编译期流程：

1. `parseConfig : Result MyConfig String` — HM 推断 `a = MyConfig`
2. 编译器展开 `MyConfig` 的字段类型
3. 逐一比对 `CliArg` 列表与字段：缺字段 → 编译错误，多余声明 → 编译错误
4. 为每个 `CliArg` 按对应字段类型生成特化的字符串→类型转换代码

`CliArg` 本身不带类型参数（`default` 和 `choices` 存储为 `String`），以避免不同字段类型的 `CliArg` 无法放入同一 `List`。实际类型检查全部在 `Cli.parse` 调用点的编译期展开阶段完成。

---

## 示例

### 1. 基本用法

`kun build.kun -v -o dist/ --jobs 8 app`

```kun
import Cli
import IO

type BuildConfig =
  { verbose : Bool          // -v, --verbose
  , output  : ?Path         // -o, --output
  , jobs    : Int           // -j, --jobs
  , source  : String        // SOURCE（位置参数）
  }

parseConfig : List String -> Result BuildConfig String
parseConfig =
  Cli.parse
    { meta  = Cli.meta
            |> Cli.intro "build.kun"
            |> Cli.text "Compiles and packages."
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
      Err msg ->
        IO.println msg
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

Arguments:
  SOURCE              Source directory
```

### 2. 子命令（多级嵌套）

`kun deploy.kun push --force origin main`

```kun
import Cli

type PushOpts =
  { force  : Bool
  , remote : String
  , branch : String
  }

type StatusOpts =
  { short : Bool }

// 子命令返回的联合类型
type DeployCmd
  = Push PushOpts
  | Status StatusOpts

parsePush =
  { meta  = Cli.intro "push" Cli.meta
  , args =
      [ Cli.flag "force" 'f' "Force push"
      , Cli.arg "remote" "Remote name"
      , Cli.arg "branch" "Branch name"
      ]
  }

parseStatus =
  { meta = Cli.intro "status" Cli.meta
  , args = [ Cli.flag "short" 's' "Short format" ]
  }

parseDeploy =
  Cli.parse
    { meta  = Cli.intro "deploy.kun" Cli.meta
    , levels =
        [ Cli.subCmd "push" "Push to remote" parsePush
        , Cli.subCmd "status" "Show status" parseStatus
        ]
    }
```

多级子命令通过嵌套 `levels` 实现——子命令的 spec 中再含 `levels` 即可。

### 3. 互斥组

```kun
import Cli

type MutexConfig = { global : Bool, local : Bool }

parseConfig =
  Cli.parse
    { meta = Cli.meta
    , groups =
        [ Cli.oneOf "config-source"
            [ Cli.flag "global" 'g' "Use global config"
            , Cli.flag "local" 'l' "Use local config"
            ]
        ]
    }
```

### 4. 枚举约束

```kun
Cli.option "level" 'l' "Log level"
  |> Cli.withChoices ["debug", "info", "warn"]
```

### 5. 透传模式

`kun gcc.kun -o a.out -Wall -O2 main.c`

```kun
import Cli

type CompileConfig =
  { output        : Path
  , compilerArgs  : List String
  }

parseCompile =
  Cli.parse
    { meta  = Cli.meta
    , loose = true
    , args =
        [ Cli.option "output" 'o' "Output file"
        , Cli.arg "compilerArgs" "Compiler arguments"
        ]
    }
```

`output : Path` 无 `?` 无 default → 必填。`--o a.out` 之后所有 `-Wall`、`-O2`、`main.c` 均流入 `compilerArgs`。

### 6. 多个位置参数

```kun
import Cli

type CpConfig =
  { source : String
  , dest   : String
  , target : Path
  }

parseCp =
  Cli.parse
    { meta = Cli.meta
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

按声明顺序消费：`a.txt` → `source`，`b.txt` → `dest`，`/tmp` → `target`。`--` 分隔符遵循 POSIX 惯例：`--` 之后全部 token 视为位置参数。

### 7. 可选位置 + 余量位置

```kun
import Cli

type ToolConfig =
  { name  : ?String
  , files : List String
  }

parseTool =
  Cli.parse
    { meta = Cli.meta
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

位置参数消费策略为非贪婪：先尝试匹配前置的 `?T`（0 或 1 个），剩余全部进入 `List T`。`--` 之后全部 token 视为位置参数。

### 错误信息

```
Error: unrecognized option '--verbse'. Did you mean '--verbose'?

Error: option '--jobs' expects an integer, got 'abc'

Error: required argument 'source' is missing

Try 'build.kun --help' for more information.
```

`--help`/`-h` 始终自动可用，不可禁用。出现解析错误时自动提示 `--help`。
