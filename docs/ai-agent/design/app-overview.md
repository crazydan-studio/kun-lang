# 应用概览

## Kun 语言概览

Kun（鲲）是一款面向 Linux 的函数式脚本语言，其核心目标是消除传统 Shell 脚本的种种问题，同时保留 Unix 哲学中"小程序组合完成复杂任务"的精髓。

## 类型系统

### 基础类型

| 类型 | 说明 |
|---|---|
| `Int` | 整数（64位有符号） |
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
| `Map` | 映射表，提供对数复杂度的查找、插入和删除 |
| `Set` | 集合，元素唯一且无序 |
| `Stream` | 惰性流，支持大文件处理和管道数据流 |
| `Tuple` | 元组 |

### 和类型（Sum Types）

| 类型 | 变体 | 说明 |
|---|---|---|
| `?T` | `T` / `Nil` | Nilable 类型，值可能不存在（`Nil`）。`T` 默认非 Nil，`?T` 显式标记可选 |
| `Result` | `Ok a` / `Err e` | 表示操作可能成功或失败 |

### 标准库补充类型

脚本领域特定的类型（`Port`、`Pid`、`Signal`、`ExitCode`、`DateTime`、`User`/`Group`、`IpAddress`、`Errno`、`FileType`、`IOError`、`CommandError` 等）由[标准库](standard-library.md)以 ADT 或 newtype 形式定义，详见独立文档。

## 命令调用系统

所有命令通过 `Cmd.<bin>` 语法调用，参数通过 Record 类型表达：

```kun
Cmd.ls { long = true, all = true } p"/tmp"
// camelCase → kebab-case 自动映射：long → --long, all → --all
// 最终生成：ls --long --all /tmp
```

### 子命令

```kun
Cmd.git.log { maxCount = 50 } "main"
Cmd.docker.container.ls { all = true }
```

### 特殊字符命令名

含 `-`、`.`、`+` 或数字开头的命令使用 `Cmd["..."]` 转义：

```kun
Cmd["ntfs-3g"] { force = true } "/dev/sda1"
Cmd["g++"] { o = "a.out" } "main.cpp"
  |> Cmd.withRawOpt "-Wall" Nil
```

### 类型化选项与自动模块发现

编译器在编译时自动搜索 `~/.kun/cmd/<Name>.kun`、`$KUN_PATH/cmd/<Name>.kun`、`<runtime>/lib/kun/cmd/<Name>.kun`——若找到类型化模块则加载并提供选项类型检查，未找到则退回裸调用。

### Command 执行模型

`Cmd.<bin>` 返回 `Command` 值——不立即执行。Command 在以下时机自动执行：

- `|>` 隐式触发：左侧 `Command`，右侧函数期望 `Stream`
- `do` 块语句边界：未消费的 `Command` 作为 `do` 块语句结果
- `Cmd.<bin>?`：`?` 后缀，立即执行并返回 `Result`

### OS 管道：`Cmd.pipe` / `Cmd.pipe?`

```kun
Cmd.pipe [Cmd.ps {}, Cmd.grep { pattern = "nginx" }, Cmd.head { n = 10 }]
// 链中任一命令非零退出 → panic（等价 set -o pipefail）

Cmd.pipe? [Cmd.ps {}, Cmd.grep { pattern = "nginx" }]
// 链中任一命令失败 → Err (PipeFailed ...)
```

### 修饰函数

```kun
Cmd.withEnv     : Map String String -> Command -> Command
Cmd.withStdin   : String -> Command -> Command
Cmd.withStdin   : Stream Bytes -> Command -> Command
Cmd.withRawOpt  : String -> ?String -> Command -> Command
Cmd.mergeStderr : Command -> Command
Cmd.withCwd     : Path -> Command -> Command
Cmd.withRunAs   : String -> Command -> Command

// Command 组合（短路条件）
Cmd.andThen : Command -> Command -> Command
Cmd.orElse  : Command -> Command -> Command
```

## 管道与组合

内置管道机制和高阶函数实现命令组合：

- **进程内管道 `|>`**：将左侧表达式的值作为右侧函数的最后一个参数传入，数据在 Kun 进程内以类型化形式传递
- **OS 管道 `Cmd.pipe`**：通过 OS pipe fd 在子进程间以字节流形式传输
- **严格求值**：采用严格求值作为默认策略，`let` 绑定延迟求值，`Stream` 惰性
- **高阶函数**：map、filter、fold、reduce 等

## 模式匹配

支持多种模式匹配形式：

- **和类型模式**：匹配 `Result` 等和类型的变体
- **列表模式**：匹配列表结构（空列表、`[a, ..rest]`、特定元素序列）
- **映射模式**：匹配特定键的存在
- **守卫子句**：附加到模式分支的额外布尔条件

## 错误处理

### 默认 panic

命令失败时默认 panic（unwind → defer 逆序执行），结构化错误信息包含命令名、退出码、stderr。

### 显式 `?` 后缀

`Cmd.<bin>?` 和 `Cmd.pipe?` 返回 `Result` 而非 panic：

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

### defer 资源清理

```kun
do
  tmp = TempFile.create
  defer (File.remove tmp)
  Cmd.ffmpeg {} "input.mp4" tmp
// do 块退出时自动 remove tmp
```

## 安全模型

安全策略通过 CLI 参数声明，与代码分离：

```bash
kun script.kun                           # 默认：仅 CWD 可读写，无网络
kun --allow-path /tmp script.kun         # 额外允许 /tmp
kun --allow-net script.kun               # 开放网络出站
kun --no-sandbox script.kun              # 完全关闭
kun --force script.kun                   # 强制运行（跳过安全确认）
kun --env=inherit script.kun             # 继承全部环境变量
kun --cpu-limit 120s --mem-limit 1G script.kun
```

子进程 fork 后自动安装 Landlock（首选）/ mount namespace（兜底）/ seccomp + rlimit 多层沙箱隔离。

## 语法设计

语法借鉴 Elm、Haskell 和 Rust（以 Elm 为主），深度融合 Unix 哲学，确保简洁、统一、一致。所有数据必须赋初值，消除 null，支持自动类型推断。

## 运行时执行

运行时使用 Linux 的 fork-exec 机制执行外部命令，通过 pipe 捕获 stdout/stderr。`Cmd.<bin>` 参数通过 Record 类型表达，运行时自动序列化为 argv 数组——shell 元字符在 exec 层面为普通字符，无注入风险。

## 函数与模块

- 支持导入导出函数，提供逻辑复用
- 目录即命名空间，`export (...)` 声明公开符号，`import X (...)` 导入
- 默认私有，限定导入，别名导入
- 交互式 REPL 环境
