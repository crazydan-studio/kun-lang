# OS 命令调用机制

## 定位

Kun 通过 `cmd` 字面量构造 `Command` 值，通过显式执行函数（`Cmd.exec`/`Cmd.execSafe`/`Cmd.stream`）触发 fork-exec。本文件定义 Command 的 ADT 表示、`cmd` 字面量语法、选项映射规则、执行入口与修饰函数。

> **设计原则**（详见 [语法设计](syntax.md) 与新设计总则）：
> - **Command 是 ADT**：`Command` 是普通代数数据类型，`cmd` 字面量是构造 `Command` 的语法糖，无解析器魔法
> - **显式执行**：所有 Command 执行必须显式调用执行函数，**无 `?`/`!` 后缀糖**，**无 `|>` 隐式触发**
> - **`|>` 回归纯管道**：`|>` 统一类型为 `a -> (a -> b) -> b`，对 Command 与 Stream 一视同仁，无双重语义
> - **入口级 handle**：`Cmd` 是内置效应（保留名），其默认 handler 在编译器源码（Zig）中实现，编译进 `kun` 二进制

具体的运行时实现细节见[系统基线](../architecture/system-baseline.md#命令调用机制)。

## Command ADT

`Command` 为代数数据类型，支持 `Simple` 单命令与 `Pipe` 管道两种变体。`cmd` 字面量构造 `Simple` 变体，`pipe` 纯函数构造 `Pipe` 变体。

```kun
type Command =
  Simple SimpleCommand
  | Pipe (List Command)

type SimpleCommand =
  { name        : String
  , subcommands : List String
  , options     : List OptField
  , args        : List String
  , env         : Map String String
  , stdin       : ?StdinSource
  , workDir     : ?Path
  , runAs       : ?String
  , mergeErr    : Bool
  , timeout     : ?Duration
  , retry       : ?(Int Duration)
  , useDash     : Bool
  }

type OptField =
  { key   : OptKey
  , value : OptValue
  }

type OptKey =
  IdentKey String     // 标识符键（自动映射）
  | RawKey String     // 字符串键（原样）

type OptValue =
  FlagSet             // Bool = true
  | FlagClear         // Bool = false / Nil
  | Single String     // 单值
  | Repeated (List String)  // 多值

type StdinSource =
  StdinStr String
  | StdinFile Path
  | StdinStream (Stream Bytes)
```

## `cmd` 字面量语法

### 四段式固定结构

```
cmd <命令> <子命令>* <选项>? <位置参数>?
```

- **命令**：字符串或标识符（必填）
- **子命令**：字符串或标识符（零或多个）
- **选项**：Record `{ ... }`（可省略，缺省 `{}`）
- **位置参数**：List `[ ... ]`（可省略，缺省 `[]`）

```kun
cmd docker run { d = true, name = "my-web" } [ "nginx" ]
```

### 命令名 / 子命令名形式

命令名与子命令名既可用标识符（如 `docker`、`run`）也可用字符串字面量（如 `"g++"`、`"./build.sh"`）。

| 形式 | 示例 | 适用场景 |
|---|---|---|
| 标识符 | `cmd ls { a } [ p"/tmp" ]` | 标准 CLI 命令名 |
| 字符串 | `cmd "g++" { o = "a.out" } [ "main.cpp" ]` | 含 `-`/`.`/`+`/数字/特殊字符的命令名 |
| 字符串子命令 | `cmd git "log" {} [ "master" ]` | 含特殊字符的子命令名 |

### 选项 Record

选项以 Record 字面量 `{ ... }` 形式书写，键可为标识符或字符串字面量，值可为 `Bool`/`String`/`Int`/`Float`/`Path`/`Char`/`List` 等。

```kun
cmd docker run
  { d = true                       // Bool → 旗标
  , name = "my-web"                // String → flag + 值
  , p = [ "80:80", "443:443" ]     // List → 重复 flag
  , verbose = false                // Bool = false → 省略
  }
  [ "nginx" ]
```

### 位置参数

位置参数以 List 字面量 `[ ... ]` 形式书写，**必须用 `[ ]`**，不支持裸字符串。

```kun
cmd cp {} [ "a.txt", "b.txt" ]
cmd ls { a } [ p"/tmp" ]
```

### 简写形式

任何键省略 `= value` 时等同 `= true`：

```kun
cmd ls { a, l, h } [ p"/tmp" ]    // 等价 { a = true, l = true, h = true }
```

字符串键同样支持简写：

```kun
cmd java { "-Xmx" = "1024m", "-verbose" } []   // -verbose 等同 "-verbose" = true
```

## 选项映射规则

### 键形式映射

| 键形式 | 示例 | 映射规则 |
|---|---|---|
| 标识符单字符 | `a`, `l`, `p` | 补 `-` 前缀 |
| 标识符多字符 | `maxCount`, `verbose` | 补 `--` 前缀 + camelCase→kebab-case |
| 字符串键 | `"-Xmx"`, `"/user"`, `"-2"` | 原样使用，不补前缀 |
| 简写（任何键） | `a`, `"-2"`, `"--readOnly"` | ≡ `= true` |

> **camelCase → kebab-case 规则**：大写字母触发断词（`maxCount` → `--max-count`），全小写多字符键不做连字符拆分（`verbose` → `--verbose`，`readonly` → `--readonly`）。

### 值类型映射

| 值类型 | 生成 argv |
|---|---|
| `Bool = true` | 旗标（无值） |
| `Bool = false` / `Nil` | 省略 |
| 单值（String/Int/Float/Path/Char） | flag + 值 |
| `List` | 重复 flag + 各值 |

### 完整映射表

| 键 | 值 | 生成 argv |
|---|---|---|
| `a`（标识符单字符） | `true` | `-a` |
| `a` | `false`/`Nil` | （省略） |
| `a` | `"value"` | `-a value` |
| `a` | `[ "v1","v2" ]` | `-a v1 -a v2` |
| `a`（简写） | — | `-a` |
| `maxCount` | `true` | `--max-count` |
| `maxCount` | `50` | `--max-count 50` |
| `maxCount` | `[ "50","100" ]` | `--max-count 50 --max-count 100` |
| `verbose`（全小写） | `true` | `--verbose` |
| `"-Xmx"` | `"1024m"` | `-Xmx 1024m` |
| `"/user"` | `"admin"` | `/user admin` |
| `"-2"`（简写） | — | `-2` |
| `"-read-only"` | `true` | `-read-only` |

## argv 生成顺序

```
argv = [命令名] + [子命令...] + [选项 flags（按 Record 声明顺序）] + [ "--" if 有位置参数且 useDash] + [位置参数]
```

- **选项 flags 顺序**：按选项 Record 中字段的声明顺序生成（不是字母序）
- **`--` 分隔符**：仅当有位置参数且 `useDash = true` 时插入
- **位置参数顺序**：按 List 中元素顺序

## `--` 分隔符

### 默认行为

有位置参数时自动插入 `--`，与选项 flags 隔开，避免位置参数被误识别为选项。

```kun
// argv = [ "echo", "--", "hello", "world" ]
cmd echo {} [ "hello", "world" ] |> Cmd.exec
```

### 关闭 `--`

`Cmd.withoutDash` 纯函数设置 `useDash = false`，关闭自动插入：

```kun
Cmd.withoutDash : Command -> Command

// argv = [ "echo", "hello", "world" ]   // 无 --
cmd echo {} [ "hello", "world" ] |> Cmd.withoutDash |> Cmd.exec
```

## `cmd` 字面量示例

```kun
// 基本命令
cmd date {} []
cmd ls { a, l } [ p"/tmp" ]

// 子命令
cmd docker run { d = true, name = "my-web" } [ "nginx" ]
cmd git log { "-2", pretty = "format:%h" } [ "master" ]

// 字符串命令名
cmd "@vue/cli" create {} [ "my-app" ]
cmd "./build.sh" { verbose = true } [ "prod-env" ]
cmd "g++" { o = "a.out", "-Wall" = true, "-O2" = true } [ "main.cpp" ]

// 字符串子命令
cmd git "log" { } [ "master" ]

// 非标准 flag
cmd java { "-Xmx" = "1024m", "-jar" = p"app.jar" } []
cmd net { "/user" = "administrator", "/active" = "yes" } []

// 多值选项
cmd docker run
  { p = [ "80:80", "443:443" ]
  , v = [ "/host:/container" ]
  }
  [ "nginx" ]

// 简写
cmd ls { a, l, h } [ p"/tmp" ]

// 关闭 --
cmd echo {} [ "hello", "world" ] |> Cmd.withoutDash
```

## Command 执行

### 显式执行原则

**所有 Command 执行必须显式调用执行函数**，无 `?`/`!` 后缀糖，无 `|>` 隐式触发。

理由：

1. **类型系统纯净**：`|>` 回归标准 `a -> (a -> b) -> b`，无 Command 检测特例
2. **语义统一**：`|>` 统一为纯管道，无"对 Command 隐式执行，对 Stream 纯管道"的双重语义
3. **显式性**：执行意图明确，错误消息清晰（标准类型不匹配，非"隐式触发失败"）
4. **与效应系统一致**：所有效应调用（含 Command 执行）统一显式

### 三个执行入口

```kun
// Cmd 效应操作

// 执行，丢弃 stdout，失败 panic。适用于仅副作用的命令（mkdir/cp）。
Cmd.exec     : Command -> Unit ! {Cmd}

// 执行，返回 Result，stdout 通过 Stream 消费。适用于需错误处理的场景。
Cmd.execSafe : Command -> Result (Stream String) CommandError ! {Cmd}

// 执行，返回 Stream，失败 panic。适用于需输出流但不需错误处理的场景。
Cmd.stream   : Command -> Stream String ! {Cmd}

// PATH 查找。
Cmd.which    : String -> ?Path ! {Cmd}
```

#### 三入口语义对比

| API | 返回类型 | 失败行为 | 适用场景 |
|---|---|---|---|
| `Cmd.exec` | `Unit` | panic | 仅副作用（mkdir/cp） |
| `Cmd.execSafe` | `Result (Stream String) CommandError` | 返回 Err | 需错误处理 |
| `Cmd.stream` | `Stream String` | panic | 需输出流，不需错误处理 |

`Cmd.stream` 等价于 `case Cmd.execSafe c of Ok s -> s; Err e -> panic e`，是便利组合。

### `|>` 的合法用法

`|>` 退化为纯管道操作符，统一类型 `a -> (a -> b) -> b`：

```kun
// Command 修饰（Command -> Command）
cmd ... |> Cmd.withWorkDir p"/build"
cmd ... |> Cmd.mergeStderr
cmd ... |> Cmd.withoutDash

// Command 执行（Command -> 其他类型）
cmd ... |> Cmd.exec        // 执行，丢弃输出
cmd ... |> Cmd.execSafe    // 执行，返回 Result
cmd ... |> Cmd.stream      // 执行，返回 Stream

// Stream 管道（Stream -> Stream）
stream |> Stream.lines
stream |> Stream.filter pred
stream |> Stream.toList
```

### 不再合法的用法

```kun
// ❌ 非法：|> 左侧 Command，右侧期望 Stream（类型不匹配）
cmd ls { a } [ "/tmp" ] |> Stream.lines
// 编译错误：Command 不匹配 Stream String
// Hint: 使用 Cmd.stream 执行命令获取输出流：
//       cmd ... |> Cmd.stream |> Stream.lines
```

### 典型用法

```kun
// 仅副作用
cmd mkdir { p = true } [ "/tmp/build" ]
  |> Cmd.exec

// 错误处理
let
  result =
    cmd cat {} [ p"/etc/maybe_missing" ]
      |> Cmd.execSafe

  case result of
    Ok stream ->
      Stream.iter IO.println stream
    Err e ->
      IO.println "not found"
in
  ()

// 输出流处理
let
  lines =
    cmd ls { a } [ "/tmp" ]
      |> Cmd.stream
      |> Stream.lines
      |> Stream.filter (String.contains "log")
      |> Stream.toList
in
  lines
```

## 管道：`pipe` 纯函数

### 纯函数 `pipe`

**仅保留纯函数 `pipe`**，废弃 `Cmd.pipe?`/`Cmd.pipe!`：

```kun
pipe : List Command -> Command
pipe = \cmds ->
  case cmds of
    [] -> panic "pipe requires at least one command"
    [c] -> c
    cs -> Pipe cs
```

`pipe` 构造 `Pipe` ADT 变体，是纯函数。执行需显式调用 `Cmd.exec`/`Cmd.execSafe`/`Cmd.stream`。

### 空列表处理（编译期检查）

`pipe` 的参数列表若为字面量空列表 `[]`，**编译错误**：

```kun
// ❌ 编译错误：pipe 要求列表非空
pipe []

// ✅ 合法
pipe [c1]
pipe [c1, c2, ...]
```

若参数为变量（编译期未知是否空），运行时检查，空列表 panic。

> **理由**：纯函数应避免 panic，但 `pipe []` 无合理返回值（`?Command` 增加调用方负担），故字面量空列表编译期拒绝。

### 嵌套深度限制

`pipe` 命令列表最多 **16 个命令**，超过 → **编译错误**。理由：OS pipe 缓冲区与 fd 数量限制，16 层足够覆盖真实场景。若需更深，拆分为多个 `pipe` + 中间文件。

```kun
// ❌ 编译错误
pipe [c1, c2, ..., c17]   // 超过 16 层

// ✅ 合法
pipe [c1, ..., c16]
```

### 管道执行示例

```kun
// 管道执行（错误处理）
// result : Result (Stream String) CommandError ! {Cmd}
result =
  pipe
    [ cmd ps { a } []
    , cmd grep { pattern = "nginx" } []
    ]
    |> Cmd.execSafe

// 管道执行（输出流处理）
pipe
  [ cmd ps { a } []
  , cmd grep { pattern = "nginx" } []
  ]
  |> Cmd.stream
  |> Stream.lines
  |> Stream.toList
```

## 修饰函数

修饰函数均为纯函数，接收 `Command` 并返回新 `Command`：

```kun
Cmd.withEnv       : Map String String -> Command -> Command
Cmd.withStdin     : String -> Command -> Command
Cmd.withStdin     : Stream Bytes -> Command -> Command
Cmd.withStdinFile : Path -> Command -> Command
Cmd.withWorkDir   : Path -> Command -> Command
Cmd.withRunAs     : String -> Command -> Command
Cmd.mergeStderr   : Command -> Command
Cmd.withoutDash   : Command -> Command
Cmd.andThen       : Command -> Command -> Command
Cmd.orElse        : Command -> Command -> Command
Cmd.timeout       : Duration -> Command -> Command
Cmd.retry         : Int -> Duration -> Command -> Command
```

> **`withStdin` 重载消歧**：编译器通过第一参数的类型（`String` vs `Stream Bytes`）在调用点进行消歧。HM 推断根据上下文确定调用哪一个签名。

### `Cmd.withStdin` 死锁预防策略

父进程同时向子进程 stdin 写入并读取 stdout 时，存在管道缓冲区满死锁风险。Kun 采用单线程非阻塞 poll 策略：

1. stdout 与 stdin 共享同一 `poll` 事件循环
2. **优先读 stdout**（清空缓冲给子进程空间，再尝试推送 stdin）
3. stdin 非阻塞写入，`EAGAIN` 时转向读 stdout
4. stdin 写尽后 `shutdown(fd, SHUT_WR)` 关闭写端
5. 不引入额外线程（保持单线程语义）
6. 输入超过 1MB 时推荐用 `Stream Bytes` 模式

此策略确保长时间运行的管道不会因缓冲区满而死锁。

### 工作目录

Kun **不提供全局 `cd`** 或 `chdir`。`Cmd.withWorkDir : Path -> Command -> Command` 指定每个子进程独立的工作目录（fork 后、exec 前 `chdir`）。父进程 CWD 在脚本启动时冻结为 `File.currentDir`，不可变——需使用相对路径的场景通过 `Path.resolve` 基于 `File.currentDir` 转为绝对路径后显式传递，或对各命令使用 `Cmd.withWorkDir` 隔离设置。

```kun
let
  cmd ls {} [] |> Cmd.exec                                  // CWD = File.currentDir

  cmd tar { c = true, f = "backup.tar" } [ "." ]
    |> Cmd.withWorkDir p"/build/output"
    |> Cmd.exec                                          // 仅此子进程 CWD = /build/output

  cmd ls {} [] |> Cmd.exec                                  // CWD 仍为 File.currentDir
in
  ()
```

需要跨多个命令使用同一 CWD 时，用变量绑定：

```kun
let
  workDir = p"/build/output"

  cmd tar { c = true, f = "backup.tar" } [ "." ]
    |> Cmd.withWorkDir workDir |> Cmd.exec

  cmd ls { a = true } []
    |> Cmd.withWorkDir workDir |> Cmd.exec
in
  ()
```

### 执行用户：`Cmd.withRunAs`

`Cmd.withRunAs : String -> Command -> Command` 指定子进程的执行用户。fork 后、exec 前按序执行完整的权限降级流程：

1. `initgroups(username, primary_gid)` — 设置附加组列表（清除父进程继承的组）
2. `setgid(primary_gid)` — 设置主组
3. `setuid(target_uid)` — 设置用户（必须在 `setgid` 之后）
4. 验证 `setuid(0)` 返回 `-1`（确认无法重新提升权限）

需 Kun 进程具备 OS 级权限（root 或 `CAP_SETUID` + `CAP_SETGID`）。若父进程为 root，子进程 fork 后自动继承 `PR_SET_NO_NEW_PRIVS` 标记，进一步阻止子进程通过 setuid binary 重新提升特权。

```kun
cmd systemctl { restart = true } [ "nginx" ]
  |> Cmd.withRunAs "root"
  |> Cmd.exec
```

### 短路条件组合：`Cmd.andThen` / `Cmd.orElse`

```kun
// Cmd.andThen : Command -> Command -> Command（前一个成功时执行后一个）
// Cmd.orElse  : Command -> Command -> Command（前一个失败时执行备选）
let
  cmd docker build { tag = "app" } [ "." ]
    |> Cmd.andThen (cmd docker push {} [ "app:latest" ])
    |> Cmd.exec

  cmd ping { c = 3 } [ "192.168.1.1" ]
    |> Cmd.orElse (cmd echo {} [ "unreachable" ])
    |> Cmd.exec
in
  ()
```

`Cmd.andThen` / `Cmd.orElse` 返回 `Command`（延迟执行），不立即 fork。不引入 `&&`/`||` 运算符以避免与逻辑短路运算符冲突。

### 超时与重试：`Cmd.timeout` / `Cmd.retry`

`Cmd.timeout` 与 `Cmd.retry` 是**修饰函数**（纯操作），返回带 `timeout`/`retry` 字段的 `Command`。执行需配合 `Cmd.exec`/`Cmd.execSafe`/`Cmd.stream`：

```kun
// Cmd.timeout : Duration -> Command -> Command
// Cmd.retry   : Int -> Duration -> Command -> Command

let
  result =
    cmd curl {} [ "https://example.com" ]
      |> Cmd.timeout 5s
      |> Cmd.execSafe

  case result of
    Ok stream -> Stream.iter IO.println stream
    Err err   -> IO.println "request timed out"

  result2 =
    cmd curl {} [ "https://example.com" ]
      |> Cmd.retry 3 1s
      |> Cmd.execSafe

  case result2 of
    Ok stream -> Stream.iter IO.println stream
    Err err   -> IO.println "request failed after 3 retries"
in
  ()
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

修饰函数通过 `|>` 链式应用时按从左到右的顺序累积属性，最终由 `Cmd.exec`/`Cmd.execSafe`/`Cmd.stream` 触发 fork：

```kun
let
  cmd someCmd {} [ dir ]
    |> Cmd.withWorkDir p"/work"        // 1. 设置工作目录
    |> Cmd.withRunAs "appuser"         // 2. 设置执行用户
    |> Cmd.timeout 5s                  // 3. 设置超时
    |> Cmd.exec                        // 4. fork → chdir → setuid → exec
in
  ()
```

fork 在 `Cmd.exec` 处触发，子进程内依次执行 `chdir("/work")` → `setuid(appuser)` → `exec`。修饰函数必须在触发执行的操作之前。

## PATH 查找

`Cmd.which : String -> ?Path ! {Cmd}` 用于显式 PATH 查找。`cmd` 字面量构造的 Command 在执行时也会进行运行时 PATH 解析（首次解析结果被缓存）。

- 搜索逻辑：按 PATH 中目录顺序遍历，每个目录内检查文件是否存在且可执行（`access(X_OK)`）
- PATH 中不存在的目录静默跳过；非目录条目（如文件）跳过并 stderr warn 记录
- PATH 为空或未设置时使用默认值 `/usr/local/bin:/usr/bin:/bin`
- 符号链接跟随——最终目标的可执行权限决定结果；循环符号链接静默跳过
- 找到返回 `Path`，未找到返回 `Nil`

```kun
let
  result = Cmd.which "docker"
in
  case result of
    Nil -> IO.println "docker not found"
    p   -> IO.println f"docker at {p}"
```

## 类型化模块自动发现

编译器在编译时自动搜索类型化命令模块，搜索路径按优先级：

1. `~/.kun/cmd/<Name>.kun`
2. `$KUN_PATH/cmd/<Name>.kun`
3. `<runtime>/lib/kun/cmd/<Name>.kun`

若找到类型化模块则加载并提供**选项类型检查**；未找到则退回**裸调用**——运行时 PATH 查找二进制 + 选项映射规则。

通过 [`kun cmd init`](kun-cli-tool.md#子命令) 可从 `man`/`--help` 自动生成命令模块骨架。

## `Cmd` 效应与标准库

`Cmd` 是内置保留效应，其签名在标准库以普通 `effect` 声明（详见 [标准库设计](standard-library.md#cmd-命令调用)）：

```kun
// <runtime>/lib/kun/Cmd.kun
export (Cmd, pipe, cmd)

effect Cmd =
  { exec     : Command -> Unit
  , execSafe : Command -> Result (Stream String) CommandError
  , stream   : Command -> Stream String
  , which    : String -> ?Path
  }
```

**handler 实现**在编译器源码（Zig）中，编译进 `kun` 二进制，用户不可见、不可改。用户可在 `main`/`test*` 内用自定义 handler 包装（通过 `continue` 委托默认 Zig 实现）。

```kun
// 用户在 main 内 handle Cmd，用 continue 委托默认实现
loggingCmd : Handler {Cmd} a ! {Cmd, IO}
loggingCmd =
  handler Cmd of
    exec c ->
      let
        IO.eprintln f"[cmd] {c}"
        result = continue (Cmd.exec c)    // 委托内置 exec
      in
        result
    ...
```

## API 签名汇总

```kun
// 字面量语法（编译器内置）
// cmd <命令> <子命令>* <选项>? <位置参数>? : Command

// OS 管道
// [PureKun]
pipe : List Command -> Command

// 修饰函数（均为纯函数，Command -> Command 或类似）
// [PureKun]
withEnv       : Map String String -> Command -> Command
// [PureKun]
withStdin     : String -> Command -> Command
// [PureKun]
withStdin     : Stream Bytes -> Command -> Command
// [PureKun] 从文件路径注入 stdin
withStdinFile : Path -> Command -> Command
// [PureKun]
mergeStderr   : Command -> Command
// [PureKun]
withWorkDir   : Path -> Command -> Command
// [PureKun] 指定子进程执行用户  // [推迟 v1.0]
withRunAs     : String -> Command -> Command
// [PureKun] 关闭 -- 分隔符自动插入
withoutDash   : Command -> Command

// 短路条件组合
// [PureKun]
andThen       : Command -> Command -> Command
// [PureKun]
orElse        : Command -> Command -> Command

// 超时与重试（修饰函数）
// [PureKun]
timeout       : Duration -> Command -> Command  // [推迟 v1.0]
// [PureKun]
retry         : Int -> Duration -> Command -> Command  // [推迟 v1.0]

// Cmd 效应操作（立即执行，需显式调用）
// [Primitive] 执行 Command——fork-exec 阻塞等待，失败 panic，stdout 丢弃
exec          : Command -> Unit ! {Cmd}
// [Primitive] 执行 Command 的安全变体——失败返回 Err，stdout 通过 Stream String 消费
execSafe      : Command -> Result (Stream String) CommandError ! {Cmd}
// [Primitive] 执行 Command，返回 Stream——失败 panic
stream        : Command -> Stream String ! {Cmd}
// [Primitive] PATH 查找命令位置，不可执行/未找到返回 Nil
which         : String -> ?Path ! {Cmd}
```

## 废弃的 API

以下 API 在新设计中废弃，被新机制替代：

| 废弃 | 替代 |
|---|---|
| `Cmd.<bin>` 语法 | `cmd` 字面量 |
| `Cmd[ "g++" ]` 转义 | `cmd "g++"` |
| `Cmd.withRawOpt` | 字符串键（`"-Wall" = true`） |
| `Cmd.pipe?` | `pipe` + `Cmd.execSafe` |
| `Cmd.pipe!` | `pipe` + `Cmd.exec` |
| `?` 后缀（`c?`） | `Cmd.execSafe c` |
| `!` 后缀（`c!`） | `Cmd.exec c` |
| `\|>` 隐式触发 | 显式 `Cmd.stream`/`Cmd.exec`/`Cmd.execSafe` |
| `do`/`do in` | `let in` |

### 迁移示例

```kun
// ❌ 废弃写法
do
  result = Cmd.cat? p"/etc/maybe_missing"
  case result of
    Ok stream -> ...
    Err err -> ...

  Cmd.mkdir! { p = true } p"/tmp/build"

  Cmd["g++"] { o = "a.out" } "main.cpp"
    |> Cmd.withRawOpt "-Wall" Nil
    |> Cmd.withRawOpt "-O2" Nil
    |> Cmd.exec

  Cmd.ls { long = true } p"/tmp"
    |> Stream.lines                  // |> 隐式触发执行

// ✅ 新设计写法
let
  result =
    cmd cat {} [ p"/etc/maybe_missing" ]
      |> Cmd.execSafe

  case result of
    Ok stream -> ...
    Err err -> ...

  cmd mkdir { p = true } [ "/tmp/build" ]
    |> Cmd.exec

  cmd "g++" { o = "a.out", "-Wall" = true, "-O2" = true } [ "main.cpp" ]
    |> Cmd.exec

  lines =
    cmd ls { long = true } [ "/tmp" ]
      |> Cmd.stream
      |> Stream.lines
in
  lines
```

## 与标准库的关系

- [标准库 `Cmd` 模块](standard-library.md#cmd-命令调用)：Cmd 效应签名声明与导入说明
- [系统基线](../architecture/system-baseline.md#命令调用机制)：描述 fork-exec 运行时**实现机制**（系统契约、安全层、内存管理）
- 本文档：定义命令调用的**语法、语义、API 签名与使用机制**

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.07.15 | 重构为代数效应与命令系统设计：Command 改为 ADT（`Simple`/`Pipe`），引入 `cmd` 字面量四段式语法（命令/子命令/选项/位置参数），选项支持标识符键（自动映射）与字符串键（原样）；显式执行三入口（`Cmd.exec`/`Cmd.execSafe`/`Cmd.stream`）+ `Cmd.which`；引入纯函数 `pipe`（替代 `Cmd.pipe?`/`Cmd.pipe!`，最多 16 层，字面量空列表编译错误）；修饰函数新增 `Cmd.withoutDash`（关闭 `--`），`Cmd.withStdin` 添加死锁预防策略；废弃 `Cmd.<bin>` 语法、`Cmd["..."]` 转义、`Cmd.withRawOpt`、`?`/`!` 后缀、`|>` 隐式触发；废弃 `do`/`do in` 改用 `let in` |
| 2026.06.18 | API 精简：`execSafe` 签名从 `Result Unit` 改为 `Command -> Result (Stream String) CommandError`（与 `Cmd.<bin>?` 对齐）；移除 `stdoutToString`/`stderrToString`；新增 `Cmd.<bin>!`/`Cmd.pipe!` 构造语法（断言执行简写） |
| 2026.06.15 | 审计修复三轮：参数转义/execve 语义文档化；0 字节管道输出行为；空 pipe 列表编译期报错；Cmd.which PATH 搜索细节；Cmd.timeout kill 流程；Cmd.retry 边界值处理 |
| 2026.06.15 | 审计修复：`\|>` 管道执行限制为 `do` 块内（效应检查器守卫）；`Cmd.exec` 阻塞语义文档化 |
| 2026.06.14 | `Cmd.withRunAs` 权限降级流程补全：`initgroups` → `setgid` → `setuid` → 验证 |
| 2026.06.14 | 移除 `do` 块语句边界隐式执行规则；新增 `Cmd.exec : Command -> Unit` 显式执行；未被消费的 Command 是编译错误；新增 Command 生命周期示例 |
| 2026.06.13 | API 签名伪语法规范；锚点规范化 |
| 2026.06.12 | 从 `app-overview.md` 和 `system-baseline.md` 中提取命令调用机制为独立文档 |
