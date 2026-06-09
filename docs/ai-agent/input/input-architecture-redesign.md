# 输入记录：Kun 语言架构重设计方案

## 来源

项目维护者 — 架构评审与深度讨论

## 日期

2026-06-08

## 状态

📋 讨论中。本文档为 `docs/ai-agent/input/` 中的原始输入记录，后续需在 `docs/ai-agent/discussions/` 中发起讨论，在 `docs/ai-agent/requirements/` 中综合为结构化需求。

---

## 原始动机

经过对原方案从以下维度的深度评审：
- **实现可行性**（Zig 视角）：约 50,000+ 行预估代码量、HM + Monadic IO + 幻影类型 + 编译器代码生成 的复杂度不可控
- **安全纵深防御**：`capability_check` 与沙箱层的矛盾、seccomp 路径过滤盲区、Landlock 内核版本依赖
- **性能与资源**：Stream 函数指针链开销、Arena 无增量回收、大 Record 拷贝
- **用户模型**：Shell 开发者面对 HM 推断 + Monadic IO + 幻影类型 + Builder API 的陡峭学习曲线

决定对 Kun 进行一次**根本性简化**：保留类型安全和表达式导向的核心优势，砍掉 Monadic IO 效应系统、`.cmd.kun` 编译器代码生成、能力声明等过度设计层。

---

## 设计概要

### 一、保留的核心设计

以下原方案组件**完整保留**，不改动：

| 组件 | 保留理由 |
|------|---------|
| HM 类型推断 + 约束生成 + Martelli-Montanari 合一 | 类型安全是 Kun 相对于 Bash 的核心价值。错误信息应优先报告源码位置和变量名，类型变量术语降级为补充信息 |
| ADT（和类型）+ 穷举检查 | 结构化错误处理的基础 |
| 模式匹配（变体/List/元组/Record/守卫子句） | 表达能力远超 Shell |
| Record / Tuple / List / Map / Set | 结构化数据优于文本解析 |
| 模块系统（`module export` + `import with`） | 真正的代码复用 |
| Lambda + 高阶函数 + `\|>` `<\|` `>>` `<<` | 函数式管道组合 |
| strict evaluation + let lazy binding | 可预测的执行语义 |
| `?T` nilable + `??` + `?.` | 比 null 安全 |
| Path 字面量 `p"..."` / Regex 字面量 `r"..."` / f-string | 表达力 |
| 标准库类型（Port, Pid, Signal, ExitCode, DateTime, FileStat, DirEntry 等） | 类型化系统接口 |
| `Signal.on`（signalfd 机制） | 信号处理 |

### 二、移除的组件及替代方案

| 移除 | 替代方案 | 原因 |
|------|---------|------|
| `IO T` 效应类型 | AST 标记：含 `do` 块的函数自动标记为效应函数。纯函数不能调用效应函数，编译期检查 | ~2000-3000 行类型检查器扩展 → ~200 行 AST 遍历 |
| `do`/`<-`/`<-!` Monadic 语法 | `do`/`do in` 退化为纯执行顺序保证，不含 IO 类型信息。`<-` / `<-!` / `=!` 移除 | 用户不需要理解 bind 和 Monad |
| `.cmd.kun` 模块体系 | 完全移除。命令通过 `Cmd.<bin>` / `Cmd["..."]` 直接调用。不存在 `.cmd.kun` 文件格式、`command` 声明、Builder API、幻影类型、注册中心等 | 零实现成本，用户无需学习第二套 DSL |
| `with caps` 能力声明 | CLI 参数：`--allow-path /tmp --allow-net` | 安全策略与代码分离，运行时更灵活 |
| `Nat` 类型 | `Int` + 运行时范围检查 | 减少类型系统复杂度，移除 `42u` 字面量 |
| `Stream`（函数指针 `{state, next, destroy}`） | `Stream` 作为 tagged union，将双层间接调用降为单层；编译期已知的变换链可通过 Zig comptime 融合为单循环消除全部中间开销 | 消除闭包链开销，实现简单 |
| `=!` / `<-!` 早返回 | 命令默认 panic（结构化错误信息），显式错误处理用 `Cmd.<bin>?` 后缀 | 安全默认 vs 类型体操 |
| `stdin` 关键字 | `Cmd.stdin : String -> Command -> Command` 普通函数 | 减少关键字 |
| `module` / `export` 在可执行脚本中 | 可执行脚本不声明 `module`，直接定义 `main : Unit` | 简化最小脚本的启动摩擦 |

> 注：移除上述组件后，以下现有文档细节也一并失效——`syntax.md:38` 的 `Nat` 字面量 `42u`；`standard-library.md` 中函数签名里的 `IO` 类型标记（`now : IO DateTime`、`sleep : Duration -> IO Unit` 等）改为无 IO 标记的 `Std` 模块签名；`project-vision.md:39` 的 dlopen 实现策略；`code-formatting.md` 文件级声明顺序中的 `with caps` 和 `command` 声明。

### 三、命令调用：`Cmd.<bin>`

#### 语法

```kun
Cmd.<bin> [#{ envVars }] [{ options }] [posArgs...]
```

- `#{ "KEY" = "value" }`（Map String String）→ 子进程环境变量，完全替换继承的白名单
- `{ field = value }`（Record）→ 命令选项，camelCase 字段名自动映射为 kebab-case flag
- 其余表达式 → 位置参数，按顺序追加到 argv 末尾

#### camelCase → kebab-case 自动映射

| Kun Record 字段 | CLI flag | 示例命令 |
|----------------|---------|---------|
| `{ maxCount = 50 }` | `--max-count 50` | `Cmd.git.log { maxCount = 50 } "main"` |
| `{ oneline = true }` | `--oneline` | — |
| `{ l = true }` | `-l`（单字符） | `Cmd.ls { l = true }` |
| `{ humanReadable = true }` | `--human-readable` | `Cmd.df { humanReadable = true }` |
| `Bool = false` | 省略不传 | — |
| `Int` / `String` / `Path` | `--key value` | — |
| `List a` | `--key v1 --key v2` | `Cmd.docker.run { publish = ["80:80", "443:443"] }` |
| `Nil` | 省略不传 | — |

#### 环境变量

```kun
// 缺省：干净白名单（PATH/HOME/USER/TERM/LANG/PWD/SHELL/TZ）
Cmd.ls { long = true }

// 逐命令覆盖
Cmd.node #{ "NODE_ENV" = "production" } { maxOldSpaceSize = 4096 } "server.js"

// 极端安全：空环境
Cmd.untrusted_tool #{ } {}

// CLI 全局策略：
//   kun --env=inherit  → 完全继承
//   kun --env=none     → 完全空环境
```

始终剔除列表（`LD_PRELOAD`、`LD_AUDIT`、`LD_DEBUG`）无论策略如何永不传递。

#### 子命令

```kun
Cmd.git.log { maxCount = 50 } "main"
Cmd.git.commit { m = "Init" }
Cmd.docker.container.ls { all = true }
```

`Cmd.git.log` 中的 `.` 链："docker.container.ls" 作为一个整体——运行时在 PATH 中搜索 `docker`，然后传递子命令 `container` `ls` 作为 argv 前置参数：`exec("docker", ["container", "ls", "--all"])`。

#### 特殊字符命令名的兜底语法

`Cmd.<bin>` 要求命令名是合法 Kun 标识符。对于含 `-`、`.`、`+` 或数字开头的命令，使用 `Cmd["..."]` 转义：

```kun
Cmd["ntfs-3g"] { force = true } "/dev/sda1"
Cmd["7z"] { x = true } "archive.7z"
Cmd["g++"] { Wall = true, o = "a.out" } "main.cpp"
Cmd["a-b.c"]["d-a"] { flag = true }          // 含子命令的特殊字符命令
```

`Cmd["<bin>"]` 与 `Cmd.<bin>` 生成完全相同的 argv，编译器不做区分。对于含子命令的特殊字符命令，使用连续 `["..."]` 链式导航，与 `.` 链等价。

#### 类型化选项的渐进路线

| 层级 | 方案 | 类型安全 | 示例 |
|------|------|---------|------|
| 第 0 层 | 无定义，字面量 Record | 字段名即时检查，推断字段类型 | `Cmd.ls { long = true }` |
| 第 1 层 | 命名类型引用 | 跨调用一致性 | `type LsOpts = { long : Bool }; Cmd.ls opts` |
| 第 2 层 | 社区模块 | IDE 自动补全 + 文档 | `import Cmd.Git; Git.log { maxCount = 50 }` |

裸调用 `Cmd.git.log` 和 `import Cmd.Git` 两种方式共存：
- 裸 `Cmd.git.log` → 运行时在 PATH 中动态查找 `git` 二进制，camelCase 映射，无类型信息（第 0 层）
- `import Cmd.Git; Git.log` → 社区维护的类型化模块，内部调用 `Cmd.git.log`，提供类型化选项 Record（第 2 层）

#### PATH 查找

`Cmd.<bin>` 的命令查找发生在**运行时**（每次调用时解析 PATH），而非编译期。编译时不检查命令是否存在——机器 A 上编译的脚本可在机器 B 上运行。若运行时命令未找到，触发 `NotFound` panic。首次 PATH 解析成功后结果被缓存（尊重运行时的 `PATH` 环境变量变化，每次 `do` 块入口刷新），后续调用无需重复搜索。如需编译期检查：`kun check --resolve-cmds` 命令。

### 四、管道

#### OS 管道：`=>`

连接两个 `Cmd.*` 调用，编译为 `pipe2()` + 两次 `fork()`：

```kun
Cmd.ps { aux = true } => Cmd.grep { pattern = "nginx" } => Cmd.head { n = "10" }
```

- 默认：链中任一命令非零退出 → panic（等价 `set -o pipefail`）
- 错误处理：在链的**终点命令**上加 `?` 后缀，链中任一命令失败 → 返回 `Err` 而非 panic
- Fork 时机：`=>` 链中的所有子进程在链被消费时**同时 fork**（通过 pipe2 级联连接），利用 OS 管道缓冲区实现并发执行。消费端阻塞在终点命令的 stdout pipe 上
- `?` 设计理由：管道命令之间语义依赖——`grep` 失败时上游数据已流向它，单独恢复某个中间命令缺乏实际意义。需要独立错误处理时，拆分为单独命令调用：
  ```kun
  r1 = Cmd.cat? p"x"
  case r1 of
    Ok data -> Cmd.grep { pattern = "y" } |> Cmd.stdin (Stream.string data)
    Err e   -> // 处理 cat 失败
  ```

#### 进程内管道：`|>`

`|>` 左侧是 `Stream String`，右侧是纯函数变换，不创建子进程：

```kun
Cmd.cat p"/var/log/app.log"
|> Stream.lines               // Stream String，惰性按行切分
|> Stream.filter (\l -> String.contains "ERROR" l)
|> Stream.map parseLine       // Stream LogEntry
|> Stream.take 100
|> Stream.toList              // 终端：触发消费
```

#### 交叉流向

```
OS 管道 (=>)                     进程内管道 (|>)
  ──────────────────              ─────────────────
  fork 子进程，fd 直连             内存变换，惰性
  产出 Stream String              Stream a → Stream b
  ──────────────────              ─────────────────
         │                                │
         └────────── 单向 ───────────────→│
                  从 OS 到进程内           │
                                          │
         从进程内回 OS：显式 Cmd.stdin     │
         ┌──────────────────────────────┘
```

```kun
// 单向自然流向
Cmd.ps {} => Cmd.grep {} |> Stream.lines |> Stream.toList

// 回 OS 管道：显式 Cmd.stdin 函数
fileList = Cmd.find {} |> Cmd.exec |> Stream.string
Cmd.tar { cf = "archive.tar" } |> Cmd.stdin fileList |> Cmd.exec
```

`Cmd.stdin` 的类型为 `String -> Command -> Command`：接收序列化后的 stdin 内容和目标 Command，返回注入了 stdin 的新 Command。

`Cmd.mergeStderr : Command -> Command` 将子进程的 stderr 合并到 stdout pipe 中——等价于 Bash 的 `2>&1`。典型场景：日志聚合脚本中同时捕获正常输出和错误输出进行统一过滤。

> **`Cmd.stdin` 流式扩展点**：目前仅支持 `String` 输入——整个 stdin 内容须先完整读入内存。v0.2 预留 `Stream a -> Command -> Command` 签名扩展以支持大文件流式传入。

`Cmd.exec` 的语义：`Command` 类型的值作为 `|>` 左操作数时**自动隐式触发 exec**（编译器通过类型检查确定）。**同一 `Command` 值被多次消费是编译错误**（而非 lint 警告）。`Cmd.exec` 显式调用仅在实际不需要 `|>` 链变换时使用。

#### `Cmd.exec` 正式契约

```
Cmd.exec 的契约:
  输入:   Command 值（由 Cmd.<bin> + 选项 + Cmd.stdin 构造）
  动作:   fork → chdir 到逻辑 CWD（子进程内） → setrlimit → exec → waitpid
  返回:   Stream String（无 ?）或 Result (Stream String) CommandError（有 ?）
  stdout: 通过 pipe 捕获，返回为 Stream String
  stderr: 见「错误处理」章节 stderr 行为矩阵
  stdin:
    - 若通过 Cmd.stdin 注入 → 序列化写入子进程 stdin pipe 后关闭写端
    - 若处于 => 管道链中 → 来自前一命令的 stdout pipe（stdin fd 直接继承）
    - 否则 → stdin 继承父进程（通常为 /dev/null 或外部管道）
```

`Cmd.stdin` 与 Kun 原生多行字符串 `"""..."""` 组合可覆盖 Bash here-document 场景，无需新增语法：

```kun
Cmd.mysql { u = "root" }
  |> Cmd.stdin """
    CREATE DATABASE mydb;
    GRANT ALL ON mydb.* TO 'user'@'localhost';
    """
  |> Cmd.exec
```

### 五、Stream 设计

> Stream 采用 tagged union 代替函数指针 `{state, next, destroy}`，将双层间接降为单层（`switch(tag)` 替代 `fn_ptr` 调用）。编译期已知的 `map`/`filter`/`take` 变换链可通过 Zig comptime 融合为单循环。已读取的管道数据不在内存中产生额外副本——缓冲区（8KB）+ 当前元素 + 终端累积结果。

简化为固定结构体，无函数指针：

```zig
const Stream = union(enum) {
    cmd: struct { fd: i32, pid: i32, buf: [4096]u8 },
    mapped: struct { upstream: *Stream, f: FnPtr },
    filtered: struct { upstream: *Stream, pred: FnPtr },
    taken: struct { upstream: *Stream, remaining: usize },
};
```

终端操作：

```kun
Stream.lines   : Stream String                    // 按 \n 切分
Stream.string  : Stream String -> String           // 全文收集
Stream.map     : (a -> b) -> Stream a -> Stream b  // 惰性变换
Stream.filter  : (a -> Bool) -> Stream a -> Stream a
Stream.take    : Int -> Stream a -> Stream a
Stream.toList  : Stream a -> List a                // 终端
Stream.iter    : (a -> Unit) -> Stream a -> Unit    // 终端
Stream.fold    : (b -> a -> b) -> b -> Stream a -> b // 终端
Stream.parseMap   : (a -> Result b e) -> Stream a -> Stream b    // 跳过失败
Stream.parseMap?  : (a -> Result b e) -> Stream a -> Stream (Result b e) // 保留 Result
Stream.bytes      : Stream a -> Bytes                    // 终端：二进制安全读取
```

#### 纯/效应操作分类

| 操作 | 类别 | 说明 |
|------|------|------|
| `Stream.map` / `Stream.filter` / `Stream.take` | **纯** | 惰性变换，不触发 IO，纯上下文中可用 |
| `Stream.parseMap` / `Stream.parseMap?` | **纯** | 同上 |
| `Stream.lines` | **纯** | 仅标记换行边界，不触发读取 |
| `Stream.toList` / `Stream.iter` / `Stream.fold` | **效应** | 终端操作，触发 pipe 读取 + waitpid，仅 `do` 块可用 |
| `Stream.string` / `Stream.bytes` | **效应** | 终端操作，全文/二进制收集，仅 `do` 块可用 |
| `Stream.fromList` | **纯** | 从纯 List 构造 Stream，无 IO 绑定 |

> `Stream.lines` 期望文本输入——对二进制数据（如 `Cmd.cat p"/bin/ls"`）按 `\n` 切分可能导致整文件落入单条"行"，造成大内存分配。二进制数据使用 `Stream.bytes`。运行时检测：读取前 4KB 若非合法 UTF-8 则 panic 并提示使用 `Stream.bytes`。`Cmd.*` 的 stdout 管道构造时设置 `O_NONBLOCK`。

### 六、`do` 块与效应函数

#### 规则

1. `Cmd.*` 和 Stream 终端操作只能在 `do` 块中调用
2. 含 `do` 块的函数自动标记为效应函数（编译器 AST 标记，不扩展 HM）
3. 效应函数调用效应函数 → 调用者也必须在 `do` 块中
4. 纯函数（无 `do` 块）不能调用效应函数 → 编译期拒绝
5. Lambda 含有 `Cmd.*` 或效应函数调用时，该 lambda **必须在 `do` 块内定义**。定义为效应 lambda 后可作为参数传递给纯高阶函数（调用点已在 `do` 块内，执行上下文安全）
6. 外层 `do` 块的效应上下文自动传播到 `if`/`case` 的每个分支——分支中可直接调用 `Cmd.*`，无需显式嵌套 `do`。嵌套 `do` 仅在分支需要独立 `defer` 作用域时使用

#### 语法

```kun
// do 无 in：返回最后一个表达式的类型
main : Unit
main =
  do
    Std.println "deploying..."
    Cmd.rsync { archive = true, verbose = true } "src/" "dst/"

// do in：执行副作用后返回纯值
countFiles : Path -> Int
countFiles = \dir ->
  do
    entries = Cmd.ls { all = true } dir |> Stream.lines |> Stream.toList
  in
    List.length entries
```

#### 编译错误信息设计

效应检查的编译错误应面向 Shell 用户的可读性，而非类型理论术语：

```
错误: Cmd.ls 只能在 do 块中调用
  ┌─ helper.kun:5:3
5 │   Cmd.ls { long = true }
  │   ───────────┬──────────
  │              ╰── 此处调用了需要执行环境的命令
  │
  修复: 将调用处包裹在 do 块中，或将 helper 函数的定义体改为 do 块
```

```
错误: 效应泄漏
  ┌─ lib.kun:5:3
5 │   Cmd.ls {} dir |> Stream.lines |> Stream.filter pred
  │   ────────────────────────────────────────────────────
  │   ╰── 函数 'filterFiles' 调用了 Cmd.ls，但函数体不在 do 块中
  │
  修复: filterFiles = \dir pred ->
            do
              Cmd.ls {} dir |> Stream.lines |> Stream.filter pred
```

### 七、错误处理：默认 panic + 可选 Result

#### 默认模式

```kun
do
  Cmd.cat p"/etc/nonexistent"
// panic: CommandFailed { command: "cat", exitCode: 1, stderr: "cat: /etc/nonexistent: No such file or directory" }
```

#### 显式错误处理：`?` 后缀

`?` 放在命令名（或子命令链的末端）之后，使该命令返回 `Result` 而非 panic：

```kun
Cmd.git.log?        // 单个命令，? 放在命令名后
Cmd["ntfs-3g"]?     // 特殊字符命令，? 在 ] 之后
Cmd.cat? p"/etc/maybe_missing"

Cmd.cat p"log.txt" => Cmd.grep? "error"   // OS 管道链，? 在终点命令上
```

对于 `=>` 管道链，`?` 放在链的**终点命令**上，作用于整条链——链中任一命令失败，整链返回 `Err`。

`?` 命令的返回类型为 `Result (Stream String) CommandError`（对比：不带 `?` 返回 `Stream String`，失败时 panic）。

```kun
do
  result = Cmd.cat? p"/etc/maybe_missing"
  case result of
    Ok stream -> stream |> Stream.lines |> Stream.toList
    Err (CommandFailed { exitCode, stderr }) ->
      Std.println f"cat failed ({exitCode}): {stderr}"
      Std.exit 1
    Err (NotFound cmd) ->
      Std.println f"command not found: {cmd}"
      Std.exit 127
```

#### 语义化错误类型

```kun
type CommandError
  = NotFound String              // ENOENT
  | PermissionDenied String      // EACCES/EPERM（无法执行二进制）
  | CommandFailed                // 退出码 ≠ 0
      { command  : String
      , exitCode : Int
      , stderr   : String        // 完整 stderr 输出
      }
  | KilledBySignal               // 被信号终止
      { command : String
      , signal  : Int
      }
  | IoError String               // 管道/socket 创建失败
  | PipeFailed                   // OS 管道链中某命令失败
      { commands  : List String  // 管道链中按序的命令名列表
      , failedAt  : Int          // 哪个命令失败（0-based）
      , error     : CommandError // 具体失败原因（含该命令的 exitCode 和 stderr）
      }
```

#### stderr 默认行为

| 场景 | stderr 行为 |
|------|------------|
| 命令成功（exit 0） | 透传到父进程 stderr——用户实时看到进度/诊断输出 |
| 命令失败（exit ≠ 0，无 `?`） | panic 消息中显示完整 stderr |
| 命令失败（exit ≠ 0，有 `?`） | `CommandFailed.stderr` 包含完整 stderr |
| OS 管道链中某命令失败 | 触发 `PipeFailed`，各命令 stderr 透传到父进程 |

#### panic 语义

panic 触发 unwind 时，当前 `do` 块的所有 `defer` 按 LIFO 逆序**始终执行**。若 `defer` 块自身也 panic，原始 panic 与 `defer` panic 合并输出（原始原因优先，`defer` 失败作为附加信息）：

```
panic: cat: /etc/nonexistent: No such file or directory
  also: cleanup failed: permission denied removing /tmp/tempfile
```

未捕获的顶层 panic 退出码与 Unix 惯例对齐：

| 错误变体 | Kun 进程退出码 |
|---------|-------------|
| `CommandFailed { exitCode = n }` | `n`（传播子进程退出码） |
| `NotFound _` | 127 |
| `PermissionDenied _` | 126 |
| `KilledBySignal { signal = s }` | `128 + s` |
| `IoError _` | 1 |
| 用户调用 `Std.exit n` | `n` |

### 八、`Std` 模块（内建，缺省自动导入）

```kun
// 输出
Std.print    : String -> Unit
Std.println  : String -> Unit

// 输入（从 stdin fd 0 读取，管道输入自动可用）
Std.readln   : Unit -> String

// CWD
Std.cd       : Path -> Unit
Std.cwd      : Unit -> Path

// 目录栈
Std.pushd    : Path -> Unit
Std.popd     : Unit -> Unit

// 环境变量（直接修改当前进程环境，所有后续 fork 的子进程继承）
Std.getenv   : String -> ?String
Std.setenv   : String -> String -> Unit
Std.unsetenv : String -> Unit

// 进程控制
Std.exit     : Int -> Unit
Std.pid      : Unit -> Int

// 时间
Std.sleep    : Duration -> Unit
Std.now      : Unit -> DateTime

// 脚本参数（来自 -- 之后的部分）
Std.args     : Unit -> List String

// 超时
Std.timeout  : Duration -> Command -> Result (Stream String) CommandError

// 重试（Kun 标准库函数，约 15 行，内部调用 Std.timeout）
retry : Int -> Duration -> Command -> Result (Stream String) CommandError

// 命令可用性
Cmd.which : String -> ?Path                 // 运行时 PATH 查找 → ?Path，Nil=未找到
```

逻辑 CWD：`Std.cd` 更新运行时维护的逻辑 CWD。fork 子进程时，在 `exec` 前 `chdir` 到此值。Kun 进程的 OS CWD 始终不变。

外部管道输入（`echo "hello" | kun script.kun`）自动可用——`Std.readln` 从 stdin（fd 0）读取，脚本启动时若 `isatty(0) == 0` 则按管道/文件处理。

`Std.setenv` 直接修改当前 Kun 进程环境（`setenv(3)`），沙箱（Landlock/mount namespace）不限制 `setenv`——仅限制文件系统和网络。

#### 内建类型化命令（种子生态）

为打破"需要社区 → 社区需要流行 → 流行需要社区"的三重死锁，以下命令以 syscall 直接实现，无需 fork 子进程，提供类型化输出：

```kun
// 文件信息（fstat / getdents64）
Std.ls     : Path -> Stream { name : String, size : Int, fileType : FileType }
Std.stat   : Path -> Result FileStat IOError

// 进程信息（procfs / sysinfo）
Std.ps     : Unit -> Stream { pid : Pid, cmd : String }
Std.free   : Unit -> { total : Int, used : Int, free : Int }
Std.df     : Path -> { fs : String, total : Int, used : Int, avail : Int }

// 文本搜索（syscall walkDir + regex match，recursive 缺省为 false）
Std.grep   : { pattern : String, path : Path, recursive : ?Bool } -> Stream { file : Path, line : Int, text : String }
```

### 八·附、`Parser` 模块

提供编译期类型安全的 JSON 解析/序列化，利用 Kun 的 HM 类型系统实现泛型反序列化：

```kun
module Parser export (JsonValue, JsonValue(..), parseJson, fromJson, toJson, fromString, toString)

// JSON 值类型
type JsonValue
  = JsonNull
  | JsonBool Bool
  | JsonNumber Float
  | JsonString String
  | JsonArray (List JsonValue)
  | JsonObject (Map String JsonValue)

// JSON String → JsonValue（验证语法，不绑类型）
parseJson : String -> Result JsonValue String

// JsonValue → Record（编译期推断目标类型，结构不匹配时 Err）
fromJson : JsonValue -> Result a String

// Record → JsonValue
toJson : a -> Result JsonValue String

// 便捷组合：String → Record（等价于 parseJson + fromJson）
fromString : String -> Result a String

// 便捷组合：Record → String（等价于 toJson + 格式化）
toString : a -> Result String String
```

> `fromJson` 和 `fromString` 的目标类型 `a` 在编译期由调用上下文推断。编译器在编译期为每个调用点生成特化的反序列化代码（类似 Rust `serde` 派生宏），直接将 JSON 结构映射为目标 Record 的字段——**运行时不依赖类型反射**，零额外开销。

使用示例：

```kun
import Parser

type Config = { host : String, port : Int, debug : Bool }

main : Unit
main =
  do
    // 分步处理：灵活控制每个阶段的错误
    raw = File.read p"/etc/app/config.json"
    case raw of
      Ok text ->
        case Parser.fromString text of
          Ok (cfg : Config) -> Std.println f"connecting to {cfg.host}:{cfg.port}"
          Err msg -> Std.println f"parse error: {msg}"
      Err _ -> Std.println "failed to read config"

    // 序列化 Record → JSON String
    cfg = { host = "localhost", port = 8080, debug = false }
    case Parser.toString cfg of
      Ok text -> Std.println text   // → {"host":"localhost","port":8080,"debug":false}
      Err msg -> Std.println f"serialize error: {msg}"
```

### 九、可执行脚本入口

可执行的 `.kun` 脚本**不声明 `module`**，也不导出 `main`。脚本必须定义 `main` 函数，否则编译期报错：

```kun
// ✅ 正确：无模块声明的可执行脚本
main : Unit
main =
  do
    Std.println "hello"

// ✅ 正确：接受命令行参数
main : List String -> Unit
main = \args ->
  do
    Std.println f"got {List.length args} arguments"
```

```kun
// ❌ 错误：可执行脚本中声明 module
module Foo export (bar)    // 编译错误：可执行脚本不可声明 module
main : Unit
main = do { ... }
```

```kun
// ❌ 错误：可执行脚本未定义 main
Std.println "no main"      // 编译错误：缺少 main 函数
```

规则：
- 可执行脚本文件中**没有 `module` 声明** → 编译器将其视为可执行脚本入口
- 可执行脚本**必须**定义 `main : Unit` 或 `main : List String -> Unit`
- `main` 不接受外部 `import`——仅由运行时根据入口规则自动调用
- 库模块文件**有 `module` 声明** → 不可独立执行，仅作为导入源
- 支持 Shebang（`#!/usr/bin/env kun`），Kun 二进制启动时检查 argv[1] 是否为文件路径

CLI 参数结构：

```bash
kun [flags] <script> [--] [script-args...]
```

`Std.args` 返回 `--` 之后的部分（不含 `--` 本身）。示例：`kun deploy.kun -- --verbose` → `Std.args` 返回 `["--verbose"]`。

### 十、`defer`：结构化资源清理

```kun
do
  tmp = TempFile.create             // 返回 Path（内部调用 mkstemp(3)）
  defer (File.remove tmp)           // LIFO 逆序执行
  Cmd.ffmpeg {} "input.mp4" tmp
// do 块退出时自动 remove tmp
```

多个 `defer` 按声明逆序执行，闭包捕获局部变量。替代 Bash `trap ... EXIT`。`defer` 适合"尽力清理"逻辑（remove temp files, unlock），不适合"必须成功"的操作——`defer` 自身 panic 的语义见「错误处理」章节。

#### `do in` 的变量生命周期

`do` 块中绑定的变量在 `in` 表达式中可用。`in` 之后所有副作用已执行完毕——Stream 终端操作在 `do` 部分触发消费，结果绑定为纯值传递给 `in`：

```kun
countFiles : Path -> Int
countFiles = \dir ->
  do
    entries = Cmd.ls { all = true } dir |> Stream.lines |> Stream.toList   // 消费完成
  in
    List.length entries   // entries 是纯 List String，生命周期延续到函数返回
```

`defer` 在 `do` 块结束时执行，**在 `in` 表达式求值之前**。`in` 中使用的变量是已在内存中的纯值——`in` 无法引用仅在副作用执行中有效的资源（如子进程尚未 waitpid 的 Stream）。

### 十一、信号处理

保留原设计的 `Signal.on`（signalfd 机制，非 OS 信号上下文直接执行）：

```kun
do
  Signal.on SIGTERM (\sig ->
    do
      Std.println "received SIGTERM, shutting down..."
      Std.exit 0
  )
  // 执行工作——收到 SIGTERM 时 Signal.on 回调自动执行
```

`Signal.on` 注册的回调在收到信号时的事件循环上下文中执行（通过 signalfd 读取 → 调用回调）。回调内部是独立的 `do` 块，可安全执行任意 IO 操作。多次注册同一信号的处理函数时，新处理器覆盖旧的。

#### 事件循环模型

Kun 运行时在 `do` 块的执行间隙轮询 `signalfd`——信号不中断正在执行的纯函数或 syscall，而是在下一个安全点被读取和处理。安全点包括：`do` 块边界、每个 IO thunk 入口、每次 `Cmd.exec` 返回前、Stream 终端操作消费循环中每 1000 个元素。调度顺序：多个排队信号按接收顺序处理；exit 信号（SIGTERM/SIGINT）在回调完成后立即触发 unwind 和 `defer` 链。`Std.sleep` 在等待期间通过 epoll 同时监听 timerfd 和 signalfd，信号可中断等待。

### 十二、安全隔离

#### 安全降级决策矩阵

| 内核版本 | 条件 | 可用机制 | 路径控制 | 网络控制 | 降级行为 |
|---------|------|---------|---------|---------|---------|
| ≥ 5.13 | — | **Landlock** | ✅ 文件/目录级 | ✅ 端口级 | 首选方案 |
| 3.8-5.12 | `userns_clone = 1` | **Mount + Network namespace** | ⚠️ 目录级（/usr 泄漏） | ✅ 完全隔离 | 兜底方案 |
| 3.5-5.12 | `userns_clone = 0` 或容器内 | **seccomp** | ❌ 无路径控制 | ❌ 无网络控制 | 仅 syscall 过滤，**降级 warning** |
| < 3.5 | — | — | — | — | **拒绝运行** |

降级到纯 seccomp 时输出警告：

```
警告: 安全降级 — Landlock 不可用（需内核 5.13+），mount namespace 亦不可用。
       当前仅 seccomp 提供系统调用过滤，文件系统无路径级保护，网络无隔离。
       使用 --force 可强制执行（不推荐），或使用 --no-sandbox 关闭安全层。
```

`/proc/` 保护：Landlock 方案中黑名单 `/proc/self/mem`、`/proc/kcore`、`/proc/sysrq-trigger`、`/proc/kallsyms`；mount namespace 方案中 `/proc/` 挂载 `hidepid=2`。

#### 优先 Landlock，mount namespace 兜底

```
if kernel >= 5.13:
    landlock_create_ruleset() → landlock_add_rule() for each allowed path/port → landlock_restrict_self()
elif kernel >= 3.8:
    创建 mount namespace → tmpfs 根 → bind-mount 白名单目录 + /usr + /lib + 最小 /etc
else:
    降级为仅有 seccomp（syscall 类型过滤，不按路径）
```

#### mount namespace 兜底的挂载策略

```
容器文件系统：
  /allowed/path1/        ← bind-mount from host（用户 --allow-path 指定）
  /allowed/path2/        ← bind-mount
  /usr/                  ← bind-mount, read-only
  /lib64/ → /usr/lib64/
  /etc/                  ← tmpfs + bind-mount 仅必要文件（ld.so.cache/resolv.conf/nsswitch.conf/passwd/group/hosts/localtime）
  /proc/                 ← procfs, hidepid=2
  /dev/                  ← devtmpfs + 基础设备节点
  /tmp/                  ← 独立 tmpfs
```

被有效隐藏：`/home/`、`/root/`、`/var/log/`、`/opt/`、`/boot/`、宿主 `/etc/shadow`、`/etc/ssh/` 等。

#### CLI 控制

```bash
kun script.kun                           # 默认：Landlock/mount ns，仅 CWD 可读写，无网络
kun --allow-path /tmp script.kun         # 额外允许 /tmp
kun --allow-net script.kun               # 开放网络出站（默认仅出站）
kun --allow-net=in:8080 script.kun       # 开放 8080 端口入站
kun --allow-net=in:127.0.0.1:3000 script.kun # 指定地址 + 端口入站
kun --allow-net=all script.kun           # 同时开放出站 + 入站（需显式指定）
kun --no-sandbox script.kun              # 完全关闭（开发/信任环境）
kun --env=inherit script.kun             # 继承全部环境变量
kun --env=none script.kun                # 空环境启动
kun --cpu-limit 120s --mem-limit 1G script.kun  # 资源限制（默认 CPU 60s/内存 512MB）
```

#### 资源限制（rlimit）

fork 子进程后、exec 前自动设置 rlimit，防止资源耗尽：

| 限制 | 默认值 | CLI 覆盖 |
|------|--------|---------|
| `RLIMIT_CPU` | 60s | `--cpu-limit` |
| `RLIMIT_AS` | 512MB | `--mem-limit` |
| `RLIMIT_NOFILE` | 256 | — |
| `RLIMIT_NPROC` | 32 | — |

#### seccomp 规则

在 fork 子进程后、exec 前安装 seccomp-BPF 过滤规则。规则从安全参数推导，始终禁止列表硬编码：

**默认基线**（始终允许）：
`read`, `write`, `openat`, `close`, `fstat`, `lseek`, `mmap`, `munmap`, `brk`, `mprotect`, `rt_sigaction`, `sigreturn`, `exit_group`, `futex`, `clock_gettime`, `getpid`, `getrandom`, `nanosleep`, `getcwd`, `getdents64`, `prlimit64`

**敏感条件追加**：

| 条件 | 追加允许的 syscall |
|------|-------------------|
| `--allow-path` 存在 | `openat`, `read`, `write`, `fstat`, `close`, `lseek`, `ftruncate`, `fsync`, `unlink`, `mkdir`, `rename` |
| `--allow-net` 存在 | `socket`, `connect`, `sendto`, `recvfrom`, `bind`, `listen`, `accept4` |
| `=>` 链中使用 | `pipe2`, `dup2`, `clone` |

**始终禁止**：
`mount`, `umount2`, `pivot_root`, `kexec_load`, `kexec_file_load`, `init_module`, `finit_module`, `delete_module`, `ptrace`, `process_vm_readv`, `process_vm_writev`, `clock_settime`, `settimeofday`, `adjtimex`, `reboot`, `swapon`, `swapoff`, `acct`, `setdomainname`, `sethostname`

通过 CLI 控制严格级别：

```bash
kun --seccomp=strict script.kun    # 默认 + 禁止 socket 相关（即使 --allow-net）
```

### 十三、REPL 与调试体验

Shell 用户的核心工作流是交互式试错。MVP 应包含一个最小 REPL（表达式求值 + 类型查询），后续迭代补充语法高亮和自动补全。REPL 约 500 行 Zig 可实现基础版本——缺少它 Kun 在脚本语言市场中是严重劣势。

REPL 基础能力：
- 输入表达式 → 求值并打印结果 + 推断类型
- `:type <expr>` → 仅打印类型
- `:load <file>` → 加载 `.kun` 文件（库模块）
- `:cmds <prefix>` → 扫描 PATH 列出匹配的命令名（用于发现可用的 `Cmd.<bin>`）
- `Ctrl+C` → 中断当前求值

### 十四、路线图注记

| 特性 | 版本 |
|------|------|
| 并行独立命令执行（`Task.spawn` / `Task.wait`） | v1.0 |
| `Cmd.stdin` 流式 `Stream a -> Command` | v0.2 |
| stderr 独立捕获（`Cmd.stderr`） | v0.2 |
| `--allow-path` 读写粒度（`:ro`/`:rw`） | v0.2 |
| YAML/TOML 解析 | v0.2 |

---


## 完整示例

### 示例 1：日志分析脚本

```kun
type LogEntry =
  { timestamp : String
  , level     : String
  , message   : String
  }

parseLine : String -> Result LogEntry String
parseLine = \line ->
  case String.split " " line of
    [ts, lvl, ..rest] -> Ok { timestamp = ts, level = lvl, message = String.join " " rest }
    _                 -> Err f"invalid line: {line}"

main : Unit
main =
  do
    entries =
      Cmd.cat p"/var/log/app.log"            // Stream String（惰性）
      => Cmd.grep { pattern = "ERR" }         // OS 管道
      => Cmd.head { n = "100" }               // OS 管道
      |> Stream.lines                          // 过渡到进程内管道
      |> Stream.parseMap parseLine             // 跳过解析失败的行
      |> Stream.toList                         // 终端：触发全链路

    Std.println f"found {List.length entries} errors"
    List.iter (\e -> Std.println f"[{e.timestamp}] {e.message}") entries
```

### 示例 2：部署脚本

```kun
type DeployConfig =
  { source : Path
  , target : Path
  , backup : Bool
  }

deploy : DeployConfig -> Unit
deploy = \cfg ->
  do
    // 备份
    if cfg.backup then
      do
        Std.println "creating backup..."
        Cmd.tar { czf = "backup.tar.gz" } cfg.target
    else
      Std.println "skipping backup"

    // 同步
    Cmd.rsync #{ "RSYNC_PASSWORD" = Std.getenv "RSYNC_PWD" ?? "" }
      { archive = true, compress = true, delete = true }
      cfg.source cfg.target

    // 重载
    Cmd.systemctl { reload = "myapp" }

main : Unit
main =
  do
    deploy { source = p"./dist/", target = p"/var/www/", backup = true }
    Std.println "deploy complete"
```

### 示例 3：带 defer 的资源清理

```kun
main : Unit
main =
  do
    Std.println "starting..."
    lock = Std.pid |> Int.toString |> (\pid -> f"/var/run/app.{pid}.lock")
    File.touch lock
    defer (File.remove lock)
    defer (Std.println "cleanup complete")

    Signal.on SIGTERM (\sig ->
      do
        Std.println "received SIGTERM, cleaning up..."
        Std.exit 0
    )

    Cmd.nginx {}
    Std.println "nginx started"
    Std.sleep 365d  // 模拟长期运行——sleep 被 SIGTERM 中断后退出，defer 自动执行
```

### 示例 4：环境变量 + 子命令

```kun
main : Unit
main =
  do
    // 构建
    Cmd.npm #{ "NODE_ENV" = "production" } { install = true }
    Cmd.npm { run = "build" }

    // Docker 构建和推送
    Cmd.docker.build #{ "DOCKER_HOST" = "tcp://builder:2375" }
      { tag = "myapp:latest", file = "Dockerfile" } "."

    Cmd.docker.push {} "myapp:latest"
```

---

## 设计取舍记录

### 安全模型：声明式 → 命令式权限

原方案的 `with caps` 允许脚本作者在代码中声明最小权限——"此脚本只需要 `/tmp`"，安全契约内嵌于代码，不可被调用者绕过。新方案将权限控制完全移至 CLI 参数（`--allow-path`、`--allow-net`），让操作者在运行时决定安全边界。

**取舍理由**：CLI 参数模式允许同一脚本在不同环境中以不同权限运行——开发时 `--no-sandbox`、CI 中 `--allow-path /build`、生产中仅 `--allow-path /data`。声明式模式需要修改脚本源码才能实现此灵活性。权衡：安全控制从"作者不可绕过"变为"操作者可绕过"，牺牲不可绕过的安全性换取运维灵活性。

**影响**：脚本作者无法强制安全约束，需要依赖操作者的安全素养和文档/READMe 约定。对于运维脚本语言，这个权衡合理——脚本信任的基础是源码审查，权限只是纵深防御层。配合 `kun --audit script.kun` 静态分析命令可部分缓解"操作者不知脚本需要什么权限"的问题。

### 效应跟踪：IO 类型 → AST 标记

原方案的 `IO T` 类型包装器提供编译期可证明的纯/效应分离，但要求用户在类型签名中显式标注 IO。新方案用 AST 标记替代：含 `do` 块的函数为效应函数，Lambda 效应性在定义点检查。

**取舍理由**：消除了 HM 推断中的 IO 效应传播逻辑（~2000 行），用户无需理解 Monad。代价：纯函数的效应性不在类型签名中可见——需要查看源码或依赖 IDE 确定函数是否含副作用。对于脚本语言，"在 `do` 里看到 `Cmd.*` 所以有副作用"的直观判断优于"从类型签名证明无副作用"的理论完备性。

---

## 与原方案的关键差异汇总

| 维度 | 原方案 | 新方案 |
|------|--------|--------|
| 效应追踪 | `IO T` 类型包装器 + HM 扩展 | AST 标记 + call-site lambda 检查（不扩散到类型签名） |
| 命令调用 | `.cmd.kun` DSL + Builder API + 幻影类型 | `Cmd.<bin>` + Record 选项 + 位置参数 |
| 命令选项映射 | 手动 `withArg`/`withFlag` 链式调用 | camelCase → kebab-case 自动转换 |
| 错误处理 | `=!`/`<-!` 早返回 + `Result` 强制处理 | panic 默认 + `Cmd.<bin>?` 后缀返回 Result |
| 安全模型 | `with caps` 脚本内声明 | CLI `--allow-path` / `--allow-net` / `--force` |
| 安全实现 | 分层但依赖 Landlock | Landlock 优先 + mount namespace 兜底 + rlimit + seccomp 规则定义 + 降级决策矩阵 |
| Stream | `{ state, next, destroy }` 函数指针链 | tagged union（双层间接→单层），comptime 融合 |
| 资源清理 | 无 | `defer` 语句 + panic unwind 完整语义 |
| 环境变量 | `env` 隐式字段 + 能力系统 | `#{ }` Map + CLI `--env=` + 始终剔除列表 |
| 结构化数据 | `.cmd.kun` + 社区模块 | `Parser` 模块（`fromString`/`toString` + JSON ↔ Record）+ syscall 类型化命令种子 |
| 超时与重试 | 无 | `Std.timeout` + `retry` |
| 可执行脚本 | `module Main export (main)` | 无模块声明，直接定义 `main : Unit` |
| stdin/stderr 控制 | `<-` 解包 + IO 包装 | `Cmd.stdin` / `Cmd.mergeStderr` 普通函数 |
| 特殊字符命令名 | `.cmd.kun` 文件定义 | `Cmd["any-name"]` / `Cmd["a"]["b"]` 转义 |
| 关键词数量 | `with caps`, `do`, `<-`, `<-!`, `=!`, 等 | `do`, `defer`, `=>` |
| 预估代码量 | ~50,000+ 行 Zig | ~20,000-25,000 行 Zig |
| 学习曲线 | 需要理解 Monad + 幻影类型 + Builder API | 需要理解 Record + 模式匹配 + do 块 |
| 可行实现时间 | 大型团队多年 | 单人 6-12 个月 |

---

## 现有文档冲突清单

以下现有文档与重设计方案存在冲突，需在后续阶段逐一更新或废弃：

| 现有文档 | 冲突点 | 处理 |
|---------|--------|------|
| `project-vision.md:23-25` | `.cmd.kun` + `kun cmd init` 提及 | 重写为 "结构化的 `Cmd.<bin>` + Record 参数" |
| `project-vision.md:39` | dlopen 实现策略 | 改为 "fork-exec + Stream 管道捕获" |
| `module-boundaries.md` | 命令函数系统、安全子系统、能力管理器 | 大幅重写：移除 `.cmd.kun` 编译器、`InternalCommand`、能力管理器；新增 `Cmd` 动态查找 + Landlock/mount ns |
| `system-baseline.md:30-34` | 初始化阶段含"能力系统初始化" | 移除能力初始化，改为 CLI 安全参数解析 + 沙箱安装 |
| `system-baseline.md:350-535` | 命令加载机制（dlopen/ptrace/fork-exec 分层） | 简化为：fork-exec + Stream pipe |
| `syntax.md:8` | 设计原则含"权限显式语法标记" | 移除 |
| `syntax.md:38` | `Nat` 字面量 `42u` | 移除 |
| `standard-library.md:200-222` | `IOError` 类型定义 | 改为新 `CommandError` |
| `command-function-system.md` | 整份文档 | 废弃或完全重写 |
| `roles-and-permissions.md` | 整份文档 | 废弃或重写为 Landlock + mount ns + CLI 参数 |
| `supply-chain-security.md` | 整份文档 | 可归档——新方案不涉及命令签名和注册中心 |
| `feature-inventory.md` | 状态追踪 | 全面更新：移除 `Nat`/`IO`/`.cmd.kun`/`with caps` 条目；新增 `Cmd.<bin>`/`=>`/`defer`/Landlock/mount ns |
| `code-formatting.md:20-28` | 声明顺序含 `with caps` 和 `command` | 移除，简化为 `module → import → 其余` |
