# 执行计划：类型系统核心设计

## 背景与目标

当前 `docs/design/app-overview.md` 仅对类型系统做了概要列举，缺乏类型等价规则、推断算法、模式匹配类型规则、泛型约束、效应类型等核心设计。需将类型系统从粗略列举推进到可指导实现的完整设计文档。

## 变更范围

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `docs/design/type-system.md` | 类型系统核心设计文档（主要产出） |
| 新建 | `docs/diagrams/type-system-hierarchy.puml` | 类型层次与关系图 |
| 新建 | `docs/diagrams/type-checking-flow.puml` | 类型检查算法流程图 |
| 新建 | `docs/design/standard-library.md` | 标准库类型设计（Port/Pid/Signal/Errno 等） |
| 新建 | `docs/design/syntax.md` | 语法设计（与类型系统并行） |
| 修改 | `docs/design/app-overview.md` | 同步类型描述 |
| 修改 | `docs/design/feature-inventory.md` | 更新功能状态 |
| 修改 | `docs/design/index.md` | 添加新文件引用 |
| 修改 | `docs/.vitepress/config.mts` | nav + sidebar 更新 |
| 修改 | `docs/context/project-context.md` | 活跃工作更新 |
| 修改 | `docs/backlog/index.md` | 待办状态更新 |
| 修改 | `docs/context/conventions.md` | 追加 markdown 校验约束 |
| 修改 | `docs/architecture/system-baseline.md` | 同步类型概览 |
| 修改 | `docs/architecture/module-boundaries.md` | 同步标准库描述 |

## 实施步骤

```
Step 1: 类型系统设计文档 —— 14 设计维度（已执行）
Step 2: P0 审计修复 —— Array 幽灵类型消除 / IOError 定义 / Regex 补齐 / Ord/Eq 约束
Step 3: P1 类型补充 —— Port/Pid/Signal/Errno + DateTime/ExitCode/UserGroup/IpAddress
Step 4: 标准库拆分 —— 将非编译器固有类型从 type-system.md 迁出
Step 5: 语法设计 —— 覆盖全部语法模式，统一 9 处不一致
Step 6: 基础设施 —— markdownlint / gitignore / 导航更新
Step 7: 文档同步 —— project-context / backlog / 上下文文档
```

## 验证方法

- `cd docs && pnpm lint:md` —— Markdown 语法检查通过
- `cd docs && pnpm build` —— VitePress 构建通过
- PlantUML 图表正确渲染（build 生成 SVG）
- 审计者审查设计一致性与完整性

## 风险评估

| 风险 | 概率 | 缓解 |
|------|------|------|
| 设计决策使后续实现困难 | 低 | 决策先经审计再定稿 |
| 文档不一致 | 中 | 每次变更后 lint + build 验证 |
