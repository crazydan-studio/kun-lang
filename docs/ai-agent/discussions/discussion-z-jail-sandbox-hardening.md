# Z-Jail 沙箱加固参考分析

> **日期**：2026-07-16
> **状态**：已定稿（部分采纳）
> **参考**：[Z-Jail](https://github.com/Division-36/Z-Jail/) — 零依赖轻量级 Linux 沙箱（~73 KiB，7 层防御，C99）
> **相关文档**：[系统基线 - 安全隔离](../architecture/system-baseline.md#安全隔离)、[`kun` CLI 工具 - 安全控制](../design/kun-cli-tool.md#安全控制)

## 背景

评估是否可参考 [Z-Jail](https://github.com/Division-36/Z-Jail/) 实现轻量级沙盒，以及对 Kun 现有沙箱设计需要做哪些改动。

Z-Jail 是一个面向 CTF/CI 评测场景的轻量级 Linux 沙箱，特点是零外部依赖、~73 KiB 二进制、7 层独立防御。Kun 已有基于 Landlock + mount namespace + seccomp-BPF 的沙箱设计，需评估 Z-Jail 的思路能否补强 Kun 的防御完整性。

## Z-Jail vs Kun 现有沙箱对比

| 维度 | Z-Jail | Kun 现有设计 |
|---|---|---|
| **隔离对象** | 外部目标二进制（`execve` 替换） | 解释器自身进程 + fork 出的 `Cmd` 子进程 |
| **隔离时机** | 单次：`clone` → 子进程内逐层安装 → `execve` 目标 | 父进程初始化一次（Landlock/ns）+ 每次 fork 子进程（seccomp+rlimit） |
| **namespace** | 5 个全开：mount/pid/net/ipc/uts | mount + net（Landlock 不可用时）；未用 pid/ipc/uts |
| **文件系统** | `pivot_root` + 懒卸载旧根（强制隔离） | `pivot_root` 仅在 ns 兜底模式；Landlock 模式靠路径规则（不换根） |
| **seccomp 策略** | **白名单**（仅 15 个 syscall，极严） | **黑名单**（禁危险类，允许 openat/read/write 等） |
| **capabilities** | 显式 `capset` 全清 + securebits 锁定 | 仅 `PR_SET_NO_NEW_PRIVS`，未显式 drop capabilities |
| **fd 清理** | 关闭所有 fd≥3（仅留 report pipe） | 未提及 fd 清理（潜在逃逸面） |
| **资源限制** | `setrlimit`（CPU/AS/NOFILE/NPROC） | `rlimit`（CPU/mem） |
| **审计** | JSON 审计 + BLAKE2b 二进制指纹 | `--no-sandbox`/`--force` 日志记录（较简） |
| **Landlock** | 未使用（靠 ns+pivot_root 全隔离） | 主力机制（内核 5.13+），ns 兜底 |

## 可借鉴点（已采纳）

### 1. 显式 capabilities drop + securebits 锁定（P0，已采纳）

Kun 现有设计只有 `PR_SET_NO_NEW_PRIVS`，**没有显式 `capset` 清零所有 capabilities**。`NO_NEW_PRIVS` 仅阻止**获取新特权**，但不撤销**当前已持有的 capabilities**——若解释器以 root 或带 capability 启动，已持有的能力仍可用。

Z-Jail 的做法更严密：`capset(hdr, data={0,0,0})` 清零所有 capability 集（effective/permitted/inheritable），并锁定 securebits（`SECBIT_KEEP_CAPS_LOCKED | SECBIT_NO_SETUID_FIXUP_LOCKED | SECBIT_NOROOT_LOCKED | SECBIT_NO_CAP_AMBIENT_RAISE_LOCKED`），防止任何能力复活。

**与 `Cmd.withRunAs` 的协调**：`Cmd.withRunAs` 需 `CAP_SETUID`/`CAP_SETGID` 执行 `setgid`/`setuid`。若父进程层无条件全清 capability，子进程 fork 继承零 capability 后 withRunAs 将 EPERM。故采用**条件保留**策略：

- **脚本未使用 `Cmd.withRunAs`**（默认）：`capset(hdr, data={0,0,0})` 全清，并锁定 securebits（`SECBIT_KEEP_CAPS_LOCKED | SECBIT_NO_SETUID_FIXUP_LOCKED | SECBIT_NOROOT_LOCKED | SECBIT_NO_CAP_AMBIENT_RAISE_LOCKED`），不可逆——与 Z-Jail 完全一致
- **脚本使用了 `Cmd.withRunAs`**：`capset` 清零除 `CAP_SETUID`/`CAP_SETGID` 外的所有 capability（保留这两个于 inheritable 集），securebits 仅锁定非 KEEP_CAPS 项（`SECBIT_NO_SETUID_FIXUP_LOCKED | SECBIT_NOROOT_LOCKED | SECBIT_NO_CAP_AMBIENT_RAISE_LOCKED`），KEEP_CAPS 不锁定以便子进程在 withRunAs 期间仍可操作 capability；子进程在 withRunAs 完成（initgroups → setgid → setuid）后，再执行 `capset` 全清 + `SECBIT_KEEP_CAPS_LOCKED`，最终达到无 cap 状态

注：securebits 必须使用 `_LOCKED` 变体才能不可逆地锁定（非 `_LOCKED` 变体仅 SET 但可被后续 `prctl` 重置，与"防止任何能力复活"的语义不符）。

**落盘**：`system-baseline.md` 父进程层，`NO_NEW_PRIVS` 之后增加显式 `capset` 全清 + securebits 锁定（按 withRunAs 使用与否分支）；子进程 withRunAs 完成后追加 `capset` 全清；Command 执行契约同步更新。

### 2. fd 清理（fd scrub）（P0，已采纳）

Kun 设计**未提及 fd 清理**。解释器进程可能持有特权 fd（Landlock 规则文件、审计日志、内部 pipe），fork 出的子进程默认继承全部 fd——子进程可通过 `/proc/self/fd/<N>` 访问这些 fd 绕过沙箱。

Z-Jail 在 setrlimit 后立即关闭所有 fd≥3（仅留 report pipe）。

**落盘**：`system-baseline.md` 子进程 fork 后、exec 前增加 fd 清理步骤（关闭 fd≥3，保留 stdin/stdout/stderr 及 `Cmd.withStdin` 指定 fd）；Command 执行契约同步更新。

### 3. `PR_SET_DUMPABLE=0`（P1，已采纳）

Z-Jail 在 fd 清理后设置 `PR_SET_DUMPABLE=0`，禁用 core dump 并锁定 `/proc/self/mem`。core dump 可能泄露内存中的敏感数据，`/proc/self/mem` 可被用于绕过某些保护。Kun 现有设计未提及此项。

**落盘**：`system-baseline.md` 父进程层 `NO_NEW_PRIVS` 之后增加 `PR_SET_DUMPABLE=0`。

### 4. IPC namespace（P1，已采纳）

Z-Jail 创建 5 个 namespace，Kun 现有仅用 mount+net。IPC namespace 隔离 SysV 共享内存/信号量/消息队列，防止通过 IPC 机制逃逸或干扰其他进程。UTS namespace（隔离 hostname）对脚本场景价值低，未采纳。

**落盘**：`system-baseline.md` ns 兜底模式增加 `CLONE_NEWIPC`（与 `CLONE_NEWNET` 同时创建）。

### 5. JSON 审计 + 内容指纹（P2，已采纳）

Z-Jail 每次执行产出结构化 JSON 审计记录（含时间戳、退出码、沙箱配置、BLAKE2b 指纹）。Kun 现有设计仅记录 `--no-sandbox`/`--force` 的使用日志。

**落盘**：`kun-cli-tool.md` 安全参数新增 `--audit=<path>` 选项，输出 JSON 审计记录（脚本路径、安全参数、沙箱配置、退出码、脚本内容 SHA-256 哈希、时间戳），用于 CI/合规场景追溯。

## 不采纳的部分（关键差异）

### 1. seccomp 白名单策略——不适用

Z-Jail 用 15-syscall 白名单是因为它隔离的是"做完就退出"的静态二进制（CTF 评测）。Kun 是脚本语言运行时，需要 `mmap`（动态内存/GC）、`futex`（线程同步）、`epoll`/`poll`（I/O 多路复用）、`clone`（fork 子进程）、`wait4`（回收子进程）、`pipe2`（Cmd 管道）、`stat`/`fstat`/`lstat`（File.exists 等）、`getrandom`（Random）、`clock_gettime`（DateTime）等数十个 syscall。

**若采用 15-syscall 白名单，Kun 解释器自身无法运行。** Kun 的 seccomp 必须保持**黑名单**策略（禁危险类，允许功能所需 syscall），这正是现有设计的正确选择。

### 2. `pivot_root` 强制换根——不适用

Z-Jail 总是 `pivot_root` 到 `--root` 目录，完全脱离宿主文件系统。Kun 的主力是 **Landlock 路径级控制**（`--allow-path /tmp:rw`），需要保留对真实文件系统的细粒度访问——若强制 `pivot_root`，`--allow-path` 的路径语义会失效（新根下没有 `/tmp`）。

**现有设计已正确**：Landlock 模式不换根（靠路径规则），ns 兜底模式才 `pivot_root`。Z-Jail 的换根思路已在 Kun 的 ns 兜底模式中体现。

### 3. Truthimatics 判定引擎——不适用

Z-Jail 的"证据判定引擎"用于评估外部二进制是否可信，是 CTF 评测场景特有需求。Kun 不执行外部二进制（FFI 除外，已由 `--allow-ffi` 控制），无需此机制。

## 落盘清单

| 文件 | 变更 |
|---|---|
| `docs/ai-agent/architecture/system-baseline.md` | 父进程层新增 `PR_SET_DUMPABLE=0`、capabilities 显式清零 + securebits 锁定（按 `Cmd.withRunAs` 使用与否分支，保留 `CAP_SETUID`/`CAP_SETGID`）、ns 兜底新增 `CLONE_NEWIPC`；子进程层新增 fd 清理；Command 执行契约同步更新 fd 清理步骤与 withRunAs 后 `capset` 全清；新增 Z-Jail 参考说明；版本历史 |
| `docs/ai-agent/design/kun-cli-tool.md` | 安全参数新增 `--audit=<path>` JSON 审计记录选项（含字段说明与示例）；版本历史 |
| `docs/ai-agent/discussions/discussion-z-jail-sandbox-hardening.md` | 新建本讨论记录 |
| `docs/ai-agent/discussions/index.md` | 新增本讨论记录的索引行 |

## 参考链接

- Z-Jail 仓库：https://github.com/Division-36/Z-Jail/
- Z-Jail README（分层防御架构、7 层说明、性能基准）
