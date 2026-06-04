# 讨论记录：设计审计第二轮——修复项确认与遗留问题

## 背景

第一轮审计发现 34 项问题，其中 9 项已修复。第二轮审计重新评估修复效果，发现新增的遗留问题。

## 共识结论

### 已关闭（无需进一步操作）

| # | 问题 | 理由 |
|---|------|------|
| 1 | DNS 侧信道 | 按设计决策关闭，不纳入能力控制 |
| 2 | 进程替换 `<(cmd)` | Bash 特异模式，Kun 使用函数组合的编程模型不同 |
| 3 | 后台任务 `&`/`wait` | 已知缺失，延迟到 Task 模块（post-MVP） |
| 4 | `Fd` 类型 | 抽象层级差异，MVP 可接受；流式进程管道需要时加入路线图 |
| 5 | 惰性求值矛盾 C1 | ✅ 已修复 |
| 6 | `FileStat` 类型 G1 | ✅ 已修复（待修复 owner/mode 字段） |
| 7 | `Signal.on` 信号接收 G2 | ✅ 已修复（待补充信号投递机制文档） |
| 8 | `net.unix` G3 | ✅ 已修复 |
| 9 | `process.exec` 路径解析 G4 | ✅ 已修复 |
| 10 | `[]` 通配风险 D1 | ✅ 已修复 |
| 11 | `process.trace` 限制 D2 | ✅ 已修复 |
| 12 | `chdir` 定义 D3 | ✅ 已修复 |
| 13 | 沙箱目录粒度局限 D4 | ✅ 已修复 |
| 14 | 目录路径 `/` 结尾 | ✅ 已修复 |

### 需修复（第二轮审计发现）

| # | 严重度 | 类型 | 问题 | 文件 | 修复方案 |
|---|--------|------|------|------|---------|
| R1 | 高 | VULN | 沙箱对子进程的 fs.read 约束有限（动态链接命令需暴露系统库路径） | `roles-and-permissions.md` | 文档化三层防御：capability_check → Landlock（路径级）→ mount namespace（最小化）；注明 Linux 5.13+ Landlock 依赖 |
| R2 | 高 | VULN | Symlink TOCTOU —— 路径检查与使用之间存在竞态 | `roles-and-permissions.md` | 运行时 `fs.read`/`fs.write` 使用 `openat2()` 配合 `RESOLVE_NO_SYMLINKS` + `RESOLVE_BENEATH`（内核 5.6+） |
| R3 | 高 | GAP | 命令退出码处理——`grep`/`diff`/`test`/`cmp` 的非零退出码被错误映射为 `Err` | `command-signature-system.md` | 返回类型改为 `CmdResult t = { stdout : t, exitCode : ExitCode }`，非零退出码不为 `Err` |
| R4 | — | CLOSED | 环境变量过滤已改为通用子进程安全机制，不绑定 `process.exec` | `roles-and-permissions.md` | 改为"CDF 命令函数执行子进程前"通用过滤 |
| R5 | 中 | VULN | 开放 fd 继承到子进程——文件描述符在 exec 后泄漏 | `system-baseline.md` | 所有运行时管理的 fd 创建时设 `CLOEXEC` |
| R6 | — | CLOSED | `exec` 原语→不新增 `Exec` 模块。`process.exec` 完全移除，CDF 即授权 | — | 不新增 |
| R7 | 低 | DEFECT | `FileStat.owner` 使用 `UserName` 而非 `Uid`——孤儿 UID 导致 stat 失败 | `standard-library.md` | `owner : Uid` 为主字段，`ownerName : String` 为便利字段 |
| R8 | 低 | DEFECT | `FileStat.mode` 使用 `Int` 而非 `FileMode`——八进制/十进制混淆 | `standard-library.md` | 新增 `FileMode` newtype |
| R9 | 低 | DEFECT | 能力交集运算中 `[]`（通配）语义未定义 | `roles-and-permissions.md` | 明确规则：子声明 `[]` 继承父的限制，不能超出 |
| R10 | 低 | DEFECT | 容器模式（Docker/K8s）时沙箱完全禁用 | `roles-and-permissions.md` | 文档化已知限制 |
| R11 | 低 | DEFECT | `Signal.on` 信号处理器的投递机制未说明 | `standard-library.md` | 文档化使用 signalfd/self-pipe 延迟投递，不在信号上下文中执行 IO |
| R12 | 低 | DEFECT | 能力管理器线程不安全 | `roles-and-permissions.md` | 文档化"当前单线程，多线程支持 post-MVP" |

## 后续行动

按用户指示决定是否实施上述 12 项修复。
