# `kun` CLI 工具

## 定位

`kun` 是一个集解释、编译、执行、格式化、lint 于一体的命令行工具。本文件定义其命令结构、安全控制参数及脚本入口约定。脚本内参数解析由标准库 [`Cli` 模块](cli.md) 提供，安全策略的运行时实现见[系统基线](../architecture/system-baseline.md#安全隔离)。

## 命令结构

```
kun [安全参数] <子命令> [子命令参数] <脚本.kun> [脚本参数...]
```

### 子命令

| 子命令 | 用途 | 示例 |
|--------|------|------|
| *(默认)* | 解释执行 `.kun` 脚本 | `kun script.kun` |
| `fmt` | 格式化 `.kun` 文件 | `kun fmt script.kun` |
| `lint` | lint 检查 `.kun` 文件 | `kun lint script.kun` |
| `check` | 仅类型检查，不执行 | `kun check script.kun` |
| `repl` | 启动交互式 REPL | `kun repl` |
| `cmd init` | 从 man/--help 生成类型化命令模块骨架 | `kun cmd init ls` |

## 执行模式

### 解释执行（默认）

```bash
kun script.kun                    # 解释执行
kun --allow-path /tmp script.kun  # 带安全参数
kun script.kun foo bar            # 脚本参数 foo bar
```

### 格式化

```bash
kun fmt script.kun                # 格式化单个文件
kun fmt lib/                      # 格式化目录下所有 .kun 文件
kun fmt --check script.kun        # 仅检查格式，不修改
```

### Lint

```bash
kun lint script.kun               # lint 单个文件
kun lint lib/                     # lint 整个目录
```

### 类型检查

```bash
kun check script.kun              # 仅类型检查，不执行副作用
```

## 脚本入口

`.kun` 脚本通过 `main` 函数作为执行入口：

```kun
main : List String -> Unit
main = \args ->
  do
    case args of
      []           -> IO.println "no arguments"
      [name]       -> IO.println f"hello, {name}"
      [cmd, ..rest] -> IO.println f"{cmd} with {List.length rest} args"
```

### 入口规则

| 条件 | 行为 |
|------|------|
| 定义 `main : List String -> Unit` | 从 `main` 启动，传入命令行参数 |
| 定义 `main` (无类型标注) | 编译器自动按 `List String -> Unit` 类型检查 |
| 未定义 `main` | 编译错误：可执行脚本缺少 `main` 入口 |
| `main` 签名不合法 | 类型标注不为 `List String -> Unit` 时编译错误 |

### 命令行参数

- 脚本名（`argv[0]`）不传入 `args` 列表，仅包含用户提供的参数
- 参数类型为 `List String`，每个元素是单个参数字符串
- 无参数时传入空列表 `[]`

```bash
kun script.kun foo bar    # args = ["foo", "bar"]
kun script.kun            # args = []
```

### 可执行脚本约束

- 可执行脚本文件**不能有 `export` 声明**
- 有 `export` 而无 `main` → 库模块；有 `main` 而无 `export` → 可执行脚本
- 同时出现两者为编译错误
- `main` 的签名**唯一合法形式为 `List String -> Unit`**
- 不需要命令行参数时用 `\_ ->` 忽略参数
- 支持 Shebang：`#!/usr/bin/env kun`

```kun
// ✅ 正确：可执行脚本
main : List String -> Unit
main = \_ ->
  do
    IO.println "hello"

// ❌ 错误：可执行脚本不能有 export
export (helper)    // 编译错误
main : List String -> Unit
main = \_ -> do IO.println "hello"

// ❌ 错误：main 签名不合法
main : Unit        // 编译错误
```

### 命名参数（脚本内）

脚本内命名参数（`--output file.txt`、`-v` 等）通过标准库 [`Cli` 模块](cli.md) 将 `List String` 解析为结构化配置：

```kun
import Cli

type Config = { verbose : Bool, output : ?Path, name : ?String }

parseConfig : List String -> Result Config Cli.CliError
parseConfig =
  Cli.parse
    { meta  = { intro = "script.kun" }
    , args =
        [ Cli.flag "verbose" 'v' "Verbose output"
        , Cli.option "output" 'o' "Output file"
        , Cli.option "name" 'n' "Config name"
        ]
    }

main : List String -> Unit
main = \raw ->
  do
    case parseConfig raw of
      Ok cfg  -> IO.println f"config: {cfg.verbose} {cfg.output}"
      Err err -> IO.println (Cli.show err)
```

## 安全控制

安全策略通过 CLI 参数声明，与脚本代码分离。默认策略：仅当前工作目录可读写，无网络访问。

### 安全参数

| 参数 | 说明 |
|------|------|
| `--allow-path <path>` | 额外允许的路径（默认 `:rw`），可多次指定 |
| `--allow-net` | 开放网络出站 |
| `--no-sandbox` | 完全关闭沙箱隔离 |
| `--force` | 强制运行，跳过安全确认 |
| `--env=<strategy>` | 环境变量继承策略（见下方） |
| `--cpu-limit <duration>` | CPU 时间限制（默认 60s） |
| `--mem-limit <size>` | 内存限制（默认 512MB） |

### 使用示例

```bash
# 默认安全策略：仅 CWD 可读写，无网络
kun script.kun

# 额外允许 /tmp 路径
kun --allow-path /tmp script.kun

# 开放网络
kun --allow-net script.kun

# 完全关闭沙箱
kun --no-sandbox script.kun

# 强制运行
kun --force script.kun

# 继承全部环境变量
kun --env=inherit script.kun

# 资源限制
kun --cpu-limit 120s --mem-limit 1G script.kun

# 组合参数
kun --allow-path /tmp --allow-net --cpu-limit 30s script.kun
```

### 环境变量策略

| 策略 | 行为 |
|------|------|
| `--env=clean`（默认） | 仅传递干净白名单：`PATH`、`HOME`、`USER`、`TERM`、`LANG`、`PWD`、`SHELL`、`TZ` |
| `--env=inherit` | 继承全部环境变量（始终剔除列表例外） |

始终剔除列表（无论策略如何永不传递）：`LD_PRELOAD`、`LD_AUDIT`、`LD_DEBUG`、`LD_LIBRARY_PATH`、`LD_PROFILE`、`LD_ORIGIN_PATH`、`GCONV_PATH`、`GLIBC_TUNABLES`。

### 沙箱层级

运行时安全隔离按内核能力逐级降级：

```
优先 Landlock（5.13+：文件控制；6.7+：文件 + 网络控制）
  → mount namespace 兜底（内核 3.8+）
    → seccomp 降级（内核 3.5+）
      → 拒绝运行（内核 < 3.5）
```

详细实现见[系统基线](../architecture/system-baseline.md#安全隔离)。

### 资源限制

子进程 fork 后、exec 前自动设置 rlimit：

| 限制 | 默认值 | CLI 覆盖 |
|---|---|---|
| `RLIMIT_CPU` | 60s | `--cpu-limit` |
| `RLIMIT_AS` | 512MB | `--mem-limit` |
| `RLIMIT_NOFILE` | 256 | — |
| `RLIMIT_NPROC` | 32 | — |

## REPL

启动命令：

```bash
kun repl
```

支持以下交互命令：

| 命令 | 说明 |
|------|------|
| `<expr>` | 求值表达式，打印结果与类型 |
| `:type <expr>` | 显示表达式类型 |
| `:load <file>` | 加载 `.kun` 文件 |
| `:cmds` | 列出可用的类型化命令模块 |
| `:modules` | 列出已加载的模块 |
| `:exit` / `:quit` | 退出 REPL |

REPL 默认运行在 `--no-sandbox` 模式。

## 与相关文档的关系

| 文档 | 内容 |
|------|------|
| [`Cli` 模块](cli.md) | 脚本内 `List String` → 结构化 Config 的类型驱动解析器 |
| [系统基线](../architecture/system-baseline.md#安全隔离) | Landlock/mount ns/seccomp/rlimit 运行时实现细节 |
| [语法设计](syntax.md) | `main` 入口、`export`/`import` 语法 |
| [功能清单](feature-inventory.md) | 各功能实现状态追踪 |

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 2026.06 | 2026-06-12 | 从 `app-overview.md`、`syntax.md`、`system-baseline.md` 中提取 CLI 工具与安全控制为独立文档 |
