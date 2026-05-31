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
|---|---|
| 活跃需求 | 语言核心设计与类型系统定义（定型）、语法设计（定型，含 21 项语法调整）、标准库类型设计（定型）、运行时架构设计（定型） |
| Owner Doc | `docs/design/type-system.md`、`docs/design/syntax.md`、`docs/design/standard-library.md`、`docs/architecture/system-baseline.md` |
| 活跃计划 | 命令签名系统设计、安全模型设计 |
| 最近完成 | 运行时架构设计全量扩展（生命周期、执行模型、错误诊断、命令加载、类型表示、内存管理、模块解析、标准库集成） |
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

## AI 阻塞条件

- `project-context.md` 中的活跃需求为空时，AI 不应实施任何代码变更
- 涉及类型系统核心（ADT、模式匹配、类型推断）变更需先更新 `docs/architecture/` 下的设计文档
- 运行时安全模型（沙箱、能力）变更需人工确认
