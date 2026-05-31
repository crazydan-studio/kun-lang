# 安全角色与权限模型

## 最小权限原则

Kun 脚本默认只能访问其工作目录及其子目录下的文件。这是安全模型的基线。

### 默认权限

| 资源类型 | 默认权限 |
|---|---|
| 工作目录及其子目录 | 读写 |
| 环境变量 | 无访问 |
| 网络访问 | 禁止 |
| 其他文件系统路径 | 禁止 |
| 进程管理 | 禁止 |
| 系统调用 | 受限 |

### 显式权限声明

所有超出默认权限的访问必须通过显式的权限声明获得。权限声明在脚本中通过特定的语法结构来表达。

## 单命令权限分配

Kun 的能力模型支持在脚本级别声明权限的基础上，进一步为单个命令调用分配独立的权限。这使得同一个脚本中的不同命令可以拥有不同的能力边界，实现真正的最小权限粒度。

### 权限作用域层级

```
脚本级权限声明（全局基线）
  └── 作用域权限声明（临时扩缩）
        └── 单命令权限注解（精确约束）
```

权限的作用域从大到小依次为：脚本级 → 作用域级 → 单命令级。内层权限是外层权限的子集或交集，即内层只能进一步限制或临时扩展现有能力，不能突破外层未授予的权限。

### 单命令权限注解

通过命令调用的 `with capabilities` 注解，为该次命令调用指定精确的权限集合。未在注解中列出的权限，即使脚本级已声明，该命令也无法使用：

```
// 脚本级声明
capability fs.read("/etc"), fs.read("/var/log"), net.http("api.example.com")

// 该 cat 调用仅可读取 /etc 下的文件，不能访问 /var/log 或网络
cat p"/etc/nginx/nginx.conf" with capabilities fs.read("/etc")

// 该 curl 调用仅可访问 api.example.com，不能读取文件
curl "https://api.example.com/data" with capabilities net.http("api.example.com")

// 该 grep 可同时访问文件和网络（从脚本级继承的权限子集）
cat p"/etc/config" |> grep "pattern" with capabilities fs.read("/etc")
```

### 作用域权限声明

通过 `with capability` 作用域语法，为一段代码块临时授予额外的能力。能力在代码块结束时自动撤销，不会泄漏到外部作用域：

```
// 脚本级未声明网络权限

// 在此作用域内临时授予网络权限
with capability net.http("api.example.com") {
  response = curl "https://api.example.com/data"
  process response
}
// 能力已自动撤销，此处不再拥有网络访问权限
```

作用域可以嵌套，内层作用域可以进一步限制外层的能力：

```
with capability fs.read("/etc"), net.http("*") {
  // 可读写 /etc 和访问任意网络
  config = cat p"/etc/app/config.kun"

  // 内层作用域限制：仅保留文件读取，禁止网络
  with capabilities fs.read("/etc") {
    parsed = parse config
    // 此处 curl 会触发 PermissionError
  }
}
```

### 权限继承与约束规则

| 规则 | 说明 |
|---|---|
| 单命令权限 <= 脚本级权限 | 单命令注解只能使用脚本级已声明的权限子集 |
| 作用域权限 <= 脚本级权限 + 显式扩展 | 作用域可临时扩展脚本级权限，但需显式声明 |
| 内层权限 <= 外层权限 | 嵌套作用域只能限制或保持外层权限 |
| 能力撤销后不可恢复 | 作用域结束后，临时能力永久撤销 |
| 管道中权限取交集 | 管道左侧命令的输出权限必须与右侧命令的输入权限兼容 |

### 管道中的权限传递

在管道操作中，每个命令的权限独立校验。管道操作符不会传递能力：

```
// 脚本级声明
capability fs.read("/var/log"), fs.write("/tmp")

// cat 有 /var/log 的读取权限，sort 仅继承了脚本级的写入权限
// sort 不能读取 /var/log（未在 with capabilities 中显式授予）
cat p"/var/log/app.log" |> sort with capabilities fs.read("/var/log"), fs.write("/tmp")

// 将 cat 输出重定向到文件：需要右侧命令的写入权限
// 此处 write_file 需要 fs.write("/tmp")
cat p"/var/log/app.log" |> write_file p"/tmp/filtered.log" with capabilities fs.read("/var/log"), fs.write("/tmp")
```

### 类型安全与权限的结合

单命令权限注解与类型系统深度集成。类型检查器在编译期即可验证权限注解的合法性：

- 如果单命令权限注解引用了脚本级未声明的权限，编译期报错
- 如果作用域内使用了超出当前有效权限的命令，编译期报错
- 权限约束作为函数类型的一部分，可以在签名中表达

这种编译期的权限验证进一步缩小了供应链攻击的窗口——即使命令二进制被篡改，也无法突破类型系统证明的权限边界。

## 能力安全（Capability-Based Security）

### 能力特性

- **不可伪造**：能力只能由运行时或父脚本授予，不能被自行创建
- **不可转移**：能力一旦获取，不能被传递给其他脚本（除非父脚本显式传递）
- **可丢弃**：能力可以被主动丢弃

### 能力获取途径

1. **启动时授予**：运行时根据脚本的权限声明在启动时授予对应能力
2. **父脚本传递**：父脚本可以将自己的部分能力传递给子脚本
3. **动态授予**：运行时在用户确认后动态授予新能力（适用于交互式场景）

### 能力生命周期

```
获取能力 → 持有能力 → 使用能力 → 丢弃能力
                ↑
            （不可复制、不可伪造、不可转移）
```

## Namespace 沙箱

### 实现机制

- **Mount Namespace**：隔离文件系统视图，限制脚本可见的文件系统范围
- **PID Namespace**：隔离进程视图，限制脚本可见的进程范围

### 容器环境检测

当在 Docker、Kubernetes 等容器化环境中运行时，解释器检测到已在命名空间中运行，避免创建嵌套命名空间，依赖容器的现有隔离。

## 权限异常报告

当脚本尝试访问未被授权的资源时，Kun 解释器会抛出结构化的权限异常（`PermissionError`），包含详细的诊断信息和有针对性的修改建议，帮助开发者快速定位和修复权限问题。

### 异常结构

每次权限异常包含以下字段：

| 字段 | 说明 |
|---|---|
| `resource_type` | 请求的资源类型（文件、网络、环境变量、进程等） |
| `resource_path` | 具体的资源标识（文件路径、URL、变量名、PID 等） |
| `required_capability` | 所需的能力名称 |
| `source_location` | 触发异常的源码位置（文件名、行号、列号） |
| `reason` | 权限被拒绝的原因（未声明、能力已丢弃、超出沙箱范围等） |
| `suggestion` | 针对性的修改建议 |

### 异常报告示例

```
错误：PermissionError

  尝试访问的资源：文件 /etc/nginx/nginx.conf
  资源类型：文件系统读取
  所需能力：fs.read("/etc/nginx/nginx.conf")
  源码位置：config.kun:42:5
  拒绝原因：路径 "/etc/nginx/nginx.conf" 不在工作目录 /home/user/project 及其子目录内

修改建议：
  在脚本头部添加以下权限声明：

    capability fs.read("/etc/nginx/nginx.conf")

  或授权访问整个目录：

    capability fs.read("/etc/nginx")
```

```
错误：PermissionError

  尝试访问的资源：环境变量 HOME
  资源类型：环境变量读取
  所需能力：env.read("HOME")
  源码位置：utils.kun:15:12
  拒绝原因：脚本未声明任何环境变量访问权限

修改建议：
  在脚本头部添加以下权限声明：

    capability env.read("HOME")

  如需访问多个环境变量，可使用通配符：

    capability env.read("*")  // 允许读取所有环境变量
```

```
错误：PermissionError

  尝试访问的资源：https://api.example.com/data
  资源类型：网络请求
  所需能力：net.http("api.example.com", 443)
  源码位置：fetch.kun:8:3
  拒绝原因：脚本未声明任何网络访问权限

修改建议：
  在脚本头部添加以下权限声明：

    capability net.http("api.example.com")

  如需访问任意 HTTPS 地址，可使用通配符：

    capability net.http("*")

  注意：授予权限前请确认该网络资源可信。
```

### 修改建议生成策略

Kun 解释器根据以下规则生成有针对性的修改建议：

1. **资源类型感知**：根据被拒绝的资源类型，自动匹配对应的权限声明语法（文件系统用 `fs.read`/`fs.write`，网络用 `net.http`/`net.tcp`，环境变量用 `env.read`/`env.write` 等）
2. **路径规范化**：对文件系统路径，建议使用最小必要的父目录而非精确文件路径，减少权限声明的冗余
3. **通配符提示**：当同一类型的多个资源被访问时，提示可使用通配符简化声明
4. **安全提醒**：对于网络访问和进程管理等高敏感操作，在建议中附加安全提醒
5. **语法模板**：每条建议都附带可直接复制粘贴到脚本头部的语法模板，降低开发者的认知负担
6. **上下文关联**：对于父子脚本场景，当子脚本缺少权限时，额外提示是否需要父脚本显式传递该能力

### 与传统 Shell 错误信息的对比

| 维度 | 传统 Shell | Kun |
|---|---|---|
| 错误信息 | `Permission denied` | 结构化异常，含资源类型、路径、所需能力 |
| 原因说明 | 无 | 精确描述拒绝原因 |
| 修改建议 | 无 | 针对性的权限声明语法模板 |
| 源码定位 | 无 | 文件名、行号、列号 |
| 安全上下文 | 无 | 提示通配符风险、父子脚本传递 |

## 权限模型与 Unix 传统的对比

| 维度 | 传统 Shell | Kun |
|---|---|---|
| 默认权限 | 用户全部权限 | 仅工作目录 |
| 权限获取 | 继承用户权限 | 显式声明 + 能力授予 |
| 权限隔离 | 无 | Namespace 沙箱 |
| 权限伪造 | 无限制 | 能力不可伪造 |
| 最小权限 | 依赖用户自觉 | 语言层面强制 |
| 错误诊断 | `Permission denied` | 结构化异常 + 详细原因 + 修改建议 |
| 权限粒度 | 用户级（sudo/文件权限） | 脚本级 → 作用域级 → 单命令级 |
| 命令行为约束 | 无 | CDF 行为契约 + seccomp 过滤 |
| 二进制防篡改 | 无 | SHA-256 哈希校验 |

## 与容器化方案的对比

Kun 的安全模型与 Docker、gVisor、Firecracker 等容器化/虚拟化方案目标一致（隔离与最小权限），但在设计哲学和技术路径上有根本差异。

### 核心设计哲学差异

| 维度 | 容器化方案 | Kun |
|---|---|---|
| 隔离单元 | 整个容器（包含完整运行环境） | 单个命令（函数级别的隔离） |
| 设计目标 | 运行任意应用/服务 | 运行和组合 Linux 命令脚本 |
| 权限模型 | 容器级策略（Seccomp/AppArmor profile） | 单命令级能力（with capabilities 注解） |
| 组合方式 | 容器间通过网络、卷挂载、消息队列 | 命令间通过类型化管道（进程内传递） |
| 启动开销 | 重（秒级，需初始化 rootfs、cgroup、namespace） | 轻（微秒级，dlopen 加载 + seccomp 注入） |
| 交互模式 | 声明式编排（Dockerfile / K8s YAML） | 命令式脚本（Kun 语言） |

### 技术实现对比

| 维度 | Docker | gVisor | Firecracker | Kun |
|---|---|---|---|---|
| 隔离机制 | Linux Namespace + cgroups | 用户态内核（ sentry ） | 硬件虚拟化（ KVM ） | Namespace + seccomp + CDF 契约 |
| 内核访问 | 共享宿主内核 | 用户态内核代理 | 独立内核 | 共享宿主内核（seccomp 过滤） |
| 攻击面 | 容器 daemon + 宿主内核 | gVisor 用户态内核（较小） | 极小（仅 virtio 驱动） | Kun 运行时 + 宿主内核（seccomp 收窄） |
| 安全边界 | 进程级 | 进程级 | 虚拟机级 | 命令级（进程内函数调用） |
| 内存开销 | 数十 MB（最小镜像） | 数百 MB | 数 MB | 几乎为零（共享进程地址空间） |
| 文件系统隔离 | 容器镜像层（overlayfs） | 容器镜像层 | 独立 rootfs | Mount Namespace + CDF 声明 |
| 网络隔离 | veth bridge / macvlan | 同 Docker | 独立网络设备 | Network Namespace + CDF 声明 |
| 启动时间 | 0.5 ~ 3 秒 | 1 ~ 5 秒 | 125 毫秒 | < 1 毫秒 |

### 适用场景对比

| 场景 | 容器化方案 | Kun |
|---|---|---|
| 运行 Web 服务/数据库 | 最佳选择 | 不适用 |
| 运行异构应用栈 | 最佳选择 | 不适用 |
| CI/CD 流水线 | 适合（但重量级） | 适合（轻量、精确） |
| 系统管理脚本 | 不适用（过于重量级） | 最佳选择 |
| 命令编排与组合 | 不适用（需网络通信） | 最佳选择（类型化管道） |
| 快速原型验证 | 需要构建镜像 | 直接编写脚本 |
| 多租户隔离 | 容器级隔离 | 单命令级隔离（更细粒度） |

### 互补关系

Kun 与容器化方案并非替代关系，而是互补关系：

1. **Kun 在容器内运行**：在 Docker/Kubernetes 中运行 Kun 脚本时，Kun 检测到容器环境后避免创建嵌套 namespace，依赖容器的现有隔离。Kun 的能力系统为容器内的脚本提供更细粒度的权限控制
2. **Kun 管理容器**：Kun 可通过 CDF 为 `docker`、`kubectl` 等命令建立签名，以类型安全的方式管理容器生命周期
3. **分层防御**：容器提供粗粒度的环境隔离，Kun 在容器内部提供细粒度的命令级权限控制，形成纵深防御

详细的安全防御方案（包括供应链攻击防御）请参见 [供应链安全](supply-chain-security.md)。

## 能力类型目录

Kun 的能力系统定义了以下能力类型，每个类型对应一类系统资源访问：

### 文件系统能力

| 能力 | 参数 | 语义 | 示例 |
|------|------|------|------|
| `fs.read(path)` | 文件或目录路径 | 读取指定路径的内容和元数据 | `fs.read("/etc")` |
| `fs.write(path)` | 文件或目录路径 | 写入、创建或删除指定路径 | `fs.write("/tmp")` |
| `fs.meta` | （无参数） | 读取任意路径的元数据（stat），不读内容 | `fs.meta` |
| `fs.read(Any)` | 字面量 `Any` | 可读取任意文件系统路径 | `fs.read(Any)` |
| `fs.write(Any)` | 字面量 `Any` | 可写入任意文件系统路径 | `fs.write(Any)` |

路径参数规则：
- 精确路径：`fs.read("/etc/nginx/nginx.conf")` — 仅匹配该文件
- 目录前缀：`fs.read("/etc")` — 匹配 `/etc` 及其所有子路径
- 通配符：`fs.read(Any)` — 匹配所有路径，无限制

### 网络能力

| 能力 | 参数 | 语义 | 示例 |
|------|------|------|------|
| `net.http(host)` | 域名或 IP | HTTP 请求到指定主机 | `net.http("api.example.com")` |
| `net.https(host)` | 域名或 IP | HTTPS 请求到指定主机 | `net.https("api.example.com")` |
| `net.tcp(addr)` | IP:Port 或 `Any` | TCP 连接到指定地址 | `net.tcp("10.0.0.1:5432")` |
| `net.listen(port)` | 端口号 | 监听指定 TCP/UDP 端口 | `net.listen(8080)` |
| `net.http("*")` | 通配符 `*` | HTTP 请求到任意主机 | `net.http("*")` |
| `net.tcp(Any)` | 字面量 `Any` | TCP 连接到任意地址 | `net.tcp(Any)` |

### 进程能力

| 能力 | 参数 | 语义 | 示例 |
|------|------|------|------|
| `process.exec` | （无参数） | 执行子进程 | `process.exec` |
| `process.signal(pid)` | 进程 ID | 向指定进程发送信号 | `process.signal(pid)` |
| `process.kill` | （无参数） | 终止任意进程 | `process.kill` |
| `process.trace` | （无参数） | 跟踪/调试其他进程（ptrace） | `process.trace` |

### 环境能力

| 能力 | 参数 | 语义 | 示例 |
|------|------|------|------|
| `env.read(name)` | 环境变量名 | 读取指定环境变量 | `env.read("HOME")` |
| `env.write(name)` | 环境变量名 | 设置或修改环境变量 | `env.write("PATH")` |
| `env.read("*")` | 通配符 | 读取所有环境变量 | `env.read("*")` |

### 系统能力

| 能力 | 参数 | 语义 | 示例 |
|------|------|------|------|
| `sys.time` | （无参数） | 读取系统时间 | `sys.time` |
| `sys.random` | （无参数） | 访问随机数设备 | `sys.random` |
| `sys.hostname` | （无参数） | 读取或设置主机名 | `sys.hostname` |
| `sys.syslog` | （无参数） | 写入系统日志 | `sys.syslog` |

### 能力组合规则

```
// 多个能力在 capability 行中用逗号分隔
capability fs.read("/etc"), net.http("api.example.com"), env.read("HOME")

// 通配符可以与其他精确声明共存
capability fs.read("/var/log"), fs.read(Any)
// → 通配符 fs.read(Any) 包含 /var/log，但根据最小权限原则应移除冗余项
```

## 运行时能力检查架构

### 能力管理器（Capability Manager）

能力管理器是安全子系统的核心组件，在运行时维护当前执行上下文的有效能力集合：

```
CapabilityManager
├── current_scope: CapabilitySet     // 当前作用域的有效能力
├── script_level: CapabilitySet      // 脚本级能力（启动时解析声明获得）
├── scope_stack: [CapabilitySet]     // 作用域栈（嵌套 with capability 形成）
├── command_map: {CmdName -> CapSet} // 单命令能力注解映射
└── audit_log: [AccessAttempt]       // 访问审计日志
```

### 检查流程

```
命令/函数请求访问资源 R
        │
        ▼
CapabilityManager.lookup(R)
        │
        ├── R 匹配 current_scope 中某项？──是──→ 允许访问，记录审计
        │
        └── 否
            │
            ├── 交互模式且用户在线？──是──→ 弹出确认对话框
            │                               │
            │                               ├── 用户确认 → 动态授予 → 允许
            │                               │
            │                               └── 用户拒绝 → PermissionError
            │
            └── 非交互模式？
                            │
                            └──→ PermissionError (含修改建议)
```

### 能力匹配算法

能力的匹配基于参数的结构等价：

```
fs.read("/etc/nginx/nginx.conf") 匹配 fs.read("/etc/nginx/nginx.conf")  → 精确路径匹配
fs.read("/etc/nginx/nginx.conf") 匹配 fs.read("/etc")                   → 前缀匹配（/etc 是父目录）
fs.read("/etc/nginx/nginx.conf") 匹配 fs.read(Any)                      → 通配符匹配
fs.read("/etc")                 匹配 fs.read("/var")                    → 不匹配
net.http("api.example.com")     匹配 net.http("*")                      → 通配符匹配
net.http("a.com")               匹配 net.http("b.com")                 → 不匹配
```

匹配优先级：精确匹配 > 前缀匹配 > 通配符匹配

### 审计日志

所有能力检查和访问尝试记录到审计日志：

```
{
  timestamp: 1717084800,            // Unix 纳秒
  script: "/home/user/deploy.kun",  // 脚本路径
  line: 42,                         // 源码行号
  resource: "/etc/shadow",          // 目标资源
  capability: "fs.read",            // 所需能力
  result: "denied",                 // allow / denied / granted_dynamic
  reason: "not_in_scope"            // 拒绝原因
}
```

审计日志持久化到 `~/.kun/audit/` 目录，周期性轮转。

## 动态授予流程

当脚本尝试访问未声明的资源且运行时处于交互模式时，能力管理器弹出确认对话框：

```
┌─────────────────────────────────────────────────┐
│  ⚠ 脚本请求额外权限                             │
│                                                 │
│  脚本: /home/user/deploy.kun:42                 │
│  资源: /etc/nginx/nginx.conf                    │
│  能力: fs.read("/etc/nginx/nginx.conf")        │
│  描述: 读取 Nginx 配置文件                      │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │ 本次允许          │  始终允许           │   │
│  ├─────────────────────────────────────────┤   │
│  │ 始终拒绝（路径）   │  本次拒绝           │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  提示：选择"始终允许"会将权限声明添加到         │
│  ~/.kun/granted-capabilities.toml               │
└─────────────────────────────────────────────────┘
```

用户选择被记录到持久化存储：

```
// ~/.kun/granted-capabilities.toml
[scripts."/home/user/deploy.kun"]
"fs.read(\"/etc/nginx/nginx.conf\")" = { granted = "2026-05-31", count = 15 }

[global]
"net.http(\"internal-api.corp.com\")" = { granted = "2026-05-30", count = 3 }
```

动态授予的权限在以下情况失效：
- 脚本路径变化（内容或位置变更）
- 权限声明在脚本中被显式添加后，自动撤销动态授予的记录
- 用户手动编辑 grants 文件撤销
- 超过 90 天未使用的动态权限自动过期

## 父-子脚本能力传递

### 传递机制

父脚本通过显式的 `with capabilities` 语法将能力传递给子脚本：

```
// 父脚本：deploy.kun
capability fs.read("/etc"), net.http("api.example.com")

// 调用子脚本，显式传递能力的子集
kun "child.kun" with capabilities fs.read("/etc")
```

子脚本接收到的能力集合是父脚本显式传递的子集，且不能突破父脚本自身拥有的能力：

```
// 父脚本拥有 fs.read("/etc") 和 net.http("api.example.com")
// 子脚本只能获得父脚本传递的 fs.read("/etc")，不能获得 net.http("api.example.com")
// 子脚本也不能要求超出父脚本拥有的能力
```

### 传递规则

| 场景 | 子脚本获得的能力 | 说明 |
|------|----------------|------|
| 父脚本使用 `kun sub.kun`（无注解） | 子脚本只能使用默认权限（工作目录） | 无能力传递 |
| 父脚本使用 `kun sub.kun with capabilities fs.read("/etc")` | 子脚本获得 `fs.read("/etc")` | 显式传递子集 |
| 父脚本使用 `kun sub.kun with capabilities fs.read(Any)` | 子脚本获得 `fs.read(Any)` | 可传递通配符 |
| 子脚本自身声明了 `capability fs.read("/var")` | 子脚本的实际能力 = 父传递 ∩ 子声明 | 交集合运算 |

### 能力交集合运算

子脚本的实际可用能力 = 父脚本传递的能力 ∩ 子脚本自身声明的能力：

```
// 父脚本传递: fs.read("/etc"), net.http("api.example.com")
// 子脚本声明: capability fs.read("/etc"), fs.read("/var")
// 实际可用: fs.read("/etc")
// net.http("api.example.com") 虽然由父脚本传递，但子脚本未声明 → 不可用
```

## 威胁模型分析

### 攻击面总览

```
┌─────────────────────────────────────────────────────────────┐
│                     Kun 运行时攻击面                         │
├─────────────────────────────────────────────────────────────┤
│  脚本层            │ 命令层              │ 系统层            │
├─────────────────────────────────────────────────────────────┤
│  代码注入          │ 恶意 CDF            │ 运行时二进制篡改  │
│  路径遍历          │ 命令替换            │ 共享库注入        │
│  不安全的解构      │ 管道劫持            │ 内核漏洞          │
│  信息泄露          │ 参数注入            │ 容器逃逸          │
└─────────────────────────────────────────────────────────────┘
```

### 威胁与防御矩阵

| 威胁 | 攻击向量 | 影响 | 防御机制 | 严重程度 |
|------|---------|------|---------|---------|
| 脚本代码注入 | 通过 `f"..."` 插值或命令参数注入恶意代码 | 任意代码执行 | 类型安全 + 严格求值 + 无 `eval` | 高 |
| 路径遍历 | 通过 `Path` 参数访问未授权目录（如 `../../etc/shadow`） | 未授权文件访问 | `Path` 类型在运行时规范化并检查是否越界 | 高 |
| CDF 伪装 | 篡改 CDF 使命令声明更少的权限（降低安全基线） | 命令可访问未声明资源 | CDF 密码学签名（Ed25519）+ 信任链验证 | 高 |
| 命令替换 | 将 PATH 中的命令替换为恶意版本 | 任意代码执行 | 二进制完整性校验 SHA-256 | 高 |
| 管道劫持 | 截取或篡改管道中传递的结构化数据 | 数据泄露或篡改 | 管道类型约束 + 不可变性 | 中 |
| 参数注入 | 通过特制参数使命令执行意外的操作 | 命令行为偏离预期 | CDF 参数验证器（range/regex/enum） | 中 |
| 信息泄露（时间） | 通过时序攻击推断文件存在性 | 文件存在性泄露 | 统一的错误响应时间（未来优化） | 低 |
| 拒绝服务（死循环） | 恶意构造的无限 Stream | 资源耗尽 | Stream 加 `take` 限制 + 超时机制 | 中 |
| 权限提升 | 利用能力传递中的逻辑漏洞获取超出应有权限 | 越权访问 | 能力交集合运算 + 编译期权限验证 | 高 |
| 运行时二进制篡改 | 替换 Kun 解释器二进制文件 | 完全控制 | 运行时自身签名校验 + 包管理器完整性检查 | 高 |

### 纵深防御层次

```
第 1 层：类型系统（编译期）
  ├── 类型安全：无空指针、无类型混淆
  ├── IO 边界：纯函数无副作用
  └── 权限静态验证：能力引用在编译期检查

第 2 层：能力安全（运行时）
  ├── 最小权限：默认仅工作目录
  ├── 能力不可伪造/不可转移
  └── 权限作用域嵌套

第 3 层：CDF 契约（加载时）
  ├── 密码学签名验证
  ├── 二进制完整性校验
  └── 行为契约生成 seccomp 规则

第 4 层：沙箱隔离（执行时）
  ├── Namespace 隔离（Mount/PID/Network）
  ├── seccomp-BPF 系统调用过滤
  ├── 单命令沙箱（高风险命令）
  └── 容器环境检测
```

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 0.1.0 | 2026-05-27 | 初始设计：最小权限原则、权限作用域、能力安全、异常报告 |
| 0.1.0 | 2026-05-31 | 深化：能力类型目录、运行时检查架构、动态授予流程、父-子能力传递、威胁模型分析 |
