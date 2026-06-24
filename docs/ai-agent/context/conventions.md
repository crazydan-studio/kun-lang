# 约定规范

## 命名规范

### 文件命名

- 文档文件使用 kebab-case：`project-vision.md`、`module-boundaries.md`
- 图表文件使用描述性名称：`type-system-overview.puml`、`runtime-architecture.puml`
- **Kun 模块文件**（`lib/` 内的 `.kun` 文件）使用 **PascalCase**：`Builder.kun`、`Cmd/Git.kun`、`MyApp/Config.kun`
- **Kun 入口脚本**（含 `main` 的可执行文件）使用 **kebab-case**：`deploy.kun`、`build-all.kun`
- Zig 源文件使用 snake_case：`lexer.zig`、`type_check.zig`
- **Zig 测试文件**使用 `test_{target}.zig` 格式，与实现文件同目录放置：`lexer/test_lexer.zig`、`parser/test_parser.zig`

### 目录命名

- 文档目录使用 kebab-case
- 源代码目录遵循 Zig 项目结构规范
- **Kun `lib/` 内子目录**使用 **PascalCase**：`lib/Cmd/`、`lib/Parser/`、`lib/MyApp/`

### 文件后缀

- Kun 脚本文件使用 `.kun` 后缀
- Kun 库模块文件（有 `export` 声明）也使用 `.kun` 后缀

## 文档格式

- 所有文档使用 Markdown 格式
- 遵循 [文档编写规范](../skills/writing-conventions.md)
- PlantUML 图表文件放置在 `docs/ai-agent/diagrams/` 目录

## 工作流规范

- 新功能遵循：输入 → 讨论 → 需求 → 设计 → 计划 → 实施 → 验证 → 审计
- 版本迭代前必须归档当前版本文档到 `docs/ai-agent/archive/<version>/`
- **对话结论必须落盘**：对话中产生的所有结论、需求理解、设计决策、架构变更，必须在对话结束前以文件形式记录到 `docs/ai-agent/` 对应目录。不得仅依赖对话记忆
- **语法合规审计**：所有代码示例（包括语法设计文档、类型系统文档、标准库文档、示例文件等中的 Kun 代码）必须在变更后通过子代理语法合规审计。审计同时须遵循 [代码格式化规范](../design/code-formatting.md) 检查缩进、换行等格式
- **Kun 代码验证**：`kun` 可执行文件尚未构建，Kun 代码的语法合规性通过子代理审计（语法设计文档交叉对照）验证。实现阶段后将使用 `kun check` 子命令执行编译期检查
- **Zig 代码审计**：LLM 生成的 Zig 代码在合入前必须对照 `docs/ai-agent/context/zig-patterns.md` 进行模式审计，确认 Arena 使用、分配器传递、C ABI 兼容性等关键模式正确
- **审计禁止模式**：语法合规审计必须包括对已明确禁止的语法形式的检查（注释 `--`/`#`/`/* */`、泛型尖括号 `<>`、List `::` 模式、Map `=>`、`type alias`、`pub` 关键字、`() -> T` 函数类型、反引号前缀字面量、Record 类型别名、表达式上的 `?` 操作符、函数名后缀 `funcName? args`、`let` 关键字单绑定、括号逗号函数调用等）
- **审计类型定义**：多处使用到同结构的 Record 类型应定义为 Newtype 或 ADT，而非重复内联
- **日期记录以实际命令为准**：在创建日志、任务路由记录等包含日期的文档时，必须先执行 `date +%Y-%m-%d` 获取实际日期，而非依赖系统上下文中的"今日"概念。日志文件名中的日期也必须与实际日期一致
- **代码块标签规范**：文档中的 Kun 代码块只允许使用 ` ```kun ` 标签（当前 Kun 代码）或 ` ```kun-cdf ` 标签（已废弃的 CDF DSL 引用，不提供语法高亮）。不存在 ` ```kun-cmd ` 标签
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

## 代码审查

- 所有变更须经过独立审查（子代理或人工）
- 审查要点：交叉文档一致性、API 签名正确性、安全影响
- 审计记录写入 `docs/ai-agent/audits/`

## 版本管理

- **项目版本**（Kun Lang 语言自身）采用 `x.y.z` 形式（主版本.次版本.修订号）
  - 主版本变更：破坏性语言/API 变更（如 `0.1.0` → `1.0.0`）
  - 次版本变更：新特性、标准库模块扩展（如 `0.1.0` → `0.2.0`）
  - 修订号变更：Bug 修复、文档更新（如 `0.1.0` → `0.1.1`）
- **文档版本**：各文档的 `## 版本历史` 节采用 `yyyy.MM.dd` 日期形式（如 `2026.06.15`）——仅记录该文档自身的修改时间线，与项目版本解耦
- 源代码版本通过 Git tag 管理（格式：`v<项目版本>`，如 `v0.1.0`）
- 文档版本历史记录在各文件的 `## 版本历史` 节

## 编码约定

- 源文件编码：UTF-8（无 BOM）
- 行尾：LF（Unix 风格）
- 文件末尾需有且仅有一个空行

## 测试用例编写规范

对于同类型（相同测试维度）但具体测试目标不同的测试用例，优先采用**数据列表 + 循环遍历**方式在单个测试中实现，而非为每个数据点创建独立测试函数。

**模式**：

```zig
test "describes the category being tested" {
    const cases = [_]struct { input: T, expected: U }{
        .{ .input = ..., .expected = ... },
        .{ .input = ..., .expected = ... },
    };
    for (cases) |c| {
        // call function under test with c.input
        // verify result matches c.expected
    }
}
```

**适用条件**：
- 多个测试用例测试同一函数/同一维度的不同数据点
- 每个用例的 setup/teardown 逻辑相同或仅参数不同
- 用例结果为简单的 true/false 或枚举匹配

**不适用**：
- 测试需要不同的 setup/teardown 逻辑
- 测试涉及副作用（IO、文件系统操作）且需隔离
- 单个测试失败会使后续用例失效的有状态测试

**示例**（`test_primitive.zig`）：
- `isEffectBinding covers all known patterns` — 合并了 14 个原独立测试
- `primitive impl functions return correct variant` — 合并了 5 个原独立测试
- `isKnownCmdApi covers all known patterns`（`test_cmd.zig`）— 合并了 4 个原独立测试

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.24 | 新增测试用例编写规范（列表+循环模式） |
| 2026.06.17 | 命名规范：新增 Kun 模块文件（PascalCase）、入口脚本（kebab-case）、`lib/` 子目录（PascalCase）、Zig 源文件（snake_case）命名规则；移除"待定"占位 |
| 2026.06.15 | 新增代码审查/版本管理/编码约定/注释标记规范 |
| 2026.06.10 | 初始版本 |
