# 命令签名系统设计

## 定位

命令签名系统是 Kun 将 Linux 命令抽象为类型安全函数的桥梁。每个 Linux 命令通过 CDF（Command Description File）定义精确的函数签名，使命令组合从字符串拼接变为类型驱动的函数复合。

## 设计原则

1. **精确优先**：内置签名 > 项目级 CDF > man 推断 > `--help` 推断，优先使用最精确的签名
2. **渐进增强**：无 CDF 的命令仍可使用（回退到 fork/exec），功能受限但不会完全阻塞
3. **行为透明**：CDF 声明的行为契约在运行时通过 seccomp 验证，确保命令不超出声明范围
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

```
// ls.cdf — ls 命令的签名定义

command "ls"

// 参数类型（标志 + 位置参数）
flag "all"     'a' : Bool
flag "long"    'l' : Bool
flag "human-readable" 'h' : Bool
flag "recursive" 'R' : Bool
option "time"  't' : String with (enum ["atime", "ctime", "mtime"])
positional 0        : Path    with (optional)
positional 1        : Path    with (optional)

// 输出类型
output : Stream String

// 错误类型
error : List IOError

// 行为声明
behavior
  fs.read("/")           // 读取目录内容
  fs.read(Path)          // 读取每个文件的元数据

// 子命令（无）
```

### 核心结构

| 章节 | 必需 | 说明 |
|------|------|------|
| `command` | 是 | 命令名，用于匹配和执行 |
| `flag` / `option` / `positional` | 否 | 参数定义，每种类型可重复 |
| `output` | 否 | 输出类型，默认 `Stream String` |
| `error` | 否 | 错误类型，默认 `List IOError` |
| `behavior` | 否 | 行为声明，影响 seccomp 规则生成 |
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
- 默认值：`None`（`Maybe T`，未指定时为 `None`）

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

```
command "git"

subcommand "commit"
  flag "all"     'a' : Bool
  flag "message" 'm' : String
  positional 0        : String with (optional)  // 路径规格
  behavior
    fs.read(".")
    fs.write(".git")

subcommand "push"
  flag "force"   'f' : Bool
  positional 0        : String with (optional)  // 远程名
  positional 1        : String with (optional)  // 分支名
  behavior
    net.git(Any)
```

子命令签名映射为独立函数值：

```
git.commit : Bool -> String -> Maybe String -> IO (Result (Stream String) (List IOError))
git.push   : Bool -> Maybe String -> Maybe String -> IO (Result (Stream String) (List IOError))
```

## 输出类型定义

### 常见输出模式

| 输出模式 | CDF 声明 | 运行时处理 |
|---------|---------|-----------|
| 行列表 | `output : Stream String` | 逐行拉取，每行为一个字符串 |
| JSON | `output : Stream JsonValue` | 每行解析为 JSON 值 |
| 表格 | `output : Stream (List String)` | 每行解析为字段列表 |
| 二进制 | `output : Bytes` | 原始字节输出 |
| 无输出 | `output : Unit` | 仅检查退出码 |
| 混合输出 | 见下方示例 | 根据输出内容自动判断 |

### 结构化输出示例

```
// cat — 读取文件内容
output : Stream String

// ls --json — JSON 行输出
flag "json" 'j' : Bool
output : Stream Row
  // Row 类型定义
  when json     -> JsonValue    // --json 模式
  when !json    -> String       // 普通行模式

// find — 文件名列表
output : Stream Path

// du — 磁盘使用量
output : Stream { path : Path, size : Int }
```

## 行为声明

行为声明定义命令在运行时的预期系统资源访问模式，影响 seccomp 规则生成：

### 文件系统行为

```
behavior
  fs.read("/etc")              // 读取指定路径
  fs.read("/var")              // 读取多个路径
  fs.write("/tmp")             // 写入指定路径
  fs.read(Any)                 // 可读取任意路径（宽松模式）
  fs.meta                      // 仅读取元数据（stat、lstat），不读内容
```

### 网络行为

```
behavior
  net.http("api.example.com")  // HTTP 请求到指定域名
  net.https("*")               // HTTPS 请求到任意域名
  net.listen(8080)             // 监听指定端口
  net.tcp(Any)                 // 任意 TCP 连接
```

### 进程行为

```
behavior
  process.exec                 // 启动子进程
  process.signal               // 发送信号
  process.kill                 // 终止进程
```

### 系统行为

```
behavior
  sys.time                     // 读取系统时间
  sys.env("HOME")              // 读取指定环境变量
  sys.env("*")                 // 可读取所有环境变量
  sys.random                   // 访问随机数设备
```

### seccomp 规则自动推导

行为声明到 seccomp-BPF 过滤规则的映射：

| CDF 行为声明 | 允许的系统调用 | 说明 |
|-------------|--------------|------|
| `fs.read(Path)` | `openat`、`read`、`pread64`、`fstat`、`close`、`lseek` | 文件读取 |
| `fs.write(Path)` | `openat`、`write`、`pwrite64`、`ftruncate`、`fsync`、`close` | 文件写入 |
| `net.http(host)` | `socket`、`connect`、`sendto`、`recvfrom`、`close` | 网络请求 |
| `process.exec` | `clone`、`execve`、`waitid`、`exit_group` | 进程管理 |
| 无声明 | `brk`、`mmap`、`munmap`、`exit_group` | 仅内存操作 |

## 内置签名库

### 覆盖范围

核心命令的内置签名由 Kun 发行版提供，覆盖：

| 类别 | 命令 |
|------|------|
| 文件操作 | `ls`、`cat`、`cp`、`mv`、`rm`、`mkdir`、`touch`、`chmod`、`chown`、`ln`、`readlink`、`realpath` |
| 内容处理 | `grep`、`sed`、`awk`、`sort`、`uniq`、`wc`、`cut`、`tr`、`head`、`tail`、`tee` |
| 查找检索 | `find`、`locate`、`which`、`whereis` |
| 系统信息 | `ps`、`top`、`df`、`du`、`free`、`uname`、`uptime`、`lscpu` |
| 网络 | `curl`、`wget`、`ping`、`ss`、`netstat`、`dig`、`nslookup` |
| 进程管理 | `kill`、`pkill`、`nice`、`renice`、`nohup` |
| 权限 | `sudo`、`su`、`chown`、`chmod`、`umask` |
| 压缩归档 | `tar`、`gzip`、`gunzip`、`zip`、`unzip`、`xz`、`zstd` |
| 文件传输 | `scp`、`rsync`、`sftp` |

### 内置签名的存储

内置签名编译在 Kun 运行时二进制中，以 Zig 静态数组形式存在：

```
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
  flag "verbose" 'v' : Bool        // 置信度: 高
  option "output" 'o' : String     // 置信度: 中（类型不确定）
  positional 0 : String            // 置信度: 低（位置参数含义未知）
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

```
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
  ├── 4. 行为契约注册：将 CDF behavior 转换为 seccomp 规则
  │
  ├── 5. 执行命令：通过 dlopen/ptrace/fork-exec 加载
  │
  └── 6. 输出契约验证：检查输出是否符合 CDF 声明的类型
```

### 参数验证器运行时

参数验证器在序列化参数前执行：

```
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
| seccomp 管理器 | 根据 CDF behavior 生成 seccomp-BPF 规则 |
| 能力管理器 | 根据 CDF behavior 检查权限 |
| 结果反序列化器 | 根据 CDF output 定义解析返回值 |

## 完整示例

### ls.cdf

```
// kun-cdf-v1
command "ls"

flag "all"             'a' : Bool
flag "long"            'l' : Bool
flag "human-readable"  'h' : Bool
flag "recursive"       'R' : Bool
flag "directory"       'd' : Bool
flag "sort"            'S' : Bool with (enum ["size", "time", "version"])
option "time"          't' : String with (enum ["atime", "ctime", "mtime"])
positional 0                : Path with (optional)
positional 1                : Path with (optional)

output : Stream String

behavior
  fs.read("/")
  fs.meta
```

### 生成的 Kun 类型签名

基于 CDF 自动生成 Kun 函数签名：

```
ls : { all : Bool, long : Bool, human_readable : Bool, recursive : Bool,
       directory : Bool, sort : Maybe String, time : Maybe String } ->
     Maybe Path -> Maybe Path ->
     IO (Result (Stream String) (List IOError))
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
