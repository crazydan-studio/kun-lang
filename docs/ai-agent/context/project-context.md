# 项目上下文

## 项目身份

| 字段 | 值 |
|---|---|
| 项目名称 | Kun（鲲） |
| 项目类型 | 编程语言设计与实现 |
| 当前版本 | 0.1.0 |
| 目标用户 | Linux 系统管理员、DevOps 工程师、需要编写 Shell 脚本的开发者 |
| 里程碑 | 语言设计定型与核心解释器原型 |
| 宿主语言 | Zig |
| 目标平台 | Linux |
| 许可证 | Apache 2.0 |

## 活跃工作

| 维度 | 当前值 |
|---|---|---|
| 活跃需求 | 语言核心设计与类型系统定义（定型）、语法设计（定型）、标准库类型设计（定型）、运行时架构设计（定型）、命令签名系统设计（定型）、安全模型设计（定型） |
| Owner Doc | `docs/ai-agent/design/type-system.md`、`docs/ai-agent/design/syntax.md`、`docs/ai-agent/design/standard-library.md`、`docs/ai-agent/architecture/system-baseline.md`、`docs/ai-agent/design/command-signature-system.md`、`docs/ai-agent/design/roles-and-permissions.md` |
| 活跃计划 | 实现阶段启动（类型检查器 / 解析器 / 运行时原型） |
| 最近完成 | CDF 全面重构：EBNF 形式化语法、分级可用性模型（T1-T4）、run-first 入口（`run""` + `process.run`）、内联验证器、`.` 分隔子命令、List T 重复选项、env/fd 隐式注入、FdSpec 重定向、超长参数自动分片、CmdResult 移除→exitcode 声明、Maybe→?T Nilable 类型替换、?. 可选链 / ?? Nil 合并 |
| AI 自治级别 | `implement` |
| 阻塞项 | 无 |

## 技术基线

| 层 | 技术栈 |
|---|---|
| 语言实现 | Zig（宿主语言） |
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

## AI 阻塞条件

- `project-context.md` 中的活跃需求为空时，AI 不应实施任何代码变更
- 涉及类型系统核心（ADT、模式匹配、类型推断）变更需先更新 `docs/ai-agent/architecture/` 下的设计文档
- 运行时安全模型（沙箱、能力）变更需人工确认
