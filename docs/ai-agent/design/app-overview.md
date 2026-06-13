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

脚本领域特定的类型（`Port`、`Pid`、`Signal`、`ExitCode`、`DateTime`、`Uid`/`Gid`、`IpAddress`、`Errno`、`FileType`、`IOError`、`CommandError` 等）由[标准库](standard-library.md)以 ADT 或 newtype 形式定义，详见独立文档。

## 命令调用系统

所有 Linux 命令通过 `Cmd.<bin>` 语法调用，参数通过 Record 类型表达，camelCase 字段名自动映射为 kebab-case CLI flag。`Cmd.<bin>` 返回 `Command` 值——延迟执行，在 `|>` 隐式触发、`do` 块语句边界或 `?` 后缀时自动 fork-exec。

完整设计见 [OS 命令调用机制](command-system.md)，API 签名见[标准库 Cmd 模块](standard-library.md#cmd-command-工具与命令调用)。

## 管道与组合

内置管道机制和高阶函数实现命令组合：

- **进程内管道 `|>`**：将左侧表达式的值作为右侧函数的最后一个参数传入，数据在 Kun 进程内以类型化形式传递
- **OS 管道 `Cmd.pipe`**：通过 OS pipe fd 在子进程间以字节流形式传输
- **求值策略**：采用严格求值作为默认策略，`let` 绑定延迟求值，`Stream` 惰性
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
  case File.createTempFile of
    Ok tmp ->
      defer (File.remove tmp)
      Cmd.ffmpeg {} "input.mp4" tmp
    Err _ -> IO.println "failed to create temp file"
// do 块退出时自动 remove tmp
```

## 安全模型

安全策略通过 [`kun` CLI 参数](kun-cli-tool.md#安全控制)声明（`--allow-path`、`--allow-net`、`--no-sandbox`、`--force`、`--env=`、`--cpu-limit`、`--mem-limit`），与脚本代码分离。默认仅 CWD 可读写、无网络。运行时通过 Landlock / mount namespace / seccomp + rlimit 多层沙箱隔离，详细实现见[系统基线](../architecture/system-baseline.md#安全隔离)。

## 语法设计

语法借鉴 Elm、Haskell 和 Rust（以 Elm 为主），深度融合 Unix 哲学，确保简洁、统一、一致。所有数据必须赋初值，消除 null，支持自动类型推断。

## 运行时执行

运行时使用 Linux 的 fork-exec 机制执行外部命令，通过 pipe 捕获 stdout/stderr。`Cmd.<bin>` 参数通过 Record 类型表达，运行时自动序列化为 argv 数组——shell 元字符在 exec 层面为普通字符，无注入风险。

## 函数与模块

- 支持导入导出函数，提供逻辑复用
- 目录即命名空间，`export (...)` 声明公开符号，`import X (...)` 导入
- 默认私有，限定导入，别名导入
- 交互式 REPL 环境

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.13 | 求值策略标题修正；User/Group 参考更正为 Uid/Gid |
| 2026.06.10 | 架构重设计：应用概览与核心概念定义 |
