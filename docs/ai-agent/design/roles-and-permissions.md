# 能力安全系统设计

> 本文档是 Kun 语言能力安全系统的权威设计文档。定义能力（capability）的声明语法、匹配规则、运行时检查架构及安全边界。

## 最小权限原则

Kun 的能力安全系统遵循最小权限原则（Principle of Least Privilege）：**可执行脚本默认拥有零能力**（Zero Default Capabilities）。所有对 IO 资源（文件系统、网络、进程、环境变量、系统调用）的访问都必须通过显式的 `with caps` 声明授予。

### 核心原则

- 能力仅守卫 IO 操作（fs、net、process、env、sys）。纯函数（算术运算、字符串操作、模式匹配）不需要能力检查。
- 能力可以在脚本级或作用域块级（`do` 块上）声明。
- 能力是一个 `(Namespace, Action, Targets)` 三元组。能力对象结构是编译器内置类型，非标准库 ADT。
- **资源预算**（CPU/内存限制）是独立的限流层，由执行器参数处理，不属于能力系统。默认值应适配大多数脚本。

### 默认权限表

| 资源类型 | 默认权限 | 说明 |
|---------|---------|------|
| 文件系统读 | 无 | 所有路径（包括 CWD）默认不可读 |
| 文件系统写 | 无 | 所有路径（包括 CWD）默认不可写 |
| 文件系统元数据 | 无 | `stat` 等操作默认不可用 |
| 网络出站 | 无 | HTTP/HTTPS/TCP/UDP 全部禁止 |
| 网络监听 | 无 | 禁止监听任何端口 |
| 进程执行（模块引入） | 无 | 禁止执行模块函数引入的外部命令（直接调用的命令自动推断） |
| 进程信号/终止 | 无 | 禁止信号发送与进程终止 |
| 进程运行用户切换 | 无 | 只能以当前进程用户运行命令函数 |
| 环境变量读 | 无 | 禁止读取任何环境变量 |
| 环境变量写 | 无 | 禁止修改任何环境变量 |
| 系统时间 | 无 | 禁止读取系统时间 |
| 随机设备 | 无 | 禁止访问随机数设备 |
| 主机名 | 无 | 禁止读取/设置主机名 |

### `Path.cwd`

`Path.cwd` 提供当前工作目录：在脚本启动时求值一次并冻结。运行时 `chdir` **不**影响能力声明中的 `Path.cwd`。

**`chdir` 操作**：Kun 不提供内建的 `chdir` 函数。脚本不应在运行时切换工作目录。若确实需要改变进程的 CWD（如影响子进程的路径解析），需通过外部命令 `cd` 在子 shell 中实现，该操作受 `process.exec` 控制。

### 与操作系统的关系

- 能力系统完全独立于操作系统的 sudo。两者正交运作。
- 能力系统不支持在执行期间切换用户。
- 能力系统不阻止调用 `sudo`——那是操作系统层面的问题。
- 最低 Linux 内核版本：**3.8**（支持用户命名空间，用于非特权沙箱设置）。

## 能力声明语法

### 脚本级 `with caps`

可执行脚本在顶层使用 `with caps` 关键字声明能力。脚本级能力是该脚本中所有操作的上限。

```kun
with caps
  fs.read = [Path.cwd, p"/tmp/"]
  fs.write = fs.read
with caps
  process.exec = ["ls", "cat"]

main =
  do
    ...
```

语法规则：
- `with caps` 关键词独占一行。
- 每个能力动作和目标列表各占一行，缩进表示属于该能力声明块。
- `with caps` 块不能为空。
- 引用语法（`fs.write = fs.read`）是编译期展开，非运行时操作。不允许前向引用。
- 多个 `with caps` 块：有效能力集 = 所有块的**并集**。
- 目标必须是**编译期字面量**。不允许运行时动态拼接或修改。

### 函数级 `with caps ... do`

在 `do`（或 `do in`）块上附加能力声明，用于进一步收窄权限：

```kun
readConfig =
  with caps
    fs.read = [p"/etc/kun/config"]
  do
    conf <-? readFile p"/etc/kun/config"
  in
    conf
```

语法规则：
- 能力声明附加在 `do` 块上，与 `do` 在同一缩进层级。
- 带 `with caps` 的 `do` 块仍然是单个表达式。
- `with caps` 可以附加到任意嵌套层级的 `do` 块上。
- 每个表达式最多只能有一个 `with caps`（多个出现为编译期错误）。

### 能力声明 = 权限契约

执行带有 `with caps` 声明的脚本意味着用户**隐式同意**这些能力。审计机制提供了事前的可见性：

- `kun --audit <脚本>` —— 展示声明的能力，不执行
- `kun --confirm <脚本>` —— 交互式逐项确认能力
- `kun --cap-log <脚本>` —— 执行后输出实际能力使用审计日志

## 能力匹配规则

不同动作有不同的目标模糊匹配规则：

### 文件系统（fs）

| 目标示例 | 匹配行为 |
|---------|---------|
| `p"/etc/"` | 目录前缀匹配：匹配 `/etc` 及所有子路径 |
| `p"/etc/config"` | 精确文件匹配：仅匹配该文件 |
| `Path.cwd` | 编译期展开为脚本启动时的 CWD 绝对路径 |
| `[]` | 空列表 = 匹配任何路径 |

### 网络（net）

| 目标示例 | 匹配行为 |
|---------|---------|
| `"api.example.com"` | 精确主机匹配 |
| `"*.example.com"` | 子域名 glob 匹配（匹配 `a.example.com` 等） |
| `[]` | 空列表 = 匹配任何主机 |

### 进程（process）

| 目标示例 | 匹配行为 |
|---------|---------|
| `["ls", "cat"]` | 精确命令名匹配（命令 basename 精确相等） |
| `["ls"]` | **不**匹配 `lsblk` |

### 环境变量（env）

| 目标示例 | 匹配行为 |
|---------|---------|
| `["HOME", "PATH"]` | 精确变量名匹配 |
| `[]` | 空列表 = 匹配任何变量 |

### 端口（`net.listen`）

| 目标示例 | 匹配行为 |
|---------|---------|
| `[8080, 443]` | 精确端口号匹配 |

### 无目标动作

部分动作没有目标参数，用空列表 `[]` 表示"任何/全部"：

| 能力 | 语义 |
|------|------|
| `fs.meta = []` | 可读取任意路径的元数据 |
| `process.signal = []` | 可向任意进程发信号 |
| `process.kill = []` | 可终止任意进程 |
| `process.trace = [Pid 1234]` | 仅跟踪指定 PID 的进程（必须显式指定目标） |
| `process.run-as = ["root", "nobody"]` | 允许命令函数切换到指定用户执行 |
| `sys.time = []` | 可读取系统时间 |
| `sys.random = []` | 可访问随机设备 |
| `sys.hostname = []` | 可读取/设置主机名 |

> **`[]`（空列表）使用注意**：`[]` 表示"匹配任何目标"。对敏感命名空间（`env.read`、`env.write`、`process.exec`）使用 `[]` 会显著扩大安全攻击面（如 `env.read = []` 暴露所有环境变量包括密钥）。建议仅在 `sys` 等只读系统能力上使用 `[]`，其他命名空间尽量精确声明目标。编译期可对敏感命名空间的 `[]` 使用发出警告。

## 能力类型目录

### 文件系统（fs）

| 动作 | 目标类型 | 语义 | 示例 |
|------|---------|------|------|
| `read` | `[Path]` | 读取文件/目录内容及元数据 | `fs.read = [p"/etc/", Path.cwd]` |
| `write` | `[Path]` | 写入/创建/删除文件/目录 | `fs.write = [p"/tmp/"]` |
| `meta` | （无目标） | 仅读取元数据（stat），不读内容 | `fs.meta = []` |

路径匹配规则：
- `p"/etc/"` —— 目录前缀匹配，匹配 `/etc` 及所有子路径。**目标为目录时必须以 `/` 结尾**
- `p"/etc/config"` —— 仅匹配该精确文件。**目标为文件时不能以 `/` 结尾**
- `[]` —— 空列表 = 匹配任何路径

### 网络（net）

| 动作 | 方向 | 目标类型 | 语义 | 示例 |
|------|------|---------|------|------|
| `http` | 出口 | `[String]` | 发起 HTTP 请求到指定目标 | `net.http = ["api.example.com"]` |
| `https` | 出口 | `[String]` | 发起 HTTPS 请求到指定目标 | `net.https = []`（任何主机） |
| `tcp` | 出口 | `[String]` | 发起 TCP 连接到指定目标 | `net.tcp = ["10.0.0.1:5432"]` |
| `udp` | 出口 | `[String]` | 发送 UDP 数据报到指定目标 | `net.udp = ["192.168.1.1:5353"]` |
| `unix` | 出口/进口 | `[Path]` | 连接或绑定 Unix domain socket | `net.unix = [p"/var/run/app.sock"]` |
| `listen` | 进口 | `[String]` | 在指定地址端口监听连接请求 | `net.listen = [":8080"]` |

网络能力同时控制出口（egress）和进口（ingress）两个方向：

- **出口能力**（`http`、`https`、`tcp`、`udp`、`unix`）：限制脚本主动发起的对外连接能到达的目标主机或地址。未声明出口网络能力时，脚本无法发起任何对外连接。
- **进口能力**（`listen`）：限制脚本能在哪些地址和端口上提供服务。未声明 `listen` 时，脚本无法启动任何网络服务监听。

**DNS 解析不由能力系统控制**。DNS 是 libc 内部功能（`getaddrinfo`），其网络流量受 OS 层的 Network Namespace 约束——基于已声明的 `net.*` 目标域名自动放行对应的 DNS 查询，无需独立的能力动作。`resolve` 函数是 libc `getaddrinfo` 的封装，不经过能力检查。

目标匹配规则：

| 动作 | 规则 | 示例 |
|------|------|------|
| `http` / `https` | `域名`、`域名:端口`、`IP:端口`、glob 匹配 | `"api.example.com:443"`、`"*.example.com"` |
| `tcp` / `udp` | `IP:端口`、`域名:端口` | `"10.0.0.1:5432"`、`"db.internal:3306"` |
| `unix` | 文件系统路径 | `p"/var/run/app.sock"`、`p"/tmp/kun.sock"` |
| `listen` | `<ip>:<port>`、`:<port>`、`localhost:<port>` | `"0.0.0.0:8080"`、`":9090"`、`"localhost:3000"` |
| — | `[]`（空列表） | 匹配任何目标 |

### 进程（process）

| 动作 | 目标类型 | 语义 | 示例 |
|------|---------|------|------|
| `exec` | `[String]` | 显式声明模块中引入的外部命令 | `process.exec = ["curl"]` |
| `run-as` | `[String]` | 允许命令函数切换到的用户名或 UID | `process.run-as = ["root", "nobody"]` |
| `signal` | （无目标） | 向进程发送信号 | `process.signal = []` |
| `kill` | （无目标） | 终止任意进程 | `process.kill = []` |
| `trace` | `[Pid]` | 跟踪/调试指定 PID 的进程（ptrace） | `process.trace = [Pid 1234]` |

`process.exec` 的声明规则：

| 调用方式 | 是否需要显式 `process.exec` | 说明 |
|---------|--------------------------|------|
| 脚本直接调用 `ls { ... }` | **不需要**——运行时自动推断 | 脚本作者直接调用的命令，CDF 本身即授权 |
| 模块函数内部调用 `curl` | **需要**——`process.exec = ["curl"]` | 脚本作者可能不知道模块引入了哪些外部命令 |

`process.exec` 控制的是**脚本作者对模块引入的外部命令的知情权**，而非子进程执行本身——直接调用的命令通过 CDF 的存在自动获得授权。

```kun
with caps
  // 不需要显式声明 process.exec = ["ls", "cat"]
  fs.read = [Path.cwd]

main = do
  ls { path0 = p"." }          // ✅ 直接调用，自动推断
  cat { path0 = p"README" }     // ✅ 直接调用，自动推断
  NetUtils.fetchAll url         // ❌ 模块函数内部调用 curl，
                                //    需 process.exec = ["curl"]
```

`exec` 支持两种匹配方式：

| 匹配方式 | 规则 | 示例 |
|---------|------|------|
| **basename 匹配** | 仅匹配命令名，不检查路径 | `process.exec = ["curl"]` 匹配 `curl` |
| **绝对路径匹配** | 路径必须以 `/` 开头，精确匹配目标 | `process.exec = [p"/usr/bin/curl"]` 仅匹配 `/usr/bin/curl` |

命令函数调用使用命令名匹配 basename，命令解析器按 CDF 签名搜索路径解析到具体二进制。`process.exec` 未声明时，直接调用的命令由运行时自动推断；模块引入的命令被拒绝。

#### `process.run-as`——运行用户控制

命令函数的隐式参数 `runAs` 用于指定执行用户。该参数由 `process.run-as` 能力授权：

```kun
with caps
  process.run-as = ["root", "nobody"]   // 允许切换到的用户

main =
  ls { path0 = p"/root", runAs = Just "root" }   // ✅ 以 root 执行（ls 自动推断）
  ls { path0 = p"/tmp" }                          // ✅ 缺省当前用户
  ls { runAs = Just "mysql" }                     // ❌ "mysql" 不在 process.run-as 中
```

- `runAs` 缺省 `Nothing`（当前进程用户）
- 目标为用户名（`"root"`）或 UID 字符串（`"0"`）
- 运行时通过 `setuid()`/`seteuid()` 切换用户，需进程有足够 OS 权限（root 或 CAP_SETUID）
- 此能力不替代 `sudo`——进程的 OS 权限决定了能否成功切换

命令函数（如 `ls`、`cat`）通过命令解析器按搜索路径解析到具体二进制。能力检查对命令函数使用的匹配规则与 `exec` 原语一致——若声明 `process.exec = [p"/usr/bin/ls"]` 但命令解析器将 `ls` 解析为内置实现，则路径匹配失败。建议在声明绝对路径时确保路径与命令解析器的解析结果一致。

对外部命令的权限元数据修改（如 `chmod`、`chown`）不涉及独立的能力动作，通过 `process.exec` + `fs.write` 组合控制：

| 能力 | 作用 | 示例 |
|------|------|------|
| `process.exec` | 允许启动 `chmod`/`chown` 命令 | `process.exec = ["chmod", "chown"]` |
| `fs.write` | 沙箱锚定可修改的目标路径 | `fs.write = [p"/etc/config"]` |
| OS 内核 | 实际的 `chown` 系统调用权限检查（root/owner） | 能力系统不干涉 |

`chmod` 和 `chown` 作为外部命令受 `process.exec` 门控，其内部元数据写入行为受沙箱 `fs.write` 约束。

#### 环境变量过滤（exec 前安全策略）

通过 `process.exec` 启动子进程前，运行时自动过滤环境变量，防止密钥泄漏和注入攻击：

```c
// 伪代码：exec 前执行
char** filtered_env = build_filtered_env(
    current_env(),              // 当前进程完整环境
    current_scope.env.read,     // 脚本声明的 env.read 目标
);
execve(path, argv, filtered_env);
```

| 规则 | 说明 |
|------|------|
| 始终剔除（纯注入向量，无合法用途） | `LD_PRELOAD`、`LD_AUDIT`、`LD_DEBUG`、`BASH_ENV`——无论 `env.read` 如何声明，这些变量永不传递给子进程 |
| `env.read = []`（通配） | 剔除始终剔除列表后，保留所有剩余变量 |
| `env.read = ["HOME", "PATH"]` | 剔除始终剔除列表后，仅保留 `HOME` 和 `PATH` |
| 未声明 `env.read` | **不执行过滤**，子进程继承完整环境变量 |

始终剔除列表只包含纯注入向量——有合法用途的变量（`LD_LIBRARY_PATH`、`PYTHONPATH`、`PERL5LIB`、`IFS`、`SHELL`、`LC_ALL` 等）**不**在始终剔除列表中，遵循 `env.read` 能力规则。未声明 `env.read` 时所有变量正常传递，不影响 `gcc`、`make` 等构建工具的执行。

此策略由运行时自动执行，无需额外能力声明。始终剔除列表为编译期硬编码的安全基线，不可被脚本覆盖。

### 环境变量（env）

| 动作 | 目标类型 | 语义 | 示例 |
|------|---------|------|------|
| `read` | `[String]` | 读取指定环境变量 | `env.read = ["HOME", "PATH"]` |
| `write` | `[String]` | 设置/修改环境变量 | `env.write = []`（任何变量） |

### 系统（sys）

| 动作 | 目标类型 | 语义 | 示例 |
|------|---------|------|------|
| `time` | （无目标） | 读取系统时间 | `sys.time = []` |
| `random` | （无目标） | 访问随机数设备 | `sys.random = []` |
| `hostname` | （无目标） | 读取/设置主机名 | `sys.hostname = []` |

## 运行时能力检查架构

### Capability Manager

运行时维护以下状态：

```
CapabilityManager
├── current_scope: CapabilitySet       // 当前有效能力
├── script_level: CapabilitySet       // 脚本级能力（启动时解析）
├── scope_stack: [CapabilitySet]      // 嵌套 with caps ... do 栈
└── audit_log: [AccessAttempt]        // 访问审计日志
```

> **线程安全**：CapabilityManager 当前为单线程执行设计，scope_stack 的可变状态（push/pop）无并发保护。若未来加入 `Task.parallel` 等并发机制，需要对 scope_stack 和 audit_log 加锁（Mutex 或 RwLock）。

### 检查流程

```
IO 操作 → capability_check(namespace, action, target)
          │
          ├── current_scope.contains(namespace, action, target) ?
          │     │
          │     ├── YES → 允许，记录审计日志
          │     │
          │     └── NO  → 拒绝，抛出 PermissionError（含修改建议）
```

### 审计日志

所有能力检查和访问尝试记录到审计日志：

```json
{
  "timestamp": 1717084800000000000,
  "script": "/home/user/deploy.kun",
  "line": 42,
  "resource": "/etc/shadow",
  "namespace": "fs",
  "action": "read",
  "target": "/etc/shadow",
  "result": "denied",
  "reason": "capability not declared"
}
```

审计日志持久化到 `~/.kun/audit/` 目录，周期性轮转。

### 动态授予（仅 REPL 模式）

仅在 REPL 模式中，可以通过内置函数创建新的函数执行环境来于运行时更改能力。非交互式脚本执行不支持动态能力授予。

### 能力引用语义

```kun
with caps
  fs.read = [Path.cwd, p"/tmp/"]
  fs.write = fs.read    // 编译期展开为 fs.write = [Path.cwd, p"/tmp/"]
```

引用语法是编译期展开，不是运行时操作。不允许前向引用。

## 沙箱隔离（尽力而为）

### 设计边界

Kun 的安全模型有两层防线，职责不同：

| 防线 | 控制对象 | 强度 | 说明 |
|------|---------|------|------|
| **`capability_check`** | Kun IO 原语（`readFile`、`httpGet` 等） | **硬防线**——在进程内强制检查，不可绕过 | 所有 IO 原语入口调用，检查 `(namespace, action, target)` 三元组 |
| **沙箱**（namespace + seccomp） | 通过 `process.exec` 启动的子进程 | **尽力而为**——受内核版本和动态链接限制 | 子进程以 OS 用户权限运行，Kun 无法完全约束其内部文件访问 |

`capability_check` 是第一且唯一的硬防线。沙箱提供纵深防御，但有已知局限。

### 沙箱机制

| 机制 | 能做什么 | 不能做什么 | 内核依赖 |
|------|---------|-----------|---------|
| Mount namespace | 限制子进程的文件系统**目录**可见性 | ❌ 按**文件**粒度隔离（目录级粒度） | 3.8+ |
| | | ❌ 动态链接命令需暴露系统库路径（`/usr`、`/lib`），间接暴露整个根文件系统 | |
| Network namespace | 限制子进程的网络出口和监听端口 | ❌ 无法区分协议或应用层内容 | 3.8+ |
| seccomp-BPF | 限制系统调用类型（禁止 `execve`、`ptrace` 等） | **❌ 无法按路径过滤**——seccomp 检查寄存器值，不解引用路径字符串指针 | 3.5+ |
| Landlock LSM | 路径级文件访问控制（无需 mount namespace） | 需要内核 5.13+ | 5.13+ |

### 已知局限

1. **子进程文件访问**：通过 `process.exec` 启动的子进程以 OS 用户权限运行。对动态链接的命令，mount namespace 需暴露系统库路径（`/usr`、`/lib`），间接暴露整个根文件系统。`capability_check` 不控制子进程内部行为——它只在启动前检查传参（`cat p"/etc/shadow"` 中的路径），子进程内的文件访问由 OS 和 CDF 沙箱策略约束。

2. **Symlink TOCTOU**：`capability_check` 的路径检查与实际 IO 之间存在时间窗口，攻击者可替换符号链接绕过检查。缓解：
   - 内核 5.6+：运行时 IO 原语使用 `openat2()` + `RESOLVE_NO_SYMLINKS` + `RESOLVE_BENEATH`
   - 内核 < 5.6：回退 `O_NOFOLLOW` + `fstat`（有限防护）
   - 子进程的符号链接问题不在能力系统范围内

3. **容器环境**：在 Docker/Kubernetes 中无法创建新 namespace 时，子进程沙箱隔离不可用。此时 `capability_check` 始终有效；依赖容器的现有隔离策略。

### 配置原则

- 一次沙箱配置对应一次外部命令调用
- CDF 不再包含能力行为声明，seccomp 规则由参数类型推导

## 模块能力规则

### 模块禁止声明能力

模块（库文件）**不能**声明能力。如果模块中出现 `with caps`，属于编译期错误。

```kun
// 错误：模块（库文件）不能声明能力
with caps                // ❌ 编译期错误
  fs.read = [p"/etc/"]

helper = \x -> x + 1      // ✅ 纯函数，不需要能力
```

### 模块函数可收窄能力

模块中的函数可以在其 `do` 块上声明能力。有效能力集 = 调用脚本能力 ∩ 函数自身声明：

```kun
// 库模块：lib/db.kun
readConfig =
  with caps
    fs.read = [p"/etc/kun/config"]
  do
    conf <-? readFile p"/etc/kun/config"
  in
    conf
```

当脚本调用此函数时：
1. 脚本自身声明的能力作为基线
2. 函数 `with caps` 声明进一步收窄（交集）
3. 模块函数的 `with caps` 只能收窄，不能扩权

## 父-子脚本能力传递

### 传递机制

父脚本通过 `kun <子脚本> with caps ...` 语法将能力子集传递给子脚本：

```kun
// 父脚本：deploy.kun
with caps
  fs.read = [p"/etc/"]
  net.http = ["api.example.com"]

main =
  do
    // 调用子脚本，显式传递能力子集
    kun "child.kun" with caps
      fs.read = [p"/etc/"]
```

### 传递规则

| 场景 | 子脚本获得的能力 | 说明 |
|------|----------------|------|
| `kun "child.kun"`（无 `with caps`） | 子脚本默认能力（无任何能力） | 能力不传递 |
| `kun "child.kun" with caps fs.read = [p"/etc/"]` | 子脚本获得 `fs.read = [p"/etc/"]` | 显式传递 |
| 子脚本自身声明了 `fs.read = [p"/etc/"], net.http = []` | 交集 = 父声明的 `net.http = ["api.example.com"]` ∩ 子声明的 `[]` | 空列表代表"任意"，取父传入值 |

### 交集运算

子脚本的实际可用能力 = 父脚本传递的能力 ∩ 子脚本自身声明的能力：

```kun
// 父脚本传递:  fs.read = [p"/etc/"], net.http = ["api.example.com"]
// 子脚本声明:  fs.read = [p"/etc/"], net.http = []
// 实际可用:    fs.read = [p"/etc/"]
//              net.http = ["api.example.com"]
```

交集规则：

| 父传递目标 | 子声明目标 | 交集结果 | 说明 |
|-----------|-----------|---------|------|
| `[p"/etc/"]` | `[p"/etc/"]` | `[p"/etc/"]` | 精确匹配 |
| `[p"/etc/"]` | `[]`（任意） | `[p"/etc/"]` | 子声明"任意"但不能超父——取父值 |
| `[]`（任意） | `[p"/var/"]` | `[p"/var/"]` | 父传递任意、子声明精确——取子值 |
| `["api.example.com"]` | `[]`（任意） | `["api.example.com"]` | 子不能超父 |
| `[p"/etc/"]` | `[p"/var/"]` | `[]`（不允许） | 交集为空——无可用能力 |

## 审查机制

Kun 提供三种审查机制，确保能力声明的可见性和可审计性：

### `--audit`：静态审计

展示脚本声明的所有能力，不执行脚本：

```bash
kun --audit deploy.kun
```

输出示例：

```
脚本: deploy.kun
能力声明:
  fs.read   → [Path.cwd, p"/etc/"]
  fs.write  → [p"/tmp/"]
  net.http  → ["api.example.com"]

沙箱配置:
  Mount Namespace:   /etc/, /tmp/, <CWD>
  Network Namespace: api.example.com (egress only)
  seccomp:           read, write, open, connect, ...
```

### `--confirm`：交互式确认

逐项显示能力声明，要求用户确认：

```bash
kun --confirm deploy.kun
```

```
脚本 deploy.kun 声明了以下能力：

  1. fs.read   → [Path.cwd, p"/etc/"]
  2. fs.write  → [p"/tmp/"]
  3. net.http  → ["api.example.com"]

是否同意以上能力？ [y/N]
```

### `--cap-log`：运行时审计日志

执行脚本并输出完整的能力使用审计日志：

```bash
kun --cap-log deploy.kun
```

输出每次能力检查的结果，包括允许和拒绝的尝试，以及资源访问的详细时间线。

## 权限异常报告

当脚本尝试访问未被授权的能力时，抛出结构化的 `PermissionError`。

### PermissionError 结构

| 字段 | 说明 |
|------|------|
| `resource_type` | 请求的资源类型（文件、网络、环境变量等） |
| `resource_path` | 具体的资源标识（文件路径、URL、变量名等） |
| `required_capability` | 所需的能力（格式：`namespace.action`） |
| `source_location` | 触发异常的源码位置（文件名、行号、列号） |
| `reason` | 权限被拒绝的原因 |
| `suggestion` | 针对性的修改建议，包含精确的 `with caps` 语法模板 |

### 异常报告示例

```
错误：PermissionError

  尝试访问的资源：文件 /etc/shadow
  资源类型：文件系统读取
  所需能力：fs.read /etc/shadow
  源码位置：deploy.kun:42:5
  拒绝原因：脚本未声明对路径 "/etc/shadow" 的读取权限

修改建议：
  在脚本头部添加以下能力声明：

    with caps
      fs.read = [p"/etc/shadow"]

  或授权访问整个目录：

    with caps
      fs.read = [p"/etc/"]
```

```
错误：PermissionError

  尝试访问的资源：https://api.example.com/data
  资源类型：网络请求
  所需能力：net.http api.example.com
  源码位置：fetch.kun:8:3
  拒绝原因：脚本未声明任何网络访问权限

修改建议：
  在脚本头部添加以下能力声明：

    with caps
      net.http = ["api.example.com"]

  如需匹配子域名：

    with caps
      net.http = ["*.example.com"]
```

```
错误：PermissionError

  尝试访问的资源：环境变量 HOME
  资源类型：环境变量读取
  所需能力：env.read HOME
  源码位置：utils.kun:15:12
  拒绝原因：脚本未声明任何环境变量访问权限

修改建议：
  在脚本头部添加以下能力声明：

    with caps
      env.read = ["HOME"]

  如需允许读取所有环境变量：

    with caps
      env.read = []
```

### 修改建议生成策略

1. **资源类型感知**：根据被拒绝的资源类型自动匹配对应的能力声明语法
2. **路径规范化**：对文件系统路径，建议使用最小必要的父目录
3. **通配符提示**：当需要访问多个同类资源时，提示通配符简化方案
4. **安全提醒**：对于网络访问和进程管理等高风险操作，附加安全提醒
5. **语法模板**：每条建议附带可直接复制粘贴的 `with caps` 语法模板
6. **上下文关联**：父子脚本场景下，额外提示是否需要父脚本传递能力

## 资源预算（独立限流层）

**资源预算**（CPU 时间、内存使用量、磁盘配额）不是能力系统的一部分，而是独立的限流层，由执行器参数配置。

### 设计原则

- 能力系统只负责"能做什么"（访问控制），不负责"能做多少"（资源配额）
- 资源预算由执行器参数（executor parameters）处理
- 默认值应适配大多数脚本，无需显式配置

```bash
# 资源预算由执行器参数配置，非能力系统
kun --exec-memory-limit 512MB --exec-timeout 30s deploy.kun
```

### 与能力系统的关系

| 维度 | 能力系统 | 资源预算 |
|------|---------|---------|
| 管控对象 | 能否访问某资源 | 能用多少资源 |
| 作用时机 | 每次 IO 操作 | 持续监控 |
| 声明位置 | 脚本内 `with caps` | 执行器参数 |
| 粒度 | 每个动作/目标 | 全局限制 |
| 默认值 | 零能力 | 适配多数脚本 |

## 威胁模型分析

### 攻击面总览

```
┌──────────────────────────────────────────────────────────────┐
│                    Kun 运行时攻击面                            │
├──────────────────────────────────────────────────────────────┤
│  脚本层             │ 能力层               │ 系统层            │
├──────────────────────────────────────────────────────────────┤
│  代码注入           │ 能力声明欺骗         │ 运行时二进制篡改  │
│  路径遍历           │ 能力传递漏洞         │ 共享库注入        │
│  不安全的解构       │ 沙箱逃逸             │ 内核漏洞          │
│  信息泄露           │ seccomp 绕过         │ 容器逃逸          │
└──────────────────────────────────────────────────────────────┘
```

### 威胁与防御矩阵

| 威胁 | 攻击向量 | 影响 | 防御机制 | 严重程度 |
|------|---------|------|---------|---------|
| 脚本代码注入 | 通过字符串插值注入恶意代码 | 任意代码执行 | 类型安全 + 严格求值 + 无 `eval` | 高 |
| 路径遍历 | 通过路径参数访问未授权目录 | 未授权文件访问 | `Path` 类型运行时规范化 + 能力检查 | 高 |
| 能力声明伪造 | 声明脚本不具备的能力 | 越权访问 | 编译期验证 + `--audit` 审查 + 签名验证 | 高 |
| 能力传递越权 | 子脚本获取超出预期的能力 | 权限提升 | 交集运算 + 显式传递 + 不可扩权 | 高 |
| 沙箱逃逸（namespace） | 利用内核漏洞逃逸 mount/network namespace | 完全控制 | 最低内核 3.8 + 非特权用户 + seccomp 收窄 | 高 |
| seccomp 绕过 | 利用未过滤的系统调用 | 沙箱逃逸 | 基于能力声明生成最小 seccomp 规则 | 中 |
| 拒绝服务（死循环） | 恶意构造的无限循环 | 资源耗尽 | 资源预算限流层（独立于能力系统） | 中 |
| 运行时二进制篡改 | 替换 Kun 解释器 | 完全控制 | 包管理器签名校验 + 完整性检查 | 高 |
| 共享库注入 | `LD_PRELOAD` 等方式注入恶意库 | 任意代码执行 | 能力限制 + 沙箱隔离 + 环境变量控制 | 高 |
| 容器逃逸 | 在容器内利用内核漏洞逃逸 | 宿主控制 | 容器环境检测 + 禁止嵌套 namespace | 高 |

### 纵深防御层次

```
第 1 层：类型系统（编译期）
  ├── 类型安全：无空指针、无类型混淆
  └── IO 边界：纯函数无副作用

第 2 层：能力安全（运行时）——**硬防线**
  ├── 零默认能力：脚本启动时无任何 IO 权限
  ├── capability_check：所有 Kun IO 原语入口强制检查
  ├── 能力不可伪造/不可转移：编译器内置类型
  └── 权限作用域嵌套（with caps ... do）

第 3 层：沙箱隔离（执行时）——**尽力而为**
  ├── Mount namespace（目录级隔离，动态链接命令限制大）
  ├── Network namespace（出口/入口网络隔离）
  ├── seccomp-BPF（系统调用类型过滤，不支持路径级）
  ├── Landlock LSM（路径级控制，需内核 5.13+）
  └── 容器环境检测（无法 namespace 时降级）

第 4 层：CDF 契约（加载时）
  ├── 密码学签名验证
  └── 二进制完整性校验
```

各层的信任假设：第 2 层（`capability_check`）是唯一不被其他层依赖的硬防线。第 3 层（沙箱）和第 4 层（CDF）提供纵深防御，但已知有局限，不可单独依赖于它们保障安全。

## 与 Unix 传统/容器化方案的对比

### 与 Unix 传统权限的对比

| 维度 | 传统 Unix Shell | Kun |
|------|----------------|-----|
| 默认权限 | 继承用户全部权限 | 零能力（无任何默认权限） |
| 权限获取 | 继承用户身份 | 显式 `with caps` 声明 |
| 权限隔离 | 无（共享用户上下文） | Namespace 沙箱 |
| 权限伪造 | 无限制（用户可做任何事） | 能力不可伪造（编译器内置） |
| 最小权限 | 依赖用户自觉 | 语言层面强制 |
| 错误诊断 | `Permission denied` | 结构化异常 + 原因 + 修改建议 |
| 权限粒度 | 用户级（UID/GID/sudo） | 脚本级 → 函数级（`with caps ... do`） |
| 参数校验 | 无 | 类型系统 + CDF 参数验证 |
| 审计 | 系统日志（auditd） | 内置 `--audit`/`--confirm`/`--cap-log` |

### 与容器化方案的对比

| 维度 | Docker | gVisor | Firecracker | Kun |
|------|--------|--------|-------------|-----|
| 隔离机制 | Linux Namespace + cgroups | 用户态内核（sentry） | 硬件虚拟化（KVM） | Namespace + seccomp + 能力系统 |
| 隔离粒度 | 整个容器 | 整个容器 | 整台虚拟机 | **单命令/单函数** |
| 默认权限 | 受限于容器配置 | 受限于 sentry 策略 | 独立内核 | **零能力** |
| 内核访问 | 共享宿主内核 | 用户态内核代理 | 独立内核 | 共享宿主内核（seccomp 收窄） |
| 攻击面 | 容器 daemon + 宿主内核 | gVisor sentry（较小） | 极小（仅 virtio） | Kun 运行时 + 宿主内核（seccomp 收窄） |
| 内存开销 | 数十 MB（最小镜像） | 数百 MB | 数 MB | 几乎为零（共享进程地址空间） |
| 启动时间 | 0.5 ~ 3 秒 | 1 ~ 5 秒 | ~125 毫秒 | **< 1 毫秒** |
| 权限模型 | 容器级策略（Seccomp/AppArmor） | 同 Docker | 虚拟机级 | **能力级（`with caps` 声明）** |
| 组合方式 | 网络/卷挂载/消息队列 | 同 Docker | 同 Docker | **类型化管道（进程内传递）** |

### 适用场景对比

| 场景 | 容器化方案 | Kun |
|------|-----------|-----|
| 运行 Web 服务/数据库 | 最佳选择 | 不适用 |
| 运行异构应用栈 | 最佳选择 | 不适用 |
| CI/CD 流水线 | 适合（但重量级） | 适合（轻量、精确控制） |
| 系统管理脚本 | 不适用（过于重量级） | **最佳选择** |
| 命令编排与组合 | 不适用（需网络通信） | **最佳选择**（类型化管道） |
| 快速原型验证 | 需构建镜像 | 直接编写脚本 |
| 多租户隔离 | 容器级 | **单命令级**（更细粒度） |

### 互补关系

Kun 与容器化方案并非替代关系，而是互补关系：

1. **Kun 在容器内运行**：在 Docker/Kubernetes 中运行 Kun 时，检测到容器环境后避免创建嵌套 namespace，依赖容器现有隔离。Kun 的能力系统为容器内脚本提供更细粒度的权限控制
2. **Kun 管理容器**：Kun 可通过类型化管道以安全方式调用 `docker`、`kubectl` 等命令
3. **分层防御**：容器提供粗粒度环境隔离，Kun 在内提供细粒度函数级权限控制，形成纵深防御

详细的安全防御方案（包括供应链攻击防御）请参见 [供应链安全](supply-chain-security.md)。

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 0.1.0 | 2026-05-27 | 初始设计：最小权限原则、权限作用域、能力安全、异常报告 |
| 0.1.0 | 2026-05-31 | 深化：能力类型目录、运行时检查架构、动态授予、父-子传递、威胁模型 |
| 0.1.0 | 2026-06-01 | **重写**：全新 `with caps` 语法、零默认能力、移除 CDF 能力声明、能力对象编译器内置、最低 Linux 内核 3.8、独立资源预算限流层、模块禁止声明能力、函数级 `with caps ... do` 交集收窄、`--audit`/`--confirm`/`--cap-log` 审查机制 |
