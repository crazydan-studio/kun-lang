# 系统基线

## 技术栈

| 层 | 技术选择 | 说明 |
|---|---|---|
| 宿主语言 | Zig | 高性能、无 hidden control flow、直接操作内存 |
| 目标平台 | Linux | 使用 fork/exec、namespace、Landlock、seccomp 等 Linux 特有机制 |
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
运行时环境建立 → 沙箱安装 → 模块解析 → 标准库绑定
```

1. **运行时环境建立**：
   - 创建 Arena 分配器（per 脚本执行）
   - 设置全局求值环境（变量帧栈）
   - 注册内置 Primitive 函数表

2. **沙箱安装**：
   - 解析 CLI 安全参数（`--allow-path`、`--allow-net`、`--no-sandbox`、`--force`、`--env=`、`--cpu-limit`、`--mem-limit`）
   - 根据内核版本安装安全隔离层：Landlock（首选）→ mount namespace（兜底）→ seccomp（最低）
   - 设置子进程 rlimit（fork 后 exec 前生效）

3. **模块解析与加载**：
   - 解析 `import` 语句
   - 按搜索路径查找模块文件
   - 递归加载依赖模块并缓存
   - 检测循环依赖

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
4. **命令调用**：`Cmd.<bin>` 构造 Command 值，在 `|>` 隐式触发或 `do` 块语句边界自动 fork-exec

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
| `let ... in` 绑定 | 延迟 | 绑定在被引用前不强制求值 |

### do 块与效应函数

`do` 块按顺序执行效应操作。含 `do` 块的函数通过编译器 AST 标记自动识别为效应函数。纯函数（无 `do` 块）不能调用效应函数——编译期拒绝。

效应函数涵盖以下命名空间的所有函数：`Cmd.*`、`IO.*`、`File.*`、`Env.*`、`Process.*`、`Time.*`、`Signal.*`、`Sys.*`、`TempFile.*`、`Std.cd`/`Std.cwd`。

`do` 块内使用 `=` 绑定值（纯值或效应函数的返回值）。`do in` 形式在副作用执行后返回纯值：

```kun
// do 无 in：返回 Unit
main : List String -> Unit
main = \_ ->
  do
    IO.println "deploying..."
    Cmd.rsync { archive = true, verbose = true } "src/" "dst/"

// do in：执行副作用后返回纯值
countFiles : Path -> Int
countFiles = \dir ->
  do
    entries =
      Cmd.ls { all = true } dir
        |> Stream.lines
        |> Stream.toList
  in
    List.length entries
```

### Command 执行模型

`Cmd.<bin>` 返回 `Command` 值——不立即执行。Command 在以下时机自动执行：

| 场景 | 触发条件 | 示例 |
|---|---|---|
| `\|>` 隐式触发 | 左侧 `Command`，右侧函数期望 `Stream` | `Cmd.cat p"/x" \|> Stream.lines` |
| `do` 块语句边界 | 未消费的 `Command` 作为 `do` 块语句结果 | `Cmd.ls { long = true }` |
| `Cmd.<bin>?` | `?` 后缀，立即执行并返回 `Result` | `result = Cmd.cat? p"/x"` |

Command 执行的契约：

```
动作: fork → chdir 到逻辑 CWD（子进程内） → setrlimit → install seccomp → exec → waitpid
返回: Stream String（场景①②）或 Result (Stream String) CommandError（场景③）
argv 序列化: Record 选项 → Cmd.withRawOpt 追加 → -- 分隔符 → 位置参数
stdout: 通过 pipe 捕获，返回为 Stream String
stderr: 透传到父进程 stderr
stdin: 继承父进程（通常为 /dev/null 或外部管道）
```

### Stream 惰性求值

Stream 在运行时表示为 tagged union，替代函数指针链：

```zig
const Stream = union(enum) {
    cmd: struct { fd: i32, pid: i32, buf: []u8 },
    mapped: struct { upstream: *Stream, f: FnPtr },
    filtered: struct { upstream: *Stream, pred: FnPtr },
    taken: struct { upstream: *Stream, remaining: usize },
};
```

- `cmd` 变体持有子进程的 pipe fd 和 pid，`buf` 为堆分配
- 变换操作（`map`、`filter`、`take`）通过包裹上游 Stream 构造新节点
- 终端操作（`toList`、`iter`、`fold`）循环消费直到 stream 终止
- 编译器检测相邻的纯参数操作（`map`/`take`）在代码生成阶段合并为单循环

## 错误诊断

### 错误类型体系

运行时定义了以下结构化错误类型：

### `TypeError`

类型检查阶段的错误，包含源文件名、行号、列号、期望类型、实际类型、错误原因、修复建议。

### `CommandError`

命令执行阶段的语义化错误类型：

```kun
type CommandError
  = NotFound String
  | PermissionDenied String
  | CommandFailed { command : String, exitCode : Int, stderr : String }
  | KilledBySignal { command : String, signal : Int, stderr : String }
  | IoError IOError
  | PipeFailed { commands : List String, failedAt : Int, error : CommandError }
```

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

## 命令调用机制

### 整体架构

所有命令通过 `Cmd.<bin>` 语法调用。命令执行采用 fork-exec 子进程 + 管道捕获 stdout/stderr。

```
Cmd.<bin> { options } [posArgs...]
  │
  ├── 自动模块发现（编译期）
  │   ├── 搜索 ~/.kun/cmd/<Name>.kun
  │   ├── 搜索 $KUN_PATH/cmd/<Name>.kun
  │   └── 搜索 <runtime>/lib/kun/cmd/<Name>.kun
  │
  ├── 找到模块 → 加载类型化选项 + 命令构造器
  │   未找到 → 裸调用：PATH 查找二进制 + camelCase 映射
  │
  └── 运行时 fork-exec + Stream pipe 捕获
```

### camelCase → kebab-case 选项映射规则

`Cmd.<bin> { field = value }` 中的 Record 字段名自动映射为 CLI flag，规则如下：

| Record 字段 | CLI flag | 规则 | 示例 |
|------------|---------|------|------|
| `{ maxCount = 50 }` | `--max-count 50` | 多字符 camelCase → kebab-case（大写字母触发断词） |
| `{ oneline = true }` | `--oneline` | 全小写多字符 → 一字不拆，直接 `--` 前缀 |
| `{ readonly = true }` | `--readonly` | 同上，不做连字符拆分 |
| `{ l = true }` | `-l` | 单小写字符 + Bool=true → 单 token 短 flag |
| `{ o = "a.out" }` | `-o a.out` | 单小写字符 + 非 Bool → 双 token（flag + 值） |
| `{ X = "POST" }` | `-X POST` | 单大写字符 → 保留大小写，`-` 前缀 |
| `{ humanReadable = true }` | `--human-readable` | 标准 camelCase 多大写断词 |
| `Bool = false` | 省略不传 | false 值不生成 flag |
| `Nil` | 省略不传 | Nil 值不生成 flag |
| `List a` | `--key v1 --key v2` | 每个元素一个重复 flag |

> **断词规则**：仅大写字母触发 `-` 断词（`maxCount` → `--max-count`）。全小写多字符键（`readonly`、`stdout`、`oneline`）不做连字符拆分。含特殊字符（`-`、`.`、`+`）或数字开头的命令名使用 `Cmd["..."]` 转义。不适合 Record 映射的 flag（如 `-Wall`、`-D`、`-Wl,...` 等）使用 `Cmd.withRawOpt` 按原样追加。

argv 生成顺序：

```
Record 选项 → Cmd.withRawOpt 追加 → -- 分隔符 → 位置参数
```
### PATH 查找

`Cmd.<bin>` 的命令查找发生在**运行时**（每次调用时解析 PATH）。编译时不检查命令是否存在。若运行时命令未找到，触发 `NotFound` panic。首次 PATH 解析成功后结果被缓存（每次 `do` 块入口刷新），后续调用无需重复搜索。

### OS 管道：`Cmd.pipe` / `Cmd.pipe?`

通过 `Cmd.pipe` 将多个 Command 连接为 OS 管道链，编译为 `pipe2()` + 多次 `fork()`：

```kun
do
  Cmd.pipe [Cmd.ps {}, Cmd.grep { pattern = "nginx" }, Cmd.head { n = "10" }]
```

- `Cmd.pipe`：链中任一命令非零退出 → panic（等价 `set -o pipefail`）
- `Cmd.pipe?`：链中任一命令失败 → 返回 `Err (PipeFailed ...)`

### stdin 注入：`Cmd.withStdin`

`Cmd.withStdin` 为 Command 注入 stdin：

```kun
Cmd.withStdin : String -> Command -> Command        // 字符串模式
Cmd.withStdin : Stream Bytes -> Command -> Command  // 流式模式
```

### 环境变量：`Cmd.withEnv`

```kun
do
  Cmd.mysql { u = "root" }
    |> Cmd.withEnv #{ "MYSQL_PWD" = Env.getenv "DB_PASS" ?? "" }
```

### 特殊字符命令名

含 `-`、`.`、`+` 或数字开头的命令使用 `Cmd["..."]` 转义：

```kun
do
  Cmd["ntfs-3g"] { force = true } "/dev/sda1"
  Cmd["g++"] { o = "a.out" } "main.cpp"
    |> Cmd.withRawOpt "-Wall" Nil
```

## 安全隔离

### CLI 控制

```bash
kun script.kun                           # 默认：Landlock/mount ns，仅 CWD 可读写，无网络
kun --allow-path /tmp script.kun         # 额外允许 /tmp（默认 :rw）
kun --allow-net script.kun               # 开放网络出站
kun --no-sandbox script.kun              # 完全关闭
kun --env=inherit script.kun             # 继承全部环境变量
kun --cpu-limit 120s --mem-limit 1G script.kun
```

### 安全层架构

```
优先 Landlock（内核 6.7+：文件 + 网络）→ mount namespace 兜底（内核 3.8+）→ seccomp 降级（内核 3.5+）→ 拒绝运行（内核 < 3.5）
```

### 资源限制（rlimit）

fork 子进程后、exec 前自动设置 rlimit：

| 限制 | 默认值 | CLI 覆盖 |
|---|---|---|
| `RLIMIT_CPU` | 60s | `--cpu-limit` |
| `RLIMIT_AS` | 512MB | `--mem-limit` |
| `RLIMIT_NOFILE` | 256 | — |
| `RLIMIT_NPROC` | 32 | — |

### 环境变量安全

子进程缺省继承干净白名单（`PATH`、`HOME`、`USER`、`TERM`、`LANG`、`PWD`、`SHELL`、`TZ`）。始终剔除列表（`LD_PRELOAD`、`LD_AUDIT`、`LD_DEBUG`、`LD_LIBRARY_PATH`、`LD_PROFILE`、`LD_ORIGIN_PATH`、`GCONV_PATH`、`GLIBC_TUNABLES`）无论策略如何永不传递。

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

```zig
const Stream = union(enum) {
    cmd: struct { fd: i32, pid: i32, buf: []u8 },
    mapped: struct { upstream: *Stream, f: FnPtr },
    filtered: struct { upstream: *Stream, pred: FnPtr },
    taken: struct { upstream: *Stream, remaining: usize },
};
```

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
| 模块级 | Arena | per 模块加载 | 模块 AST、缓存类型 |
| 全局 | 标准堆 | 运行时进程全周期 | 内置类型表、Primitive 注册表 |

Arena 分配器特性：线性分配（bump allocation），无释放操作；Arena 在阶段结束时整体销毁。

### 资源清理

资源管理原则：**谁打开谁关闭，Arena 销毁时自动清理**。Arena 维护终结器列表，销毁时按注册逆序执行。

## 模块解析与加载

### 模块搜索路径

```
1. 标准库路径:   <runtime_prefix>/lib/kun/
2. 项目本地路径: ./<script_dir>/modules/
3. 用户自定义路径: $KUN_PATH 环境变量指定的目录列表
```

### 类型化命令模块搜索路径

```
1. ~/.kun/cmd/<Name>.kun
2. $KUN_PATH/cmd/<Name>.kun
3. <runtime>/lib/kun/cmd/<Name>.kun
```

### 循环依赖检测

模块加载器维护加载中集合和已完成缓存。检测到循环依赖时编译期报错。

## 标准库集成

标准库模块分为两类：

| 类别 | 实现方式 | 示例 |
|---|---|---|
| 纯 Kun 实现 | `.kun` 文件，用语言自身实现 | `List`、`Map`、`Set`、`Result` |
| Primitive 实现 | Zig 原生函数，注册到内置表 | `IO` 操作、`File` 操作、`Stream` |

## 版本历史

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.2.0 | 2026-06-10 | 架构重设计：移除 `.cmd.kun`/`IO T`/`with caps`/dlopen/ptrace 等；新增 `Cmd.<bin>` fork-exec + Landlock/mount ns + `defer` + tagged union Stream |
| 0.1.0 | 2026-05-27 | 项目初始化，设计文档定型 |
