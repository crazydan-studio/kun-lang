# 能力映射指南

## 定位

本指南定义了 Kun 将 Linux 命令能力抽象为类型安全函数的方法论。核心原则：

> **映射能力（Capability），而非形式（Form）。**

`ls -la --sort=time /tmp` 的形式背后，能力是"列出目录内容（含隐藏、按时间排序）"。命令函数不关心用户是如何在 CLI 上敲这个命令的，只关心用户**想要什么**。

## 核心原则

### 原则 1：结果影响 —— 只映射影响"返回什么数据"的参数

| 映射 | 不映射 |
|------|--------|
| `ls -a`（是否包含隐藏文件 → 结果集变化） | `ls --color`（输出着色 → 显示样式） |
| `ps -e`（是否包含所有进程 → 结果集变化） | `ps -o`（自定义列 → 显示格式） |
| `git log -n 10`（限制返回条数 → 结果集变化） | `git log --oneline`（单行显示 → 显示格式） |

### 原则 2：格式无关 —— 结构化输出不存在"格式"参数

命令函数的返回类型是结构化类型（`Stream DirEntry`、`Result PodInfo` 等），用户通过 Record 字段访问数据，不存在 `-l`、`--json`、`-o` 等格式参数。

```kun
// CLI: ls -la          → 人类可读长格式
// CLI: ls --format=single-column → 单列输出
// CLI: ls --format=commas → 逗号分隔
// 能力: 列出目录内容。DirEntry 始终包含 name, type, size, mtime, mode 等字段
ls { path = p"/tmp", all = true }
// → Stream DirEntry   ← 始终结构化
```

运行时自动选择最佳 CLI 格式（通常是 `--json`、`-o json` 或 `-l` 中可解析性最高的）用于结构化解析。

### 原则 3：语义提升 —— 多个 CLI flags 合并为一个能力参数

```kun
// CLI: docker run --detach --restart=always --memory=512m nginx
//      中 --detach + --restart + --memory 本质是"运行容器的配置"
// 能力参数：{ mode: RunMode.Detached, restart: RestartPolicy.Always, memory: ?Memory }

// CLI: grep -r -i -l "error" /var/log
//      中 -r + -i + -l 是搜索模式的组合
// 能力参数：{ pattern: "error", path: p"/var/log", recursive: true, caseInsensitive: true }
```

### 原则 4：标准库替代 —— 如果能力等于标准库函数，不映射

| 命令 | 映射 | 替代方案 |
|------|------|---------|
| `sed`、`awk`、`sort`、`uniq`、`cut`、`tr` | ❌ | `String.replace`、`List.sort`、`Stream.filter` 等 |
| `cat`、`wc`、`tee` | ❌ | `readFile`、`Stream.length`、`writeFile` |
| `sudo`、`su` | ❌ | `runAs` 隐式参数 |
| `xargs` | ❌ | `Stream.toList` + `\|>` 管道 |
| `curl`、`wget` | ❌（作为 `.cmd.kun`） | `Http.get` / `Http.post`（标准库） |
| `gzip`、`xz`、`zstd` | ❌（作为 `.cmd.kun`） | 若标准库提供压缩 API 则不映射 |

### 原则 5：输出驱动 —— 先定义返回类型，再倒推最少参数

```
1. 用户想从 ps 获得什么？→ 进程列表（PID、名称、CPU、内存、状态）
2. 返回类型是什么？→ Stream ProcessInfo
3. 哪些参数影响结果？→ all（含所有用户）、user（指定用户）
4. 最少参数？→ 只有可选的 filter 参数
```

## 参数分类系统

每个能力参数属于以下三类之一：

| 分类 | `.cmd.kun` 处理 | 说明 | 示例 |
|------|---------|------|------|
| **核心** | `essential` | 结果的基本定位参数。通常为 path、target 等 | `ls` 的 `path`、`cp` 的 `src`/`dst`、`grep` 的 `pattern` |
| **筛选** | `filter` | 缩小或扩大结果集的参数 | `ls` 的 `all`/`recursive`、`ps` 的 `user`、`git log` 的 `maxCount`/`since` |
| **行为** | `behavior` | 改变操作执行方式的参数 | `cp` 的 `preserve`、`mkdir` 的 `parents`、`rm` 的 `force` |
| ~~显示~~ | — | 不映射 | `--color`、`--format`、`-o 自定义列`、`--oneline` |
| ~~内部~~ | — | 不映射 | `--verbose`（调试）、`--dry-run`（预览） |

不映射的参数由运行时自动选择合理的默认值。

## 能力映射表

### 文件操作

| 命令 | 能力 | 映射参数 | 不映射参数 |
|------|------|---------|-----------|
| `ls` | 列出目录内容 | `path`(essential)、`all`(filter)、`recursive`(filter)、`sortBy`(filter) | `--color`、`-l`、`-h`、`--format`、`--time-style`、`--quoting`、`-1`、`-C`、`-F`、`-d` |
| `cp` | 复制文件/目录 | `src`(essential)、`dst`(essential)、`recursive`(behavior)、`preserve`(behavior)、`force`(behavior) | `-v`、`-i`、`--backup`、`--sparse`、`--attributes-only`、`--reflink`、`-a` |
| `mv` | 移动/重命名 | `src`(essential)、`dst`(essential)、`force`(behavior) | `-v`、`-i`、`--backup`、`-u`、`-S` |
| `rm` | 删除文件/目录 | `target`(essential)、`recursive`(behavior)、`force`(behavior) | `-v`、`-i`、`--one-file-system`、`--no-preserve-root` |
| `mkdir` | 创建目录 | `path`(essential)、`parents`(behavior)、`mode`(behavior) | `-v`、`--context` |
| `chmod` | 修改权限 | `target`(essential)、`mode`(essential) | `-R`、`-v`、`--reference`、`-c` |
| `chown` | 修改所有者 | `target`(essential)、`owner`(essential)、`group`(essential)、`recursive`(behavior) | `-v`、`--reference`、`-c`、`--dereference` |
| `ln` | 创建链接 | `target`(essential)、`linkPath`(essential)、`symbolic`(behavior)、`force`(behavior) | `-v`、`-i`、`-T`、`-b` |
| `readlink` | 读取链接目标 | `path`(essential) | `-f`、`-e`、`-m`、`-n`、`-q` |
| `realpath` | 解析规范路径 | `path`(essential) | `-e`、`-m`、`-q`、`--relative-to` |

### 系统信息

| 命令 | 能力 | 映射参数 | 不映射参数 |
|------|------|---------|-----------|
| `ps` | 获取进程信息 | `all`(filter)、`user`(filter)、`pid`(filter) | `-o`、`-f`、`-l`、`--sort`、`--forest`、`-H`、`--no-headers`、`-w` |
| `free` | 获取内存信息 | 无（始终返回全量内存统计） | `-h`、`--si`、`-t`、`-l`、`-w`、`--wide` |
| `df` | 获取磁盘使用 | `path`(filter)、`type`(filter) | `-h`、`-T`、`--sync`、`-l`、`-x`、`-i`、`--no-sync` |
| `du` | 获取目录大小 | `path`(essential)、`maxDepth`(filter)、`apparentSize`(behavior) | `-h`、`--si`、`-c`、`-l`、`-s`、`-x`、`--exclude`、`--time` |
| `uname` | 获取系统信息 | 无（始终返回所有信息） | `-a`、`-s`、`-n`、`-r`、`-m`、`-p`、`-i`、`-o` |
| `uptime` | 获取运行时间 | 无 | `-p`、`-s`、`-V` |
| `lscpu` | 获取 CPU 信息 | 无 | `-e`、`-p`、`-b`、`-J`、`--all`、`--offline` |

### 内容操作

| 命令 | 能力 | 映射参数 | 不映射参数 |
|------|------|---------|-----------|
| `grep` | 搜索文本 | `pattern`(essential)、`path`(essential)、`recursive`(behavior)、`caseInsensitive`(behavior)、`invert`(behavior)、`maxCount`(filter) | `--color`、`-n`、`-l`、`-H`、`--line-number`、`-b`、`-o`、`-s`、`--binary-files` |
| `locate` | 搜索文件数据库 | `pattern`(essential) | `-i`、`-c`、`-l`、`-q`、`--regex`、`-b`、`-e`、`--existing` |

### 归档压缩（`.cmd.kun` 实现）

### 网络工具（`.cmd.kun` 实现）

### 版本控制（`.cmd.kun` 实现）

### 容器工具（`.cmd.kun` 实现）

| 命令 | 能力 | 映射参数 | 不映射参数 |
|------|------|---------|-----------|
| `docker.ps` | 列出容器 | `all`(filter)、`filter`(filter) | `-a`、`-l`、`-q`、`-s`、`-n`、`--format`、`--no-trunc`、`--size` |
| `docker.run` | 运行容器 | `image`(essential)、`command`(essential)、`detach`(behavior)、`restart`(behavior)、`memory`(behavior)、`env`(behavior)、`port`(behavior)、`volume`(behavior)、`network`(behavior) | `--rm`、`--name`、`-l`、`--label`、`--add-host`、`--dns`、`--entrypoint`、`-w`、`-u`、`--privileged`、`--cap-add`、`--security-opt`、`--log-driver`、`--log-opt` |
| `docker.pull` | 拉取镜像 | `image`(essential)、`platform`(filter) | `-a`、`--disable-content-trust`、`--quiet`、`-q` |
| `kubectl.get` | 获取 K8s 资源 | `resource`(essential)、`name`(filter)、`namespace`(filter)、`label`(filter) | `-o`、`-w`、`--all-namespaces`、`--field-selector`、`--sort-by`、`--show-labels`、`--no-headers`、`-l` |

## 从 CLI 到能力参数：转换过程

### 示例 1：`ls`

```
CLI 命令：ls -la --sort=time /var/log
                                    ↓
1. 能力识别："列出 /var/log 目录的文件/目录，含隐藏条目，按时间排序"
                                    ↓
2. 返回类型定义：
   type DirEntry = { name : Path, fileType : FileType, size : Int,
                     mtime : DateTime, mode : Permissions }
                                    ↓
3. 影响结果的参数：
   - path：目标目录（essential）
   - all：是否包含隐藏条目（filter）
   - recursive：是否递归子目录（filter）
   - sortBy：排序方式名/时间/大小（filter）
                                    ↓
4. `.cmd.kun` 实现（概念示例）：
   // 实际以纯 Kun 语法 + Builder API 定义
   // 参数映射关系不变：essential → 必填字段，filter → 可选字段
```

### 示例 2：`ps`

```
CLI 命令：ps aux --sort=-%mem
                                    ↓
1. 能力识别："获取所有进程信息，按内存使用降序排列"
                                    ↓
2. 返回类型定义：
   type ProcessInfo = { pid : Pid, name : String, user : String,
                        cpuPct : Float, memPct : Float, rss : Int,
                        state : ProcessState, command : String }
                                    ↓
3. 影响结果的参数：
   - all：含所有用户进程（filter）
   - user：限定特定用户的进程（filter）
   - pid：限定特定 PID（filter）
   排序不映射——返回后用户在 Kun 层排序
                                    ↓
4. `.cmd.kun` 实现：
   command Ps for "ps" export (ProcessInfo, ps)

   type ProcessInfo = { ... }

   ps : { all : Bool, user : ?Uid, pid : ?Pid } -> Command Stream ProcessInfo
   ps = \{ all, user, pid } ->
     asStream parseProcessLine
       |> ( if all then withFlag "-e" Nil else identity )
        |> ( case user of
               Nil -> identity
               u -> withFlag "-u" (toString u) )
        |> ( case pid of
               Nil -> identity
               p -> withFlag "-p" (toString p) )
```

### 示例 3：`docker.run`

```
CLI 命令：docker run -d --restart=always --memory=512m -e DB_HOST=prod nginx
                                    ↓
1. 能力识别："以后台模式运行 nginx 容器，自动重启，限制内存 512MB，注入环境变量"
                                    ↓
2. 返回类型定义：
   type ContainerId = String  // 容器 ID
                                    ↓
3. 影响结果的参数（注意：影响"如何运行"而非"返回什么"）：
   - image：镜像名（essential）
   - command：容器命令（essential）
   - detach：是否后台运行（behavior）
   - restart：重启策略（behavior）
   - memory：内存限制（behavior）
   - env：环境变量（behavior）
   - port：端口映射（behavior）
   - volume：卷挂载（behavior）
                                    ↓
4. `.cmd.kun` 实现（概念示例）：
   // 实际以纯 Kun 语法 + Builder API 定义
```

## 何时用 Primitive vs `.cmd.kun`

```kun
// Primitive（Zig 实现，进程内执行）
// 适用条件：基础系统调用可覆盖、逻辑简单、高频使用
ls         // getdents/statx
cp         // sendfile
mv         // rename
rm         // unlinkat
mkdir      // mkdirat
chmod      // fchmodat
chown      // fchownat
ln         // linkat
readlink   // readlinkat
realpath   // realpath
ps         // read /proc
free       // sysinfo
uname      // uname
uptime     // sysinfo
lscpu      // read /proc/cpuinfo
df         // statvfs
du         // fts_open
grep       // reuse regex engine (进程内)
locate     // read mlocate.db
walkDir    // fts_open

// `.cmd.kun` 执行（子进程）
// 适用条件：复杂协议/算法、外部库依赖、低频率操作
ss         // netlink 协议
dig        // DNS 协议
ping       // ICMP 协议
tar        // 归档格式
gzip       // 压缩算法
zip/unzip  // ZIP 格式
docker     // REST API
kubectl    // REST API
rsync      // 远程同步协议
scp        // SSH 协议
git        // 复杂的子命令树
```

## 不映射清单

以下 Linux 命令**不**映射为命令函数：

| 类别 | 命令 | 替代方式 |
|------|------|---------|
| 文本变换 | `sed`、`awk`、`sort`、`uniq`、`cut`、`tr` | Kun 标准库 `String`/`List`/`Stream` 函数 |
| 文件查看 | `cat`、`head`、`tail`、`less`、`more` | `readFile`、`Stream.take`、`Stream.drop` |
| 行计数 | `wc` | `Stream.length`、`String.length` |
| 文件复制到输出 | `tee` | `writeFile` + `IO` 组合 |
| 参数展开 | `xargs` | `Stream.toList` + `\|>` |
| 权限提升 | `sudo`、`su` | `runAs` 隐式参数 |
| 目录遍历 | `find` | `walkDir` + `filter` |
| 文件定位 | `which`、`type` | 标准库 `Filesystem.lookupPath` |
| 显示格式 | `echo`、`printf` | `print`、`println`、`format` 标准库函数 |
| 上下文切换 | `cd`、`pushd`、`popd` | Kun 本身无"当前目录"可变状态，所有路径使用绝对路径或 `Path.cwd` |

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 0.1.0 | 2026-06-04 | 初始版本：能力映射方法论、参数分类、命令映射表 |
