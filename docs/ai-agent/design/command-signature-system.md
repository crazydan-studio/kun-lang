# 命令签名系统设计

## 定位

命令签名系统是 Kun 将 Linux 命令抽象为类型安全函数的桥梁。命令函数的本质是**获取结构化结果**，而非执行特定命令。`ls p"/tmp"` 的语义是"获取 /tmp 目录下的文件列表（名称、类型、大小、时间）"，而非"执行带有这些参数的 ls"。

调用命令函数时，运行时会自动处理输出的结构化和反序列化——用户通过 CDF 声明的返回类型操作结果，不直接接触原始文本输出。

## 设计原则

1. **面向结果**：命令函数聚焦于"得到什么结果"，而非"执行什么命令"。输出格式相关的参数（`-l`、`-h`、`--json`、`--format` 等）不在 CDF 映射范围内，由运行时自动选择最佳输出方式
2. **输出即类型**：CDF 声明的输出类型决定返回值的结构。运行时自动解析命令输出为声明的结构化类型
3. **无 CDF 则不可用**：无 CDF 的命令函数无法调用。签名来源优先级为：内置签名 > 项目级 CDF > 用户级 CDF > 自动推断。若所有来源均无签名，则命令不可用
4. **来源可信**：CDF 文件通过密码学签名建立信任链，防止恶意签名定义

## CDF 文件格式

### 文件位置

```
~/.kun/cdf/<command>.cdf        # 用户级（自动推断结果缓存在此）
<project>/.kun/cdf/<command>.cdf # 项目级（提交到版本控制）
<runtime>/cdf/                   # 内置签名库（由 Kun 发行版提供）
```

### 语法

CDF 使用 Kun 语法风格的声明式格式：

```kun-cdf
// ls.cdf — ls 命令的签名定义

command "ls"

// 只声明影响结果集合的参数，不声明输出格式相关参数
flag "all"     'a' : Bool
flag "recursive" 'R' : Bool
flag "directory" 'd' : Bool
option "sort"  'S' : String with (enum ["size", "time", "version"])
option "time"  't' : String with (enum ["atime", "ctime", "mtime"])
positional 0   : Path    with (optional)
positional 1   : Path    with (optional)

// 输出类型（结构化类型，运行时自动解析）
output : Stream { name : Path, type : FileType, size : Int, mtime : DateTime }

// 错误类型
error : List IOError
```

### 核心结构

| 章节 | 必需 | 说明 |
|------|------|------|
| `command` | 是 | 命令名，用于匹配和执行 |
| `flag` / `option` / `positional` | 否 | 参数定义，每种类型可重复 |
| `output` | 否 | 输出类型，默认 `Stream String` |
| `error` | 否 | 错误类型，默认 `List IOError` |
| `behavior` | 否 | 行为声明（已废弃，seccomp 规则由参数类型推导） |
| `subcommand` | 否 | 子命令定义，递归结构 |

## 参数定义

### Flag（布尔标志）

```
flag "verbose" 'v' : Bool
flag "recursive" 'R' : Bool
```

- 长名：`--verbose`
- 短名：`-v`
- 类型：始终为 `Bool`
- 默认值：`false`（未指定时）

### Option（带值选项）

```
option "output" 'o' : Path
option "timeout" 't' : Duration with (range 1s 300s)
```

- 长名：`--output <value>`
- 短名：`-o <value>`
- 类型支持：`String`、`Path`、`Int`、`Nat`、`Duration`、`Float`
- 默认值：`Nothing`（`Maybe T`，未指定时为 `Nothing`）

### Positional（位置参数）

```
positional 0 : Path
positional 1 : String with (optional)
```

- 序号从 0 开始
- `optional` 标记表示该参数可省略
- 类型支持：`Path`、`String`、`Int`、`Nat`、`Float`

### 参数验证器

验证器约束应用在参数定义上，运行时校验：

```
option "port" 'p' : Int with (range 1 65535)
option "mode" 'm' : String with (enum ["r", "w", "x", "rw", "rx", "rwx"])
option "name" 'n' : String with (length 1 255)
option "format" 'f' : String with (regex "^[a-z]+(\\.[a-z]+)*$")
positional 0 : Path with (custom isReadable)
```

验证器链式组合：

```
option "size" 's' : String with (regex "^\\d+(K|M|G)$" && length 1 32)
```

### 子命令

```kun-cdf
command "git"

subcommand "commit"
  flag "all"     'a' : Bool
  flag "amend"   : Bool
  option "message" 'm' : String
  // output: Unit（仅退出码）

subcommand "push"
  flag "force"   'f' : Bool
  flag "verbose" 'v' : Bool
  positional 0        : String with (optional)    // 远程名
  // output: Unit（仅退出码）
```

子命令签名映射为独立函数值，参数合并到同一 Record 中，`runAs` 为隐式参数：

```kun
git.commit : { all : Bool, amend : Bool, message : Maybe String
             , runAs : Maybe String = Nothing
             } -> IO (Result Unit (List IOError))
git.push   : { force : Bool, verbose : Bool, remote : Maybe String
             , runAs : Maybe String = Nothing
             } -> IO (Result Unit (List IOError))
```

## 输出类型定义

命令函数的返回值类型直接在 CDF 中声明为结构化类型，运行时自动将命令输出解析为对应类型：

```kun-cdf
// ls — 文件列表
output : Stream { name : Path, type : FileType, size : Int, mtime : DateTime }

// du — 磁盘使用量（仅影响结果的选项）
flag "summarize" 's' : Bool  // 汇总模式返回单条
flag "separate-dirs" : Bool  // 单独统计目录
output : Stream { path : Path, size : Int }

// find — 文件搜索结果
output : Stream { path : Path, type : FileType, size : Int }

// grep — 匹配行
output : Stream { path : Path, line : Int, content : String }

// ps — 进程列表
output : Stream { pid : Pid, cpu : Float, mem : Float, cmd : String }

// curl — HTTP 响应
output : { status : Int, headers : Map String String, body : Bytes }
```

用户不需要关心命令的内部输出格式——CDF 声明了返回值的结构，运行时自动完成解析。

## seccomp 规则自动推导

seccomp-BPF 过滤规则由命令的参数类型和名称自动推导，不再依赖独立的 behavior 声明：

| 参数模式 | 允许的系统调用 | 说明 |
|---------|--------------|------|
| `Path` 类型参数 | `openat`、`read`、`pread64`、`fstat`、`close`、`lseek` | 文件读取 |
| 输出/写入语义参数 | `openat`、`write`、`pwrite64`、`ftruncate`、`fsync`、`close` | 文件写入 |
| 网络/URL 类型参数 | `socket`、`connect`、`sendto`、`recvfrom`、`close` | 网络请求 |
| 子进程相关参数 | `clone`、`execve`、`waitid`、`exit_group` | 进程管理 |
| 无匹配参数 | `brk`、`mmap`、`munmap`、`exit_group` | 仅内存操作 |

## 内置签名库

### 覆盖范围

命令函数的映射原则：

- **结构化输出类**：Kun 无法原生获取的系统信息（文件列表、进程状态、网络连接等），通过 CDF 声明结构化返回类型
- **文件系统/OS 影响类**：即使无结构化输出，但有 CDF 映射后可获得能力系统集成（参数验证、seccomp 规则、沙箱路径隔离）
- **不映射**：文本变换类（`sed`、`awk`、`sort`、`uniq`、`cut`、`tr`、`head`、`tail`）和内容查看类（`cat`、`wc`、`tee`）由 Kun 标准库和语言特性覆盖

内置签名由 Kun 发行版提供，覆盖：

| 类别 | 命令 | 输出类型 |
|------|------|---------|
| 文件信息 | `ls`、`stat`、`du`、`df` | 结构化 |
| 内容搜索 | `grep` | 结构化 |
| 归档内容 | `tar` | 结构化 |
| 压缩 | `gzip`、`gunzip`、`xz`、`zstd` | 仅退出码 |
| 查找检索 | `find`、`locate` | 结构化 |
| 进程/网络信息 | `ps`、`ss` | 结构化 |
| 系统信息 | `free`、`uname`、`lscpu`、`uptime` | 结构化 |
| 网络交互 | `curl`、`wget`、`dig`、`ping` | 结构化 |
| 远程同步 | `rsync`、`scp` | 结构化/仅退出码 |
| 文件操作 | `cp`、`mv`、`rm`、`mkdir`、`touch`、`dd` | 仅退出码 |
| 归档包 | `zip`、`unzip` | 仅退出码 |
| 权限操作 | `chmod`、`chown`、`ln`、`readlink`、`realpath`、`umask` | 仅退出码 |
| 权限提升 | — | 通过 `runAs` 参数 + `capability process.run-as` 控制 |

### 内置签名的存储

内置签名编译在 Kun 运行时二进制中，以 Zig 静态数组形式存在：

```zig
// Zig 伪代码：内置签名条目
const BUILTIN_SIGNATURES = [_]SignatureEntry{
    .{ .name = "ls",  .cdf_data = @embedFile("cdf/ls.cdf") },
    .{ .name = "cat", .cdf_data = @embedFile("cdf/cat.cdf") },
    // ... 更多
};
```

## 签名自动推断

### 推断优先级

```
1. 内置签名库（最精确，由 Kun 发行版维护）
2. 项目级 CDF（<project>/.kun/cdf/<command>.cdf）
3. 用户级 CDF（~/.kun/cdf/<command>.cdf，自动推断结果缓存）
4. man 手册推断（首选，信息最详尽）
5. --help/-h 推断（回退，信息有限）
6. 默认签名（无信息可用时：flag/positional 均为空，output 为 Stream String）
```

### man 手册解析

```
man 页面
  │
  ▼
提取 OPTIONS / ARGUMENTS / DESCRIPTION 段落
  │
  ├── 解析短标志: -v, -o file, -n NUM
  ├── 解析长标志: --verbose, --output=file
  ├── 解析参数类型: file, num, string, path
  ├── 解析枚举值: r|w|x
  └── 解析默认值: (default: 42)
  │
  ▼
生成 CDF 片段 → 合并 → 签名
```

### 子命令检测

```
命令 --help 输出
  │
  ▼
检测 "Usage: <cmd> <subcommand>" 模式
  │
  ▼
对每个子命令递归获取帮助
  ├── man <cmd>-<subcommand>      # 优先：如 git-commit
  ├── man <cmd> <subcommand>      # 回退：如 man git commit
  └── <cmd> <subcommand> --help   # 最终回退
  │
  ▼
每个子命令独立签名
```

### AI 辅助整理

当自动推断结果不够精确时，运行时输出整理提示词：

```
// 运行时输出的 CDF 草稿
// 请人工审核后保存到 ~/.kun/cdf/<command>.cdf

command "<command>"
  // 自动推断结果（可能需要人工修正）
  flag "verbose" 'v' : Bool                     // 置信度: 高
  option "output" 'o' : String                  // 置信度: 中（类型不确定）
  positional 0 : String                         // 置信度: 低（位置参数含义未知）
```

## CDF 生命周期

### 编写

```
开发 CDF → 语法验证 → 单元测试（调用签名验证）→ 签名 → 部署
```

### 签名

```
CDF 文件
  │
  ▼
Ed25519 签名（private key）
  │
  ▼
CDF + .sig 文件 → 分发
```

### 验证缓存

运行时缓存 CDF 解析结果以提升性能：

```
~/.kun/cache/
├── cdf_parsed/          # 解析后的 CDF（二进制格式）
│   ├── ls.cdf.cache
│   └── git.cdf.cache
├── man_parsed/          # 解析后的 man 页面
│   └── rsync.man.cache
└── signatures/          # 验证过的 CDF 签名
    └── custom-tool.sig.cache
```

缓存失效策略：
- 源 CDF 文件 mtime 更新 → 重新解析
- 签名有效期过期 → 重新验证
- 缓存目录超过 30 天未使用 → 自动清理

### 版本兼容性

CDF 格式版本号嵌入文件头部：

```kun-cdf
// kun-cdf-v1
command "ls"
...
```

格式变更时：
- 向下兼容：解析器支持旧版格式
- 升级提示：运行时检测到旧版 CDF 时输出建议
- 强制升级：仅当旧版格式存在安全漏洞时

## 运行时集成

### CDF 加载流程

```
命令调用
  │
  ▼
签名解析器
  │
  ├── 1. 查找签名：内置 → 项目级 → 用户级 → 自动推断
  │
  ├── 2. 签名验证：CDF 有签名？→ 验证 Ed25519 → 检查信任链
  │               │
  │               └── 验证失败 → 降级到下一个优先级 + 告警
  │
  ├── 3. 参数验证：运行时检查参数类型、范围、枚举值等
  │
  ├── 4. seccomp 规则生成：根据命令参数类型和名称推导 seccomp 规则
  │
  ├── 5. 执行命令：通过 dlopen/ptrace/fork-exec 加载
  │
  └── 6. 输出契约验证：检查输出是否符合 CDF 声明的类型
```

### 参数验证器运行时

参数验证器在序列化参数前执行：

```kun-cdf
option "port" 'p' : Int with (range 1 65535)
// 用户传入 -p 99999
// → 验证失败：ValidationError { validator: "range", constraint: "1..65535", actual: "99999" }
// → 阻止执行，报告错误
```

## 与运行时架构的关系

命令签名系统与运行时的接口定义在 `系统基线文档` 中：

| 运行时组件 | CDF 交互点 |
|-----------|-----------|
| 命令加载器 | 根据 CDF 决定加载策略（dlopen/ptrace/fork-exec） |
| 参数序列化器 | 根据 CDF 参数定义确定序列化格式 |
| seccomp 管理器 | 根据命令参数类型和名称生成 seccomp-BPF 规则 |
| 结果反序列化器 | 根据 CDF output 定义解析返回值 |

## 完整示例

### ls.cdf

```kun-cdf
// kun-cdf-v1
command "ls"

flag "all"             'a' : Bool
flag "recursive"       'R' : Bool
flag "directory"       'd' : Bool
option "sort"          'S' : String with (enum ["size", "time", "version"])
option "time"          't' : String with (enum ["atime", "ctime", "mtime"])
positional 0                : Path with (optional)
positional 1                : Path with (optional)

output : Stream { name : Path, type : FileType, size : Int, mtime : DateTime }
```

### 命令函数签名约定

所有命令函数的参数和返回值遵循以下约定：

```kun
type CmdResult t = { stdout : t, exitCode : ExitCode }

cmdName : { runAs : Maybe String            // 执行用户，缺省为当前用户
          , ...  // CDF 声明的参数合并至此
          } ->
          IO (Result (CmdResult <output_type>) (List IOError))
```

- `runAs` 是所有命令函数的**隐式参数**，CDF 中不声明，由编译器自动注入
- 命令的 `flag`/`option`/`positional` 参数合并到同一 Record 类型中
- `runAs` 缺省为当前进程用户

#### 示例：ls 的生成签名

```kun
ls : { all : Bool, recursive : Bool, directory : Bool,
       sort : Maybe String, time : Maybe String,
       path0 : Maybe Path, path1 : Maybe Path
     , runAs : Maybe String = Nothing
     } ->
     IO (Result (CmdResult (Stream { name : Path, type : FileType,
                                     size : Int, mtime : DateTime }))
                (List IOError))
```

`runAs` 的调用方式：

```kun
ls { path0 = p"/root", runAs = Just "root" }     // 以 root 执行
ls { all = true, path0 = p"/tmp" }                // 以当前用户执行
```

命令退出码的处理规则：

| 退出码 | 语义 | Kun 返回值 |
|--------|------|-----------|
| `0` | 成功 | `Ok { stdout = ..., exitCode = ExitCode 0 }` |
| `1`-`125` | 命令特定含义（如 `grep` 未匹配、`diff` 文件差异） | `Ok { stdout = ..., exitCode = ExitCode n }`——**非 `Err`** |
| `126`+ | 系统错误（命令未找到、权限拒绝、信号终止） | `Err IOError` |

这意味着 `grep` 未匹配、`diff` 文件差异等场景**不**产生 `Err`，脚本可通过检查 `exitCode` 判断结果：

```kun
case grep "ERROR" logFile of
  Ok { stdout as lines, exitCode as code } ->
    if ExitCode.isSuccess code then
      print "found errors"
    else
      print "no matches"
  Err err -> print f"grep failed: {err}"
```

## CDF 源代码管理

### git 集成

CDF 文件和加密密钥建议按以下方式管理：

```
.kun/                       # 项目根目录下的 Kun 配置目录
├── cdf/                    # 项目级 CDF 定义
│   ├── custom-tool.cdf
│   └── deploy-tool.cdf
└── trusted-keys/           # 项目信任的公钥
    ├── maintainer-1.pub
    └── maintainer-2.pub
```

- `cdf/` 提交到版本控制
- `trusted-keys/` 提交到版本控制
- 私钥永不提交，通过安全渠道管理

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 0.1.0 | 2026-05-31 | CDF 文件格式、参数定义、输出类型、行为声明、签名自动推断、内置签名库、运行时集成 |

