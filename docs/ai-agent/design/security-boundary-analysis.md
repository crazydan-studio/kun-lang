# 安全边界分析：R1/R2/R4/R5

## R1：沙箱对子进程的 fs.read 约束有限

### 问题描述

当前沙箱模型使用 mount namespace + seccomp 约束子进程文件访问。但 mount namespace 存在根本矛盾：**要运行外部命令，必须暴露系统库路径（`/usr`、`/lib`），而暴露它们的同时也暴露了敏感文件（`/etc/shadow`、`/home` 等）。**

### 攻击路径

```kun
with caps
  process.exec = ["cat"]    // 允许执行 cat
  -- 未声明 fs.read

main =
  cat p"/etc/shadow"        // capability_check 在 Kun 层拦截 → 拒绝
```

但如果 `cat` 是作为外部命令通过 mount namespace 执行的：

```
capability_check 通过（process.exec 已声明）→ 创建 mount namespace
  → bind-mount /usr/bin/cat + /lib/x86_64-linux-gnu/libc.so.6 + ...
  → /etc/shadow 在 mount namespace 中可见（同属根文件系统）
  → cat 子进程可读取 /etc/shadow
  → fs.read 被绕过
```

### 现有缓解

| 防线 | 能力 | 限制 |
|------|------|------|
| `capability_check` | 拦截 Kun 原语的 IO | 不拦截子进程内部行为 |
| mount namespace | 限制文件系统可见性 | 动态链接命令暴露系统库路径 |
| seccomp | 限制系统调用 | **无法按路径过滤**（seccomp 只检查 syscall 编号和寄存器值，不解引用路径字符串指针） |

### 解决方案：Landlock LSM（Linux 5.13+）

Landlock 提供**路径级别的访问控制**，无需 mount namespace：

```c
// 伪代码：在 spawn 子进程前
struct landlock_ruleset_attr attr = { 0 };
int ruleset_fd = landlock_create_ruleset(&attr, sizeof(attr), 0);

// 允许读取 /usr/bin/cat
landlock_add_rule(ruleset_fd, LANDLOCK_RULE_PATH_BENEATH,
    &(struct landlock_path_beneath_attr){
        .allowed_access = LANDLOCK_ACCESS_FS_READ_DIR |
                          LANDLOCK_ACCESS_FS_READ_FILE,
        .parent_fd = open("/usr/bin/cat", O_PATH),
    }, 0);

// 允许读取脚本声明的能力目标
for each target in current_scope.fs.read:
    landlock_add_rule(ruleset_fd, LANDLOCK_RULE_PATH_BENEATH,
        &(struct landlock_path_beneath_attr){
            .allowed_access = LANDLOCK_ACCESS_FS_READ_DIR |
                              LANDLOCK_ACCESS_FS_READ_FILE,
            .parent_fd = open(target, O_PATH),
        }, 0);

landlock_restrict_self(ruleset_fd, 0);
```

**效果**：子进程 `cat` 只能读取 `/usr/bin/cat`（及其依赖库）和脚本声明的 `fs.read` 目标，无法读取 `/etc/shadow`。

### 回退方案（内核 < 5.13）

| 内核版本 | 可用方案 | 限制 |
|---------|---------|------|
| 5.13+ | Landlock LSM | 路径级控制，推荐方案 |
| 5.6+ | `openat2()` + `RESOLVE_BENEATH` | 仅限运行时自身 IO，不影响子进程 |
| 3.8+ | user namespace + mount namespace | 目录粒度，无法隔离系统库路径 |
| < 3.8 | **不支持** | 无沙箱能力 |

### 决策建议

将 Landlock 作为首选的子进程文件隔离方案，mount namespace 作为内核 < 5.13 时的回退。文档中已记录容器的已知限制。

---

## R2：Symlink TOCTOU 竞态

### 问题描述

能力检查基于路径字符串，但文件系统在检查和实际 IO 之间可能变化：

```
时间 t0: capability_check("fs", "read", p"/tmp/data")
         → current_scope 包含 p"/tmp/data"
         → 通过

时间 t0+ε: 攻击者将 /tmp/data 替换为指向 /etc/shadow 的符号链接

时间 t0+2ε: openat(p"/tmp/data")
            → OS 跟随符号链接
            → 实际打开 /etc/shadow
            → fs.read 绕过
```

### 现有缓解的不足

| 缓解 | 是否有效 |
|------|---------|
| `Path` 类型运行时规范化（解析 `..` 和 `.`） | ❌ 不解析符号链接 |
| 目录级权限声明（`p"/tmp/"`） | ❌ 符号链接可重定向目录内任意文件 |
| `O_NOFOLLOW` | ⚠️ 仅防止最终组件是符号链接，不防止路径中段 |

### 解决方案：`openat2()` + `RESOLVE_NO_SYMLINKS` + `RESOLVE_BENEATH`（内核 5.6+）

```c
// 内核 5.6+ openat2() 系统调用
struct open_how how = {
    .flags = O_RDONLY,
    .resolve = RESOLVE_NO_SYMLINKS | RESOLVE_BENEATH,
};
int fd = openat2(AT_FDCWD, path, &how, sizeof(how));
```

| 标志 | 效果 |
|------|------|
| `RESOLVE_NO_SYMLINKS` | 路径中任何位置出现符号链接 → `ELOOP` |
| `RESOLVE_BENEATH` | 路径不能超出父目录范围（chroot 风格） |

**效果**：即使攻击者在检查和打开之间替换了符号链接，`openat2()` 也会拒绝跟随，返回 `ELOOP`。`capability_check` 已在事前拒绝了对 `/etc/shadow` 的访问。

### 回退方案（内核 < 5.6）

```c
// 手动检查：先打开路径，再 fstat 确认
int fd = open(path, O_RDONLY | O_NOFOLLOW);
if (fd < 0) return error;
struct stat st;
fstat(fd, &st);
if (st.st_mode & S_IFLNK) { close(fd); return error; }
// 确认 fd 在声明的目标范围内
```

但这种方式在路径中间段出现符号链接时无效——`open` 在路径中段跟随，只在最终段拒绝。`openat2()` 是唯一能完全防御的机制。

### 决策建议

运行时 IO 原语（`readFile`、`writeFile` 等）在支持 `openat2()` 的内核上使用 `RESOLVE_NO_SYMLINKS` + `RESOLVE_BENEATH`。内核 < 5.6 时回退到 `O_NOFOLLOW` + `fstat` 检查（有限防护）。子进程的符号链接问题不在能力系统范围内——由沙箱的文件系统隔离处理。

---

## R4：环境变量泄漏到子进程

### 问题描述

通过 `process.exec` 启动的子进程继承父进程的完整环境变量。即使脚本只声明了 `env.read = ["HOME"]`，子进程也能访问所有环境变量，包括密钥：

```kun
with caps
  env.read = ["HOME"]            // 脚本仅声明读取 HOME
  process.exec = ["env"]         // 脚本允许执行 env 命令

main =
  exec "env" []                  // 子进程继承完整环境变量
  // AWS_SECRET_ACCESS_KEY、DB_PASSWORD 等全部暴露给子进程
```

### 攻击路径

1. 脚本声明 `env.read = ["HOME"]`（仅需 HOME）
2. 脚本调用外部命令（如 `curl`）通过 `process.exec`
3. 子进程继承完整环境——包括 `AWS_SECRET_ACCESS_KEY`、`DB_PASSWORD`、`API_TOKEN`
4. 恶意子进程可将环境变量通过 HTTP 请求外泄

### 解决方案：exec 前环境变量过滤

在启动子进程前，运行时自动过滤环境变量：

```c
// 伪代码：exec 前执行
char** filtered_env = build_filtered_env(
    current_env(),              // 当前进程完整环境
    current_scope.env.read,     // 脚本声明的 env.read 目标
    STRIP_ALWAYS                // 始终剔除的敏感变量
);
execve(path, argv, filtered_env);
```

**过滤规则**：

| 类别 | 规则 |
|------|------|
| 脚本声明的 `env.read` | 保留（如 `env.read = ["HOME"]` → 仅保留 `HOME`） |
| `env.read = []`（通配） | 保留所有（脚本承担全部责任） |
| 始终剔除 | `LD_PRELOAD`、`LD_LIBRARY_PATH`、`BASH_ENV`、`IFS`、`SHELL`、`LC_ALL`（不受 `env.read` 影响） |

**效果**：`env.read = ["HOME"]` 时，子进程环境中只有 `HOME`，`AWS_SECRET_ACCESS_KEY` 等密钥不会泄漏。

### 特权变量列表

始终剔除的变量（无论 `env.read` 如何声明）：

```c
const char* STRIP_ALWAYS[] = {
    "LD_PRELOAD",           // 共享库注入
    "LD_LIBRARY_PATH",      // 库搜索路径劫持
    "LD_AUDIT",            // 动态链接审计注入
    "LD_DEBUG",            // 链接调试信息（可能泄漏内存地址）
    "BASH_ENV",            // bash 自动加载文件（如果子进程是 shell）
    "IFS",                 // shell 字段分隔符劫持
    "SHELL",               // 子 shell 选择
    "LC_ALL",              // 区域设置（影响子进程行为）
    "GIO_EXTRA_MODULES",   // glib 模块注入
    "PYTHONPATH",          // Python 模块注入
    "PERL5LIB",            // Perl 模块注入
};
```

### 完整过滤链

```
exec 调用
  → 1. 复制当前环境变量
  → 2. 剔除 STRIP_ALWAYS 列表中的变量
  → 3. 若 env.read 非通配，仅保留声明的变量名
  → 4. 执行 execve
```

### 决策建议

exec 前环境变量过滤作为运行时标准行为，无需额外能力声明。始终剔除列表为硬编码安全基线。

---

## R5：开放文件描述继承到子进程

### 问题描述

脚本打开文件后通过 `process.exec` 启动子进程时，子进程继承所有未设 `CLOEXEC` 的文件描述符。子进程可绕过 `fs.read` 能力检查读取已打开文件的内容。

```kun
with caps
  fs.read = [p"/tmp/data"]
  process.exec = ["cat"]

main =
  content <- readFile p"/tmp/data"   // 通过 fs.read 检查
  // readFile 内部：打开 fd，读取内容，关闭 fd
  // 但如果 fd 未设 CLOEXEC，子进程 cat 仍可访问该 fd
  exec "cat" ["/proc/self/fd/3"]
```

### 解决方案：CLOEXEC 默认策略

**所有运行时管理的文件描述符在创建时设置 `CLOEXEC`**（`O_CLOEXEC` 标志）：

```c
// 所有 open 操作使用 O_CLOEXEC
int fd = open(path, O_RDONLY | O_CLOEXEC);
// 所有接收的 fd 设 CLOEXEC
fcntl(fd, F_SETFD, FD_CLOEXEC);
```

**例外**：`stdin(0)`、`stdout(1)`、`stderr(2)` 不设 CLOEXEC——子进程需要继承标准流。

### 决策建议

CLOEXEC 规则在 `system-baseline.md` 的运行时架构中已隐含（Arena 分配自动回收），但应显式文档化所有 IO 原语创建 fd 时使用 `O_CLOEXEC`。
