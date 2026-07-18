# 日志：文档整体评审与全量修复

## 日期与会话信息

- **日期**：2026-06-07
- **会话类型**：文档分析评审 + 跨文档一致性修复 + PermissionError 重构
- **提交者**：`AI <ai@kun-lang.crazydan.io>`
- **提交范围**：10 次提交，涉及 25+ 个文件

## 工作内容

### 1. AGENTS.md 完整性修订

- 补齐文档目录总览（23 个目录完整索引）
- 升级任务路由优先为 5 步（含第 0 步：任务启动检查清单）
- 新增技能决策指引章节
- 新增 Git 规范章节
- 增强强制审计章节（链接 audit-guide + 审计技能）
- 增强错误模式升级规则（引用 lessons/）
- 计划触发条件增加流程指引

### 2. 跨文档一致性修复（第 1 轮）

- process/application-development-workflow.md：受保护区域补齐为 5 个（原缺失 dlopen/ptrace、许可证文件）；`/workspace/` 硬编码路径移除；`lint:md` → `lint`
- context/project-context.md、context/codebase-map.md：`lint:md` → `lint`
- plans/ 下 3 个文件：`lint:md` + `/workspace/` 修复
- 流程二元性标注：阶段 0-13 降级为完整生命周期参考，步骤 0-5 为主流程

### 3. 架构/设计文档分析评审

对 12 份架构与设计文档（约 5500 行）进行交叉分析，发现：

- **C1（已澄清）**：命令执行模型——分层择优（Primitive → .cmd.kun → `run""`），非互斥
- **C2（已修复）**：PermissionError 独立类型 → 折叠为 IOError.PermissionDenied Record
- **I2（已修复）**：exitCode 类型三值对齐（int32_t/Int/ExitCode → 统一为 ExitCode）
- **I4（已修复）**：system-baseline.md 过时句子替换为引用 command-function-system.md
- **O1（已修复）**：backlog 废弃 CDF 引用更新
- **R1（已修复）**：walkDir 三处重复定义去重

### 4. PermissionError 重构

- 移除 `struct PermissionError` 独立 C 中间类型
- `PermissionDenied Path` → `PermissionDenied { namespace, action, target, reason }`
- roles-and-permissions.md 错误消息格式统一为源标注图风格
- 波及 6 个文件的旧引用同步

### 5. 示例代码修复

- `split` → `String.split`（6 处，跨 file-processor.md、code-formatting.md）
- `unwrapOr` → `Result.withDefault`（networking.md）
- `endsWith` → `String.endsWith`（standard-library.md）
- 新增 `Path` 模块文档化（standard-library.md）
- type-system.md 标注 String 操作模块归属

### 6. ptrace 设计决策说明

- system-baseline.md 新增设计决策区块：ptrace vs fork-exec 性能对比 10-100x，已由 seccomp 替代

### 7. 目录索引完整性检查

- 发现 5 个目录索引缺失共 16 项引用，全部补齐：
  - context/：新增 zig-patterns.md
  - input/：新增 2 个输入记录
  - logs/：新增完整日志列表
  - plans/：新增 4 个计划
  - retrospectives/：新增回顾指南

### 8. 设计决策记录

以下设计决策在对话中确认，需同步记录：

- **String 操作归属**：`split`、`contains`、`endsWith`、`startsWith` 等 String 操作均为 `String` 类型函数，通过 `String.xxx` 模块限定调用，不存在裸顶层函数
- **Path 模块**：`Path` 为内置类型，`Path.cwd`（脚本启动时冻结）、`Path.join`、`Path.parent`、`Path.fileName`、`Path.extension` 等为 `Path` 模块函数

## 问题与解决方案

| 问题 | 分析 | 处理 |
|------|------|------|
| dlopen vs fork-exec 矛盾 | 分层择优架构，非互斥 | 补充说明归档 |
| PermissionError 类型冲突 | 独立 C 类型 vs IOError 变体 | 移除中间类型，折叠为 IOError Record |
| exitCode int32_t/Int/ExitCode 三值 | 未统一 | 转为 ExitCode type |
| 裸函数调用（split/endsWith/unwrapOr） | 示例代码使用未定义函数 | 模块限定 |
| 目录索引缺失 16 项 | 历史累积 | 全部补齐 |

## 验证

- `pnpm lint`：通过
- 交叉引用检查：86 文件中 0 处断链
- 遗留：废弃文档 `command-signature-system.md` 中的旧引用保留（历史归档）
