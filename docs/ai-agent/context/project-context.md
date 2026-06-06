# 项目上下文

## 项目身份

| 字段 | 值 |
|---|---|
| 项目名称 | Kun（鲲） |
| 项目类型 | 编程语言设计与实现 |
| 当前版本 | 0.1.0 |
| 目标用户 | Linux 系统管理员、DevOps 工程师、需要编写 Shell 脚本的开发者 |
| 里程碑 | 语言设计定型与核心解释器原型 |
| 宿主语言 | Zig（锁定 0.13.0） |
| 目标平台 | Linux |
| 许可证 | Apache 2.0 |

## 活跃工作

| 维度 | 当前值 |
|---|---|---|
| 活跃需求 | 语言核心设计与类型系统定义（定型）、语法设计（定型）、标准库类型设计（定型）、运行时架构设计（定型）、命令签名系统设计（定型）、安全模型设计（定型） |
| Owner Doc | `docs/ai-agent/design/type-system.md`、`docs/ai-agent/design/syntax.md`、`docs/ai-agent/design/standard-library.md`、`docs/ai-agent/architecture/system-baseline.md`、`docs/ai-agent/design/command-function-system.md`、`docs/ai-agent/design/roles-and-permissions.md` |
| 活跃计划 | 实现阶段启动（类型检查器 / 解析器 / 运行时原型） |
| 最近完成 | 废弃 CDF 方案，改用 `.cmd.kun` + Builder API（`design/command-function-system.md`）；全 Kun 语法、Landlock 安全、版本化注册中心；CDF 全面重构（同前）；语法操作符修订（`=?`→`=!`/`!=`→`/=`）；List 展开 `*`→`..`；Maybe→`?T` 清理；`--`→`//` 注释语法修正；行多态与扩展积类型设计；全面审计（8 轮/49 项问题修复 + 3 轮语法检查/28 处修复）；标准库 API 盲点补充（`sleep`/`Random`/`TempFile`/`TempDir`/定时器/退出码）；README 修正；`Path ++` 拼接；Record `{a, ..rest}` 解构；`?(Result T E)` 语法规则 |
| AI 自治级别 | `implement` |
| 阻塞项 | 无 |

## 技术基线

| 层 | 技术栈 |
|---|---|
| 语言实现 | Zig 0.13.0（宿主语言，版本锁定） |
| 运行时 | dlopen/dlsym 直接加载命令二进制 |
| 安全模型 | Linux namespace 沙箱 + 能力安全 |
| 文档构建 | VitePress + pnpm |
| 版本控制 | Git + GitHub |

## 验证命令

| 操作 | 命令 |
|---|---|
| 安装依赖 | `cd docs && pnpm install` |
| 构建文档 | `cd docs && pnpm build` |
| 本地预览 | `cd docs && pnpm dev` |
| 检查 Markdown 语法 | `cd docs && pnpm lint:md` |
| 单元测试 | 待定 |

## 最近任务路由

| 日期 | 任务 | 分类 | Owner Docs 检查 | Skills 检查 | 路由决策 |
|------|------|------|----------------|------------|---------|
| 2026-06-01 | 能力安全系统重新设计 | 重构+设计 | ✅ roles-and-permissions、syntax、system-baseline | ❌ 未检查（事后补查：skills/ 含 document-audit/plan-audit/closure-audit 提示词） | 应走 `plan-first`，实际未写计划直接实施（违规） |
| 2026-06-02 | 五轮设计审计与修复 | 审计+修复 | ✅ 全部 owner docs | ✅ 使用 closure-audit-prompt、document-audit-prompt | `implement` 直接执行 |
| 2026-06-04 | CDF 全面重构与命令函数系统重设计 | 设计+重构 | ✅ 全部 owner docs | ❌ 未检查 | `plan-first` → `implement`（先写 plan 后执行） |
| 2026-06-04 | 语法打磨 + 多轮全面审计 + 标准库盲点补充 | 维护+审计 | ✅ 全部 owner docs | ✅ document-audit-prompt、closure-audit-prompt、multi-dimensional-audit-prompt | `implement` 直接执行 |
| 2026-06-04 | `.cmd.kun` + Builder API 替代 CDF 方案设计 | 设计 | ✅ command-signature-system、command-function-system | ❌ 未检查 | `plan-first` → 实际直接实施 |
| 2026-06-06 | 全面清理 CDF 过时引用 + 多轮语法检查 + `.cmd.kun` 设计完善 | 审计+修复 | ✅ 全部 owner docs | ✅ document-audit-prompt、multi-dimensional-audit-prompt | `implement` 直接执行 |
| 2026-06-06 | 幻影类型系统设计 + 命令模块导出控制 + `asStream`/`asDocument` 重命名 | 设计+重构 | ✅ type-system、command-function-system、syntax | ✅ document-audit-prompt | `implement` 直接执行 |
| 2026-06-06 | 宿主语言评估（Zig vs Rust vs Go）确认 Zig、创建 zig-patterns.md、版本锁定 | 分析+配置 | ✅ project-context、system-baseline | ✅ document-audit-prompt、zig-patterns | `implement` 直接执行 |
| 2026-06-06 | LSP 工具链重构（code/lsp-server/ 四模块）+ CLI 工具 + pnpm workspace 整合 + VitePress 高亮尝试 | 重构+配置 | ✅ 全部 owner docs | ✅ document-audit-prompt | `implement` 直接执行 |
| 2026-06-06 | VitePress 代码高亮多轮迭代 + 代码块标签规范 + markdownlint 修复 | 维护 | ✅ config.mts、conventions.md | ✅ document-audit-prompt | `implement` 直接执行 |

## AI 阻塞条件

- `project-context.md` 中的活跃需求为空时，AI 不应实施任何代码变更
- 涉及类型系统核心（ADT、模式匹配、类型推断）变更需先更新 `docs/ai-agent/architecture/` 下的设计文档
- 运行时安全模型（沙箱、能力）变更需人工确认
