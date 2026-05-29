# 约定规范

## 命名规范

### 文件命名

- 文档文件使用 kebab-case：`project-vision.md`、`module-boundaries.md`
- 图表文件使用描述性名称：`type-system-overview.puml`、`runtime-architecture.puml`
- 代码文件遵循 Zig 命名规范（待定）

### 目录命名

- 文档目录使用 kebab-case
- 源代码目录遵循 Zig 项目结构规范

## 文档格式

- 所有文档使用 Markdown 格式
- 遵循 [文档编写规范](/skills/writing-conventions)
- PlantUML 图表文件放置在 `docs/diagrams/` 目录

## 工作流规范

- 新功能遵循：输入 → 讨论 → 需求 → 设计 → 计划 → 实施 → 验证 → 审计
- 版本迭代前必须归档当前版本文档到 `docs/archive/<version>/`
- 所有持久化结论必须落盘到文件
- **文档新增必更新导航**：新建文档文件后，必须同步更新 `docs/.vitepress/config.mts` 中的 nav 和对应 sidebar 项
- **文档修改后必须校验 Markdown 语法**：每次新建或编辑 `.md` 文件后，必须运行 `markdownlint` 检查语法正确性，修复所有报错后再提交
- **忽略 `.gitignore` 条目**：除非特别指定，不得读写和搜索 `.gitignore` 中已被忽略的文件和目录

## Git 规范

- 分支命名：`feature/<name>`、`fix/<name>`、`docs/<name>`
- 提交信息使用中文，格式：`<类型>: <描述>`
  - 类型：`新增`、`修复`、`重构`、`文档`、`配置`、`测试`

## VitePress 路由

- 目录入口文件命名为 `index.md`（而非 `README.md`）
- 确保每个子目录都有 `index.md` 作为 VitePress 路由入口
