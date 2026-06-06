# 约定规范

## 命名规范

### 文件命名

- 文档文件使用 kebab-case：`project-vision.md`、`module-boundaries.md`
- 图表文件使用描述性名称：`type-system-overview.puml`、`runtime-architecture.puml`
- 代码文件遵循 Zig 命名规范（待定）

### 目录命名

- 文档目录使用 kebab-case
- 源代码目录遵循 Zig 项目结构规范

### 文件后缀

- Kun 脚本文件使用 `.kun` 后缀
- 模块文件（有 `module export` 声明）也使用 `.kun` 后缀

## 文档格式

- 所有文档使用 Markdown 格式
- 遵循 [文档编写规范](/ai-agent/skills/writing-conventions)
- PlantUML 图表文件放置在 `docs/ai-agent/diagrams/` 目录

## 工作流规范

- 新功能遵循：输入 → 讨论 → 需求 → 设计 → 计划 → 实施 → 验证 → 审计
- 版本迭代前必须归档当前版本文档到 `docs/ai-agent/archive/<version>/`
- **对话结论必须落盘**：对话中产生的所有结论、需求理解、设计决策、架构变更，必须在对话结束前以文件形式记录到 `docs/ai-agent/` 对应目录。不得仅依赖对话记忆
- **语法合规审计**：所有代码示例（包括语法设计文档、类型系统文档、标准库文档、示例文件等中的 Kun 代码）必须在变更后通过子代理语法合规审计。审计同时须遵循 [代码格式化规范](/ai-agent/design/code-formatting) 检查缩进、换行等格式
- **审计禁止模式**：语法合规审计必须包括对已明确禁止的语法形式的检查（注释 `--`/`#`/`/* */`、泛型尖括号 `<>`、List `::` 模式、Map `=>`、`type alias`、`pub` 关键字、`() -> T` 函数类型、反引号前缀字面量、Record 类型别名、表达式上的 `?` 操作符、函数名后缀 `funcName? args`、`let` 关键字单绑定、括号逗号函数调用等）
- **审计类型定义**：多处使用到同结构的 Record 类型应定义为 Newtype 或 ADT，而非重复内联
- **日期记录以实际命令为准**：在创建日志、任务路由记录等包含日期的文档时，必须先执行 `date +%Y-%m-%d` 获取实际日期，而非依赖系统上下文中的"今日"概念。日志文件名中的日期也必须与实际日期一致
- **文档新增必更新导航**：新建文档文件后，必须同步更新 `docs/.vitepress/config.mts` 中的 nav 和对应 sidebar 项
- **文档修改后必须校验 Markdown 语法**：每次新建或编辑 `.md` 文件后，必须运行 `markdownlint` 检查语法正确性，修复所有报错后再提交
- **忽略 `.gitignore` 条目**：除非特别指定，不得读写和搜索 `.gitignore` 中已被忽略的文件和目录

## Git 规范

- 分支命名：`feature/<name>`、`fix/<name>`、`docs/<name>`
- 提交者统一为 `AI <ai@kun-lang.crazydan.io>`
- 提交信息使用中文，格式：`<类型>: <描述>`
  - 类型：`新增`、`修复`、`重构`、`文档`、`配置`、`测试`
- **按需提交**：AI 仅在用户明确要求提交时执行 git commit。提交前必须通过 `git status` 和 `git diff` 确认变更内容，按变更意图分组提交

## VitePress 路由

- 目录入口文件命名为 `index.md`（而非 `README.md`）
- 确保每个子目录都有 `index.md` 作为 VitePress 路由入口
