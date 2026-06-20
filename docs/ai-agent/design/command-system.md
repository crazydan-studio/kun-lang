# OS 命令调用机制

## 定位

Kun 通过 `Cmd.<bin>` 语法调用 Linux 命令。本文件定义命令调用的语法、语义与机制。

> **编译器内置**：`Cmd.<bin>` 语法和 `Cmd.<bin>?` 由编译器直接解析并生成 fork-exec 调用代码，非标准库函数调用。`Command` 类型的延迟执行语义（惰性、`|>` 隐式触发）也由编译器处理。

具体的运行时实现细节见[系统基线](../architecture/system-baseline.md#命令调用机制)。

## 语法入口

### 基础调用

```kun
Cmd.<bin> [options] [posArgs...]
```

命令名 `<bin>` 直接拼接到 `Cmd.` 之后，**选项 Record** 在前（可省略——无选项时直接写位置参数或方法结束），**位置参数**在最后：

```kun
Cmd.ls { long = true, all = true } p"/tmp"
Cmd.git.log { maxCount = 50 } "main"
Cmd.date                                         // 无选项时直接省略 Record
```

选项 Record 可为空 `{}`（显式但冗余，与省略等价）：

```kun
Cmd.date {}
```

> **选项 Record 省略规则**：当命令无需任何选项时，Record `{...}` 可整体省略。此时 `Cmd.<bin>` 后直接跟位置参数（若有）或无参数——如上例 `Cmd.date` 既无 Record 也无位置参数，是合法调用。此规则对所有 `Cmd.<bin>`、`Cmd.<bin>?`、`Cmd.<bin>!` 均适用。

> **参数传递**：Kun 使用 `execve(2)` 直接执行命令——**不经过 shell 解析**。因此 shell 元字符（`$`、`\`、`"`、`'`、`;`、`|`）**无需转义**。位置参数和选项值按原字符串传递为 `argv[]` 数组元素，每个值独立为一个 `argv` 条目。唯一约束：`String` 为 UTF-8 编码，不含 NUL 字节（`\0`），满足 `execve` 的参数要求。`Cmd["name"]` 转义语法用于命令名含特殊字符（如 `Cmd["g++"]`），参数本身无需转义。

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

### 立即执行 + 错误处理：`?` 后缀

`Cmd.<bin>?` 立即执行并在失败时返回 `Err`，等价于 `Cmd.execSafe (Cmd.<bin> ...)`：

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

### 断言执行：`!` 后缀

`Cmd.<bin>!` 立即执行并在失败时 **panic**，等价于 `Cmd.exec (Cmd.<bin> ...)`——适用于仅关心副作用、不关心 stdout 的场景：

```kun
do
  Cmd.mkdir! { p = true } p"/tmp/build"    // 失败 → panic
  Cmd.cp! {} "main.cpp" "src/main.cpp"     // 失败 → panic
```

`Cmd.<bin>?` 和 `Cmd.<bin>!` 均为编译器内置构造语法：`?` 退糖为 `Cmd.execSafe` 调用（失败返回 `Err`），`!` 退糖为 `Cmd.exec` 调用（失败 panic）。

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

> **断词规则**：仅大写字母触发 `-` 断词（`maxCount` → `--max-count`）。全小写多字符键（`readonly`、`stdout`、`oneline`）不做连字符拆分——直接 `--` 前缀整个字段名（如 `readonly` → `--readonly`）。此规则确保与以全小写多字符 flag 为主的 CLI 工具兼容（如 `--oneline`、`--readonly` 等），但无法为全小写字段生成 kebab-case flag。需要非标准 flag 映射的用 `Cmd.withRawOpt` 按原样追加。

argv 生成顺序：

```
Record 选项 → Cmd.withRawOpt 追加 → -- 分隔符 → 位置参数
```

## Command 执行模型

### 延迟执行

`Cmd.<bin>` 返回 `Command` 值——**不立即执行**。Command 在以下时机执行：

| 场景 | 触发条件 | 示例 |
|---|---|---|
| `\|>` 隐式触发 | 左侧 `Command`，右侧函数期望 `Stream` | `Cmd.cat p"/x" \|> Stream.lines` |
| `Cmd.<bin>!` | `!` 后缀，立即执行，失败 panic（`Cmd.exec` 简写） | `Cmd.ls! { long = true } p"/tmp"` |
| `Cmd.<bin>?` | `?` 后缀，立即执行，失败返回 Err（`Cmd.execSafe` 简写） | `case Cmd.cat? p"/x" of ...` |
| `Cmd.exec` | 显式执行 Command 值，失败 panic，stdout 丢弃 | `Cmd.exec c` |
| `Cmd.execSafe` | 显式执行 Command 值，失败返回 Err，stdout 通过 Stream 消费 | `case Cmd.execSafe c of ...` |
| `Cmd.pipe?` | 立即执行管道链，失败返回 Err | `Cmd.pipe? [Cmd.ps {}, Cmd.grep {}]` |
| `Cmd.pipe!` | 立即执行管道链，失败 panic | `Cmd.pipe! [Cmd.ps {}, Cmd.grep {}]` |

> `|>` 隐式触发的类型推断：编译器检测左侧 `Command` 类型与右侧函数期望的 `Stream String` 类型不匹配时，在两者之间插入 `Command → Stream String` 的执行步骤。**`|>` 隐式执行仅在 `do` 块内允许**——`do` 块外的 `|>` 收到 `Command` 值时编译期报错（"Command pipe requires a do block"）。非 `Command` 类型（如 `Stream`）的 `|>` 管道不受此限。若右侧函数为多态（如 `identity : a -> a`），编译器需先合一 `a ~ Stream String` 后确认触发。此多阶段类型检查（约束生成 → 合一 → Command 检测 → 插入执行节点）在 HM 框架内可实现，但相对常规合一增加了一步 AST 变换。编译期错误信息在无法确定触发条件时回退为"无法将 Command 用作 Stream，是否遗漏 `Cmd.<bin>?`？"

> **`exec` vs `execSafe`**：`Cmd.exec : Command -> Unit`，失败 panic，stdout 被静默丢弃——用于仅关心副作用的命令。`Cmd.execSafe : Command -> Result (Stream String) CommandError`，失败返回 `Err`，stdout 通过 Stream 消费——用于需要捕获输出或处理错误的场景。`Cmd.<bin>!` 和 `Cmd.<bin>?` 分别为两者的构造器简写。

> **空输出管道**：子进程退出码为 0 但 stdout 无输出时，`|>` 产生的 `Stream String` 为空流（零元素）。终端操作 `Stream.toList` 返回 `[]`；`Stream.iter` 不执行回调；`Stream.string` 返回空字符串 `""`。`Cmd.exec` 在子进程无输出时正常返回 `Unit`（stdout 被静默丢弃）。子进程非零退出码时行为取决于调用方式——`?` 后缀 / `Cmd.execSafe` 返回 `Err`，`!` 后缀 / `Cmd.exec` 触发 panic。

### Command 生命周期

```kun
// 构造：纯操作，不执行
c = Cmd.ls { long = true } p"/tmp"

// 修饰：纯操作，累积属性
c2 = c |> Cmd.withWorkDir p"/home" |> Cmd.mergeStderr

// 执行：效应操作，通过 ! 后缀（panic 失败）
do
  Cmd.mkdir! { p = true } p"/tmp/build"

// 显式执行：效应操作，panic 失败
do
  Cmd.exec c2

// 安全执行：效应操作，返回 Result
do
  case Cmd.execSafe c2 of
    Ok stream -> Stream.iter IO.println stream
    Err e -> IO.println (CommandError.show e)

// 管道执行：|> 触发，隐式执行
do
  Cmd.ls { long = true } p"/tmp"
    |> Cmd.mergeStderr
    |> Stream.lines
    |> Stream.iter IO.println

// 立即执行+错误处理：? 后缀（Cmd.execSafe 简写）
do
  case Cmd.ls? { long = true } p"/nonexistent" of
    Ok stream -> ...
    Err e -> IO.println (CommandError.show e)
```

### 错误处理

默认行为：命令执行失败时 **panic**（unwind → defer 逆序执行），结构化错误信息包含命令名、退出码、stderr。

`?` 后缀和 `Cmd.execSafe` 替代 panic，返回 `Result (Stream String) CommandError`，由调用者通过 `case` 处理。

`!` 后缀和 `Cmd.exec` 保持 panic 语义——仅在调用者确信命令不会失败、或失败无恢复路径时使用。

## OS 管道：`Cmd.pipe` / `Cmd.pipe?` / `Cmd.pipe!`

通过 `Cmd.pipe` 将多个 Command 连接为 OS 管道链：

```kun
Cmd.pipe [Cmd.ps {}, Cmd.grep { pattern = "nginx" }, Cmd.head { n = 10 }]
```

- `Cmd.pipe`：链中任一命令非零退出 → panic（等价 `set -o pipefail`）
- `Cmd.pipe?`：链中任一命令失败 → 返回 `Err (PipeFailed ...)`
- `Cmd.pipe!`：等价于 `Cmd.pipe` + `|>` 隐式触发 + panic 语义（丢弃输出，仅副作用）

`Cmd.pipe` 接收非空 `List Command`——传入空列表 `[]` 时编译期报错（"Cmd.pipe requires at least one command"）。`Cmd.pipe?` 同理。

`Cmd.pipe` 返回 `Command`，延迟执行（由 `|>` 或 `Cmd.exec` 触发）。`Cmd.pipe?` 和 `Cmd.pipe!` 立即执行整个管道链：
- `Cmd.pipe?` 返回 `Result (Stream String) CommandError`——等价于 `Cmd.execSafe (Cmd.pipe [...])`
- `Cmd.pipe!` 返回 `Unit`——等价于 `Cmd.exec (Cmd.pipe [...])`

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
| `Cmd.withStdinFile` | 从文件路径注入 stdin |
| `Cmd.withWorkDir` | 指定子进程工作目录 |
| `Cmd.withRunAs` | 指定执行用户 |
| `Cmd.andThen` | 短路条件：前一个成功时执行后一个 |
| `Cmd.orElse` | 短路条件：前一个失败时执行备选 |

## 追加原始 argv：`Cmd.withRawOpt`

`Cmd.withRawOpt : String -> ?String -> Command -> Command` 按原样追加 argv token，用于不适合 camelCase 自动映射的 flag（如 `-Wall`、`-Wl,...`、`-O2` 等）：

```kun
do
  Cmd["g++"] { o = "a.out" } "main.cpp"
    |> Cmd.withRawOpt "-Wall" Nil
    |> Cmd.withRawOpt "-O2" Nil
    |> Cmd.withRawOpt "-I" "/usr/local/include"
    |> Cmd.exec
```

`withRawOpt` 追加的 token 插入在 argv 序列中 `--` 分隔符之前、Record 生成的选项之后。

## 工作目录

Kun **不提供全局 `cd`** 或 `chdir`。`Cmd.withWorkDir : Path -> Command -> Command` 指定每个子进程独立的工作目录（fork 后、exec 前 `chdir`）。父进程 CWD 在脚本启动时冻结为 `File.currentDir`，不可变——需使用相对路径的场景通过 `Path.resolve` 基于 `File.currentDir` 转为绝对路径后显式传递，或对各命令使用 `Cmd.withWorkDir` 隔离设置。

```kun
do
  Cmd.ls {} |> Cmd.exec                                            // CWD = File.currentDir
  Cmd.tar { c = true, f = "backup.tar" } "."
    |> Cmd.withWorkDir p"/build/output" |> Cmd.exec               // 仅此子进程 CWD = /build/output
  Cmd.ls {} |> Cmd.exec                                            // CWD 仍为 File.currentDir
```

需要跨多个命令使用同一 CWD 时，用变量绑定：

```kun
do
  workDir = p"/build/output"
  Cmd.tar { c = true, f = "backup.tar" } "." |> Cmd.withWorkDir workDir |> Cmd.exec
  Cmd.ls { a = true } |> Cmd.withWorkDir workDir |> Cmd.exec
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
    |> Cmd.exec
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

`Cmd.withRunAs : String -> Command -> Command` 指定子进程的执行用户。fork 后、exec 前按序执行完整的权限降级流程：

1. `initgroups(username, primary_gid)` — 设置附加组列表（清除父进程继承的组）
2. `setgid(primary_gid)` — 设置主组
3. `setuid(target_uid)` — 设置用户（必须在 `setgid` 之后）
4. 验证 `setuid(0)` 返回 `-1`（确认无法重新提升权限）

需 Kun 进程具备 OS 级权限（root 或 `CAP_SETUID` + `CAP_SETGID`）。若父进程为 root，子进程 fork 后自动继承 `PR_SET_NO_NEW_PRIVS` 标记（由父进程在沙箱初始化阶段设置），进一步阻止子进程通过 setuid binary 重新提升特权。

```kun
do
  Cmd.systemctl { restart = true } "nginx"
    |> Cmd.withRunAs "root"
    |> Cmd.exec
```

## 短路条件组合：`Cmd.andThen` / `Cmd.orElse`

```kun
// Cmd.andThen : Command -> Command -> Command（前一个成功时执行后一个）
// Cmd.orElse  : Command -> Command -> Command（前一个失败时执行备选）
do
  Cmd.docker.build { tag = "app" } "."
    |> Cmd.andThen (Cmd.docker.push {} "app:latest")
    |> Cmd.exec

  Cmd.ping { c = 3 } "192.168.1.1"
    |> Cmd.orElse (Cmd.echo {} "unreachable")
    |> Cmd.exec
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

`Cmd.timeout` 超时时：向子进程发送 `SIGTERM` → 等待 2 秒 → 若进程未退出则发送 `SIGKILL` → `waitpid` 回收。子进程在超时前的部分 stdout 输出不保留（`Result` 的 `Err` 分支不含部分输出）。超时错误通过 `CommandError.Timeout` 变体返回。

`n = 0` 时等同于调用 `Cmd.timeout duration command`（仅执行一次，不重试）。`n < 0` 时编译期报错。

#### 时钟源

`Cmd.timeout` 使用 `CLOCK_MONOTONIC` 作为计时时钟源（通过 `timerfd_create` 实现，Linux 3.17+；低于 3.17 回退到 `clock_gettime(CLOCK_MONOTONIC, ...)` 轮询）。选择 `CLOCK_MONOTONIC` 而非 `CLOCK_REALTIME` 的原因：

- `CLOCK_REALTIME` 受 NTP 时间同步和系统管理员手动修改影响——时间向前跳变可能导致超时提前触发，时间向后跳变（闰秒、NTP 回拨）可能导致超时无限延长
- `CLOCK_MONOTONIC` 单调递增且不受外部时间调整影响，确保超时语义的确定性
- 与 Kun 的安全设计原则一致：运行时行为不因环境（NTP 配置、时钟调整）产生不可预期的差异

#### 修饰函数链式组合顺序

修饰函数通过 `|>` 链式应用时按从左到右的顺序累积属性，最终由 `timeout`/`retry` 或 `|>` 隐式触发 fork：

```kun
do
  Cmd.someCmd {} dir
    |> Cmd.withWorkDir p"/work"          // 1. 设置工作目录
    |> Cmd.withRunAs "appuser"       // 2. 设置执行用户
    |> Cmd.timeout 5s                // 3. 立即 fork → chdir → setuid → exec
```

fork 在 `timeout` 处触发，子进程内依次执行 `chdir("/work")` → `setuid(appuser)` → `exec`。若顺序不满足需求（如先 `timeout` 后 `withWorkDir`），`withWorkDir` 之后的修饰属性在 `timeout` fork 后无法应用——修饰函数必须在触发执行的操作之前。

## PATH 查找

`Cmd.<bin>` 的命令查找发生在**运行时**（每次调用时解析 PATH）。编译时不检查命令是否存在。首次 PATH 解析成功后结果被缓存（每次 `do` 块入口刷新）。`Cmd.which : String -> ?Path` 可用于显式 PATH 查找：

- 搜索逻辑：按 PATH 中目录顺序遍历，每个目录内检查文件是否存在且可执行（`access(X_OK)`）
- PATH 中不存在的目录静默跳过；非目录条目（如文件）跳过并 stderr warn 记录
- PATH 为空或未设置时使用默认值 `/usr/local/bin:/usr/bin:/bin`
- 符号链接跟随——最终目标的可执行权限决定结果；循环符号链接静默跳过
- 找到返回 `Path`，未找到返回 `Nil`

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
// <bin>? : ?[options] -> posArgs... -> Result (Stream String) CommandError   // ≡ Cmd.execSafe
// <bin>! : ?[options] -> posArgs... -> Unit                                    // ≡ Cmd.exec

// OS 管道链
// [PureKun]
pipe  : List Command -> Command
// [Primitive]
pipe? : List Command -> Result (Stream String) CommandError                   // ≡ Cmd.execSafe
// [PureKun]
pipe! : List Command -> Unit                                                    // ≡ Cmd.exec

// 修饰函数
// [PureKun]
withEnv     : Map String String -> Command -> Command
// [PureKun]
withRawOpt  : String -> ?String -> Command -> Command
// [PureKun]
withStdin   : String -> Command -> Command
// [PureKun]
withStdin   : Stream Bytes -> Command -> Command

// [PureKun] 从文件路径注入 stdin——读取文件内容并通过 pipe 写入子进程
withStdinFile : Path -> Command -> Command

// [PureKun]
mergeStderr : Command -> Command
// [PureKun]
withWorkDir     : Path -> Command -> Command
// [PureKun] 指定子进程执行用户  // [推迟 v1.0]
withRunAs : String -> Command -> Command

// 短路条件组合
// [PureKun]
andThen : Command -> Command -> Command
// [PureKun]
orElse  : Command -> Command -> Command

// [Primitive] 在 PATH 中查找可执行文件
which : String -> ?Path

// [Primitive] 执行 Command——fork-exec 阻塞等待，失败 panic，stdout 丢弃
exec : Command -> Unit

// [Primitive] 执行 Command 的安全变体——失败返回 Err，stdout 通过 Stream String 消费
execSafe : Command -> Result (Stream String) CommandError

// [Primitive] 命令超时（SIGKILL + waitpid）  // [推迟 v1.0]
timeout : Duration -> Command -> Result (Stream String) CommandError

// [Primitive] 命令重试（内部调用 Cmd.timeout）  // [推迟 v1.0]
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
| 2026.06.18 | API 精简：`execSafe` 签名从 `Result Unit` 改为 `Command -> Result (Stream String) CommandError`（与 `Cmd.<bin>?` 对齐）；移除 `stdoutToString`/`stderrToString`；新增 `Cmd.<bin>!`/`Cmd.pipe!` 构造语法（断言执行简写） |
| 2026.06.15 | 审计修复三轮：参数转义/execve 语义文档化；0 字节管道输出行为；空 pipe 列表编译期报错；Cmd.which PATH 搜索细节；Cmd.timeout kill 流程；Cmd.retry 边界值处理 |
| 2026.06.15 | 审计修复：`\|>` 管道执行限制为 `do` 块内（效应检查器守卫）；`Cmd.exec` 阻塞语义文档化 |
| 2026.06.14 | `Cmd.withRunAs` 权限降级流程补全：`initgroups` → `setgid` → `setuid` → 验证 |
| 2026.06.14 | 移除 `do` 块语句边界隐式执行规则；新增 `Cmd.exec : Command -> Unit` 显式执行；未被消费的 Command 是编译错误；新增 Command 生命周期示例 |
| 2026.06.13 | API 签名伪语法规范；锚点规范化 |
| 2026.06.12 | 从 `app-overview.md` 和 `system-baseline.md` 中提取命令调用机制为独立文档 |
