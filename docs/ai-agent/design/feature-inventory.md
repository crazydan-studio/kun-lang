# 功能清单

## 当前版本（0.1.x — 设计阶段）

> 以下为设计阶段的功能清单，覆盖 0.1.0（MVP 基础）至 0.3.0（行多态）的设计内容。实现状态将随着开发进展更新。

### 类型系统

| 功能 | 状态 | 说明 |
|---|---|---|
| 基础类型 | ✅ 设计定型 | Int(i64)、Nat(独立非负)、Float(f64)、Bool、String(UTF-8)、Bytes、Char、Regex(matchAll+捕获组)、Duration、Unit、Path |
| 复合类型 | ✅ 设计定型 | List(Rope 实现，支持索引)、Map、Set(内建 Eq)、Stream、Tuple |
| 和类型 | ✅ 设计定型 | Result、自定义和类型，穷举检查 |
| Nilable 类型 `?T` | ✅ 设计定型 | 语言内置 Nilable 类型，`?T` 标记可选，`?.` 可选链 + `??` Nil 合并 |
| 代数数据类型 | ✅ 设计定型 | 积类型(Record/Tuple) + 和类型的组合 |
| 模式匹配 | ✅ 设计定型 | 和类型、列表、映射、守卫子句，穷举性规则 |
| 类型推断 | ✅ 设计定型 | Hindley-Milner 算法 W，Let-多态 |
| 泛型 | ✅ 设计定型 | 无约束参数化多态（简单泛型） |
| 效应类型 | ✅ 设计定型 | IO 边界标记，纯函数 vs 副作用 |
| 类型等价 | ✅ 设计定型 | 结构等价，无子类型 |
| 参数验证器 | 📋 设计中 | range、length、regex、enum、custom，链式组合 |

### 标准库类型

| 功能 | 状态 | 说明 |
|------|------|------|
| Port | ✅ 设计定型 | 0-65535，独立类型，isPrivileged/isRegistered/isDynamic |
| Pid | ✅ 设计定型 | 1..2^22-1，构造器 pid(n) |
| Signal | ✅ 设计定型 | POSIX 信号枚举，fromInt/toInt |
| Errno | ✅ 设计定型 | POSIX 错误码枚举，与 IOError 建立映射 |
| FileType | ✅ 设计定型 | 运行时文件类型枚举，Path 不内嵌类型信息 |
| IOError | ✅ 设计定型 | 结构化系统调用错误类型 |
| DateTime | ✅ 设计定型 | 绝对时间点，format/parse，与 Duration 互操作 |
| ExitCode | ✅ 设计定型 | 0-255，isSuccess/isFailure，预定义常量 |
| Uid / Gid | ✅ 设计定型 | 用户/组 ID 数字类型，名称按需查询；RunAs 和类型支持名字和 ID |
| IpAddress | ✅ 设计定型 | IPv4/IPv6 枚举，isLoopback/isPrivate，SocketAddr |

### 命令系统

| 功能 | 状态 | 说明 |
|---|---|---|
| 命令函数抽象 | ✅ 设计定型 | 将 Linux 命令抽象为类型安全函数。通过 `.cmd.kun` + Builder API 定义，全 Kun 语法，无需独立 DSL |
| `.cmd.kun` 文件格式 | ✅ 设计定型 | `command Xxx with "<bin>" export (...)` 声明，纯 Kun 语法构造 argv |
| Builder API | ✅ 设计定型 | `withOutput`/`withArg`/`withFlag`/`withArgs`/`withUnsafeArg`/`withPath`/`withEnv`/`withRunAs`/`exitcode` |
| 内建 Primitive 命令 | ✅ 设计定型 | 简单命令（ls/stat/du/df/cp/mv/rm/chmod/chown/mkdir/ln/readlink/free/uname/lscpu/uptime/ps/locate/walkDir 等）以 Zig 内建实现，调用方式与命令函数一致 |
| runAs 运行用户 | ✅ 设计定型 | 命令函数隐式 `runAs` 参数，类型为 `?RunAs`，通过 `process.run-as` 能力控制 |
| 输出结构化 | ✅ 设计定型 | `OutputMode` ADT（`LineStream`/`Document`）+ Parser 标准库 |
| 退出码处理 | ✅ 设计定型 | `exitcode` Builder 链式设置，`ExitCodeMap` 自定义映射，缺省 0→Ok/非0→Err |
| 安全栈 | ✅ 设计定型 | `process.run` 白名单 + `capability_check` + Namespace + seccomp 推导 + Landlock（5.13+） |
| 审计日志 | ✅ 设计定型 | 所有命令执行自动记录，含允许/拒绝结果，持久化到 `~/.kun/audit/` |
| 自动推导（scaffolding） | ✅ 设计定型 | `kun cmd init <command>` 从 man/--help 生成 `.cmd.kun` 骨架，开发辅助工具 |
| 签名与注册中心 | ✅ 设计定型 | Ed25519 签名 + 注册中心版本化管理（`kun cmd install/search/publish`） |
| 编译器封装 | ✅ 设计定型 | 14 条编译期验证规则，自动注入隐式字段 + `InternalCommand.run` |
| 隐式字段 | ✅ 设计定型 | `runAs`/`env`/`stdin`/`stdout`/`stderr`/`fd` 自动注入 |
| fd 重定向 | ✅ 设计定型 | `FdSpec` ADT（ReadFromPath/WriteToPath/ReadFromStr/InheritFrom/RedirectTo） |
| 超长参数自动分片 | ✅ 设计定型 | `List` 参数超出 `execve` 限制时自动分片 + 隐式合并 stdout |
| 环境变量注入 | ✅ 设计定型 | `env : ?Map String String` 隐式字段 |
| `run` 命令入口 | ✅ 设计定型 | `run""` 保留为无 `.cmd.kun` 命令的低优先级入口 |

### 运行时

| 功能 | 状态 | 说明 |
|---|---|---|
| dlopen 命令加载 | 📋 设计中 | 直接加载命令二进制的入口函数 |
| 结构化参数传递 | 📋 设计中 | 以结构化数据而非 argv 传递参数 |
| ptrace 透明适配层 | 📋 设计中 | 适配未标准化的命令 |
| 命令可用性约束 | ✅ 设计定型 | T4 `run`（`process.run` 白名单限制）→ T3 auto-infer → T2 CDF → T1 内建；运行时自动升级 |

### 管道与组合

| 功能 | 状态 | 说明 |
|---|---|---|
| 管道操作符 | ✅ 设计定型 | `\|>`, `<\|`, `>>`, `<<` 操作符及结合性均已定义 |
| 严格求值 | ✅ 设计定型 | 严格求值为默认，let 绑定延迟求值，Stream 惰性 |
| 高阶函数 | ✅ 设计定型 | map、filter、fold、reduce 等标准库函数已定义 |

### 安全

| 功能 | 状态 | 说明 |
|---|---|---|
| 最小权限原则 | ✅ 设计定型 | 默认工作目录访问，显式权限声明 |
| 能力安全 | ✅ 设计定型 | 能力获取、使用、丢弃、传递机制，含运行时检查架构 |
| Namespace 沙箱 | ✅ 设计定型 | mount namespace + PID namespace 隔离 |
| 容器环境检测 | ✅ 设计定型 | 避免嵌套命名空间 |
| 权限异常详细报告 | ✅ 设计定型 | 结构化异常，含资源类型、路径、所需能力、源码位置、拒绝原因、修改建议 |
| 零默认能力原则 | ✅ 设计定型 | 可执行脚本启动时无任何默认权限，所有能力必须显式声明 |
| `with caps` 声明语法 | ✅ 设计定型 | 脚本级 + 函数级（`with caps do`）二级能力声明 |
| 编译器内置能力对象 | ✅ 设计定型 | `(Namespace, Action, Targets)` 三元组，编译器内置 |
| 能力审查机制 | ✅ 设计定型 | `--audit` 静态审计 / `--confirm` 交互确认 / `--cap-log` 审计日志 |
| 独立资源预算限流层 | ✅ 设计定型 | CPU/内存限制独立于能力系统，由执行器参数控制 |
| CDF 驱动的行为验证 | ✅ 设计定型 | 输出类型不匹配、隐式 IO/网络访问检测 |
| 二进制完整性校验 | ✅ 设计定型 | SHA-256 哈希校验命令二进制未被篡改 |
| CDF 密码学签名 | ✅ 设计定型 | Ed25519 签名确保签名来源可信 |
| Seccomp 系统调用过滤 | ✅ 设计定型 | 基于 CDF 自动推导系统调用过滤规则 |
| 单命令沙箱隔离 | ✅ 设计定型 | 高风险命令在独立 namespace 中执行 |
| 信任分级策略 | ✅ 设计定型 | trusted / verified / sandboxed / denied 四级 |

### IO 与数据

| 功能 | 状态 | 说明 |
|---|---|---|
| Stream 类型 | ✅ 设计定型 | 惰性流，mmap/分块/非阻塞 IO |
| Result | ✅ 设计定型 | 显式错误处理，=! / <-! 操作符 |
| `?.` / `??` | ✅ 设计定型 | 可选链（`x ?. f`）和 Nil 合并（`x ?? default`）操作符 |
| =! / <-! 操作符 | ✅ 设计定型 | 绑定期解包 Ok，传播 Err |
| Effect 类型 | ✅ 设计定型 | 结构化 IO 操作管理 |

### 语法与工具

| 功能 | 状态 | 说明 |
|------|------|------|
| 表达式导向语法 | ✅ 设计定型 | 借鉴 Elm/Haskell/Rust，语法设计文档已定型 |
| 注释语法 | ✅ 设计定型 | `//` 行注释，类型/函数/let/模块上的注释为文档注释（支持 Markdown） |
| 字面量前缀语法 | ✅ 设计定型 | `p"..."`（Path）、`r"..."`（Regex）、`f"..."`（插值字符串）统一双引号 |
| 多行字符串 | ✅ 设计定型 | `"""` 包裹，自动去公共缩进 |
| 字符串插值与格式化 | ✅ 设计定型 | `f"..."` 前缀，`{expr}` 嵌入，`:` 格式说明（类 Python） |
| 泛型语法 | ✅ 设计定型 | Elm 风格空格分隔（`List Int`），嵌套用括号分组，无尖括号 |
| 函数类型 | ✅ 设计定型 | Elm 风格柯里化（`Int -> Int -> Int`），元组参数仅用于元组 |
| 函数应用 | ✅ 设计定型 | 空格分隔参数，无逗号；元组参数用圆括号包裹 |
| let 绑定 | ✅ 设计定型 | 单条无 `let`，多条 `let ... in` 语法 |
| List 解构与展开 | ✅ 设计定型 | `[a, ..rest] = list` 解构，`[..la, 0, ..lb]` 展开 |
| 模式匹配 | ✅ 设计定型 | 新形式：`[a, ..rest]`（List）、`{x as x1, y}`（Record 别名）、`(1, y)`（元组） |
| 解构赋值 | ✅ 设计定型 | 元组/Record（含 `as` 别名）/List 解构 |
| 行多态 Record 类型 | 📋 设计中 | `{ a \| name : String }` 行多态，`{ Base \| field : T }` 扩展积类型 |
| 模块系统 | ✅ 设计定型 | `module ... export` 声明，`import ... with (...)` 导入，`Result(..)` 变体导入/导出 |
| REPL 交互环境 | 📋 设计中 | 结构化 REPL，语法高亮，错误报告 |
| 点调用 | ✅ 设计定型 | 仅限积类型字段投影和元组索引，无方法调用 |
