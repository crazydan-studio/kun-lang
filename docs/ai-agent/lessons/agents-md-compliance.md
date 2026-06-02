# 经验教训：AGENTS.md 合规性

## 背景

2026-06-01 的会话在执行能力安全系统重新设计时，未完全遵循 AGENTS.md 的流程规范，存在计划缺失、审计跳过、流程颠倒等问题。事后补充了 plan、requirements、audit 等文档。本文记录根因和整改措施。

## 违规类型与根因

| 违规 | 根因 | 整改措施 |
|------|------|---------|
| 计划触发条件满足但未写计划 | 未在任务开始前将 AGENTS.md 作为检查清单逐条确认 | 在 process/ 中增加"任务启动检查清单" |
| 自治级别受保护区域未触发 ask-first | 安全模型变更被视为"设计讨论"而非"安全模型变更" | 任务启动检查单中明确要求检查受保护区域 |
| 流程颠倒（实施后才补文档） | 没有在每步完成后检查流程完整性 | 实施前自检 + 每阶段验证 |
| subagent 委托缺乏上下文 | 未在 task prompt 中要求遵循 AGENTS.md | subagent prompt 必须包含"遵循 AGENTS.md"指令 |
| 未检查 skills/ | 不知道或忘记了 skills/ 目录的内容 | 检查清单中明确列出 8 个技能文件 |
| 旧路径/旧设计沿用 | 未及时确认最新目录结构和设计文档状态 | 阅读 owner docs 时确认文件路径和内容 |
| 缺少自我审查环节 | 实施完成后没有停下来做流程合规检查 | 实施后执行"阶段 11：闭合审计" |

## 整改措施清单

### 已执行

- [x] 在 `process/application-development-workflow.md` 头部增加"任务启动检查清单"
- [x] 补写能力安全系统重设计的 plan、requirements、audit 文档
- [x] 记录任务路由到 `context/project-context.md`

### 待执行

- [ ] 每次新任务开始时运行启动检查清单（⚠️ 6 月 2 日会话仍存在同样问题——创建新文件后未更新 VitePress 导航）
- [ ] subagent 委托时传递 AGENTS.md 约束
- [ ] 实施后自动触发闭合审计流程
- [ ] 新建文件后必须同步更新 `config.mts` 的 nav 和 sidebar 对应项

## 重复违规记录

| 日期 | 违规类型 | 说明 |
|------|---------|------|
| 2026-06-02 | VitePress 导航未同步 | 创建 `discussion-design-review-round2`、`plan-capability-redesign`、`req-capability-design` 等文件后未在 `config.mts` 中添加对应的 sidebar 入口 |
| 2026-06-02 | 旧设计模式遗留 | `roles-and-permissions.md` 中仍使用 `--` 注释（非 `//`）和 `fn x =>`（非 `\x ->`）——违反代码格式化规范 |
| 2026-06-02 | 启动检查清单未执行 | 检查清单已创建但未在新任务前实际运行 |

## 关键提醒

1. **AGENTS.md 不是一次阅读就够的**——每次任务开始前应重新通读
2. **受保护区域高于总体自治级别**——即使总体是 `implement`，受保护区域仍需 `plan-first` 或 `ask-first`
3. **先文档后代码**——文档落盘优先于代码修改
4. **plan 不能跳过**——超过 5 文件或 200 行必须写 plan，且 plan 必须先审计再实施
