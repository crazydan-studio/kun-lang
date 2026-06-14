# 功能清单

## 当前版本（2026.06 — 架构重设计）

> 以下为架构重设计后的功能清单。实现状态将随着开发进展更新。

### 类型系统

| 功能 | 状态 | 说明 |
|---|---|---|
| 基础类型 | ✅ 设计定型 | Int(i64)、Float(f64)、Bool、String(UTF-8)、Bytes、Char、Regex、Duration、Unit、Path |
| 复合类型 | ✅ 设计定型 | List、Map、Set、Stream(tagged union)、Tuple |
| 和类型 | ✅ 设计定型 | Result、自定义和类型，穷举检查 |
| Nilable 类型 `?T` | ✅ 设计定型 | 语言内置 Nilable 类型，`?.` 可选链 + `??` Nil 合并 |
| 代数数据类型 | ✅ 设计定型 | 积类型(Record/Tuple) + 和类型的组合 |
| 模式匹配 | ✅ 设计定型 | 和类型、列表、映射、守卫子句，穷举性规则 |
| 类型推断 | ✅ 设计定型 | Hindley-Milner 算法 W，Let-多态 |
| 泛型 | ✅ 设计定型 | 无约束参数化多态（简单泛型） |
| 效应跟踪 | ✅ 设计定型 | AST 标记 + 类型签名 `(a -> b)!` 效应回调标注（内部退糖为 `EffectFn(a, b)`，与 `Fn(a, b)` 在结构等价下不兼容） |
| 类型等价 | ✅ 设计定型 | 结构等价，无子类型 |

### 标准库类型

| 功能 | 状态 | 说明 |
|------|------|------|
| Port | ✅ 设计定型 | 0-65535，newtype，`of` + `isValid` |
| Pid | ✅ 设计定型 | newtype，`Pid.of` 构造 |
| Signal | ✅ 设计定型 | POSIX 信号枚举，`Signal.on`（signalfd），仅可执行脚本可用 |
| Errno | ✅ 设计定型 | POSIX 错误码枚举，与 IOError 建立映射 |
| FileType | ✅ 设计定型 | 运行时文件类型枚举（Regular/SymbolicLink/CharDevice） |
| IOError | ✅ 设计定型 | 结构化系统调用错误类型 |
| CommandError | ✅ 设计定型 | 语义化命令错误类型（NotFound/PermissionDenied/CommandFailed/KilledBySignal/IoError/PipeFailed） |
| DateTime | ✅ 设计定型 | newtype，`format` 返回 `Result String String` |
| ExitCode | ✅ 设计定型 | 0-255，newtype，`of` + `isValid`，预定义常量 |
| Uid / Gid | ✅ 设计定型 | 用户/组 ID 数字类型（Int newtype） |
| Decimal | ✅ 设计定型 | 精确十进制数值（非编译器内置） |
| FileMode | ✅ 设计定型 | 文件权限位（`of`/`isReadable`/`isWritable`/`isExecutable`/`fromInt`） |
| FileStat | ✅ 设计定型 | 完整文件元数据（`size`/`type`/`mtime`/`mode`/`owner`/`device` 等） |
| SocketAddr | ✅ 设计定型 | 套接字地址（`Tcp`/`Udp` + `IpAddress` + `Port`） |
| IpAddress | ✅ 设计定型 | IPv4/IPv6 枚举，SocketAddr |

### 标准库模块

| 功能 | 状态 | 说明 |
|------|------|------|
| Math | ✅ 设计定型 | 三角函数、指数对数、幂运算、角度转换、常量 |
| Function | ✅ 设计定型 | `identity`/`always`/`<\|`/`\|>`/`<<`/`>>`，始终缺省可用 |
| Nil | ✅ 设计定型 | `withDefault`/`map`/`orElse`/`toResult`/`andThen`，变体 `Nil` 缺省可用，函数需显式导入 |
| String | ✅ 设计定型 | `toString`（编译器级泛型）+ 类型互转函数 |
| Regex | ✅ 设计定型 | 正则匹配与替换（`fromString` 运行时构造） |
| Bytes | ✅ 设计定型 | 二进制编解码（`toHex`/`fromHex`） |
| List | ✅ 设计定型 | 不可变列表查询与变换 |
| Map | ✅ 设计定型 | 不可变字典查询与变换 |
| Set | ✅ 设计定型 | 不可变集合操作（`insert`/`remove`/`union`/`intersect`/`diff`） |
| Result | ✅ 设计定型 | `map`/`mapError`/`andThen`/`withDefault` |
| Random | ✅ 设计定型 | 密码学安全随机数 |
| Stream | ✅ 设计定型 | 惰性序列（纯变换 + IO 消费） |
| IO | ✅ 设计定型 | 控制台 IO，需显式导入 |
| Env | ✅ 设计定型 | 环境变量读写 |
| File | ✅ 设计定型 | 进程内文件 syscall（含 `createTempFile`/`createTempDir`） |
| Cmd | ✅ 设计定型 | 命令构造/修饰/执行 |
| Process | ✅ 设计定型 | `exit`/`pid`/`kill`/`wait`/`sleep` |
| Duration | ✅ 设计定型 | 时间段算术/比较/单位转换（编译器内置类型，模块函数需显式导入） |
| Task | ✅ 设计定型 | `spawn`/`all` 并发命令执行 |
| Sys | ✅ 设计定型 | `ps`/`free`/`df`
| Cli | ✅ 设计定型 | 类型驱动 CLI 解析，对标 argparse；auto --help；子命令/互斥组/透传 |
| Validator | ✅ 设计定型 | `oneOf`/`range`/`nonEmpty`/`regex`，供 `Cli.withValidator` 使用 |
| Path | ✅ 设计定型 | `cwd`/`parent`/`fileName`/`extension`/`join`/`(++)`/`toString` |
| Int | ✅ 设计定型 | 整数取反/绝对值/类型互转，需显式导入 |
| Float | ✅ 设计定型 | 浮点取反/绝对值/取整/平方根/容差比较(`approxEqual`)/类型互转，需显式导入 |
| Decimal | ✅ 设计定型 | 精确十进制数值，非编译器内置 |
| Parser.JSON | ✅ 设计定型 | JSON 值类型与字符串互转 |
| Parser.Record | ✅ 设计定型 | Record 类型安全反序列化（编译期代码生成） |
| Test | ✅ 设计定型 | 测试断言（`equal`/`ok`/`panics`），`kun test` 子命令 |

### 命令系统

> 完整设计见 [OS 命令调用机制](command-system.md)。

| 功能 | 状态 | 说明 |
|---|---|---|
| `Cmd.<bin>` 语法 | ✅ 设计定型 | 命令调用统一入口，Record 选项自动映射 camelCase → kebab-case |
| `Cmd["..."]` 转义 | ✅ 设计定型 | 特殊字符命令名的兜底语法 |
| 类型化模块自动发现 | ✅ 设计定型 | 编译时搜索 `~/.kun/cmd/` → `$KUN_PATH/cmd/` → `<runtime>/lib/kun/cmd/` |
| kun cmd init | ✅ 设计定型 | 从 man/--help 自动生成命令模块骨架 |
| Cmd.pipe / Cmd.pipe? | ✅ 设计定型 | OS 管道链（pipe2 + fork），? 变体返回 Result |
| Cmd.withEnv | ✅ 设计定型 | 链式修饰环境变量 |
| Cmd.withCwd | ✅ 设计定型 | 指定子进程工作目录（per-command chdir） |
| Cmd.withStdin | ✅ 设计定型 | stdin 注入（字符串/流式） |
| Cmd.withRawOpt | ✅ 设计定型 | 追加原始 argv token |
| Cmd.mergeStderr | ✅ 设计定型 | 合并 stderr 到 stdout |
| Cmd.andThen / Cmd.orElse | ✅ 设计定型 | 命令短路条件组合（Bash `&&`/`\|\|` 替代） |
| Cmd.timeout | ✅ 设计定型 | 命令超时（SIGKILL + waitpid） |
| Cmd.retry | ✅ 设计定型 | 命令重试（内部调用 Cmd.timeout） |
| Cmd.which | ✅ 设计定型 | PATH 查找命令 |
| Command 执行模型 | ✅ 设计定型 | 延迟执行，`\|>` 管道隐式触发 / `Cmd.exec` 显式执行 / `?` 后缀立即执行；未被消费的 Command 是编译错误 |
| Cmd.exec | ✅ 设计定型 | 显式执行 Command 值，丢弃输出，失败 panic |
| camelCase→kebab-case 映射 | ✅ 设计定型 | 多大写断词、全小写不断词、单字符短 flag；非标准 flag 用 Cmd.withRawOpt |
| Cmd.withRunAs | ✅ 设计定型 | 指定命令执行用户（setuid） |
| 预置高频命令模块 | ✅ 设计定型 | 首批 20 个高频命令类型定义（git、docker、curl 等） |

### 运行时

| 功能 | 状态 | 说明 |
|---|---|---|
| fork-exec 命令执行 | ✅ 设计定型 | 通过 pipe 捕获 stdout/stderr |
| Stream tagged union | ✅ 设计定型 | 替代函数指针链，双层间接→单层 |
| do 块顺序执行 | ✅ 设计定型 | defer LIFO 逆序清理 |
| panic + unwind | ✅ 设计定型 | defer 始终执行，panic-with-defer 语义 |
| Kun Shell | ✅ 设计定型 | 交互式环境：表达式求值 + 类型查询 + `:type`/`:load`/`:edit`/`:run`/`:save`；SQLite 日志存储、DuckDB 可替换引擎、函数收藏、AST 哈希唯一引用；详见 [Kun Shell](kun-shell.md) |

### 管道与组合

| 功能 | 状态 | 说明 |
|---|---|---|
| 管道操作符 | ✅ 设计定型 | `\|>`、`<\|`、`>>`、`<<` 操作符及结合性均已定义 |
| 严格求值 | ✅ 设计定型 | 严格求值为默认，let 绑定延迟求值，Stream 惰性 |
| 高阶函数 | ✅ 设计定型 | map、filter、fold、reduce 等标准库函数已定义 |

### 安全

> CLI 参数与安全控制见 [`kun` CLI 工具](kun-cli-tool.md)。

| 功能 | 状态 | 说明 |
|---|---|---|
| CLI `--allow-path` | ✅ 设计定型 | 路径级文件系统访问控制 |
| CLI `--allow-net` | ✅ 设计定型 | 网络出站/入站控制 |
| CLI `--no-sandbox` | ✅ 设计定型 | 完全关闭沙箱 |
| CLI `--force` | ✅ 设计定型 | 强制运行（跳过安全确认） |
| CLI `--env=` | ✅ 设计定型 | 环境变量继承策略 |
| CLI `--cpu-limit` / `--mem-limit` | ✅ 设计定型 | rlimit 资源限制 |
| Landlock | ✅ 设计定型 | 内核 5.13+：文件控制；6.7+：文件 + 网络控制（首选） |
| Network namespace 网络隔离 | ✅ 设计定型 | `CLONE_NEWNET`（内核 3.0+），覆盖 Landlock 网络控制不可用场景 |
| Mount namespace 兜底 | ✅ 设计定型 | 内核 3.8+：目录级隔离（`pivot_root`） |
| seccomp-BPF | ✅ 设计定型 | 系统调用类型过滤（含 `bpf`/`perf_event_open`/`userfaultfd`/`memfd_create`/`io_uring_*`） |
| `PR_SET_NO_NEW_PRIVS` | ✅ 设计定型 | 阻止 setuid/setgid 特权提升，Landlock 前置条件 |
| 环境变量安全过滤 | ✅ 设计定型 | 干净白名单 + 始终剔除列表（含 `BASH_FUNC_*`/`LD_*`/解释器注入向量） |

### IO 与数据

| 功能 | 状态 | 说明 |
|---|---|---|
| Stream 类型 | ✅ 设计定型 | tagged union，comptime 融合 |
| `Cmd.<bin>?` / `Cmd.pipe?` | ✅ 设计定型 | 返回 Result，显式错误处理 |
| `?.` / `??` | ✅ 设计定型 | 可选链和 Nil 合并操作符 |
| defer | ✅ 设计定型 | 结构化资源清理 |
| File.* 进程内 syscall | ✅ 设计定型 | File.readString/readBytes/stat/list 等，始终返回 Result |

### 语法与工具

| 功能 | 状态 | 说明 |
|------|------|------|
| 表达式导向语法 | ✅ 设计定型 | 借鉴 Elm/Haskell/Rust |
| 注释语法 | ✅ 设计定型 | `//` 行注释，文档注释支持 Markdown |
| 字面量前缀语法 | ✅ 设计定型 | `p"..."`、`r"..."`、`f"..."` |
| 多行字符串 | ✅ 设计定型 | `"""`、`f"""` |
| 字符串插值与格式化 | ✅ 设计定型 | `f"..."`，`{expr}` 嵌入 |
| 泛型语法 | ✅ 设计定型 | Elm 风格空格分隔 |
| 函数类型 | ✅ 设计定型 | Elm 风格柯里化 |
| 函数应用 | ✅ 设计定型 | 空格分隔参数，无逗号 |
| let 绑定 | ✅ 设计定型 | `let ... in` |
| List 解构与展开 | ✅ 设计定型 | `[a, ..rest]`、`[..la, 0, ..lb]` |
| 模式匹配 | ✅ 设计定型 | 穷举、守卫、嵌套、解构 |
| 解构赋值 | ✅ 设计定型 | 元组/Record/List |
| 扩展积类型 | ❌ 已移除 | 移除 `{ Base \| field : T }` 语法，Record 类型需精确静态匹配 |
| 模块系统 | ✅ 设计定型 | 目录即命名空间，`export (...)`，`import X (...)` |
| 可执行脚本 | ✅ 设计定型 | `main : List String -> Unit`（类型标注可选） |
| `kun doc` | ✅ 设计定型 | 为模块及函数生成 Markdown 文档（类型签名、变体、示例、交叉引用） |
| `--trace` | ✅ 设计定型 | 可选函数调用追踪（文件名:行号:列号 + 参数 + 调用深度），缺省关闭 |

### 已废弃/移除

| 功能 | 状态 | 说明 |
|------|------|------|
| `Nat` 类型 | ❌ 已移除 | `Int` + 运行时范围检查替代 |
| `IO T` 效应类型 | ❌ 已移除 | AST 标记替代 |
| `.cmd.kun` 文件格式 | ❌ 已移除 | `Cmd.<bin>` 语法 + 类型化模块替代 |
| `with caps` 能力声明 | ❌ 已移除 | CLI `--allow-path` / `--allow-net` 替代 |
| `=!` / `<-!` 早返回 | ❌ 已移除 | `Cmd.<bin>?` / `Cmd.pipe?` 替代 |
| `stdin` 关键字 | ❌ 已移除 | `Cmd.withStdin` 函数替代 |
| `command` 声明 | ❌ 已移除 | `export (…)` 声明替代 |
| dlopen/ptrace 命令加载 | ❌ 已移除 | fork-exec 统一替代 |
| Builder API / 幻影类型 | ❌ 已移除 | `Cmd.<bin>` + Record 替代 |
| 能力管理器 | ❌ 已移除 | CLI 安全参数 + Landlock/mount ns 替代 |
| 命令签名系统 (Ed25519) | ❌ 已移除 | 不涉及注册中心 |
| `Std` 模块 | ❌ 已移除 | `Path.cwd`（常量）+ `Cmd.withCwd`（per-command chdir）替代 |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.14 | 安全加固：网络隔离 CLONE_NEWNET + seccomp 扩展 + PR_SET_NO_NEW_PRIVS + env 过滤扩展；标准库增补：`File.mkdir`/`mkdirAll`/`exists`、`Bytes.fromString`/`toString`、`Map.remove`、`String.replaceAll`；新增 `Test` 测试断言模块；效应跟踪：`!` → `EffectFn` 独立类型构造器 |
| 2026.06.14 | 效应跟踪更新：新增 `(a -> b)!` 效应回调标注；命令系统更新：移除 `do` 块隐式执行，新增 `Cmd.exec` 显式执行 |
| 2026.06.13 | REPL 重命名为 Kun Shell 并扩展设计（SQLite 日志、函数收藏、AST 哈希） |
| 2026.06.10 | 架构重设计：功能清单全面刷新 |
