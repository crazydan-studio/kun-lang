# 日志：设计审计第三至第五轮修复

## 日期与会话信息

- **日期**：2026-06-02
- **会话类型**：设计审计 + 修复
- **提交者**：`AI <ai@kun-lang.crazydan.io>`

## 工作内容

### 设计审计（三轮）

对 Kun 的类型系统、语法设计、能力系统进行了三轮子代理审计：

| 审计轮次 | 新发现 | 累计修复 |
|---------|--------|---------|
| 第三轮 | 4 项残留问题 | 52 项 |
| 第四轮 | 2 项低严重度问题 | 54 项 |
| 第五轮 | 3 项文档问题 | 57 项 |

### 安全边界简化

- `capability_check` 明确为唯一硬防线，沙箱标记为"尽力而为"
- 移除对 mount namespace 和 seccomp 路径级隔离的过度承诺
- TOCTOU 按内核版本分级文档化（5.6+ `openat2()` / <5.6 `O_NOFOLLOW`）
- 移除 `security-boundary-analysis.md`（内容已整合到主文档）

### R4/R5 安全修复实施

- **R4** 环境变量过滤：exec 前自动过滤，始终剔除 `LD_PRELOAD`/`LD_AUDIT`/`LD_DEBUG`/`BASH_ENV`
- **R5** 文件描述符 CLOEXEC：所有运行时管理的 fd 创建时设 `O_CLOEXEC`

### 文档修复

- 命令退出码返回类型 `CmdResult t`（`grep`/`diff` 非零退出码不为 `Err`）
- `exec` 原语加入标准库（含 `execBytes` 二进制输出变体）
- `FileStat.owner` 改为 `Uid` 类型，`ownerName` 为便利字段
- `FileMode` newtype 替代原始 `Int`
- 能力交集 `[]` 语义规则表
- 容器模式沙箱限制文档化
- `Signal.on` signalfd 投递机制
- 多种内部矛盾和语法错误修复

## 已修改文件清单

| 文件 | 变更 |
|------|------|
| `design/roles-and-permissions.md` | 沙箱节简化、环境变量过滤、交集规则、线程安全注释、容器限制 |
| `design/standard-library.md` | Exec 模块、FileMode、FileStat 字段修正、Signal.on 投递机制、execBytes |
| `design/command-signature-system.md` | CmdResult 退出码类型 |
| `architecture/system-baseline.md` | 默认权限表述、O_CLOEXEC、openat2 TOCTOU、IOError 统一、fromList→toList |
| `design/type-system.md` | IO 效应类型独立标题 |
| `design/syntax.md` | 无参函数引用修正 |
| `design/feature-inventory.md` | 求值策略修正 |
| `design/app-overview.md` | 求值策略修正 |
| `design/security-boundary-analysis.md` | 已移除 |
| `context/project-context.md` | 任务路由记录 |
| `discussions/discussion-design-review-round2.md` | 审计共识记录 |

### 命令函数设计重构

- **命令输出结构化**：CDF 不声明输出格式参数，运行时自动选择最佳输出格式并解析为结构化类型
- **移除 `exec` 原语**：无 CDF 的命令不可调用，统一走命令函数路径，消除安全逃逸
- **`process.exec` 完全移除**：CDF 存在即授权，无 CDF 的命令不可执行
- **`runAs` 隐式参数**：所有命令函数带有 `runAs : ?String`，通过 `process.run-as` 能力控制
- **Record 参数统一**：所有 `flag`/`option`/`positional` 合并到同一 Record 类型
- **`sudo`/`su` 禁止映射**：由 `runAs` 参数替代
- **内置签名库按能力集成价值确定范围**：文本变换命令不映射，标准库覆盖

### VitePress 导航修复

- 补充 7 个缺失的 sidebar 入口（计划/需求/讨论/审计）
- 记录到 `agents-md-compliance.md` 重复违规表

## 待解决问题

- 无——设计审计 57 项已修复/关闭，命令函数设计已完成
