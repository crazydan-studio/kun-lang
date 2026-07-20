# OS 命令调用机制

## 定位

Kun 通过 `cmd` 字面量构造 `Command` 值，通过显式执行函数（`Cmd.exec`/`Cmd.execSafe`/`Cmd.streamLines`/`Cmd.streamBytes`）触发 fork-exec。本文件定义 Command 的 ADT 表示、`cmd` 字面量语法、选项映射规则、执行入口与修饰函数。

> **设计原则**（详见 [语法设计](syntax.md) 与新设计总则）：
> - **Command 是 ADT**：`Command` 是普通代数数据类型，`cmd` 字面量是构造 `Command` 的语法糖，无解析器魔法
> - **显式执行**：所有 Command 执行必须显式调用执行函数，**无 Command 的 `?`/`!` 后缀糖**（注：零参函数执行的 `!` 后缀是独立特性，见[语法设计零参效应函数类型](type-system.md#零参效应函数类型-t-e)），**无 `|>` 隐式触发**
> - **`|>` 回归纯管道**：`|>` 统一类型为 `a -> (a -> b) -> b`，对 Command 与 Stream 一视同仁，无双重语义
> - **入口级消解**：`Cmd` 是内置效应（保留名），其默认 handler 在编译器源码（Rust）中实现，编译进 `kun` 二进制；用户可在 `main`/`TestCase.body` 入口级上下文用 `do...with` / `let...in...with` 包装消解

具体的运行时实现细节见[系统基线](../architecture/system-baseline.md#命令调用机制)。

## Command ADT

`Command` 为代数数据类型，支持五变体：`Simple` 单命令、`Pipe` 管道、`Seq` 顺序执行、`OrElse` 失败回退、`Modified` 修饰符包装。`cmd` 字面量构造 `Simple` 变体，`pipe` 纯函数构造 `Pipe` 变体，`Cmd.andThen`/`Cmd.orElse` 构造 `Seq`/`OrElse` 变体，`Cmd.timeout`/`retry`/`withEnv`/等构造 `Modified` 变体。

```kun
type Command =
  Simple SimpleCommand
  | Pipe (List Command)
  | Seq Command Command          // andThen: 前一个成功后执行后一个
  | OrElse Command Command       // orElse: 前一个失败后执行备选
  | Modified Command Modifier    // 修饰符作用于任意 Command（含复合）

type SimpleCommand =
  { name        : String
  , subcommands : List String
  , options     : List OptField
  , args        : List String
  }

type Modifier =
  { env       : ?(Map String String)
  , stdin     : ?StdinSource
  , workDir   : ?Path
  , runAs     : ?String
  , mergeErr  : Bool
  , useDash   : Bool
  , timeout   : ?Duration
  , retry     : ?(Int Duration)
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

**变体语义说明**：

| 变体 | 含义 | 由谁构造 |
|---|---|---|
| `Simple sc` | 单条命令 | `cmd` 字面量 |
| `Pipe cmds` | OS 管道串联（stdout→stdin） | `pipe` 纯函数 |
| `Seq c1 c2` | `c1` 执行**成功**（退出码 0）后执行 `c2` | `Cmd.andThen` |
| `OrElse c1 c2` | `c1` 执行**失败**（退出码非 0）后执行 `c2` | `Cmd.orElse` |
| `Modified c m` | 修饰符 `m` 作用于 `c`（`c` 可为 `Simple`/`Pipe`/`Seq`/`OrElse`/嵌套 `Modified`） | `Cmd.withEnv`/`withStdinStr`/`withWorkDir`/`withRunAs`/`mergeStderr`/`withoutDash`/`timeout`/`retry` |

**修饰符作用于复合命令的语义**：`Modifier` 应用于 `Pipe (List Command)` 时作用于**整个管道**（即每个子命令的执行环境、stdin、工作目录、超时等均统一设置）；应用于 `Seq`/`OrElse` 时作用于**两个分支**。修饰符的 `timeout`/`retry` 字段对 `Pipe` 作用于整个管道执行周期，对 `Seq`/`OrElse` 作用于每次单命令执行。修饰符可嵌套（`Modified (Modified c m1) m2`），外层修饰符叠加于内层之上；同名属性以外层为优先（最后设置的覆盖先前的）。

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

**所有 Command 执行必须显式调用执行函数**，无 Command 的 `?`/`!` 后缀糖（注：零参函数执行的 `!` 后缀是独立特性，见[类型系统 - 零参效应函数类型](type-system.md#零参效应函数类型-t-e)），无 `|>` 隐式触发。

理由：

1. **类型系统纯净**：`|>` 回归标准 `a -> (a -> b) -> b`，无 Command 检测特例
2. **语义统一**：`|>` 统一为纯管道，无"对 Command 隐式执行，对 Stream 纯管道"的双重语义
3. **显式性**：执行意图明确，错误消息清晰（标准类型不匹配，非"隐式触发失败"）
4. **与效应系统一致**：所有效应调用（含 Command 执行）统一显式

### 四个执行入口

```kun
// Cmd 效应操作

// eager 执行：fork+waitpid 阻塞等待，丢弃 stdout/stderr，失败 panic。
// 适用于仅副作用的命令（mkdir/cp）。
Cmd.exec       : Command -> Unit ! {Cmd}

// eager 执行：fork+waitpid 阻塞等待，缓冲全部 stdout 为 String，返回退出码 + stdout + stderr。
// 适用于需错误处理且输出量小的场景。
Cmd.execSafe   : Command -> Result String CommandError ! {Cmd}

// lazy 执行：fork，返回 Stream，逐行消费 stdout。
// 不报告退出码（Stream Drop 时静默 kill+waitpid）。
// 适用于需流式消费 stdout、不关心退出码的场景。
Cmd.streamLines : Command -> Stream String ! {Cmd}

// lazy 执行：fork，返回 Stream，逐字节消费 stdout（二进制）。
// 不报告退出码（Stream Drop 时静默 kill+waitpid）。
// 适用于处理二进制输出（gzip -c、cat image.png）。
Cmd.streamBytes : Command -> Stream Bytes ! {Cmd}

// PATH 查找。
Cmd.which      : String -> ?Path ! {Cmd}
```

#### 四入口语义对比

| API | 求值策略 | 返回类型 | 失败行为 | stdout | stderr |
|---|---|---|---|---|---|
| `Cmd.exec` | eager（fork+waitpid） | `Unit` | panic | 丢弃 | 丢弃 |
| `Cmd.execSafe` | eager（fork+waitpid，缓冲） | `Result String CommandError` | 返回 `Err` | 缓冲为 `String` | 缓冲为 `CommandError.stderr` |
| `Cmd.streamLines` | lazy（fork，逐行） | `Stream String` | silent（不报告） | 逐行 Stream | 与 stdout 合并或丢弃（见死锁预防） |
| `Cmd.streamBytes` | lazy（fork，逐字节） | `Stream Bytes` | silent（不报告） | 逐字节 Stream | 同上 |

> **`CommandError` 包含字段**：`{ exitCode : Int, stdout : String, stderr : String }`。`Cmd.execSafe` 返回 `Result String CommandError`（**不是** `Result (Stream String) CommandError`），即 eager 缓冲全部 stdout 为单一 `String`，调用方拿到 `Ok s` 时 `s` 已是完整字符串。

> **Stream RAII（资源回收）**：`Cmd.streamLines`/`Cmd.streamBytes` 返回的 `Stream` 持有子进程句柄（pid + pipe fd）。当 Stream 被 Drop 时（消费完毕、被显式丢弃、所在 `let in` 块退出），Rust 端 RAII 自动 `kill(pid, SIGTERM)` + `waitpid(pid)` 回收子进程，避免僵尸进程和 fd 泄漏。Kun 借助 Rust RAII 实现此机制，**无需 GC finalizer**。

> **Lazy Stream 不报告退出码**：`Cmd.streamLines`/`Cmd.streamBytes` 设计为"消费即忘"模式——子进程退出码不暴露给调用方。若需根据退出码做决策，使用 `Cmd.execSafe`（eager）。这是 lazy I/O 的常见权衡：要么"惰性 + 不报告退出码"，要么"eager + 缓冲全部输出"。Kun 明确选择**双轨模型**，避免"惰性 + 即时失败检测"的不可调和矛盾。

> **`Cmd.retry` 与 lazy Stream 不兼容**：`Cmd.retry` 修饰符**仅对 eager 入口（`Cmd.exec`/`Cmd.execSafe`）生效**。对 lazy Stream 入口（`Cmd.streamLines`/`Cmd.streamBytes`），retry 不生效——lazy Stream 无法"回放"已消费的数据。若需 retry + 流式，调用方应自行实现：捕获 `execSafe` 的输出后用 `String.lines` 转 Stream，或在外层 `Cmd.orElse` 包装重试逻辑。

### `|>` 的合法用法

`|>` 退化为纯管道操作符，统一类型 `a -> (a -> b) -> b`：

```kun
// Command 修饰（Command -> Command）
cmd ... |> Cmd.withWorkDir p"/build"
cmd ... |> Cmd.mergeStderr
cmd ... |> Cmd.withoutDash

// Command 执行（Command -> 其他类型）
cmd ... |> Cmd.exec          // 执行，丢弃输出
cmd ... |> Cmd.execSafe      // 执行，返回 Result String CommandError
cmd ... |> Cmd.streamLines   // 执行，返回 Stream String（lazy）
cmd ... |> Cmd.streamBytes   // 执行，返回 Stream Bytes（lazy）

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
// Hint: 使用 Cmd.streamLines 执行命令获取输出流：
//       cmd ... |> Cmd.streamLines |> Stream.lines
```

### 典型用法

```kun
// 仅副作用
cmd mkdir { p = true } [ "/tmp/build" ]
  |> Cmd.exec

// 错误处理（eager，输出小）
let
  result =
    cmd cat {} [ p"/etc/maybe_missing" ]
      |> Cmd.execSafe
in
  case result of
    Ok output -> IO.println output          // output : String
    Err e     -> IO.println "not found"

// 输出流处理（lazy，逐行）
let
  lines =
    cmd ls { a } [ "/tmp" ]
      |> Cmd.streamLines
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

`pipe` 构造 `Pipe` ADT 变体，是纯函数。执行需显式调用 `Cmd.exec`/`Cmd.execSafe`/`Cmd.streamLines`/`Cmd.streamBytes`。

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
// 管道执行（错误处理，eager 缓冲）
// result : Result String CommandError ! {Cmd}
result =
  pipe
    [ cmd ps { a } []
    , cmd grep { pattern = "nginx" } []
    ]
    |> Cmd.execSafe

// 管道执行（输出流处理，lazy 逐行）
pipe
  [ cmd ps { a } []
  , cmd grep { pattern = "nginx" } []
  ]
  |> Cmd.streamLines
  |> Stream.toList
```

### Pipe 退出码语义

`Pipe` 执行后，**整体退出码取最后一个命令的退出码**（shell 默认语义）。即 `Cmd.execSafe` 对 `Pipe` 返回 `Ok` 当且仅当最后一个命令退出码为 0；前序命令的非零退出码被忽略（shell 行为）。

```kun
// grep 无匹配返回 1，wc 成功返回 0 → 整体 Ok（shell 默认）
pipe
  [ cmd grep { pattern = "nonexistent" } [ "/etc/passwd" ]
  , cmd wc { l = true } []
  ]
  |> Cmd.execSafe    // Ok "0"
```

> **未来扩展**：可加 `Cmd.pipefail` 修饰符（取第一个非零退出码，类似 bash `set -o pipefail`）。当前 MVP 不实现，调用方需自行检查前序命令的输出（如使用 `Cmd.execSafe` 拆分执行）。

## 修饰函数

修饰函数均为纯函数，接收 `Command` 并返回新 `Command`（构造 `Modified` 变体）：

```kun
Cmd.withEnv        : Map String String -> Command -> Command
Cmd.withStdinStr   : String -> Command -> Command
Cmd.withStdinBytes : Stream Bytes -> Command -> Command
Cmd.withStdinFile  : Path -> Command -> Command
Cmd.withWorkDir    : Path -> Command -> Command
Cmd.withRunAs      : String -> Command -> Command
Cmd.mergeStderr    : Command -> Command
Cmd.withoutDash    : Command -> Command
Cmd.andThen        : Command -> Command -> Command   // 构造 Seq
Cmd.orElse         : Command -> Command -> Command   // 构造 OrElse
Cmd.timeout        : Duration -> Command -> Command
Cmd.retry          : Int -> Duration -> Command -> Command
```

> **`withStdin` 重命名消歧**：旧设计中 `Cmd.withStdin` 有两个同名签名（`String` vs `Stream Bytes`），HM 不支持 ad-hoc overloading。新设计拆分为 `Cmd.withStdinStr`（String 输入）与 `Cmd.withStdinBytes`（Stream Bytes 输入），调用点显式消歧，无 HM 重载歧义。
>
> **关于 `Equal.equal` 等同名多签名 API**：`List.equal`/`Map.equal`/`Set.equal` 等通过**模块限定名**消歧（`List.equal eq xs ys`/`Map.equal ek ev m1 m2`），调用方写模块前缀即可，HM 推断无需特殊处理。这与 `withStdin` 不同——后者参数类型相同（都接受 `Command -> Command`），第一参数类型不同（`String` vs `Stream Bytes`），无法通过模块限定消歧，因此必须重命名。

### `Cmd.withStdin*` 死锁预防策略

父进程同时向子进程 stdin 写入并读取 stdout/stderr 时，存在管道缓冲区满死锁风险。Kun 采用单线程非阻塞 poll 策略：

1. stdout 与 stdin 与 stderr 共享同一 `poll` 事件循环
2. **优先读 stdout 与 stderr**（清空缓冲给子进程空间，再尝试推送 stdin）
3. stdin 非阻塞写入，`EAGAIN` 时转向读 stdout/stderr
4. stdin 写尽后 `close(fd)` 关闭写端（注：管道 fd 应使用 `close(2)`，**不**使用 `shutdown(2)`——`shutdown` 仅适用于 socket，对 pipe 行为未定义）
5. 不引入额外线程（保持单线程语义）
6. 输入超过 1MB 时推荐用 `Cmd.withStdinBytes`（Stream Bytes）模式

> **stderr 死锁预防**：当 `mergeStderr = false` 时（合理默认），stderr 是独立管道。Kun **始终读取 stderr**（独立 pipe + poll），避免子进程向 stderr 写入超过 64KB（Linux pipe 缓冲区）而父进程不读取导致的死锁。任何产生大量 stderr 的命令（`gcc` 编译警告、`find /` 权限错误）在 `mergeStderr = false` 下都不会挂起。
>
> **`mergeStderr = true` 时的行为**：stderr 重定向到 stdout 管道（子进程端 `dup2(stderr_fd, stdout_fd)`），父进程只读单一管道，stderr 内容混入 stdout 流。`Cmd.execSafe` 的 `CommandError.stderr` 字段为空字符串（已合并入 stdout）；`Cmd.streamLines` 的 Stream 包含 stderr 行。

> **SIGPIPE 处理**：SIGPIPE 在启动阶段设置为 `SIG_IGN`（详见 [系统基线](../architecture/system-baseline.md) SIGPIPE 处理）。父进程向子进程 stdin 写入时，若子进程已退出（如 `head -n 1` 读取大输入后退出），`write(2)` 返回 `EPIPE` 错误而非触发 SIGPIPE。Kun 端将 `EPIPE` 转换为常规 I/O 错误（`CommandError` 的 `Err` 分支），不导致父进程崩溃。这是管道场景中最常见的崩溃源之一，Kun 默认安全。

### 工作目录

Kun **不提供全局 `cd`** 或 `chdir`。`Cmd.withWorkDir : Path -> Command -> Command` 指定每个子进程独立的工作目录（fork 后、exec 前 `chdir`）。父进程 CWD 在脚本启动时冻结为 `File.currentDir`，不可变——需使用相对路径的场景通过 `Path.resolve` 基于 `File.currentDir` 转为绝对路径后显式传递，或对各命令使用 `Cmd.withWorkDir` 隔离设置。

```kun
do
  cmd ls {} [] |> Cmd.exec                                  // CWD = File.currentDir

  cmd tar { c = true, f = "backup.tar" } [ "." ]
    |> Cmd.withWorkDir p"/build/output"
    |> Cmd.exec                                          // 仅此子进程 CWD = /build/output

  cmd ls {} [] |> Cmd.exec                                  // CWD 仍为 File.currentDir
```

需要跨多个命令使用同一 CWD 时，用变量绑定：

```kun
do
  workDir = p"/build/output"

  cmd tar { c = true, f = "backup.tar" } [ "." ]
    |> Cmd.withWorkDir workDir |> Cmd.exec

  cmd ls { a = true } []
    |> Cmd.withWorkDir workDir |> Cmd.exec
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
do
  cmd docker build { tag = "app" } [ "." ]
    |> Cmd.andThen (cmd docker push {} [ "app:latest" ])
    |> Cmd.exec

  cmd ping { c = 3 } [ "192.168.1.1" ]
    |> Cmd.orElse (cmd echo {} [ "unreachable" ])
    |> Cmd.exec
```

`Cmd.andThen` / `Cmd.orElse` 返回 `Command`（延迟执行），不立即 fork。不引入 `&&`/`||` 运算符以避免与逻辑短路运算符冲突。

### 超时与重试：`Cmd.timeout` / `Cmd.retry`

`Cmd.timeout` 与 `Cmd.retry` 是**修饰函数**（纯操作），构造 `Modified` 变体。执行需配合 `Cmd.exec`/`Cmd.execSafe`（**不**支持 `Cmd.streamLines`/`Cmd.streamBytes`，详见上文 retry 与 lazy Stream 不兼容说明）：

```kun
// Cmd.timeout : Duration -> Command -> Command
// Cmd.retry   : Int -> Duration -> Command -> Command

let
  result =
    cmd curl {} [ "https://example.com" ]
      |> Cmd.timeout 5s
      |> Cmd.execSafe
in
  case result of
    Ok output -> IO.println output         // output : String（eager 缓冲）
    Err err   -> IO.println "request timed out"

let
  result2 =
    cmd curl {} [ "https://example.com" ]
      |> Cmd.retry 3 1s
      |> Cmd.execSafe
in
  case result2 of
    Ok output -> IO.println output
    Err err   -> IO.println "request failed after 3 retries"
```

`Cmd.retry` 内部调用 `Cmd.timeout`，每次重试独立 fork 子进程。失败时重试 `n` 次，全部失败后返回最后一次 `Err`。

`Cmd.timeout` 超时时：向子进程发送 `SIGTERM` → 等待 2 秒 → 若进程未退出则发送 `SIGKILL` → `waitpid` 回收。子进程在超时前的部分 stdout 输出不保留（`Result` 的 `Err` 分支的 `stdout` 字段为空字符串）。超时错误通过 `CommandError.Timeout` 变体返回。

`n = 0` 时等同于调用 `Cmd.timeout duration command`（仅执行一次，不重试）。`n < 0` 时编译期报错。

#### 时钟源

`Cmd.timeout` 使用 `CLOCK_MONOTONIC` 作为计时时钟源（通过 `timerfd_create` 实现，Linux 3.17+；低于 3.17 回退到 `clock_gettime(CLOCK_MONOTONIC, ...)` 轮询）。选择 `CLOCK_MONOTONIC` 而非 `CLOCK_REALTIME` 的原因：

- `CLOCK_REALTIME` 受 NTP 时间同步和系统管理员手动修改影响——时间向前跳变可能导致超时提前触发，时间向后跳变（闰秒、NTP 回拨）可能导致超时无限延长
- `CLOCK_MONOTONIC` 单调递增且不受外部时间调整影响，确保超时语义的确定性
- 与 Kun 的安全设计原则一致：运行时行为不因环境（NTP 配置、时钟调整）产生不可预期的差异

#### 修饰函数链式组合顺序

修饰函数通过 `|>` 链式应用时按从左到右的顺序累积属性（构造嵌套的 `Modified` 变体），最终由 `Cmd.exec`/`Cmd.execSafe`/`Cmd.streamLines`/`Cmd.streamBytes` 触发 fork：

```kun
do
  cmd someCmd {} [ dir ]
    |> Cmd.withWorkDir p"/work"        // 1. 设置工作目录
    |> Cmd.withRunAs "appuser"         // 2. 设置执行用户
    |> Cmd.timeout 5s                  // 3. 设置超时
    |> Cmd.exec                        // 4. fork → chdir → setuid → exec
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

`Cmd` 是内置保留效应，其签名在标准库以普通 `effect` 声明（详见 [标准库设计](standard-library.md#cmd-command-工具与命令调用)）：

```kun
// <runtime>/lib/kun/Cmd.kun
export (Cmd, pipe, cmd, withEnv, withStdinStr, withStdinBytes, withStdinFile, mergeStderr, withWorkDir, withRunAs, withoutDash, andThen, orElse, timeout, retry)

effect Cmd =
  { exec        : Command -> Unit
  , execSafe    : Command -> Result String CommandError
  , streamLines : Command -> Stream String
  , streamBytes : Command -> Stream Bytes
  , which       : String -> ?Path
  }
```

**handler 实现**在编译器源码（Rust）中，编译进 `kun` 二进制，用户不可见、不可改。用户可在 `main`/`TestCase.body` 内用自定义 handler 包装（通过 `continue` 委托默认 Rust 实现）。

```kun
// 用户在 main 内消解 Cmd（do...with / let...in...with），用 continue 委托默认实现
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
withEnv        : Map String String -> Command -> Command
// [PureKun] 字符串 stdin（小输入）
withStdinStr   : String -> Command -> Command
// [PureKun] Stream Bytes stdin（大输入）
withStdinBytes : Stream Bytes -> Command -> Command
// [PureKun] 从文件路径注入 stdin
withStdinFile  : Path -> Command -> Command
// [PureKun] stderr 合并入 stdout
mergeStderr    : Command -> Command
// [PureKun]
withWorkDir    : Path -> Command -> Command
// [PureKun] 指定子进程执行用户
withRunAs      : String -> Command -> Command
// [PureKun] 关闭 -- 分隔符自动插入
withoutDash    : Command -> Command

// 短路条件组合（构造 Seq / OrElse 变体）
// [PureKun]
andThen        : Command -> Command -> Command
// [PureKun]
orElse         : Command -> Command -> Command

// 超时与重试（修饰函数，构造 Modified 变体）
// [PureKun]
timeout        : Duration -> Command -> Command
// [PureKun]
retry          : Int -> Duration -> Command -> Command

// Cmd 效应操作（立即执行，需显式调用）
// [Primitive] 执行 Command——fork-exec 阻塞等待，失败 panic，stdout/stderr 丢弃
exec           : Command -> Unit ! {Cmd}
// [Primitive] 执行 Command 的安全变体——eager 缓冲全部 stdout 为 String，返回退出码 + stdout + stderr
execSafe       : Command -> Result String CommandError ! {Cmd}
// [Primitive] 执行 Command，返回 Stream String（逐行 stdout，lazy，不报告退出码）
streamLines    : Command -> Stream String ! {Cmd}
// [Primitive] 执行 Command，返回 Stream Bytes（逐字节 stdout，lazy，不报告退出码）
streamBytes    : Command -> Stream Bytes ! {Cmd}
// [Primitive] PATH 查找命令位置，不可执行/未找到返回 Nil
which          : String -> ?Path ! {Cmd}
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
| `\|>` 隐式触发 | 显式 `Cmd.streamLines`/`Cmd.exec`/`Cmd.execSafe` |
| `Cmd.stream` | `Cmd.streamLines`（或 `Cmd.streamBytes` 处理二进制） |
| `Cmd.withStdin`（双签名重载） | `Cmd.withStdinStr` / `Cmd.withStdinBytes`（拆分消歧） |
| `do in`（返回值形式） | `let <body> in <expr>`（`do <body>` 保留为返回 `Unit` 的语法糖，≈ `let <body> in ()`） |

### 迁移示例

```kun
// ❌ 旧式写法（已废弃）
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
in
  case result of
    Ok output -> ...                    // output : String
    Err err   -> ...

cmd mkdir { p = true } [ "/tmp/build" ]
  |> Cmd.exec

cmd "g++" { o = "a.out", "-Wall" = true, "-O2" = true } [ "main.cpp" ]
  |> Cmd.exec

lines =
  cmd ls { long = true } [ "/tmp" ]
    |> Cmd.streamLines
    |> Stream.toList
```

## 与标准库的关系

- [标准库 `Cmd` 模块](standard-library.md#cmd-command-工具与命令调用)：Cmd 效应签名声明与导入说明
- [系统基线](../architecture/system-baseline.md#命令调用机制)：描述 fork-exec 运行时**实现机制**（系统契约、安全层、内存管理）
- 本文档：定义命令调用的**语法、语义、API 签名与使用机制**

