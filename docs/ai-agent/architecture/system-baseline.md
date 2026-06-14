# 系统基线

## 技术栈

| 层 | 技术选择 | 说明 |
|---|---|---|
| 宿主语言 | Zig 0.13.0 | 高性能、无 hidden control flow、直接操作内存 |
| 目标平台 | Linux | 使用 fork/exec、namespace、Landlock、seccomp 等 Linux 特有机制 |
| 二进制产物 | `kun`（脚本执行器）+ `kun-shell`（交互式环境）+ `libkun_core.so`（共享解释器核心） | 单体可执行文件 + 动态链接库 |
| 文档构建 | VitePress + pnpm | 现代化的静态文档站点 |
| 版本控制 | Git + GitHub | 分布式版本控制 |

## 运行时生命周期

运行时从启动到退出的完整流程分为四个阶段：

### 启动阶段

```
CLI 参数解析 → 源码读取 → 词法分析 → 语法分析 → 类型检查
```

1. **CLI 参数解析**：运行时解析命令行参数，分离安全参数（`--allow-path`、`--allow-net` 等）与脚本参数
2. **源码读取**：以 UTF-8 编码读取 `.kun` 文件内容到内存
3. **词法分析**：将源码扫描为 Token 序列
4. **语法分析**：将 Token 序列解析为 AST
5. **类型检查**：对 AST 进行类型推断和检查，生成带类型标注的 Typed AST；同时执行效应检查（AST 标记含 `do` 块的函数为效应函数）

类型检查通过后才进入初始化阶段。类型检查失败时输出结构化错误报告并终止。

### 初始化阶段

```
运行时环境建立 → 模块解析 → 沙箱安装 → 标准库绑定
```

1. **运行时环境建立**：
   - 创建 Arena 分配器（per 脚本执行）
   - 设置全局求值环境（变量帧栈）
   - 注册内置 Primitive 函数表

2. **模块解析与加载**：
   - 解析 `import` 语句
   - 按搜索路径查找模块文件
   - 递归加载依赖模块并缓存
   - 检测循环依赖

3. **沙箱安装**：
   - 解析 CLI 安全参数（`--allow-path`、`--allow-net`、`--no-sandbox`、`--force`、`--env=`、`--cpu-limit`、`--mem-limit`）
   - 父进程安装主沙箱层：Landlock（首选，内核 5.13+）→ mount namespace（兜底，内核 3.8+）→ 拒绝运行（内核 < 3.8）
   - 子进程策略安装（fork 后 exec 前）：seccomp-BPF 系统调用过滤 + rlimit 资源限制

4. **标准库绑定**：
   - 将内置类型（List、Map、Set、Stream 等）的操作注册到环境
   - 将 IO 操作注册为 Primitive

### 执行阶段

```
入口解析 → AST 求值 → do 块顺序执行 → 命令调用
```

1. **入口解析**：按入口规则确定执行起点（`main : List String -> Unit`）
2. **AST 求值**：递归求值 Typed AST 节点
3. **do 块顺序执行**：`do` 块按顺序执行语句，`defer` 在退出时按 LIFO 逆序执行
4. **命令调用**：`Cmd.<bin>` 构造 Command 值，通过 `|>` 管道隐式触发、`Cmd.exec` 显式执行或 `?` 后缀立即执行时 fork-exec

求值策略详见下方"执行模型"章节。

### 清理阶段

```
defer 执行 → 资源释放 → 退出码传播 → 运行时终止
```

1. **defer 执行**：按 LIFO 逆序执行所有 `defer` 块
2. **资源释放**：
   - 关闭所有打开的文件描述符
   - 销毁 Arena 分配器（释放所有 per-script 分配的内存）
   - 释放模块缓存

3. **退出码传播**：根据执行结果确定进程退出码
   - `main` 正常返回 → 退出码 0
   - 未处理的 panic 传播到顶层 → 退出码依据错误类型确定

## 执行模型

### 求值策略

Kun 采用**严格求值**（Strict Evaluation）作为默认策略：

| 构造 | 求值策略 | 说明 |
|---|---|---|
| 纯表达式 | 严格 | 参数在函数应用前求值 |
| 函数体 | 严格 | 进入函数时立即求值 |
| `case` 分支 | 按需 | 仅匹配到的分支被求值 |
| `if`/三元 | 按需 | 仅条件匹配的分支被求值 |
| `&&`/`\|\|` | 短路 | 左侧确定结果时右侧不求值 |
| `Stream` | 惰性 | 元素在消费时按需拉取 |
| `let ... in` 绑定 | 延迟 | `let` 与 `in` 之间的绑定仅在 `in` 之后被引用时才真正求值，绑定时不求值 |

### do 块与效应函数

`do` 块按顺序执行效应操作。含 `do` 块的函数通过编译器 AST 标记自动识别为效应函数。签名中声明了 `(a -> b)!` 效应回调参数的函数同样自动标记为效应函数。纯函数（无 `do` 块、无 `!` 参数）不能调用效应函数——编译期拒绝。

效应函数涵盖以下命名空间的所有函数：`IO.*`、`File.*`、`Env.*`、`Process.*`、`Sys.*`、`Task.*`，以及 `Signal.on`（信号注册）。`Cmd.<bin>` 构造 `Command` 值及 `Cmd` 装饰函数（`Cmd.pipe`、`Cmd.withEnv` 等，接收并返回 `Command`）为纯操作。`Cmd.<bin>?`、`Cmd.pipe?`、`Cmd.timeout`、`Cmd.retry`（立即执行并返回 `Result`）及 `Cmd.exec`（显式执行 Command 并丢弃输出）为效应函数。

`do` 块内使用 `=` 绑定值（纯值或效应函数的返回值）。`do in` 形式在副作用执行后返回纯值。语法细节见 [`syntax.md`](../design/syntax.md) do 块章节。

### Command 执行模型

`Cmd.<bin>` 返回 `Command` 值——不立即执行。执行触发条件见 [OS 命令调用机制](../design/command-system.md#command-执行模型)（`|>` 管道隐式触发、`Cmd.exec` 显式执行、`?` 后缀立即执行）。未被消费的 `Command` 值是编译错误。具体执行流程见下方「命令调用机制」章节。

### Stream 惰性求值

Stream 在运行时表示为 tagged union，替代函数指针链：

```zig
const Stream = union(enum) {
    cmd: struct { fd: i32, pid: i32, buf: []u8 },
    mapped: struct { upstream: *Stream, f: FnPtr },
    filtered: struct { upstream: *Stream, pred: FnPtr },
    taken: struct { upstream: *Stream, remaining: usize },
    dropped: struct { upstream: *Stream, remaining: usize },
    lines: struct { upstream: *Stream, buf: []u8, pos: usize },
    parse_mapped: struct { upstream: *Stream, f: FnPtr },
    parse_mapped_keep: struct { upstream: *Stream, f: FnPtr },
};
```

- `cmd` 变体持有子进程的 pipe fd 和 pid，`buf` 为堆分配
- 变换操作（`map`、`filter`、`take`、`drop`）通过包裹上游 Stream 构造新节点
- `lines` 变体：按 `\n` 切分输入流——`buf` 为跨 chunk 的累积缓冲区，`pos` 追踪下一行起始位置
- `parse_mapped`：映射并丢弃 `Err` 结果（对应 `Stream.parseMap`）
- `parse_mapped_keep`：映射并保留 `Result`（对应 `Stream.parseMapKeep`）
- 终端操作（`toList`、`iter`、`fold`）循环消费直到 stream 终止
- 编译器检测相邻的纯参数操作（`map`/`take`）在代码生成阶段合并为单循环

#### Stream 消费强制检查

编译器对未被消费的 Stream 执行流敏感检测：若 `do` 块内通过 `Cmd.<bin>` 或 `Cmd.pipe` 产生的 Stream 在块退出时尚未被终端操作（`toList`/`iter`/`fold`/`string`/`bytes`）消费，编译期报错并提示添加终端操作。条件消费路径（如 `if cond then stream |> Stream.toList else ...`）中，所有路径均需消费 Stream。此检测防止子进程变为僵尸进程和 fd 泄漏。

#### 管道缓冲区与非阻塞 IO

子进程 stdout 通过 pipe 捕获，Linux 默认 pipe 缓冲区为 64KB。Stream 消费时若子进程输出超过缓冲区容量，子进程 `write()` 阻塞等待父进程 `read()`。Kun 运行时采用以下策略：

- 每个 `cmd` 变体持有独立 pipe fd，消费循环中通过 `poll`/`select` 实现非阻塞读取
- 编译器对纯 Stream 管道（无 IO 源）生成单循环消费代码，无缓冲区风险
- IO 绑定的 Stream 管道在终端操作时驱动逐元素拉取，父进程在消费每一元素后立即释放缓冲区空间

此策略确保长时间运行的管道（如 `Cmd.find |> Stream.lines |> Stream.filter`）不会因缓冲区满而死锁。

## 错误诊断

### 错误类型体系

运行时定义了以下结构化错误类型：

### `TypeError`

类型检查阶段的错误，包含源文件名、行号、列号、期望类型、实际类型、错误原因、修复建议。

### 类型检查算法

类型检查采用 **Hindley-Milner**（HM）推断，分为两个阶段：

#### 阶段一：约束生成

遍历 Typed AST，为每个表达式节点生成类型约束方程。约束类型包括：

- **等价约束**：`T1 ~ T2`，要求两个类型合一为相同结构
- **实例化约束**：多态类型在使用点生成新的类型变量，确保泛型函数每次调用独立
- **函数应用约束**：`f a` 生成 `Tf ~ Ta -> Tr`（函数类型与参数类型、返回类型的关系）

Let 多态：`let` 绑定的泛型函数在约束生成时对其类型签名做泛化（generalization），产生的类型变量进入多态环境，每次引用时实例化为新类型变量。

#### 阶段二：合一

对阶段一生成的约束集，使用 **Algorithm W** 风格的合一求解器逐条解析：

1. 维护一个**代换**（substitution）映射，记录类型变量到具体类型的替换关系
2. 对每条等价约束 `T1 ~ T2`，按结构递归合一：
   - 两者同为类型变量 → 代换中任一为另一（按优先级取）
   - 一方为类型变量，另一方为具体类型 → 代换该变量为该类型（occurs check 防止无限递归）
   - 两者同为具体类型（如 `List a ~ List Int`） → 递归合一部分参数
   - 结构不匹配（如 `Int ~ String`） → 产生 `TypeError`
3. 全部约束合完成后，将最终的代换应用到 AST，生成带完整类型标注的 Typed AST

#### Let 多态与泛化

`let` 绑定引入的多态函数类型通过以下步骤处理：

```
let f = \x -> x
// 1. 推断 f 的类型变量：a -> a
// 2. 泛化：将自由类型变量提升为多态类型变量：forall a. a -> a
// 3. 实例化：f 42 → 实例化为 Int -> Int；f "hi" → 实例化为 String -> String
```

#### 效应检查

在类型合一的同时，效应检查器（Effect Checker）扫描 AST 中的 `do` 块、效应命名空间调用和 `!` 参数声明：

- 识别含 `do` 块的函数，标记为效应函数
- 识别签名中声明了 `(a -> b)!` 参数的函数，标记为效应函数（`!` 在编译器内部退糖为 `EffectFn(a, b)` 类型构造器，与 `Fn(a, b)` 在结构等价下不兼容）
- 验证纯函数体中无效应函数调用
- 验证纯函数签名中无 `!` 参数声明
- 验证 `!` 参数的传入实参为效应函数（实参的类型为 `EffectFn(a, b)`，效应检查器验证该函数含 `do` 块或效应命名空间调用）
- 验证 `do` 块外的代码无效应命名空间（`IO.*`、`File.*`、`Env.*`、`Process.*`、`Sys.*`、`Task.*`，以及 `Signal.on`）函数调用
- 验证 `Cmd.<bin>?`、`Cmd.pipe?`、`Cmd.timeout`、`Cmd.retry`、`Cmd.exec` 仅在 `do` 块内使用
- Lambda 含有效应函数调用时，要求该 lambda 在 `do` 块内定义
- 验证 `do` 块内未被消费的 `Command` 值：未被 `Cmd.exec`、`|>` 管道或 `?` 后缀消费的 `Command` 值为编译错误

效应检查失败也产生 `TypeError`，纳入统一的错误报告。

#### 错误报告

类型错误输出包含：

| 字段 | 说明 |
|------|------|
| 源文件名 + 行号 + 列号 | 错误发生的精确位置 |
| 期望类型 | 上下文要求的类型 |
| 实际类型 | 推断出的实际类型 |
| 错误原因 | 类型不匹配的具体原因（如 "Int 与 String 无法合一"） |
| 修复建议 | 基于启发式规则的建议（如 "是否缺少类型转换？"） |

### `CommandError`

命令执行阶段的语义化错误类型，完整定义见 [`standard-library.md`](../design/standard-library.md)。包含 `NotFound`、`PermissionDenied`、`CommandFailed`、`KilledBySignal`、`IoError`、`PipeFailed` 六个变体。

### 错误传播模型

| 错误类型 | 检测阶段 | 传播方式 | 处理方式 |
|---|---|---|---|
| `TypeError` | 类型检查 | 编译期报错 | 必须修复后重试 |
| 命令失败（无 `?`） | 运行时 | panic | unwind + defer 链 |
| 命令失败（有 `?`） | 运行时 | `Result` | 调用者通过 `case` 处理 |
| 同步 syscall 失败 | 运行时 | `Result` | 调用者通过 `case` 处理 |

### panic 语义

panic 触发 unwind 时，当前 `do` 块的所有 `defer` 按 LIFO 逆序始终执行。未捕获的顶层 panic 退出码：

| 错误变体 | Kun 进程退出码 |
|---|---|
| `CommandFailed { exitCode = n }` | `n`（传播子进程退出码） |
| `NotFound _` | 127 |
| `PermissionDenied _` | 126 |
| `KilledBySignal { signal = s }` | `128 + s` |
| `PipeFailed { error }` | 传播内层 `error` 的退出码 |
| `IoError _` | 1 |
| 用户调用 `Process.exit n` | `n` |

panic 发生时若存在活跃子进程（已 fork 但未 waitpid），运行时在 unwind 前按以下顺序处理：

1. 向所有活跃子进程发送 `SIGTERM`，等待最多 5 秒
2. 超时仍未退出的子进程发送 `SIGKILL`
3. `waitpid` 回收所有子进程后执行 defer 链
4. defer 中清理操作（如 `File.remove tmp`）在子进程终止后安全执行，避免删除正在写入的文件

此策略确保资源清理的确定性，防止孤儿进程和文件损坏。

> **已知限制**：若子进程处于 D 状态（不可中断睡眠——通常因等待 NFS/磁盘 I/O），`SIGKILL` 无法终止，`waitpid` 将永久阻塞 Kun 进程。此系 Linux 内核的根本性限制，无法在用户态解决。`--cpu-limit` rlimit 对此场景无效——D 状态进程不消耗 CPU 时间，`RLIMIT_CPU` 不会触发。Kun 通过在 panic 清理阶段设置 wall-clock 超时（`alarm()` / `timerfd`）缓解：若整个清理流程超过 10 秒，Kun 进程自行 `_exit(1)` 退出。此策略确保单个 Kun 进程不会永久占用 PID 和内存，但无法回收处于 D 状态的子进程（将被 init 收养）。

## 命令调用机制

所有命令通过 `Cmd.<bin>` 语法调用，命令执行采用 fork-exec 子进程 + 管道捕获 stdout/stderr。语言层设计见 [OS 命令调用机制](../design/command-system.md)。

### 子进程执行流程

```
Cmd.<bin> { options } [posArgs...]
  │
  ├── 编译期：模块发现与选项类型检查
  │   ├── 搜索 ~/.kun/cmd/<Name>.kun → $KUN_PATH/cmd/<Name>.kun → <runtime>/lib/kun/cmd/<Name>.kun
  │   ├── 找到类型化模块 → 加载并提供选项类型检查
  │   └── 未找到 → 裸调用：运行时 PATH 查找 + camelCase 自动映射
  │
  └── 运行时：fork-exec + Stream pipe 捕获
```

Command 执行的系统契约：

```
动作: fork → chdir 到 Cmd.withCwd 指定目录或 Path.cwd（子进程内） → [Cmd.withRunAs: initgroups → setgid → setuid] → setrlimit → install seccomp → exec → waitpid
返回: Stream String（|> 管道触发 / Cmd.exec 显式执行）或 Result (Stream String) CommandError（? 后缀）
argv: Record 选项 → Cmd.withRawOpt 追加 → -- 分隔符 → 位置参数
stdout: pipe 捕获为 Stream String
stderr: 透传到父进程（mergeStderr 时合并到 stdout）
stdin: 继承父进程（/dev/null 或外部管道）
```

### 运行时 PATH 解析

`Cmd.<bin>` 的命令查找发生在**运行时**。编译时不检查命令是否存在。首次 PATH 解析成功后结果缓存（每次 `do` 块入口刷新）。运行时未找到命令则触发 `NotFound` panic。

## 安全隔离

CLI 安全参数（`--allow-path`、`--allow-net`、`--no-sandbox`、`--force`、`--env=`、`--cpu-limit`、`--mem-limit`）的完整说明见 [`kun` CLI 工具](../design/kun-cli-tool.md#安全控制)。

### 安全层架构

父进程与子进程采用两层安全机制叠加（非替代）：

1. **父进程层**（初始化阶段一次性安装）：
   - `prctl(PR_SET_NO_NEW_PRIVS, 1)` — 最优先执行，禁止当前进程及所有后代获取新特权（setuid exec 将无法提升权限），是 Landlock 生效的前提条件
   - Landlock 文件控制（首选，内核 5.13+）/ 文件 + 网络控制（内核 6.7+）
   - Mount namespace 目录级隔离（兜底，内核 3.8+）：同时创建 network namespace（`CLONE_NEWNET`，内核 3.0+）——在 Landlock 网络控制不可用时（内核 5.13–6.6）提供网络隔离
   - 拒绝运行（内核 < 3.8）
2. **子进程层**（每次 fork 后始终安装）：seccomp-BPF 系统调用过滤 + rlimit 资源限制

### 网络隔离

Kun 的默认安全策略为"无网络访问"。`--allow-net` 为全局开关——启用后所有 `Cmd.*` 子进程均可发起网络连接。未启用 `--allow-net` 时，网络隔离通过以下机制实现：

| 内核版本 | 网络隔离机制 |
|---------|------------|
| ≥ 6.7 | Landlock 网络控制（文件 + 网络规则集） |
| ≥ 3.0 | Network namespace（`CLONE_NEWNET`，与 mount namespace 同时创建） |
| < 3.0 | 拒绝运行 |

`CLONE_NEWNET` 创建一个拥有独立网络栈的新 namespace——无任何网络接口（含 lo），子进程无法建立任何 TCP/UDP 连接。无 per-command 或 per-destination 过滤——精细化网络出口控制需通过 Landlock 网络控制（内核 6.7+）在后续版本中实现。

Landlock 使用严格模式：内核版本不支持所需规则集时拒绝运行，不做静默降级。Mount namespace 采用 `pivot_root`（需 `CLONE_NEWNS`）而非 `chroot`，消除 chroot 已知逃逸路径（`chdir("..")` 多次 + `chroot(".")` 可回到真实根）。`/proc`、`/sys`、`/dev` 在 mount namespace 中重新挂载为最小安全实例：`/dev` 仅暴露 `null`、`zero`、`random`、`urandom`、`tty`、`stdin`/`stdout`/`stderr`、`fd`、`shm`，隐藏 `/dev/mem`、`/dev/kmem` 等可读写内核内存的危险设备。

seccomp-BPF 过滤规则禁止以下系统调用类别：

| 类别 | 禁止的 syscall |
|------|---------------|
| 进程注入 | `ptrace`、`process_vm_readv`、`process_vm_writev` |
| 内核模块 | `init_module`、`finit_module`、`delete_module` |
| 内核执行 | `kexec_load`、`kexec_file_load` |
| BPF 逃逸 | `bpf`（可加载 eBPF 程序绕过 seccomp 或注入内核钩子） |
| 文件系统重挂载 | `mount`、`umount2`、`pivot_root`（子进程禁止）；`fsopen`、`fsmount`、`fsconfig`、`open_tree`、`move_mount`（Linux 5.2+ 新 mount API，可绕过传统 mount 限制） |
| 容器逃逸 | `unshare`、`clone`（含 `CLONE_NEWNS`/`CLONE_NEWUSER`/`CLONE_NEWNET` 等标志时） |
| 原始套接字 | `socket`（`AF_PACKET` 协议族） |
| Landlock 逃逸 | `open_by_handle_at`、`name_to_handle_at`（按 inode 打开文件可绕过 Landlock 路径级限制） |
| 内核利用原语 | `perf_event_open`（CPU PMU 侧信道 / kprobe 附加）、`userfaultfd`（用户态缺页处理，可绕过 W^X）、`memfd_create`（匿名内存文件 + `execveat` 可绕过文件系统级执行限制） |
| 异步 I/O 逃逸 | `io_uring_setup`、`io_uring_enter`、`io_uring_register`（历史漏洞频发，可绕过 seccomp 检查） |

子进程的 seccomp 规则集是固定编译期常量，不受用户配置影响。

沙箱层级展示见 [`kun` CLI 工具](../design/kun-cli-tool.md#沙箱层级)。

### 资源限制（rlimit）

子进程 fork 后、exec 前自动设置 rlimit，默认值与 CLI 覆盖参数见 [`kun` CLI 工具](../design/kun-cli-tool.md#资源限制)。

### 环境变量安全

子进程缺省继承干净白名单（`PATH`、`HOME`、`USER`、`TERM`、`LANG`、`PWD`、`SHELL`、`TZ`、`DISPLAY`、`XDG_RUNTIME_DIR`、`LC_ALL`、`LC_CTYPE`、`TMPDIR`）。始终剔除列表（`LD_PRELOAD`、`LD_AUDIT`、`LD_DEBUG`、`LD_LIBRARY_PATH`、`LD_PROFILE`、`LD_ORIGIN_PATH`、`GCONV_PATH`、`GLIBC_TUNABLES`）无论策略如何永不传递。额外始终剔除的模式匹配规则：`BASH_FUNC_*`（bash Shellshock-class 函数注入，CVE-2014-6271）、`PYTHONPATH`、`PERL5LIB`、`PERLLIB`、`RUBYLIB`、`RUBYOPT`、`GIO_EXTRA_MODULES`、`GTK_MODULES`（各语言解释器的模块注入向量）。

## 类型运行时表示

### 基础类型

| Kun 类型 | C ABI 表示 | 大小 | 对齐 |
|---|---|---|---|
| `Int` | `int64_t` | 8 字节 | 8 |
| `Float` | `double` | 8 字节 | 8 |
| `Bool` | `uint8_t` | 1 字节 | 1 |
| `Char` | `uint32_t` | 4 字节 | 4 |
| `Duration` | `int64_t` | 8 字节 | 8 |
| `Unit` | `void` | 0 字节 | — |

### 字符串与字节类型

| Kun 类型 | C ABI 表示 |
|---|---|
| `String` | `Slice { uint8_t* ptr, uint64_t len }` |
| `Bytes` | `Slice { uint8_t* ptr, uint64_t len }` |
| `Path` | `Slice { uint8_t* ptr, uint64_t len }` |

```c
typedef struct {
    uint8_t* ptr;
    uint64_t len;
} Slice;
```

### 复合类型

#### `List t`

```c
typedef struct {
    uint8_t* ptr;
    uint64_t len;
    uint64_t cap;
} Array;
```

#### `Map k v`

Map 运行时采用哈希表实现。开地址法，键值对存储在桶数组中。

#### `Set t`

Set 运行时采用与 Map 相同的哈希表结构，仅使用键部分。

### 和类型（ADT）

ADT 在运行时表示为带标记的联合体（tagged union），tag 使用 `uint8_t`。

### Stream

Stream 运行时表示采用 tagged union，定义见上方「Stream 惰性求值」章节。

### 函数值

```c
typedef struct {
    void*    (*fn_ptr)(void* env, void* args);
    void*    env;
    uint64_t arity;
    uint64_t env_size;
} Closure;
```

## 内存管理

### 分配策略

采用分层分配策略，核心是 Arena 分配器：

| 层次 | 分配器 | 生命周期 | 用途 |
|---|---|---|---|
| 脚本级 | Arena | per 脚本执行 | AST、类型表示、临时字符串 |
| 模块级 | Arena | per 模块加载（加载与类型检查完成后销毁） | 模块 AST、缓存类型 |
| 全局 | 标准堆 | 运行时进程全周期 | 内置类型表、Primitive 注册表 |

Arena 分配器特性：线性分配（bump allocation），无释放操作；Arena 在阶段结束时整体销毁。

### 资源清理

资源管理原则：**谁打开谁关闭，Arena 销毁时自动清理**。Arena 维护终结器列表，销毁时按注册逆序执行。

## 模块解析与加载

Kun 采用目录即命名空间方案：文件名（去掉 `.kun` 后缀）即模块名，目录层级表达名字空间。模块名由文件路径唯一确定，无需在文件中声明。

### 模块组织

```
my-project/
├── deploy.kun                 ← 可执行脚本（有 main，无 export）
├── lib/                       ← 项目库根目录
│   ├── Cmd/
│   │   └── Git.kun            ← 模块 Cmd.Git
│   ├── File.kun               ← 模块 File
│   └── List.kun               ← 模块 List
└── tests/
    └── test-config.kun        ← 可执行测试脚本
```

### 搜索路径

模块搜索路径优先级定义见 [语法设计](../design/syntax.md#搜索路径)。加载流程如下：

### 加载流程

```
import File
      │
      ▼
搜索 lib/File.kun（同库） → 搜索 $KUN_PATH/File.kun → 搜索 <runtime>/lib/kun/File.kun
      │
      ▼
已在缓存中？──是──→ 返回缓存副本
      │
      ▼否
读取文件 → 词法分析 → 语法分析 → 类型检查 → 递归加载依赖 → 缓存
```

### 循环依赖检测

加载器维护加载中集合和已完成缓存。检测到循环依赖时编译期报错。

### 缓存失效

模块索引缓存在脚本执行期间持久有效。以下场景触发缓存刷新：

- 文件系统变更检测：加载前通过 `stat` 检查模块文件 `mtime`，若变化则重新加载
- `--force` 参数：跳过缓存，强制重新解析与类型检查全部模块
- 新增模块：编译器在每次执行入口遍历库根目录，增量更新索引缓存

此策略确保在不重启 `kun` 的情况下，新增或修改的模块文件在下一次脚本执行时自动生效。

## 标准库集成

标准库模块分为两类：

| 类别 | 实现方式 | 示例 |
|---|---|---|
| 纯 Kun 实现 | `.kun` 文件，用语言自身实现 | `List`、`Map`、`Set`、`Result` |
| Primitive 实现 | Zig 原生函数，注册到内置表 | `IO` 操作、`File` 操作、`Stream` |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.14 | 效应函数列表修正：`Signal.*` → `Signal.on`；Stream tagged union 新增 `dropped`/`lines`/`parse_mapped`/`parse_mapped_keep` 变体；seccomp 新增新 mount API syscall（`fsopen`/`fsmount`/`fsconfig`/`open_tree`/`move_mount`）；用户定义效应函数自动获取 `EffectFn` 内部类型 |
| 2026.06.14 | 安全加固：seccomp 新增 `bpf`/`perf_event_open`/`userfaultfd`/`memfd_create`；新增 `prctl(PR_SET_NO_NEW_PRIVS)` 沙箱前置条件；网络隔离新增 CLONE_NEWNET 覆盖内核 5.13–6.6；环境变量过滤新增 `BASH_FUNC_*`/`PYTHONPATH`/`PERL5LIB` 等注入防御；D-state 文档修正（`--cpu-limit` 无效 + wall-clock 超时方案）；`Cmd.withRunAs` 完整权限降级流程 |
| 2026.06.14 | 效应检查算法更新：新增 `(a -> b)!` 效应回调参数检测（含 `!` 的函数标记为效应函数、纯函数禁止声明 `!`、`!` 实参必须为效应函数）；Command 执行模型更新：移除 `do` 块隐式执行，新增 `Cmd.exec` 显式执行，未被消费 Command 是编译错误；效应函数列表新增 `Cmd.exec` |
| 2026.06.13 | 类型检查算法章节；初始化阶段顺序修正（模块解析在沙箱之前）；Stream 消费强制检查 + 管道非阻塞 IO 策略；Landlock 严格模式 + pivot_root + /proc 处理；panic 活跃子进程回收策略；env 白名单扩展；模块缓存失效策略 |
| 2026.06.12 | 文档重构：命令调用机制独立为 `command-system.md`；CLI 工具与安全控制独立为 `kun-cli-tool.md`；`TempFile`/`TempDir` 整合为 `File.createTempFile`/`File.createTempDir`；新增 `Cmd.mergeStderr`、`Cmd.timeout`/`Cmd.retry`、`Cmd.withRunAs`/`Cmd.andThen`/`Cmd.orElse` 文档；版本号统一为 yyyy.MM.dd 日期格式 |
| 2026.06.11 | 模块系统重设计：目录即命名空间；`export (…)` 替代 `module Xxx export (…)`；`import X (…)` 替代 `import X with (…)` |
| 2026.06.10 | 架构重设计：移除 `.cmd.kun`/`IO T`/`with caps`/dlopen/ptrace 等；新增 `Cmd.<bin>` fork-exec + Landlock/mount ns + `defer` + tagged union Stream |
| 2026.05.27 | 项目初始化，设计文档定型 |
