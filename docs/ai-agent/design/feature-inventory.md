# 功能清单

## 当前版本（2026.07 — 代数效应与命令系统重设计）

> 以下为代数效应与命令系统重设计后的功能清单。实现状态将随着开发进展更新。

### 类型系统

| 功能 | 状态 | 说明 |
|---|---|---|
| 基础类型 | ✅ 设计定型 | Int(i64)、Float(f64)、Bool、String(UTF-8)、Bytes、Char、Regex、Duration、Unit、Path |
| 复合类型 | ✅ 设计定型 | List、Map、Set、Stream（惰性特区）、Tuple |
| `alias` 别名 | ✅ 设计定型 | 透明别名，结构等价，编译期展开，无运行时存在，无构造器 |
| `type` ADT | ✅ 设计定型 | 名义等价，单变体 `type X = X T` / 多变体 `type X = A \| B` 一致为 tagged union，**不做 tag 擦除** |
| 和类型 | ✅ 设计定型 | Result、自定义和类型，穷举检查 |
| Nilable 类型 `?T` | ✅ 设计定型 | `Nilable T` 的语法糖；`Nil`/`Some` 为构造器；**禁止嵌套** `??T` → 编译错误（Nested Nilable） |
| 模式匹配 | ✅ 设计定型 | 和类型、列表、映射、守卫子句、or 模式，穷举性规则 |
| 类型推断 | ✅ 设计定型 | Hindley-Milner 算法 W，Let-多态（**值限制**，OCaml 风格） |
| 泛型 | ✅ 设计定型 | 无约束参数化多态；**不支持行多态**，效应集为闭集 + 单效应变量 `e` |
| 函数类型 | ✅ 设计定型 | `<param> -> <result> ! <effectSet>`；无 `!` ≡ `! {}`（纯） |
| 效应集 | ✅ 设计定型 | `! {}`/`! {IO}`/`! {IO, File}`/`! e`/`! {IO, e}`；无序集合，合一按排序后比较 |
| 相等比较 `==` | ✅ 设计定型 | **结构浅比较**；基础类型值比较；容器/Record/ADT 引用比较；深比较用 `Equal` 模块；Map 键仅限内置可哈希类型 |
| 递归类型 | ✅ 设计定型 | 等递归类型，展开深度上限 256 层（`KUN_MAX_TYPE_DEPTH` 可覆盖，0 表示无限制），超限编译错误 |
| 种类系统 | ✅ 设计定型 | `Type`、`Type -> Type`、`Type -> Type -> Type`、`Effect`、`EffectSet` |
| 类型等价 | ✅ 设计定型 | `alias` 结构等价 / `type` 名义等价；无子类型；**不支持 typeclass** |

### 代数效应系统

| 功能 | 状态 | 说明 |
|---|---|---|
| 内置效应 | ✅ 设计定型 | 7 个：`IO`/`File`/`Cmd`/`Random`/`DateTime`/`Signal`/`FFI`；保留名，用户不可重名定义 |
| `effect` 声明 | ✅ 设计定型 | Record 风格 `effect <Name> = { op : sig, ... }`；签名在标准库（Kun），handler 实现在编译器源码（Zig） |
| `handler` 声明 | ✅ 设计定型 | case of 风格 `<name> = handler <Effect> of <op> <args> -> <impl>`；类型 `Handler {e} a ! {handlerEffects}` |
| `handle with` 表达式 | ✅ 设计定型 | **仅 `main`/`test*` 内可用**；`handle <expr> with <handler>`；handler 组合 `h1 >> h2` |
| `continue` 委托 | ✅ 设计定型 | 控制流原语，委托外层/默认 handler；每分支恰好一次；不可多次调用；不可作值传递；不可嵌套 lambda |
| `abort` 提前终止 | ✅ 设计定型 | 控制流原语，提前终止 handler；返回值须匹配 handler 产出类型；与 `continue` 二选一 |
| 效应多态 | ✅ 设计定型 | 单效应变量 `e`，调用时实例化；`map : (a -> b ! e) -> List a -> List b ! e` |
| Let 泛化值限制 | ✅ 设计定型 | 语法值（lambda/字面量/ADT 构造）泛化类型与效应变量；函数应用/效应调用不泛化 |
| HM 效应集合一 | ✅ 设计定型 | `! e ~ ! IO` 成立（`e := {IO}`）；`! e ~ ! {IO, e}` occurs check 失败 |
| 强制消解 | ✅ 设计定型 | 用户效应必须 `handle`；内置效应运行时自动注入默认 Zig handler；未消解用户效应冒泡到 `main`/`test*` 编译错误 |
| 多效应 handler | ✅ 设计定型 | `handler {DB, Log} of DB.query q -> ...`；操作名必须限定（`DB.query`）避免歧义 |
| Mock Handler | ✅ 设计定型 | 测试用，每效应可独立 mock；`continue` 委托默认或不调用 `continue` 直接返回 |
| Stream 消费检查 | ✅ 设计定型 | 单 `let in` 块强制消费；跨块传递视为已消费；`case`/`if` 各分支均需消费；`defer` 不计入 |

### FFI 系统

| 功能 | 状态 | 说明 |
|---|---|---|
| `extern` 块 | ✅ 设计定型 | `extern <EffectName> from "lib" = { func : sig, ... }`，自动产生独立效应，自动生成默认 handler 委托 `FFI.call` |
| `extern` 语法规则 | ✅ 设计定型 | 库名必须字符串字面量；不可嵌套；签名不可含效应标注；至少一函数；不可与 `effect` 同名 |
| 调用形式 | ✅ 设计定型 | `<Effect>.<func> <args>`，**无 `unsafe`**（效应名已标注 FFI 来源） |
| `FFI.call` | ✅ 设计定型 | 直接 C 调用，类型擦除，需 `unsafe`（罕见场景） |
| `FfiValue` ADT | ✅ 设计定型 | `IntVal`/`FloatVal`/`BoolVal`/`StringVal`/`BytesVal`/`PathVal`/`OpaqueVal (Opaque Any)`/`BufferVal FfiBuffer`/`UnitVal` |
| `Opaque a` | ✅ 设计定型 | 幻影类型，编译期区分（`Opaque File` ≠ `Opaque Curl`），运行时 `void*`；不可解引用、不可算术 |
| `FfiBuffer` 不逃逸 | ✅ 设计定型 | 编译器内置规则硬编码（非标注）；绑定 `let in` 块；不可作为返回值；不可赋值外层；可经 `Ffi.toBytes`/`Ffi.toString` 拷贝逃逸 |
| FFI 内存管理 | ✅ 设计定型 | `Ffi.alloc` 绑定 `let in` 块生命周期，块结束自动释放 |
| `--allow-ffi` | ✅ 设计定型 | 运行时检查；FFI 效应冒泡到 `main` 时未启用则拒绝执行 |
| 防欺骗四层 | ✅ 设计定型 | 保留名 + `extern` 强制产生内置 FFI + 命名空间隔离 + 运行时 `--allow-ffi` |
| 平台支持 | ✅ 设计定型 | **仅 Linux**（`.so`/`dlopen`），不跨平台；非 Linux 平台 `extern` 声明编译错误 |
| 复杂 C 类型支持 | ✅ 设计定型 [MVP 限制] | MVP 支持基础类型 + `Opaque a` + `?T` + `List T`；不支持 C struct 按值传递/union/函数指针/变参 |

### Command 系统

> 完整设计见 [OS 命令调用机制](command-system.md)。

| 功能 | 状态 | 说明 |
|---|---|---|
| `cmd` 字面量 | ✅ 设计定型 | 四段式：`cmd <命令> <子命令>* <选项>? <位置参数>?`；命令/子命令可为字符串或标识符 |
| Command ADT | ✅ 设计定型 | `type Command = Simple SimpleCommand \| Pipe (List Command)`；`cmd` 字面量为语法糖 |
| 选项键映射 | ✅ 设计定型 | 标识符单字符补 `-`，标识符多字符补 `--` + camelCase→kebab-case，字符串键原样 |
| 选项值类型 | ✅ 设计定型 | `Bool = true` 旗标；`Bool = false`/`Nil` 省略；单值 flag+值；`List` 重复 flag+各值；简写 ≡ `= true` |
| `--` 分隔符 | ✅ 设计定型 | 有位置参数时自动插入；`Cmd.withoutDash` 关闭 |
| 位置参数 | ✅ 设计定型 | 必须用 `[ ]`，不支持裸字符串 |
| `pipe` 纯函数 | ✅ 设计定型 | `pipe : List Command -> Command`；**深度上限 16**，超限编译错误；空列表字面量 `[]` 编译错误，变量运行时 panic |
| `Cmd.exec` | ✅ 设计定型 | `Command -> Unit ! {Cmd}`，失败 panic，丢弃输出 |
| `Cmd.execSafe` | ✅ 设计定型 | `Command -> Result (Stream String) CommandError ! {Cmd}`，失败返回 Err |
| `Cmd.stream` | ✅ 设计定型 | `Command -> Stream String ! {Cmd}`，失败 panic |
| `Cmd.which` | ✅ 设计定型 | `String -> ?Path ! {Cmd}`，PATH 查找 |
| `Cmd.withEnv`/`withStdin`/`withStdinFile`/`withWorkDir`/`withRunAs` | ✅ 设计定型 | 纯修饰函数（`Command -> Command`） |
| `Cmd.mergeStderr`/`withoutDash`/`andThen`/`orElse`/`timeout`/`retry` | ✅ 设计定型 | 纯修饰函数 |
| `Cmd.withStdin` 死锁预防 | ✅ 设计定型 | 单线程非阻塞 poll；优先读 stdout；stdin 非阻塞写；输入 >1MB 推荐 `Stream Bytes` |
| `\|>` 纯管道 | ✅ 设计定型 | `a -> (a -> b) -> b`；**不再隐式触发 Command 执行** |

### 录制/回放

| 功能 | 状态 | 说明 |
|---|---|---|
| `recordHandler` | ✅ 设计定型 | `Path -> List Effect -> Handler e a ! {File}`；包装默认 handler，记录每次效应调用 |
| `replayHandler` | ✅ 设计定型 | `Path -> Handler e a ! {File}`；按时间戳顺序从录制读取，不实际执行副作用 |
| 录制格式 | ✅ 设计定型 | JSON Lines，每行一次调用；字段 `ts`/`seq`/`eff`/`op`/`args`/`result` |
| 匹配规则 | ✅ 设计定型 | 按 `eff`+`op`+`seq` 匹配；重命名导致回放失败需重新录制；跨版本不保证兼容 |
| 确定性保证 | ✅ 设计定型 | 时间戳顺序消费；`seq` 不匹配报错；`DateTime`/`Random` 录制固定消除非确定性 |

### 标准库类型

| 功能 | 状态 | 说明 |
|------|------|------|
| Signal | ✅ 设计定型 | 内置效应；`Signal.on` 注册信号处理 |
| IOError | ✅ 设计定型 | 结构化系统调用错误类型 |
| CommandError | ✅ 设计定型 | 语义化命令错误类型（NotFound/PermissionDenied/CommandFailed/KilledBySignal/IoError/PipeFailed/Timeout） |
| DateTime | ✅ 设计定型 [推迟 v0.2] | 内置 `DateTime` 效应；`format` 返回 `Result String String` |
| Uid / Gid | ✅ 设计定型 | 用户/组 ID 数字类型（`type UserId = UserId Int` 单变体 ADT） |
| Decimal | ✅ 设计定型 | 精确十进制数值（非编译器内置） |
| TestResult | ✅ 设计定型 | `type TestResult = Pass \| Fail String \| Skip String` |
| FfiBuffer | ✅ 设计定型 | 编译器内置类型，不逃逸规则硬编码 |
| FfiValue | ✅ 设计定型 | FFI 调用的擦除类型，9 个变体 |

### 标准库模块

| 功能 | 状态 | 说明 |
|------|------|------|
| Function | ✅ 设计定型 | `identity`/`always`/`<\|`/`\|>`/`<<`/`>>`，始终缺省可用 |
| Nilable | ✅ 设计定型 | `withDefault`/`map`/`orElse`/`toResult`/`andThen`，变体 `Nil` 缺省可用，函数需显式导入 |
| Lazy | ✅ 设计定型 | 显式惰性特区：`lazy`/`force`，memoize 一次 |
| String | ✅ 设计定型 | `toString`（编译器级泛型）+ 类型互转函数 |
| Regex | ✅ 设计定型 [推迟 v0.2] | 正则匹配与替换（基于 zig-regex 引擎，`fromString` 运行时构造） |
| Bytes | ✅ 设计定型 | 二进制编解码（`toHex`/`fromHex`） |
| List | ✅ 设计定型 | 不可变列表查询与变换 |
| Map | ✅ 设计定型 | 不可变字典查询与变换；键仅限内置可哈希类型；`Map.fromHashFn` 传入自定义哈希 |
| Set | ✅ 设计定型 | 不可变集合操作（`insert`/`remove`/`union`/`intersect`/`diff`） |
| Result | ✅ 设计定型 | `map`/`mapError`/`andThen`/`withDefault` |
| Equal | ✅ 设计定型 | 深比较模块：`List.equal`/`Map.equal`/`Set.equal` 等 |
| Random | ✅ 设计定型 | 内置 `Random` 效应，CSPRNG |
| Stream | ✅ 设计定型 | 惰性序列（纯变换 + IO 消费） |
| IO | ✅ 设计定型 | 内置 `IO` 效应（控制台） |
| File | ✅ 设计定型 | 内置 `File` 效应（文件系统） |
| Cmd | ✅ 设计定型 | 内置 `Cmd` 效应（子进程执行） |
| DateTime | ✅ 设计定型 [推迟 v0.2] | 内置 `DateTime` 效应 |
| Signal | ✅ 设计定型 | 内置 `Signal` 效应 |
| FFI | ✅ 设计定型 | 内置 `FFI` 效应，`Ffi.alloc`/`toBytes`/`toString` |
| Process | ✅ 设计定型 | `exit`/`pid`/`kill`/`wait`/`sleep` |
| Duration | ✅ 设计定型 | 时间段算术/比较/单位转换（编译器内置类型，模块函数需显式导入） |
| Task | ✅ 设计定型 | `spawn`/`all` 并发命令执行 |
| Hash | ✅ 设计定型 | SHA-256 哈希（`sha256`/`sha256Hex`；`md5` 推迟 v0.3） |
| Base64 | ✅ 设计定型 | Base64 编解码（`encode`/`decode`） |
| Cli | ✅ 设计定型 | 类型驱动 CLI 解析，对标 argparse；auto --help；子命令/互斥组/透传 |
| Validator | ✅ 设计定型 [推迟 v0.2] | `oneOf`/`range`/`nonEmpty`/`regex`，供 `Cli.withValidator` 使用（依赖 Regex） |
| Parser.JSON | ✅ 设计定型 | JSON 值类型与字符串互转 |
| Parser.Record | ✅ 设计定型 | Record 类型安全反序列化（编译期代码生成） |
| Path | ✅ 设计定型 | `parent`/`fileName`/`extension`/`join`/`(++)`/`resolve`/`normalize`/`isAbsolute`/`isRelative`/`relative`/`toString` |
| Int | ✅ 设计定型 | 整数算术 + **位运算**（`&`/`\|`/`^`/`not`/`shl`/`shr`/`ushr`/`popCount`/`leadingZeros`/`trailingZeros`）；需显式导入 |
| Float | ✅ 设计定型 | 浮点绝对值/取整/三角/指数对数/幂/常量/类型互转/`approxEqual`，Math 已并入 Float |
| Decimal | ✅ 设计定型 | 精确十进制数值，非编译器内置 |
| Lazy | ✅ 设计定型 | 显式惰性特区：`Lazy.lazy : (Unit -> a) -> Lazy a`；`Lazy.force : Lazy a -> a`（memoize） |
| Test | ✅ 设计定型 | `assert : Bool -> Unit`（仅 `test*` 可用）；`kun test` 子命令 |

> **编译期代码展开基础设施**（Cli/Parser.Record 的共同依赖）：设计定型，但不在 MVP（v0.1.0）范围。Cli 和 Parser.Record 均推迟到 v0.3 实施，届时编译期内省基础设施（基于 Zig comptime + @typeInfo）与二者同时实现。

### 求值策略与块表达式

| 功能 | 状态 | 说明 |
|---|---|---|
| 立即求值 | ✅ 设计定型 | 所有表达式立即求值；`let in` 绑定立即；call-by-value |
| 块表达式 | ✅ 设计定型 | "单一表达式"更名为"块表达式"；`let in` 统一所有多语句形式 |
| `let in` 三种语句 | ✅ 设计定型 | 绑定（`name = expr`）/效应调用（无绑定，立即执行）/纯表达式（无绑定，告警） |
| `let in` 省略形式 | ✅ 设计定型 | 返回 `Unit` 时可省略 `in`（≡ `let <body> in ()`）；缩进对齐判定结束 |
| `let in` 嵌套 | ✅ 设计定型 | 嵌套 `let in` 各层独立；内层绑定可在外层使用 |
| `let in` 效应集推导 | ✅ 设计定型 | 体内所有效应语句的并集 |
| `Lazy` 显式惰性 | ✅ 设计定型 | `Lazy.lazy` 构造 thunk；`Lazy.force` 强制求值（memoize） |
| `Stream` 惰性特区 | ✅ 设计定型 | 内置惰性；元素按需拉取 |
| `&&`/`\|\|` 短路 | ✅ 设计定型 | 短路求值 |
| `case`/`if` 按需求值 | ✅ 设计定型 | 仅匹配分支求值 |

### 运行时

| 功能 | 状态 | 说明 |
|---|---|---|
| fork-exec 命令执行 | ✅ 设计定型 | 通过 pipe 捕获 stdout/stderr |
| Stream tagged union | ✅ 设计定型 | 替代函数指针链，双层间接→单层 |
| `let in` 顺序执行 | ✅ 设计定型 | 立即求值，按声明顺序；`defer` LIFO 逆序清理 |
| panic + unwind | ✅ 设计定型 | `defer` 始终执行；回收活跃子进程（SIGTERM → 5s → SIGKILL → waitpid）；Arena 销毁 |
| panic 退出码 | ✅ 设计定型 | `CommandFailed exitCode=n` → n；`NotFound` → 127；`PermissionDenied` → 126；`KilledBySignal signal=s` → 128+s；纯运行时错误/assert 失败/递归超限 → 1；SIGINT → 130；SIGTERM → 143 |
| Kun Shell | ✅ 设计定型 [推迟 v2.0] | 交互式环境；详见 [Kun Shell](kun-shell.md) |

### 安全 [实现推迟 v0.5]

> CLI 参数与安全控制见 [`kun` CLI 工具](kun-cli-tool.md)。安全沙箱设计已定型，实现推迟至 v0.5。

| 功能 | 状态 | 说明 |
|---|---|---|
| CLI `--allow-path` | ✅ 设计定型 [v0.5] | 路径级文件系统访问控制 |
| CLI `--allow-net` | ✅ 设计定型 [v0.5] | 网络出站/入站控制 |
| CLI `--allow-ffi` | ✅ 设计定型 | FFI 运行时检查；FFI 效应冒泡到 `main` 时未启用则拒绝执行 |
| CLI `--no-sandbox` | ✅ 设计定型 [v0.5] | 完全关闭沙箱 |
| CLI `--force` | ✅ 设计定型 [v0.5] | 强制运行（跳过安全确认） |
| CLI `--env=` | ✅ 设计定型 [v0.5] | 环境变量继承策略 |
| CLI `--cpu-limit` / `--mem-limit` | ✅ 设计定型 [v0.5] | rlimit 资源限制 |
| 效应安全模型 | ✅ 设计定型 | 用户效应必须 `handle` 消解；内置效应运行时默认 handler；FFI `--allow-ffi` 强制 |
| Landlock | ✅ 设计定型 [v0.5] | 内核 5.13+：文件控制；6.7+：文件 + 网络控制（首选） |
| Network namespace 网络隔离 | ✅ 设计定型 [v0.5] | `CLONE_NEWNET`（内核 3.0+），覆盖 Landlock 网络控制不可用场景 |
| Mount namespace 兜底 | ✅ 设计定型 [v0.5] | 内核 3.8+：目录级隔离（`pivot_root`） |
| seccomp-BPF | ✅ 设计定型 [v0.5] | 系统调用类型过滤 |
| `PR_SET_NO_NEW_PRIVS` | ✅ 设计定型 [v0.5] | 阻止 setuid/setgid 特权提升，Landlock 前置条件 |
| 环境变量安全过滤 | ✅ 设计定型 [v0.5] | 干净白名单 + 始终剔除列表 |

### 语法与工具

| 功能 | 状态 | 说明 |
|------|------|------|
| 块表达式语法 | ✅ 设计定型 | "单一表达式"更名为"块表达式"；`let in` 统一多语句 |
| 文档注释 | ✅ 设计定型 | 多行 `//` + Markdown；紧邻声明；`kun doc` 提取；支持标题/列表/代码块/链接/交叉引用 `[[Module.func]]` |
| 注释语法 | ✅ 设计定型 | `//` 行注释，无块注释 |
| 字面量前缀语法 | ✅ 设计定型 | `p"..."`、`r"..."`、`f"..."` |
| 多行字符串 | ✅ 设计定型 | `"""`、`f"""` |
| 字符串插值与格式化 | ✅ 设计定型 | `f"..."`，`{expr}` 嵌入 |
| `cmd` 字面量 | ✅ 设计定型 | 四段式：`cmd <命令> <子命令>* <选项>? <位置参数>?` |
| 泛型语法 | ✅ 设计定型 | Elm 风格空格分隔 |
| 函数类型 | ✅ 设计定型 | `<param> -> <result> ! <effectSet>`，无 `!` ≡ `! {}` |
| 函数应用 | ✅ 设计定型 | 空格分隔参数，无逗号 |
| `let in` 块表达式 | ✅ 设计定型 | 三种语句；返回 `Unit` 可省略 `in`；缩进对齐结束 |
| `defer` | ✅ 设计定型 | 绑定最近 `let in` 块，LIFO，panic 时执行 |
| `effect` 声明 | ✅ 设计定型 | Record 风格 `effect <Name> = { op : sig, ... }` |
| `handler` 声明 | ✅ 设计定型 | case of 风格 `<name> = handler <Effect> of <op> <args> -> <impl>` |
| `handle with` 表达式 | ✅ 设计定型 | 仅 `main`/`test*` 内可用 |
| `continue` / `abort` | ✅ 设计定型 | 控制流原语，每 handler 分支二选一 |
| `extern` 块 | ✅ 设计定型 | `extern <Name> from "lib" = { func : sig, ... }` |
| `assert` | ✅ 设计定型 | `Bool -> Unit`，仅 `test*` 可用，失败 panic |
| `TestResult` | ✅ 设计定型 | `Pass`/`Fail String`/`Skip String` |
| `test*` 函数 | ✅ 设计定型 | `test` 前缀命名，零参效应函数 `Unit ! {E}` 或 `TestResult ! {E}`，由 `kun test` 运行器消解 |
| List 解构与展开 | ✅ 设计定型 | `[a, ..rest]`、`[..la, 0, ..lb]` |
| 模式匹配 | ✅ 设计定型 | 穷举、守卫、嵌套、解构、or 模式 |
| 解构赋值 | ✅ 设计定型 | 元组/Record/List |
| 模块系统 | ✅ 设计定型 | 默认私有，`export` 公开，re-export，**无 wildcard**，别名解决冲突，选择性导入 + 全名引用，模块别名 |
| `alias` 别名 | ✅ 设计定型 | 结构等价，编译期展开，无构造器 |
| `type` ADT | ✅ 设计定型 | 名义等价，单变体/多变体一致，有 tag 不擦除 |
| `Int` 位运算 | ✅ 设计定型 | `&`/`\|`/`^`/`not`/`shl`/`shr`/`ushr`/`popCount`/`leadingZeros`/`trailingZeros`；优先级 `shl`/`shr` > `&` > `^` > `\|` |
| 可执行脚本 | ✅ 设计定型 | `main : List String -> Unit ! {IO, File, Cmd, ...}`（类型标注可选），`kun --run <file.kun>` |
| `kun doc` | ✅ 设计定型 | 为模块及函数生成 Markdown 文档（类型签名、变体、示例、交叉引用），实现推迟 v0.5 |
| `--trace` | ✅ 设计定型 | 可选函数调用追踪（文件名:行号:列号 + 参数 + 调用深度），缺省关闭 |

### 已废弃（2026.07 重设计）

| 功能 | 状态 | 替代 |
|------|------|------|
| `do` / `do in` 块 | ❌ 已废弃 | 统一 `let in`（返回 `Unit` 可省略 `in`） |
| "单一表达式范式" | ❌ 已废弃 | 更名"块表达式" |
| `?` 后缀（`c?`） | ❌ 已废弃 | `Cmd.execSafe c` |
| `!` 后缀（`c!`） | ❌ 已废弃 | `Cmd.exec c` |
| `Cmd.<bin>` 语法 | ❌ 已废弃 | `cmd` 字面量 |
| `Cmd[ "g++" ]` 转义 | ❌ 已废弃 | `cmd "g++"` |
| `Cmd.withRawOpt` | ❌ 已废弃 | 字符串键 |
| `Cmd.pipe?` | ❌ 已废弃 | `pipe` + `Cmd.execSafe` |
| `Cmd.pipe!` | ❌ 已废弃 | `pipe` + `Cmd.exec` |
| `\|>` 隐式触发执行 | ❌ 已废弃 | 显式 `Cmd.stream`/`Cmd.exec`/`Cmd.execSafe`；`\|>` 回归纯管道 |
| `Newtype` 概念 | ❌ 已废弃 | `type X = X T` 单变体 ADT（与多变体一致，有 tag 不擦除） |
| Nilable 隐式包装 | ❌ 已废弃 | 简化：`?T` 为 `Nilable T`；禁止嵌套 `??T` |
| Nilable 操作符脱糖 | ❌ 已废弃 | `Nil`/`Some` 为构造器，模式匹配 |
| Record 字段 Nil 填充 | ❌ 已废弃 | 简化 Nilable 语义 |
| 效应回调标记 `!`（旧式 `(a -> b)!`） | ❌ 已废弃 | 效应集 `! {E}` + 单效应变量 `e` |
| `EffectFn`/`Fn` 内部区分 | ❌ 已废弃 | 统一函数类型 `a -> b ! E`，效应集作为类型组成部分 |
| `let` 绑定延迟求值 | ❌ 已废弃 | 立即求值；`Lazy.lazy`/`Lazy.force` 显式惰性特区 |
| `do`/`let` 互斥 | ❌ 已废弃 | `let in` 统一，无互斥 |
| `IO T` 效应类型 | ❌ 已移除 | AST 标记替代（早期废弃） |
| `.cmd.kun` 文件格式 | ❌ 已移除 | `cmd` 字面量替代 |
| `with caps` 能力声明 | ❌ 已移除 | CLI `--allow-path` / `--allow-net` / `--allow-ffi` 替代 |
| `=!` / `<-!` 早返回 | ❌ 已移除 | `Cmd.execSafe` 替代 |
| `stdin` 关键字 | ❌ 已移除 | `Cmd.withStdin` 函数替代 |
| `command` 声明 | ❌ 已移除 | `export (…)` 声明替代 |
| dlopen/ptrace 命令加载 | ❌ 已移除 | fork-exec 统一替代 |
| Builder API / 幻影类型 | ❌ 已移除 | `cmd` 字面量 + Record 替代 |
| 能力管理器 | ❌ 已移除 | CLI 安全参数 + Landlock/mount ns 替代 |
| 命令签名系统 (Ed25519) | ❌ 已移除 | 不涉及注册中心 |
| `Std` 模块 | ❌ 已移除 | `File.currentDir` + `Cmd.withWorkDir` 替代 |
| `Nat` 类型 | ❌ 已移除 | `Int` + 运行时范围检查替代 |
| 扩展积类型 `{ Base \| field : T }` | ❌ 已移除 | Record 类型需精确静态匹配 |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.07.16 | 三项设计调整：（1）零参效应函数约定——签名 `-> T ! {E}` / `Unit -> T ! {E}` 改为 `T ! {E}`（无 `->` 前缀），`effect`/`extern` 操作记录 `Unit -> T` 改为 `T`，调用加 `!` 后缀（`Name!`），裸名为函数引用，`!` 后缀与已废弃的 Command 断言执行 `!` 是不同特性；`test*` 函数签名从 `Unit -> Unit/TestResult ! {E}` 改为零参效应函数 `Unit ! {E}` / `TestResult ! {E}`（功能清单第 17/28/45/58 行同步更新）（2）守卫子句改用 `if`（移除 `when` 关键字）（3）类型标注与值绑定支持同行形式 `name : Type = expr` |
| 2026.07.15 | 代数效应与命令系统重设计：新增 7 内置效应（IO/File/Cmd/Random/DateTime/Signal/FFI）、`effect`/`handler`/`handle with` 系统、`extern` FFI 块（仅 Linux，`--allow-ffi`）、`cmd` 字面量四段式、显式执行三入口（`Cmd.exec`/`Cmd.execSafe`/`Cmd.stream`）、录制/回放（JSON Lines 按时间戳）、`alias`/`type` 分离（结构 vs 名义等价，不做 tag 擦除）、`==` 浅比较 + `Equal` 模块深比较、Nilable 简化（禁止嵌套 `??T`）、立即求值 + `Lazy`/`Stream` 显式惰性、统一 `let in`（废弃 `do`/`do in`，Unit 返回可省略 `in`）、`defer` 绑定 `let in` 块、`continue`/`abort` 控制流原语、`assert`/`TestResult`、`Int` 位运算、文档注释规范、模块系统规则（默认私有/re-export/无 wildcard/别名）、panic 退出码规则、递归类型深度上限 256（`KUN_MAX_TYPE_DEPTH`）、Let 泛化值限制；废弃 `?`/`!` 后缀、`Cmd.<bin>`/`Cmd.pipe?`/`Cmd.pipe!`/`Cmd.withRawOpt`、`Newtype`、Nilable 隐式包装、效应回调标记 `!` 旧式、`EffectFn`/`Fn` 区分、`let` 延迟求值、`do`/`let` 互斥 |
| 2026.06.25 | 模块系统实现状态更新（四级搜索路径实现、--run 端到端） |
| 2026.06.18 | Kun Shell 添加 [推迟 v2.0] 标注：设计已定型，实现在 v2.0 前不启动 |
| 2026.06.14 | 安全加固：网络隔离 CLONE_NEWNET + seccomp 扩展 + PR_SET_NO_NEW_PRIVS + env 过滤扩展；标准库增补：`File.mkdir`/`mkdirAll`/`exists`、`Bytes.fromString`/`toString`、`Map.remove`、`String.replaceAll`；新增 `Test` 测试断言模块；效应跟踪：`!` → `EffectFn` 独立类型构造器 |
| 2026.06.14 | 效应跟踪更新：新增 `(a -> b)!` 效应回调标注；命令系统更新：移除 `do` 块隐式执行，新增 `Cmd.exec` 显式执行 |
| 2026.06.13 | REPL 重命名为 Kun Shell 并扩展设计（SQLite 日志、函数收藏、AST 哈希） |
| 2026.06.10 | 架构重设计：功能清单全面刷新 |
