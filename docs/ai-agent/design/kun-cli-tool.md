# `kun` CLI 工具

## 定位

`kun` 是一个集解释、编译、执行、格式化、lint 于一体的命令行工具。本文件定义其命令结构、安全控制参数及脚本入口约定。`kun` 自身 CLI 参数（全局选项、子命令）的解析与 `Cli` 模块共享同一 spec 模型与解析引擎（位于 `libkunlang.so`），见 [`Cli` 模块](cli.md#与-CLI-二进制的关系)。脚本内参数解析由标准库 [`Cli` 模块](cli.md) 提供。安全策略的运行时实现见[系统基线](../architecture/system-baseline.md#安全隔离)。

## 命令结构

```
kun [全局选项] <子命令> [子命令参数] <脚本.kun> [脚本参数...]
```

### 子命令

| 子命令 | 用途 | 示例 |
|--------|------|------|
| *(默认)* | 解释执行 `.kun` 脚本 | `kun script.kun` |
| `run` | 解释执行 `.kun` 脚本（与默认形式等价的显式别名，便于与 `test`/`fmt` 等子命令对仗） | `kun run script.kun` ≡ `kun script.kun` |
| `fmt` | 格式化 `.kun` 文件 | `kun fmt script.kun` |
| `lint` | lint 检查 `.kun` 文件 | `kun lint script.kun` |
| `check` | 仅类型检查，不执行 | `kun check script.kun` |
| `doc` | 为模块及函数生成 Markdown 文档 | `kun doc lib/` |
| `cmd init` | 从 man/--help 生成类型化命令模块骨架 | `kun cmd init ls` |
| `test` | `<module>_test.kun` 测试文件、`TestCase` 类型值、`--filter`/`--timeout`/`--parallel`/`--fail-fast`/`--report` |

> **执行形式统一**：脚本执行统一为 `kun script.kun`（默认形式，无子命令）或 `kun run script.kun`（显式 `run` 子命令，等价别名）。不再支持 `kun --run script.kun`（旧形式，已废弃）。`--allow-ffi`/`--allow-path`/`--allow-net` 等安全参数在两种形式下均可使用：`kun --allow-ffi script.kun` 或 `kun run --allow-ffi script.kun`。

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

### 生成文档

```bash
kun doc lib/                      # 为 lib/ 目录下所有模块生成文档
kun doc lib/File.kun              # 为单个模块文件生成文档
kun doc --output docs/api/ lib/   # 指定输出目录
```

`kun doc` 解析模块中的文档注释（`//` 注释，紧邻 `type`/函数定义/`export` 声明上方），为每个模块生成 Markdown 文档，包含：

- 模块名称与描述
- 导出符号列表
- 每个导出函数的类型签名与文档注释
- 类型定义与变体描述
- 使用示例（提取自文档注释中的 `` ```kun `` 代码块）
- 交叉引用（其他模块的类型/函数自动链接）

生成的文档可直接用于 VitePress 等静态站点生成器。

### 函数调用追踪

通过 `--trace` 选项在执行脚本时打印函数调用信息，缺省关闭：

```bash
kun --trace script.kun            # 打印所有函数调用
kun --trace=caller script.kun     # 仅打印直接调用位置
kun --trace=full script.kun       # 打印完整调用栈
```

`--trace` 输出格式：

```
[Trace] File.read(p"/etc/hostname") at main.kun:3:15
[Trace]   String.trim("hostname\n") at main.kun:4:10
[Trace]   IO.println("hostname") at main.kun:5:5
```

追踪信息包含：（1）被调函数名与参数摘要、（2）调用所在的文件名:行号:列号、（3）调用深度（缩进表示）。效果函数（`IO.*`/`File.*` 等）的追踪包含实际参数值，纯函数仅记录调用位置和参数类型。

`--trace` 不改变脚本行为（无副作用），仅追加 stderr 输出。

## 脚本入口

`.kun` 脚本通过 `main` 函数作为执行入口。`main` 函数与 `TestCase` 值的 `body` 字段是入口级上下文，允许使用 `do...with` / `let...in...with` 消解效应（业务函数不可使用，详见 [类型系统 - 内置效应](type-system.md#内置效应)）。

```kun
main : List String -> Unit ! {IO, File, Cmd, ...}
main = \args -> do
  case args of
    []           -> IO.println "no arguments"
    [name]       -> IO.println f"hello, {name}"
    [cmd, ..rest] -> IO.println f"{cmd} with {List.length rest} args"
```

### 入口规则

| 条件 | 行为 |
|------|------|
| 定义 `main : List String -> Unit ! {<effects>}` | 从 `main` 启动，传入命令行参数 |
| 定义 `main` (无类型标注) | 编译器自动按 `List String -> Unit ! e` 类型检查 |
| 未定义 `main` | 编译错误：可执行脚本缺少 `main` 入口 |
| `main` 签名不合法 | 类型标注不为 `List String -> Unit ! e` 时编译错误 |

### `main` 与 `TestCase.body` 的 `do ... with` / `let ... in ... with` 限制

`do...with` / `let...in...with` 表达式**仅在 `main` 函数与 `TestCase` 值的 `body` 字段内可用**——业务函数只声明效应不消解，效应冒泡到入口级上下文集中消解。

- **`main`**：程序入口，允许消解用户效应（内置效应自动注入默认 handler）
- **`TestCase.body`**：`TestCase` 不透明类型值（`opaque type TestCase`，由 `test` Primitive 构造，详见 [单元测试设计](testing.md)）的 `body` 字段，由 `kun test` 运行器在入口级上下文执行，允许使用 `do...with` / `let...in...with`；用户效应通常通过 `Test.with` 模块函数声明式消解（设置 `TestCase.with` 字段，详见 [单元测试设计](testing.md)）
- **其他业务函数**：禁止使用 `do...with` / `let...in...with`，只声明效应

### `main` 边界与效应集校验

**`main` 允许的效应**：
- 所有内置效应（`IO`/`File`/`Cmd`/`Random`/`DateTime`/`Signal`/`FFI`）
- 不允许用户效应（`DB`/`Log`/`Libc` 等），必须 `do...with` / `let...in...with` 消解

**未消解效应的处理**：
- 内置效应：运行时自动注入默认 Zig handler
- 用户效应（含 `extern` 库效应）：编译错误，必须显式消解（`do...with` / `let...in...with`）
- `FFI` 效应到达 `main`：运行时检查 `--allow-ffi`（见下方）

```kun
main : List String -> Unit ! {Cmd, IO}
main = \args -> do
  result = fetchUser (UserId "1")
with
  postgreHandler >> journaldLog
  // 用户效应 DB/Log 被消解
  // 剩余 {Cmd, IO} 冒泡到 main，运行时自动注入默认 handler
```

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
- `main` 的签名**唯一合法形式为 `List String -> Unit ! e`**（`e` 可为内置效应集或空集）
- 不需要命令行参数时用 `\_ ->` 忽略参数
- 支持 Shebang：`#!/usr/bin/env kun`

> **Shebang 限制**：Linux 内核仅将 shebang 行的第一个参数传递给解释器。因此 `#!/usr/bin/env kun --allow-path /tmp` 中 `--allow-path /tmp` 会被内核截断。安全参数必须通过命令行传递（`kun --allow-path /tmp script.kun`），或使用 `#!/usr/bin/kun` 并将参数写入脚本内的 `# kun-args: --allow-path /tmp` 前置指令。

```kun
// ✅ 正确：可执行脚本
main : List String -> Unit ! {IO}
main = \_ -> do
  IO.println "hello"

// ❌ 错误：可执行脚本不能有 export
export (helper)    // 编译错误
main : List String -> Unit ! {IO}
main = \_ -> do
  IO.println "hello"

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

main : List String -> Unit ! {IO}
main = \raw -> do
  case parseConfig raw of
    Ok cfg  -> IO.println f"config: {cfg.verbose} {cfg.output}"
    Err err -> IO.println (Cli.show err)
```

## 安全控制

安全策略通过 CLI 参数声明，与脚本代码分离。默认策略：仅当前工作目录可读写，无网络访问。

### 安全参数

| 参数 | 说明 |
|------|------|
| `--allow-path <path>[:mode]` | 允许脚本访问指定路径。`mode` 可选：`:r`（仅读）、`:w`（仅写）、`:rw`（读写，默认）。可多次指定以允许多个路径 |
| `--allow-net` | 开放网络出站 |
| `--allow-ffi` | 允许脚本使用 FFI（`extern` 块或直接 `FFI.call`）。未启用时，`FFI` 效应到达 `main` 将拒绝执行 |
| `--no-sandbox` | 完全关闭沙箱隔离 |
| `--force` | 跳过安全确认——当脚本的路径/网络使用声明与实际情况不一致时，不提示用户而直接运行。仅用于受信任脚本的自动化运行 |
| `--env=<strategy>` | 环境变量继承策略（见下方） |
| `--cpu-limit <duration>` | CPU 时间限制（CPU 秒，非 wall-clock 时间，对应 `RLIMIT_CPU`），覆盖主进程及全部子进程（默认 60s） |
| `--mem-limit <size>` | 内存限制（虚拟地址空间限制，非 RSS，对应 `RLIMIT_AS`），覆盖主进程及全部子进程（默认 512MB） |
| `--audit=<path>` | 输出 JSON 审计记录到指定文件（可选，用于 CI/合规场景追溯）。记录含脚本路径、安全参数、沙箱配置、退出码、脚本内容哈希、时间戳 |

#### `--audit` 审计记录

启用 `--audit=<path>` 时，脚本执行完成后（无论成功或失败）输出结构化 JSON 审计记录：

```json
{
  "schema": "kun.audit/v1",
  "timestamp": "2026-07-16T10:30:00.123Z",
  "script": "deploy.kun",
  "args": ["--prod"],
  "exit_code": 0,
  "duration_ms": 1250,
  "security": {
    "sandbox": true,
    "allow_path": ["/tmp:rw", "/var/log:rw"],
    "allow_net": false,
    "allow_ffi": false,
    "cpu_limit": "60s",
    "mem_limit": "512MB"
  },
  "sandbox_layers": {
    "no_new_privs": true,
    "dumpable": false,
    "capabilities_dropped": true,
    "landlock": false,
    "namespaces": ["mount", "net", "ipc"],
    "seccomp": true,
    "fd_scrub": true
  },
  "content_fingerprint": "sha256:e3b0c44298fc1c149afbf4c8996fb924..."
}
```

字段说明：
- `content_fingerprint`：脚本文件的 SHA-256 哈希，用于检测脚本是否被篡改
- `sandbox_layers`：实际安装的沙箱层（反映内核能力与配置，如 Landlock 在内核 < 5.13 时为 `false`，此时启用 ns 兑底模式包含 `mount`/`net`/`ipc` 三个 namespace）
- `exit_code`：脚本退出码（0 成功，1 失败，126 安全拒绝，详见退出码章节）

审计记录在脚本退出后写入，写入失败时通过 stderr 告警（`audit write failed: <path>`），退出码不变。沙箱模式下审计路径自动加入 `--allow-path` 白名单。`--no-sandbox` 模式下 `sandbox` 为 `false`，`sandbox_layers` 仍记录实际状态。

#### `--allow-ffi` 与 FFI 安全检查

`FFI` 是内置保留效应，其身份不可伪造。`FFI` 效应到达 `main` 时，运行时检查 `--allow-ffi`：

- **未启用 `--allow-ffi` 且 `FFI` 效应到达 `main`**：拒绝执行，返回退出码 126（安全拒绝）
- **启用 `--allow-ffi`**：运行时默认 Zig handler 消解 FFI（`dlopen` + `dlsym` + C ABI 调用）

`FFI` 安全检查是四层防护中的最后一层（详见 [标准库 FFI 模块](standard-library.md#ffi-外部-c-库调用)）：

1. **保留名检查**：`FFI` 为编译器保留名，用户不可定义同名 `effect`
2. **`extern` 调用强制产生内置 FFI**：`extern` 块的默认 handler 调用 `FFI.call`，编译器硬编码为内置 FFI 效应
3. **命名空间隔离**：内置效应在编译器内部命名空间，不查用户定义
4. **运行时 `--allow-ffi` 检查**：检查最终冒泡到 `main` 的 FFI 效应，未启用则拒绝执行

用户无法通过命名、定义、handler 等手段绕过 FFI 安全检查。`FFI` 效应身份与边界得到完整保护。

### 退出码

`kun` 二进制本身的退出码：

| 退出码 | 含义 |
|--------|------|
| 0 | 脚本执行成功（main 正常返回） |
| 1 | 脚本执行失败（panic、类型错误、运行时错误） |
| 2 | 用法错误（无效 CLI 参数、文件未找到） |
| 126 | 安全拒绝——脚本请求的操作被安全沙箱阻止（含未启用 `--allow-ffi` 但 FFI 效应到达 `main`） |

panic 退出码传播规则见 [应用概览 - panic 退出码规则](app-overview.md#panic-退出码规则)。

### 使用示例

```bash
# 默认安全策略：仅 CWD 可读写，无网络
kun script.kun

# 额外允许 /tmp 路径
kun --allow-path /tmp script.kun

# 开放网络
kun --allow-net script.kun

# 允许 FFI（脚本使用 extern 块或 FFI.call）
kun --allow-ffi script.kun

# 完全关闭沙箱
kun --no-sandbox script.kun

# 强制运行
kun --force script.kun

# 继承全部环境变量
kun --env=inherit script.kun

# 资源限制（覆盖主进程及全部子进程）
kun --cpu-limit 120s --mem-limit 1G script.kun

# 组合参数
kun --cpu-limit 30s --allow-ffi script.kun
```

### 环境变量策略

| 策略 | 行为 |
|------|------|
| `--env=clean`（默认） | 仅传递干净白名单：`PATH`、`HOME`、`USER`、`TERM`、`LANG`、`PWD`、`SHELL`、`TZ`、`DISPLAY`、`XDG_RUNTIME_DIR`、`LC_ALL`、`LC_CTYPE`、`TMPDIR` |
| `--env=inherit` | 继承全部环境变量（始终剔除列表例外） |

始终剔除列表（无论策略如何永不传递）：`LD_PRELOAD`、`LD_AUDIT`、`LD_DEBUG`、`LD_LIBRARY_PATH`、`LD_PROFILE`、`LD_ORIGIN_PATH`、`GCONV_PATH`、`GLIBC_TUNABLES`。额外始终剔除的模式匹配规则：`BASH_FUNC_*`（bash Shellshock-class 函数注入）、`PYTHONPATH`、`PERL5LIB`、`PERLLIB`、`RUBYLIB`、`RUBYOPT`、`GIO_EXTRA_MODULES`、`GTK_MODULES`。 |

### 沙箱层级

运行时采用两层安全机制叠加：

1. **父进程层**（初始化阶段一次性安装）：Mount namespace `/proc`/`/sys`/`/dev` 加固（内核 3.8+，始终执行）→ Landlock（首选：5.13+ 文件控制；6.7+ 文件 + 网络控制）→ mount namespace 目录级隔离（兜底，内核 3.8+，Landlock 不可用时）→ 拒绝运行（内核 < 3.8）
2. **子进程层**（每次 fork 后始终安装）：seccomp-BPF 系统调用过滤 + rlimit 资源限制

详细实现见[系统基线](../architecture/system-baseline.md#安全隔离)。

### 资源限制

rlimit 在进程启动时一次性设置，覆盖主进程（解释器自身）及所有 `fork` 的子进程——每一字节内存和 CPU 秒数来自同一预算。任一超出限制触发 panic（`SIGXCPU` 或超出 `RLIMIT_AS` 时内核拒绝分配）。

| 限制 | 默认值 | CLI 覆盖 |
|---|---|---|
| `RLIMIT_CPU` | 60s | `--cpu-limit` |
| `RLIMIT_AS` | 512MB | `--mem-limit` |
| `RLIMIT_NOFILE` | 256 | — |
| `RLIMIT_NPROC` | 32 | — |

> 默认值适用于常规脚本场景。超出限制触发 panic（`SIGXCPU` 或内核拒绝内存分配）。如需更宽松限制，通过 `--cpu-limit`/`--mem-limit` 调整。

## Kun Shell

Kun Shell 是 Kun 的交互式环境，以独立可执行文件 `kun-shell` 提供。`kun-shell` 与 `kun` 通过动态链接库 `libkunlang.so` 共享解释器核心代码。完整设计见 [Kun Shell](kun-shell.md)。

> **未来版本**。当前仅提供 `kun` 脚本执行器和 `libkunlang.so` 共享库。

## 与相关文档的关系

| 文档 | 内容 |
|------|------|
| [`Cli` 模块](cli.md) | 脚本内 `List String` → 结构化 Config 的类型驱动解析器；`kun` 自身 CLI 参数解析与之共享 spec 模型与引擎 |
| [系统基线](../architecture/system-baseline.md#安全隔离) | Landlock/mount ns/seccomp/rlimit 运行时实现细节 |
| [`Kun Shell`](kun-shell.md) | 交互式环境：SQLite/DuckDB 日志存储、函数收藏、AST 哈希唯一引用 |
| [语法设计](syntax.md) | `main` 入口、`export`/`import` 语法 |
| [功能清单](feature-inventory.md) | 各功能实现状态追踪 |

