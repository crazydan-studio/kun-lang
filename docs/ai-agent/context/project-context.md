# 项目上下文

## 项目身份

| 字段 | 值 |
|---|---|
| 项目名称 | Kun（鲲） |
| 项目类型 | 编程语言设计与实现 |
| 当前版本 | 2026.06 |
| 目标用户 | Linux 系统管理员、DevOps 工程师、需要编写 Shell 脚本的开发者 |
| 里程碑 | 架构重设计完成，语言设计定型 |
| 宿主语言 | Zig（锁定 0.13.0） |
| 目标平台 | Linux |
| 许可证 | Apache 2.0 |

## 活跃工作

| 维度 | 当前值 |
|---|---|
| 活跃需求 | 语言核心设计与类型系统定义（定型）、语法设计（定型）、标准库类型设计（定型）、运行时架构设计（定型）、命令调用系统设计（定型）、安全隔离设计（定型） |
| Owner Doc | `docs/ai-agent/design/type-system.md`、`docs/ai-agent/design/syntax.md`、`docs/ai-agent/design/standard-library.md`、`docs/ai-agent/architecture/system-baseline.md`、`docs/ai-agent/architecture/module-boundaries.md` |
| 活跃计划 | 实现阶段启动（类型检查器 / 解析器 / 运行时原型） |
| 最近完成 | 架构重设计——移除 `IO T` 效应类型/`.cmd.kun`/`with caps`/`Nat`/dlopen/ptrace/Builder API/幻影类型；新增 `Cmd.<bin>` fork-exec/Landlock+mount ns+seccomp/defer/tagged union Stream/`Parser.Record`；标记角色安全/供应链安全/命令函数系统/能力映射指南为已废弃 |
| AI 自治级别 | `implement` |
| 阻塞项 | 无 |

## 技术基线

| 层 | 技术栈 |
|---|---|
| 语言实现 | Zig 0.13.0（宿主语言，版本锁定） |
| 运行时 | fork-exec + pipe 捕获 stdout/stderr |
| 安全模型 | CLI 参数（`--allow-path`/`--allow-net`）+ Landlock + mount namespace 兜底 + seccomp + rlimit |
| 文档构建 | VitePress + pnpm |
| 版本控制 | Git + GitHub |

## 验证命令

| 操作 | 命令 |
|---|---|
| 安装依赖 | `cd docs && pnpm install` |
| 构建文档 | `cd docs && pnpm build` |
| 本地预览 | `cd docs && pnpm dev` |
| 检查 Markdown 语法 | `cd docs && pnpm lint` |
| 单元测试 | 待定 |

## 最近任务路由

| 日期 | 任务 | 分类 | Owner Docs 检查 | Skills 检查 | 路由决策 |
|------|------|------|----------------|------------|---------|
| 2026-06-10 | 架构重设计——架构/设计/示例文档全面重写 | 设计+重构 | ✅ 全部 owner docs | ✅ document-audit-prompt、closure-audit-prompt | `plan-first` → `implement`（先审后实施） |
| 2026-06-07 | AGENTS.md 完整性修订（补齐全目录索引 + 跨文档一致性修复 10 项） | 文档+修复 | ✅ AGENTS.md、context/、process/、skills/ | ✅ writing-conventions、closure-audit | `implement` 直接执行 |
| 2026-06-07 | 架构与设计文档全面分析评审（12 份文档/5500 行交叉分析） | 分析+审计 | ✅ system-baseline、type-system、syntax | ✅ document-audit、multi-dimensional-audit | `implement` 直接执行 |
| 2026-06-07 | 示例代码未定义函数修复 + Path 模块文档化 | 修复 | ✅ syntax、standard-library、examples | ✅ writing-conventions | `implement` 直接执行 |
| 2026-06-07 | 目录索引完整性检查补齐（5 个目录/16 项） | 文档 | ✅ 全部 index.md | ✅ writing-conventions | `implement` 直接执行 |

## AI 阻塞条件

- `project-context.md` 中的活跃需求为空时，AI 不应实施任何代码变更
- 涉及类型系统核心（ADT、模式匹配、类型推断）变更需先更新 `docs/ai-agent/architecture/` 下的设计文档
- 运行时安全模型（沙箱、Landlock/seccomp）变更需人工确认
