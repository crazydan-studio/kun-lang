# 应用概览

## Kun 语言概览

Kun（鲲）是一款面向 Linux 的函数式脚本语言，其核心目标是消除传统 Shell 脚本的种种问题，同时保留 Unix 哲学中"小程序组合完成复杂任务"的精髓。

## 类型系统

### 基础类型

| 类型 | 说明 |
|---|---|
| `Int` | 整数（64 位有符号）；支持位运算（`&`/`\|`/`^`/`not`/`shl`/`shr`/`ushr`/`popCount` 等） |
| `Float` | 浮点数 |
| `Bool` | 布尔值 |
| `String` | 文本字符串（UTF-8） |
| `Bytes` | 二进制数据，与 `String` 明确区分 |
| `Char` | 单个字符（Unicode 标量值） |
| `Regex` | 正则表达式 |
| `Duration` | 时间段 |
| `Unit` | 单元类型，表示无返回值 |
| `Path` | 文件系统路径 |

### 复合类型

| 类型 | 说明 |
|---|---|
| `List` | 顺序序列，支持索引访问和模式匹配解构 |
| `Map` | 映射表，键仅限内置可哈希类型；自定义类型作键用 `Map.fromHashFn` |
| `Set` | 集合，元素唯一且无序 |
| `Stream` | 惰性流，显式惰性特区；支持大文件处理和管道数据流 |
| `Tuple` | 元组 |
| `Record` | 积类型，匿名结构 `{ x : Float, y : Float }` |
| `Nilable a` | 内置 ADT，语法糖 `?T`，`Nil`/`Some` 为构造器；**禁止嵌套** `??T` |
| `Result` | 内置 ADT `Result a e = Ok a \| Err e` |

### 类型声明：`alias` 与 `type`

Kun 采用 **`alias`/`type` 分离** 的类型声明体系：

- **`alias`**：透明别名，结构等价，编译期展开，无运行时存在，无构造器，无抽象屏障
  - 例：`alias Point = { x : Float, y : Float }`、`alias UserId = Int`
- **`type`**：代数数据类型（ADT），名义等价，有抽象屏障，有构造器，**不做 tag 擦除**
  - 单变体（包装类型）：`type UserId = UserId Int`、`type User = User { name : String, id : Int }`
  - 多变体（和类型）：`type Color = Red \| Green \| Blue`、`type Result a e = Ok a \| Err e`

详细规则见 [类型系统](type-system.md#类型声明体系alias-与-type-分离)。

### 标准库补充类型

脚本领域特定的类型（`Signal`、`DateTime`、`Uid`/`Gid`、`IOError`、`CommandError`、`TestResult`、`FfiBuffer`、`FfiValue` 等）由[标准库](standard-library.md)以 ADT 或效应签名形式定义，详见独立文档。

## 代数效应系统

Kun 将副作用视为**类型层的效应集**——函数类型显式标注效应集 `a -> b ! E`，纯函数是效应空集 `! {}` 的特例。

### 7 个内置效应

| 效应 | 含义 | 触发来源 |
|---|---|---|
| `IO` | 控制台 IO | `IO.println`/`IO.readln` |
| `File` | 文件系统 | `File.read`/`File.write` |
| `Cmd` | 子进程执行 | `Cmd.exec`/`Cmd.execSafe`/`Cmd.stream` |
| `Random` | CSPRNG | `Random.int`/`Random.bytes` |
| `DateTime` | 系统时间 | `DateTime.now` |
| `Signal` | 信号处理 | `Signal.on` |
| `FFI` | 外部 C 库调用 | `FFI.call`（由 `extern` 块默认 handler 委托） |

效应签名在标准库（Kun）中声明（`effect X = { op : sig }` Record 风格），handler 实现在编译器源码（Zig）中——签名与实现彻底分离。用户自定义效应（如 `DB`/`Log`）通过 `effect`/`handler` 语法声明与实现。

### `do ... with` / `let ... in ... with` 限入口

业务函数只声明效应不消解，效应冒泡到 `main`/`TestCase.body`，入口级上下文内通过 `do <body> with <handler>`（Unit 返回）或 `let <body> in <expr> with <handler>`（值返回）集中消解（`TestCase.body` 由 `kun test` 运行器提供入口级上下文，详见 [单元测试设计](testing.md)）：

```kun
// 业务函数：声明效应，不消解
fetchUser : UserId -> Result User ! {DB, Log}
fetchUser = \uid ->
  let
    Log.info f"fetching {uid}"
    result = DB.query (selectUser uid)
  in
    case result of
      Ok [row] -> Ok (User row)
      _ -> Err NotFound

// main：集中消解用户效应（do...with / let...in...with）
main : List String -> Unit ! {Cmd, IO}
main = \args -> do
  result = fetchUser (UserId "1")
  case result of
    Ok user -> IO.println f"found: {user.name}"
    Err _ -> IO.println "not found"
with
  postgreHandler >> journaldLog
  // 用户效应 DB/Log 被消解
  // 剩余 {Cmd, IO} 冒泡到 main，运行时自动注入默认 Zig handler
```

未消解的用户效应冒泡到 `main`/`TestCase.body` 时编译错误；内置效应运行时自动注入默认 Zig handler。`FFI` 效应到达 `main` 时运行时检查 `--allow-ffi`。

### `continue`/`abort` 二选一

handler 每个分支必须有且仅有一次 `continue`（委托外层/默认）或 `abort`（提前终止）。`continue` 多次调用、二者皆无皆编译错误。详见 [类型系统](type-system.md#handler-系统)。

## Command 调用系统

所有 Linux 命令通过 **`cmd` 字面量** 构造为 `Command` ADT——四段式 `cmd <命令> <子命令>* <选项>? <位置参数>?`。命令/子命令可为字符串或标识符，选项用 Record（camelCase 自动映射 kebab-case），位置参数用 List。

```kun
c =
  cmd docker run
    { d = true
    , name = "my-web"
    , p = [ "80:80" ]
    }
    [ "nginx" ]
```

**执行全显式**——无 Command 的 `?`/`!` 后缀糖（零参函数执行的 `!` 后缀是独立特性，见[类型系统 - 零参效应函数类型](type-system.md#零参效应函数类型-t-e)），无 `|>` 隐式触发：

```kun
Cmd.exec     : Command -> Unit ! {Cmd}                                // 失败 panic，丢弃输出
Cmd.execSafe : Command -> Result (Stream String) CommandError ! {Cmd} // 失败返回 Err
Cmd.stream   : Command -> Stream String ! {Cmd}                       // 失败 panic，返回 Stream
```

`|>` 退化为纯管道操作符，统一类型 `a -> (a -> b) -> b`。完整设计见 [OS 命令调用机制](command-system.md)。

## 管道与组合

内置管道机制和高阶函数实现命令组合：

- **进程内管道 `|>`**：纯管道操作符，将左侧表达式的值作为右侧函数的最后一个参数传入；**不再隐式触发 Command 执行**
- **OS 管道 `pipe`**：纯函数 `pipe : List Command -> Command`，构造 `Pipe` ADT 变体；深度上限 16，超限编译错误
- **求值策略**：立即求值为默认策略，所有表达式与 `let in` 绑定立即求值；`Lazy` 模块（`Lazy.lazy`/`Lazy.force`）与 `Stream` 为显式惰性特区
- **高阶函数**：map、filter、fold、reduce 等；效应多态通过单效应变量 `e` 表达（`map : (a -> b ! e) -> List a -> List b ! e`）

## 模式匹配

支持多种模式匹配形式：

- **和类型模式**：匹配 `Result`/自定义 ADT 等和类型的变体
- **Nilable 模式**：匹配 `Some`/`Nil`（构造器形式，非操作符脱糖）
- **列表模式**：匹配列表结构（空列表、`[a, ..rest]`、特定元素序列）
- **映射模式**：匹配特定键的存在
- **守卫子句**：附加到模式分支的额外布尔条件
- **Or 模式**：`Pat1 | Pat2 -> expr` 多模式共享分支体

## 错误处理

### 默认 panic

命令失败时默认 panic（unwind → `defer` LIFO 逆序执行 → 回收活跃子进程 → Arena 销毁），结构化错误信息包含命令名、退出码、stderr。

### 显式执行入口

| API | 返回类型 | 失败行为 | 适用场景 |
|---|---|---|---|
| `Cmd.exec` | `Unit` | panic | 仅副作用（mkdir/cp） |
| `Cmd.execSafe` | `Result (Stream String) CommandError` | 返回 Err | 需错误处理 |
| `Cmd.stream` | `Stream String` | panic | 需输出流，不需错误处理 |

```kun
let
  result =
    cmd cat {} [ p"/etc/maybe_missing" ]
      |> Cmd.execSafe
in
  case result of
    Ok stream -> Stream.iter IO.println stream
    Err err ->
      case err of
        CommandFailed { exitCode, stderr } -> IO.println stderr
        NotFound cmd -> IO.println f"not found: {cmd}"
```

### `defer` 资源清理

`defer expr` 绑定到所在 `do`/`let in` 块，块退出时（正常或 panic）按 LIFO 逆序执行：

```kun
do
  case File.createTemp! of
    Ok tmp -> do
      defer (File.remove tmp)
      cmd ffmpeg {} [ "input.mp4", tmp ] |> Cmd.exec
    Err _ -> IO.println "failed to create temp file"
```

### panic 退出码规则

| panic 原因 | 退出码 |
|---|---|
| `CommandFailed { exitCode = n }` | `n` |
| `NotFound` | 127 |
| `PermissionDenied` | 126 |
| `KilledBySignal { signal = s }` | `128 + s` |
| 纯运行时错误（除零、越界） | 1 |
| 递归深度超限 | 1 |
| `assert` 失败 | 1 |
| SIGINT | 130 |
| SIGTERM | 143 |

## FFI 系统

FFI 采用**分层归属**设计——底层 `FFI` 内置效应（受 `--allow-ffi` 控制），上层每个 `extern` 块自动产生独立效应（如 `Libc`/`Curl`），可独立消解/mock。

```kun
extern Libc from "libc" =
  { strlen : String -> Int
  , fopen  : String -> String -> ?(Opaque File)
  , fclose : Opaque File -> Int
  , fread  : FfiBuffer -> Int -> Int -> Opaque File -> Int
  }
```

调用形式 `Libc.strlen "hello"`（产生 `! {Libc}`，**无 `unsafe`**），默认 handler 委托 `FFI.call`（产生 `! {FFI}`）。`FfiBuffer` 不逃逸（编译器内置规则硬编码，非标注），`Ffi.alloc` 绑定 `let in` 块自动释放。

**仅 Linux 支持**——FFI 不跨平台，专注 Linux `.so`/`dlopen`。非 Linux 平台 `extern` 声明编译错误。

防欺骗四层：保留名 + `extern` 强制产生内置 FFI + 命名空间隔离 + 运行时 `--allow-ffi` 检查。详见 [类型系统](type-system.md#ffi-系统)。

## 录制/回放

录制 handler 包装默认 handler，记录每次效应调用的输入输出与时间戳；回放 handler 按时间戳顺序从录制读取结果，不实际执行副作用——为生产 bug 的确定性复现、时间相关测试、回归测试提供基础。

```kun
// 生产录制
main : List String -> Unit ! {Libc, File, IO}
main = \args -> do
  result = readFileContent (Path.fromString "/etc/hostname")
  case result of
    Ok content -> IO.println content
    Err e -> IO.println e
with
  recordHandler p"/trace/session-001.jsonl" ["Libc", "File", "IO"]

// 测试回放（确定性复现，作为 TestCase 值）
testReplay : TestCase =
  test "replay readFileContent" (\ ->
    let
      result = readFileContent (Path.fromString "/etc/hostname")
    in
      case result of
        Ok content -> IO.println content
        Err e -> IO.println e
    with
      replayHandler p"/trace/session-001.jsonl"
  )
```

录制格式为 JSON Lines，每行一次调用，字段含 `ts`（时间戳）/`seq`（序号）/`eff`/`op`/`args`/`result`。详见 [标准库](standard-library.md#录制回放)。

## 安全模型

安全策略通过 [`kun` CLI 参数](kun-cli-tool.md#安全控制)声明（`--allow-path`、`--allow-net`、`--allow-ffi`、`--no-sandbox`、`--force`、`--env=`、`--cpu-limit`、`--mem-limit`），与脚本代码分离。默认仅 CWD 可读写、无网络、FFI 默认禁用。运行时通过 Landlock / mount namespace / seccomp + rlimit 多层沙箱隔离，详细实现见[系统基线](../architecture/system-baseline.md#安全隔离)。

**效应安全模型**：

- 用户效应（`DB`/`Log` 等）必须消解（`do...with` / `let...in...with`），未消解冒泡到 `main`/`TestCase.body` 编译错误
- 内置效应（`IO`/`File`/`Cmd`/`Random`/`DateTime`/`Signal`）运行时自动注入默认 Zig handler
- `FFI` 效应冒泡到 `main` 时运行时检查 `--allow-ffi`，未启用则拒绝执行
- 用户无法通过命名、定义、handler 等手段绕过 FFI 安全检查（保留名 + 硬编码 + 命名空间隔离 + 运行时检查）

## 语法设计

Kun 采用**单表达式**范式——程序中所有构造均为具有确定类型值的表达式，多语句形式以 `let <body> in <expr>`（返回值）或 `do <body>`（返回 `Unit`，≈ `let <body> in ()`）表达。`do` 是 `let ... in ()` 的语法糖，可紧跟 `->`（函数箭头或分支箭头）以减少缩进。`case`/`if` 根据结果是否被消费决定分支的包裹规则（unbound 继承外层效应上下文，bound 多语句返回 `Unit` 用 `do`、返回非 `Unit` 用 `let in`、单语句直接书写）。语法借鉴 Elm、Haskell 和 Rust（以 Elm 为主），深度融合 Unix 哲学，确保简洁、统一、一致。所有数据必须赋初值，消除 null，支持自动类型推断。

```kun
// let in（返回值）
let
  users = DB.query all          // 立即执行
  count = List.length users     // 立即计算
  IO.println "done"             // 立即执行
in
  count

// do（返回 Unit，≈ let <body> in ()）
do
  IO.println "line1"
  IO.println "line2"
```

## 运行时执行

运行时使用 Linux 的 fork-exec 机制执行外部命令，通过 pipe 捕获 stdout/stderr。`cmd` 字面量构造 `Command` ADT（纯操作），运行时通过 `Cmd.exec`/`Cmd.execSafe`/`Cmd.stream` 显式触发 fork-exec——shell 元字符在 exec 层面为普通字符，无注入风险。

## 函数与模块

- 支持导入导出函数，提供逻辑复用
- 目录即命名空间，`export (...)` 声明公开符号，`import X (...)` 导入
- **默认私有**——仅 `export` 列出的符号公开
- **Re-export**：`export` 列出的符号无需本模块定义，可来自 `import`
- **不支持 wildcard 导入**（避免冲突与隐式）：`import DB.*` 编译错误
- **导入冲突需别名解决**：`import DB (query as dbQuery)`
- **选择性导入 + 全名引用**：`import DB (query, execute)` 后可直接用 `query` 或全名 `DB.query`
- **模块别名 + 选择性导入**：`import DB as D (query, execute)`
- `effect`/`extern` 效应名通过 `export (DB)` 导出，不支持单独导出效应操作
- Kun Shell 交互式环境（未来版本）

