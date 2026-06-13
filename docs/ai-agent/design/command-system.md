# OS 命令调用机制

## 定位

Kun 通过 `Cmd.<bin>` 语法调用 Linux 命令。本文件定义命令调用的语法、语义与机制。

> **编译器内置**：`Cmd.<bin>` 语法和 `Cmd.<bin>?` 由编译器直接解析并生成 fork-exec 调用代码，非标准库函数调用。`Command` 类型的延迟执行语义（惰性、`|>` 隐式触发、`do` 块边界触发）也由编译器处理。

具体的运行时实现细节见[系统基线](../architecture/system-baseline.md#命令调用机制)。

## 语法入口

### 基础调用

```kun
Cmd.<bin> [options] [posArgs...]
```

命令名 `<bin>` 直接拼接到 `Cmd.` 之后，可选 Record 选项在前（可省略），位置参数在最后：

```kun
Cmd.ls { long = true, all = true } p"/tmp"
Cmd.git.log { maxCount = 50 } "main"
Cmd.date                                         // 无选项时直接省略 Record
```

选项 Record 可为空 `{}`（显式但冗余）：

```kun
Cmd.date {}
```

### 子命令

多层子命令以 `.` 链接：

```kun
Cmd.docker.container.ls { all = true }
Cmd.git.remote.add {} "origin" "https://..."
```

### 特殊字符命令名

含 `-`、`.`、`+` 或数字开头的命令使用 `Cmd["..."]` 转义：

```kun
Cmd["ntfs-3g"] { force = true } "/dev/sda1"
Cmd["g++"] { o = "a.out" } "main.cpp"
  |> Cmd.withRawOpt "-Wall" Nil
```

### 立即执行：`?` 后缀

`Cmd.<bin>?` 立即执行并返回 `Result (Stream String) CommandError`，而非延迟 `Command` 值：

```kun
do
  result = Cmd.cat? p"/etc/maybe_missing"
  case result of
    Ok stream -> ...
    Err err ->
      case err of
        CommandFailed { exitCode, stderr } -> ...
        NotFound cmd -> ...
```

## camelCase → kebab-case 选项映射

`Cmd.<bin> { field = value }` 中的 Record 字段名自动映射为 CLI flag：

| Record 字段 | CLI flag | 规则 | 示例 |
|------------|---------|------|------|
| `{ maxCount = 50 }` | `--max-count 50` | 多字符 camelCase：大写字母触发断词 | |
| `{ oneline = true }` | `--oneline` | 全小写多字符：一字不拆，直接 `--` 前缀 | |
| `{ readonly = true }` | `--readonly` | 同上，不做连字符拆分 | |
| `{ l = true }` | `-l` | 单小写字符 + Bool=true：单 token 短 flag | |
| `{ o = "a.out" }` | `-o a.out` | 单小写字符 + 非 Bool：双 token（flag + 值） | |
| `{ X = "POST" }` | `-X POST` | 单大写字符：保留大小写，`-` 前缀 | |
| `{ humanReadable = true }` | `--human-readable` | 标准 camelCase 多大写断词 | |
| `Bool = false` | 省略不传 | false 值不生成 flag | |
| `Nil` | 省略不传 | Nil 值不生成 flag | |
| `List a` | `--key v1 --key v2` | 每个元素一个重复 flag | |

> **断词规则**：仅大写字母触发 `-` 断词（`maxCount` → `--max-count`）。全小写多字符键（`readonly`、`stdout`、`oneline`）不做连字符拆分。不适合 Record 映射的 flag（如 `-Wall`、`-Wl,...` 等）使用 `Cmd.withRawOpt` 按原样追加。

argv 生成顺序：

```
Record 选项 → Cmd.withRawOpt 追加 → -- 分隔符 → 位置参数
```

## Command 执行模型

### 延迟执行

`Cmd.<bin>` 返回 `Command` 值——**不立即执行**。Command 在以下时机自动执行：

| 场景 | 触发条件 | 示例 |
|---|---|---|
| `\|>` 隐式触发 | 左侧 `Command`，右侧函数期望 `Stream` | `Cmd.cat p"/x" \|> Stream.lines` |
| `do` 块语句边界 | 未被 `=` 绑定或 `|>` 消费的 `Command` 表达式作为独立语句执行 | `Cmd.ls { long = true }` |
| `Cmd.<bin>?` | `?` 后缀，立即执行并返回 `Result` | `result = Cmd.cat? p"/x"` |

> `do` 块边界规则：`Cmd.<bin>` 表达式若被 `=` 绑定（如 `c = Cmd.ls {}`）则视为"已消费"，不在此处触发执行——`c` 绑定为 `Command` 值，后续可通过 `|>` 或终端操作触发。若 `Cmd.<bin>` 表达式作为独立语句出现（无 `=` 绑定），则视为"未消费"，在语句边界自动触发执行。

### 错误处理

默认行为：命令执行失败时 **panic**（unwind → defer 逆序执行），结构化错误信息包含命令名、退出码、stderr。

`?` 后缀替代 panic，返回 `Result (Stream String) CommandError`，由调用者通过 `case` 处理。

## OS 管道：`Cmd.pipe` / `Cmd.pipe?`

通过 `Cmd.pipe` 将多个 Command 连接为 OS 管道链：

```kun
Cmd.pipe [Cmd.ps {}, Cmd.grep { pattern = "nginx" }, Cmd.head { n = 10 }]
```

- `Cmd.pipe`：链中任一命令非零退出 → panic（等价 `set -o pipefail`）
- `Cmd.pipe?`：链中任一命令失败 → 返回 `Err (PipeFailed ...)`

`Cmd.pipe` 的结果可继续接入进程内管道 `|>` 链：

```kun
Cmd.pipe
  [ Cmd.ps {}, Cmd.grep {} ]
  |> Stream.lines
  |> Stream.toList
```

## 修饰函数

以下函数接收 `Command` 并返回 `Command`（链式修饰，不立即执行）。

| 函数 | 用途 |
|------|------|
| `Cmd.withEnv` | 添加环境变量 |
| `Cmd.withStdin` | 注入 stdin（字符串或字节流） |
| `Cmd.withRawOpt` | 追加原始 argv token（见下方说明） |
| `Cmd.mergeStderr` | stderr 合并到 stdout |
| `Cmd.withCwd` | 指定子进程工作目录 |
| `Cmd.withRunAs` | 指定执行用户 |
| `Cmd.andThen` | 短路条件：前一个成功时执行后一个 |
| `Cmd.orElse` | 短路条件：前一个失败时执行备选 |

### 追加原始 argv：`Cmd.withRawOpt`

`Cmd.withRawOpt : String -> ?String -> Command -> Command` 按原样追加 argv token，用于不适合 camelCase 自动映射的 flag（如 `-Wall`、`-Wl,...`、`-O2` 等）：

```kun
do
  Cmd["g++"] { o = "a.out" } "main.cpp"
    |> Cmd.withRawOpt "-Wall" Nil
    |> Cmd.withRawOpt "-O2" Nil
    |> Cmd.withRawOpt "-I" "/usr/local/include"
```

`withRawOpt` 追加的 token 插入在 argv 序列中 `--` 分隔符之前、Record 生成的选项之后。

## 工作目录

Kun **不提供全局 `cd`**。`Cmd.withCwd : Path -> Command -> Command` 指定每个子进程独立的工作目录（fork 后、exec 前 `chdir`）。父进程 OS CWD 始终不变，缺省使用 `Path.cwd`（脚本启动时冻结的常量）。

```kun
do
  Cmd.ls {}                                       // CWD = Path.cwd
  Cmd.tar { c = true, f = "backup.tar" } "."
    |> Cmd.withCwd p"/build/output"               // 仅此子进程 CWD = /build/output
  Cmd.ls {}                                       // CWD 仍为 Path.cwd
```

需要跨多个命令使用同一 CWD 时，用变量绑定：

```kun
do
  workDir = p"/build/output"
  Cmd.tar { c = true, f = "backup.tar" } "." |> Cmd.withCwd workDir
  Cmd.ls { a = true } |> Cmd.withCwd workDir
```

## stdin 注入：`Cmd.withStdin`

```kun
Cmd.withStdin : String -> Command -> Command        // 字符串模式
Cmd.withStdin : Stream Bytes -> Command -> Command  // 流式模式
```

String 重载适用于小体积输入（< 1MB），超出时推荐使用流式模式。两种模式均在 fork 后通过 pipe 写入子进程 stdin，若子进程不消费 stdin 且输入超过 pipe 缓冲区（64KB），父进程写入阻塞。

## 环境变量：`Cmd.withEnv`

```kun
do
  Cmd.mysql { u = "root" }
    |> Cmd.withEnv #{ "MYSQL_PWD" = Env.getenv "DB_PASS" ?? "" }
```

## stderr 合并：`Cmd.mergeStderr`

`Cmd.mergeStderr : Command -> Command` 将子进程的 stderr 合并到 stdout 流中，使 stderr 输出也能通过 `Stream` 捕获和管道处理：

```kun
do
  Cmd.ffmpeg {} "input.mp4" "output.mp4"
    |> Cmd.mergeStderr
    |> Stream.lines
    |> Stream.iter (\line -> do IO.println line)
```

## 执行用户：`Cmd.withRunAs`

`Cmd.withRunAs : String -> Command -> Command` 指定子进程的执行用户。fork 后、exec 前调用 `setuid()`，需 Kun 进程具备 OS 级权限（root 或 `CAP_SETUID`）。

```kun
do
  Cmd.systemctl { restart = true } "nginx"
    |> Cmd.withRunAs "root"
```

## 短路条件组合：`Cmd.andThen` / `Cmd.orElse`

```kun
// Cmd.andThen : Command -> Command -> Command（前一个成功时执行后一个）
// Cmd.orElse  : Command -> Command -> Command（前一个失败时执行备选）
do
  Cmd.docker.build { tag = "app" } "."
    |> Cmd.andThen (Cmd.docker.push {} "app:latest")

  Cmd.ping { c = 3 } "192.168.1.1"
    |> Cmd.orElse (Cmd.echo {} "unreachable")
```

`Cmd.andThen` / `Cmd.orElse` 返回 `Command`（延迟执行），不立即 fork。不引入 `&&`/`||` 运算符以避免与逻辑短路运算符冲突。

## 超时与重试：`Cmd.timeout` / `Cmd.retry`

不同于修饰函数，`timeout` 和 `retry` 立即执行并返回 `Result`：

```kun
// Cmd.timeout : Duration -> Command -> Result (Stream String) CommandError
// Cmd.retry   : Int -> Duration -> Command -> Result (Stream String) CommandError
do
  case Cmd.curl {} "https://example.com" |> Cmd.timeout 5s of
    Ok stream -> ...
    Err err   -> IO.println "request timed out"

  case Cmd.curl {} "https://example.com" |> Cmd.retry 3 1s of
    Ok stream -> ...
    Err err   -> IO.println "request failed after 3 retries"
```

`Cmd.retry` 内部调用 `Cmd.timeout`，每次重试独立 fork 子进程。失败时重试 `n` 次，全部失败后返回最后一次 `Err`。

## PATH 查找

`Cmd.<bin>` 的命令查找发生在**运行时**（每次调用时解析 PATH）。编译时不检查命令是否存在。首次 PATH 解析成功后结果被缓存（每次 `do` 块入口刷新）。`Cmd.which : String -> ?Path` 可用于显式 PATH 查找。

## 类型化模块自动发现

编译器在编译时自动搜索类型化命令模块，搜索路径按优先级：

1. `~/.kun/cmd/<Name>.kun`
2. `$KUN_PATH/cmd/<Name>.kun`
3. `<runtime>/lib/kun/cmd/<Name>.kun`

若找到类型化模块则加载并提供**选项类型检查**；未找到则退回**裸调用**——运行时 PATH 查找二进制 + camelCase 自动映射。

通过 [`kun cmd init`](kun-cli-tool.md#子命令) 可从 `man`/`--help` 自动生成命令模块骨架。

## API 签名

```kun
// Command 构造（编译器内置）
// <bin>  : ?[options] -> posArgs... -> Command
// <bin>? : ?[options] -> posArgs... -> Result (Stream String) CommandError

// OS 管道链
pipe  : List Command -> Command
pipe? : List Command -> Result (Stream String) CommandError

// 修饰函数
withEnv     : Map String String -> Command -> Command
withRawOpt  : String -> ?String -> Command -> Command
withStdin   : String -> Command -> Command
withStdin   : Stream Bytes -> Command -> Command
mergeStderr : Command -> Command
withCwd     : Path -> Command -> Command
withRunAs   : String -> Command -> Command

// 短路条件组合
andThen : Command -> Command -> Command
orElse  : Command -> Command -> Command

// 工具
which   : String -> ?Path
timeout : Duration -> Command -> Result (Stream String) CommandError
retry   : Int -> Duration -> Command -> Result (Stream String) CommandError
```

> `<bin>`、`?[options]`、`posArgs...` 为元语法占位符，非 Kun 语法。`Cmd.<bin>` 接收可选选项 Record（`?[options]`）和零或多个位置参数（`posArgs...`）。具体调用示例见[语法入口](#语法入口)。

## 与标准库的关系

- [标准库 Cmd 模块](standard-library.md#cmd-command-工具与命令调用)：Cmd 模块导入与定位说明
- [系统基线](../architecture/system-baseline.md#命令调用机制)：描述 fork-exec 运行时**实现机制**（系统契约、安全层、内存管理）
- 本文档：定义命令调用的**语法、语义、API 签名与使用机制**

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.13 | API 签名伪语法规范；锚点规范化 |
| 2026.06.12 | 从 `app-overview.md` 和 `system-baseline.md` 中提取命令调用机制为独立文档 |
