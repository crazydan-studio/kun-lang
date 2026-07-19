# `handle with` 入口级范围与语法收缩

> **日期**：2026-07-18
> **状态**：已定稿
> **相关文档**：[语法设计 - `do ... with` / `let ... in ... with` 表达式](../design/syntax.md#do--with--let--in--with-表达式)、[类型系统 - `do ... with` / `let ... in ... with` 表达式（限入口函数）](../design/type-system.md#do--with--let--in--with-表达式限入口函数)、[应用概览 - `do ... with` / `let ... in ... with` 限入口](../design/app-overview.md#do--with--let--in--with-限入口)、[单元测试设计](../design/testing.md)、[代码格式化 - `do ... with` / `let ... in ... with` 表达式](../design/code-formatting.md#do--with--let--in--with-表达式)

## 背景

代数效应与命令系统重设计落地后，`handle <expr> with <handler>` 入口级效应消解机制存在两项待决问题：

1. **入口级范围**：`handle with` 仅允许在 `main`/`TestCase.body` 内使用，还是允许业务函数中途消解？
2. **语法形式**：保留 `handle <expr> with <handler>` 三关键字形式，还是收缩为 `do`/`let in` 块的 `with` 后缀（移除 `handle` 关键字）？

本文档记录这两项决策及其理由。

## 决策一：保留入口级限制（仅 `main`/`TestCase.body`）

**决策**：`handle with`（现在为 `do...with` / `let...in...with`）**仅允许在 `main` 函数与 `TestCase` 类型值的 `body` 字段内使用**。业务函数只声明效应不消解，效应冒泡到入口级上下文集中消解。

**理由**：

- **效应签名可靠性**：业务函数的效应集 `! E` 是函数契约的一部分。若允许业务函数中途消解效应，调用者无法从签名推断真实剩余效应，效应集签名失去意义。入口级集中消解保证函数效应集 = 实际可能冒泡的效应集。
- **可测试性**：效应冒泡到调用者（包括测试入口），测试通过 `Test.with` 模块函数或 `do...with` / `let...in...with` 注入 mock handler 替换真实副作用。若允许业务函数中途消解，测试无法拦截其内部效应调用，破坏 mock 隔离。
- **单向效应流**：效应从业务函数 → 调用者 → 入口级上下文，单向流动、无中途回流。这种单向性简化效应追踪、错误诊断、安全审计（如 `FFI` 效应必然冒泡到 `main`，由 `--allow-ffi` 集中检查）。
- **与 `kun test` 运行器协同**：`TestCase.body` 由运行器在入口级上下文执行（包装 → `TestCase.with` 消解用户效应 → `testHandler` 消解 `Test` 效应），入口级限制使 `body` 与 `main` 同级，统一处理。

**识别机制**：编译器按 `main` 函数名 + `TestCase` 类型值的 `body` 字段识别入口级上下文（运行器提供 `TestCase.body` 的入口级上下文）。其他业务函数禁止使用 `do...with` / `let...in...with`，违反则编译错误。

## 决策二：采用 `do ... with` / `let ... in ... with` 形式，移除 `handle` 关键字

**决策**：移除 `handle` 关键字，效应消解统一通过 `do`/`let in` 块的可选 `with` 后缀表达：

```kun
// Unit 返回：do <body> with <handler>
do
  <body>
with
  <handler>

// 值返回：let <body> in <expr> with <handler>
let
  <body>
in
  <expr>
with
  <handler>
```

`with <handler>` 位于前置 `do`/`let in` 块**末尾**（与 `do`/`let` 同缩进），将 handler 绑定到整个前置块。

**理由**：

- **更简洁**：`handle <expr> with <handler>` 需要 `handle` + `<expr>` + `with` + `<handler>` 四段；新形式复用 `do`/`let in` 块结构，仅追加 `with <handler>` 后缀，少一个关键字。
- **与 `do`/`let in` 统一**：效应消解不再有独立的 `handle` 语法形式，而是 `do`/`let in` 块的可选后缀。语法表更收敛，认知负担更低。
- **减少缩进**：`handle <expr> with <handler>` 中的 `<expr>` 通常本身是 `do`/`let in` 块，导致双重缩进（外层 `handle` 一层、内层 `do`/`let in` 一层）。新形式下，`do`/`let in` 直接绑定 `with`，减少一层缩进。

**迁移对照**：

| 旧形式 | 新形式 |
|---|---|
| `handle (do <body>) with <h>` | `do <body> with <h>` |
| `handle (let <body> in <expr>) with <h>` | `let <body> in <expr> with <h>` |
| `handle <bare expr> with <h>`（裸表达式） | 包装为 `let v = <expr> in v with <h>`（值返回）或 `do <body> with <h>`（Unit 返回） |

**规则约束**：

- `with` 仍是关键字，用于 `do...with` / `let...in...with` 后缀
- `with` 不可脱离 `do`/`let in` 单独使用——`<expr> with <handler>` 编译错误
- 入口级限制不变：`do...with` / `let...in...with` 仅 `main`/`TestCase.body` 内可用
- `handler X of ...` 声明语法**不变**（使用 `handler` 关键字 + `of`，与 `handle` 关键字无关）
- `continue`/`abort` 控制流原语**不变**

## 与现有设计的关系

- **2026.07.16 v2 调整**：`TestCase.body` 由 `Test.body` 重命名而来（详见 [单元测试设计讨论](discussion-unit-testing-design.md)）；入口级 `handle with` 从 `main`/`test*` 扩展为 `main`/`TestCase.body`
- **2026.07.18 调整**（本决策）：移除 `handle` 关键字，统一为 `do...with` / `let...in...with`；入口级范围保持不变（`main`/`TestCase.body`）

## 落盘清单

| 文件 | 变更 |
|---|---|
| `docs/ai-agent/design/syntax.md` | 关键字表移除 `handle`（Token 表行 71 + 关键字表行 414）；表达式分类表 `handle <expr> with <handler>` 行改为 `do <body> with <handler>` / `let <body> in <expr> with <handler>`；解析器识别规则新增第 5 条 `with` 作为 `do`/`let in` 可选后缀；`## \`handle with\` 表达式` 章节重写为 `## \`do ... with\` / \`let ... in ... with\` 表达式`（两种形式、规则、入口级上下文表、main 函数示例）；`### 入口级 \`handle with\` 与 \`TestCase.body\`` 改为 `### 入口级 \`do ... with\` / \`let ... in ... with\` 与 \`TestCase.body\``；FFI 示例 `Some handle ->` 变量名改为 `Some file ->`（避免与已移除关键字同名）；Cmd 命名空间表 `handle ... with h` 改为 `do ... with h` |
| `docs/ai-agent/design/type-system.md` | `### \`handle\` 表达式（限入口函数）` 章节重写为 `### \`do ... with\` / \`let ... in ... with\` 表达式（限入口函数）`；入口级上下文表列名 `可用 \`handle\`` 改为 `可用 \`do...with\` / \`let...in...with\``；main 边界示例 `handle ... let ... in ... with ...` 改为 `do ... with ...`；错误消息模板 `必须在 main 内 handle` 改为 `必须在 main 内消解（do...with / let...in...with）`；`handle <expr> with dbHandler` 改为 `do <body> with dbHandler`；FFI 示例 `Some handle ->` 变量名改为 `Some file ->`；`可独立 handle/mock` 改为 `可独立消解/mock`；`默认场景（用户不 handle 库效应）` 改为 `默认场景（用户不消解库效应）`；参考文档链接 `effect/handler/handle/extern/cmd` 改为 `effect/handler/with/extern/cmd` |
| `docs/ai-agent/design/standard-library.md` | FFI 内存管理示例 `Libc.fread buf 1 4096 handle` 变量名改为 `file`；FFI `Some handle ->` 改为 `Some file ->`；`可在 main 内 handle 内置效应` 改为 `可在 main 内消解内置效应（do...with / let...in...with）`；`force 上下文 .../handle with` 改为 `.../do...with/let...in...with`；`IO 模块定位 .../handle with 消解` 改为 `.../do...with / let...in...with 消解`；`可独立 handle/mock` 改为 `可独立消解/mock`；`默认场景（用户不 handle 库效应）` 改为 `默认场景（用户不消解库效应）`；录制/回放示例 `handle ... let ... in ... with ...` 改为 `do ... with ...` 与 `let ... in ... with ...` |
| `docs/ai-agent/design/testing.md` | 相关文档链接 `类型系统 - \`handle\` 表达式` 改为 `类型系统 - \`do ... with\` / \`let ... in ... with\` 表达式`；设计原则 4 `每测试独立 \`handle with\` 效应上下文` 改为 `每测试独立 \`do...with\` / \`let...in...with\` 效应上下文`；测试执行模型伪代码 `handle wrapped with h` / `handle resolved with testHandler` 改为 `let v = wrapped in v with h` / `let v = resolved in v with testHandler`；`入口级 \`handle with\` 上下文` 注改为 `入口级 \`do...with\` / \`let...in...with\` 上下文`；`--parallel` 章节 `独立的 \`handle with\` 上下文` 改为 `独立的 \`do...with\` / \`let...in...with\` 上下文`；对比表 `入口级 \`handle with\`` 改为 `入口级 \`do...with\` / \`let...in...with\``；兼容性迁移条目新增 2026.07.18 `handle` 关键字移除说明 |
| `docs/ai-agent/design/code-formatting.md` | 缩进总则注 `handle...with` 改为 `do...with`、`let...in...with`；缩进表 `handle with 的 with` 与 `handle...with 的 body` 两行改为 `do ... with / let ... in ... with 的 with` 与 `do...with 的 body / let...in...with 的 body 与 expr`；`### \`handle with\` 表达式` 章节重写为 `### \`do ... with\` / \`let ... in ... with\` 表达式`（含 Unit 返回与值返回两种示例） |
| `docs/ai-agent/design/app-overview.md` | `### \`handle with\` 限入口` 改为 `### \`do ... with\` / \`let ... in ... with\` 限入口`；main 示例 `handle ... let ... in ... with ...` 改为 `do ... with ...`；FFI 系统 `可独立 handle/mock` 改为 `可独立消解/mock`；录制/回放示例迁移；效应安全模型 `必须 \`handle\` 消解` 改为 `必须消解（\`do...with\` / \`let...in...with\`）` |
| `docs/ai-agent/design/command-system.md` | 设计原则 `入口级 handle` 改为 `入口级消解`；`用户在 main 内 handle Cmd` 注释改为 `用户在 main 内消解 Cmd（do...with / let...in...with）` |
| `docs/ai-agent/design/kun-cli-tool.md` | 脚本入口 `允许使用 \`handle with\` 消解效应` 改为 `允许使用 \`do...with\` / \`let...in...with\` 消解效应`；`### \`main\` 与 \`TestCase.body\` 的 \`handle with\` 限制` 改为 `### \`main\` 与 \`TestCase.body\` 的 \`do ... with\` / \`let ... in ... with\` 限制`；main 边界示例 `handle ... do ... with ...` 改为 `do ... with ...`；`必须 \`handle\` 消解` / `必须显式 \`handle\`` 改为 `必须 \`do...with\` / \`let...in...with\` 消解` / `必须显式消解（\`do...with\` / \`let...in...with\`）` |
| `docs/ai-agent/design/cli.md` | `--parallel` 章节 `独立的 \`handle with\` 上下文` 改为 `独立的 \`do...with\` / \`let...in...with\` 上下文` |
| `docs/ai-agent/design/feature-inventory.md` | 代数效应系统表 `handle with 表达式` 行重写为 `do ... with / let ... in ... with 表达式`；强制消解行 `必须 \`handle\`` 改为 `必须消解（\`do...with\` / \`let...in...with\`）`；安全表 `必须 \`handle\` 消解` 改为 `必须消解（\`do...with\` / \`let...in...with\`）`；语法与工具表 `handle with 表达式` 行重写为 `do ... with / let ... in ... with 表达式` |
| `docs/ai-agent/architecture/system-baseline.md` | 类型检查器验证规则 `验证 \`handle with\` 仅出现在入口函数` 改为 `验证 \`do...with\` / \`let...in...with\` 仅出现在入口函数` |
| `docs/ai-agent/discussions/discussion-unit-testing-design.md` | 相关文档锚点 `type-system.md#handle-表达式限入口函数` 更新为 `#do--with--let--in--with-表达式限入口函数` |
| `docs/ai-agent/discussions/discussion-handle-with-scope-and-syntax.md` | 新建本讨论记录 |
| `docs/ai-agent/discussions/index.md` | 新增本讨论记录的索引行 |
