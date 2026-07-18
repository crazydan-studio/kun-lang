# 日志：code/kun-lang/ 实现撤销

## 日期与会话信息

- **日期**：2026-07-17
- **会话类型**：撤销 / 重构
- **commit**：`559180a` —— "撤销 code/kun-lang/ 实现，清理代码开发相关文档"
- **作者**：AI 码农 `<coder@ai.crazydan.io>`
- **影响范围**：151 文件变更，+8 / −50,533 行

## 工作内容

### 1. 撤销 `code/kun-lang/` 全部源码

删除 `code/kun-lang/` 全部源码（~5 万行），覆盖以下子系统：

- **入口与构建**：`build.zig`、`src/main.zig`、`src/lib.zig`、`src/test_main.zig`
- **AST**：`src/ast/ast.zig`、`src/ast/typed.zig`
- **词法分析器**：`src/lexer/lexer.zig`、`src/lexer/test_lexer.zig`
- **语法分析器**：`src/parser/parser.zig`、`src/parser/test_parser.zig`
- **类型检查器**：`src/typecheck/{env,unify,infer,constraint,effect,pattern,error,test_*}.zig`
- **运行时**：`src/runtime/{value,env,eval,defer,hash_map,glob_engine,stream_consumer,primitive,datetime_fmt,regex_engine,test_*}.zig`
- **命令调用系统**：`src/command/cmd.zig`、`src/command/test_cmd.zig`
- **模块解析**：`src/module/module_resolver.zig`、`src/module/test_module_resolver.zig`
- **国际化**：`src/i18n/{i18n,env,error,message,test_i18n}.zig`
- **标准库**：`src/stdlib/{io,fs,crypto,data,stream,char,...}.zig`
- **依赖**：`deps/zig-regex/` 全树（36 文件，含 unicode 数据表）

### 2. 清理实现相关 logs（3 篇）

- `log-2026-06-20-audit-phase-1.md`
- `log-2026-06-20-implementation-phase-1.md`
- `log-2026-06-26-phase-8-implementation.md`

### 3. 清理实现相关 plans（9 篇）

- `plan-implementation-phase-1.md` ~ `plan-implementation-phase-8.md`
- `plan-audit-fix-phase-1-5.md`

### 4. 清理实现相关 audits（18 篇）

- `audit-phase3-implementation.md`
- `audit-plan-phase2-round{1,2-3,5-6,7-8,9-10}.md`
- `audit-phase5-plan.md`、`audit-phase5-plan-round{1..13}.md`

### 5. 保留设计文档

- `docs/ai-agent/design/` 全部保留（type-system、syntax、standard-library、command-system、app-overview 等）
- `docs/ai-agent/architecture/` 全部保留（system-baseline、module-boundaries、zig-patterns）
- `docs/ai-agent/context/` 全部保留（project-context、codebase-map、conventions）
- `docs/ai-agent/requirements/`、`process/`、`references/` 全部保留

### 6. 更新 `code/README.md`

添加撤销说明：

> 注：`kun-lang/`（核心语言：编译器 + 运行时 + CLI）的实现已撤销，相关代码已移除。
> 其设计文档仍保留在 `docs/ai-agent/design/` 与 `docs/ai-agent/architecture/` 中。

### 7. 同步索引文件

- `logs/index.md` 移除 3 篇实现日志的索引行
- `plans/index.md` 移除 9 篇实现计划的索引行
- `audits/index.md` 移除 18 篇实现审计的索引行
- `backlog/index.md` 更新工作项

## 遇到的问题

### 1. 撤销时未创建闭合文档

撤销决策未配套创建闭合审计/回顾/日志，导致：
- 决策过程无追溯
- 影响评估无记录
- 经验教训未沉淀

**修复**：本次（2026-07-18）事后补建——
- `docs/ai-agent/audits/audit-codebase-revocation-closure.md`
- `docs/ai-agent/retrospectives/retrospective-codebase-revocation.md`
- `docs/ai-agent/logs/log-2026-07-17-codebase-revocation.md`（本文件）

### 2. `project-context.md` / `codebase-map.md` / `system-baseline.md` 存在矛盾引用

撤销当时未审计全部上下文与架构文档，导致三处矛盾引用：
- `project-context.md` 仍声称 "Phase 7-8 全部完成，708 测试通过，标准库 95% 真实实现"；"最近任务路由" 表仍含全部实现期条目；验证命令仍指向 `cd code/kun-lang && zig build`
- `codebase-map.md` 仍展示 `code/kun-lang/src/` 完整源码树
- `system-baseline.md` Typed AST 章节仍引用已删除的 `code/kun-lang/src/ast/typed.zig` 和 `code/kun-lang/src/ast/ast.zig`

**修复**：本次同步修复三处矛盾引用——
- `project-context.md` 改为反映"设计阶段，代码实现已撤销待重写"的当前状态
- `codebase-map.md` 改为展示 `code/` 当前组织（README + examples + kun-shell + kun-lsp）
- `system-baseline.md` Typed AST 注释改为反映"`code/kun-lang/` 实现已撤销，本节为设计规范，待重新实现时遵循"

## 撤销理由

`code/kun-lang/` 实现于 2026-06-20 至 2026-06-26 期间，基于旧设计完成 Phase 1–8。随后设计发生重大改动：

- **代数效应系统重设计**：`effect`/`handler`/`handle with` 入口级、闭集 + 单效应变量 `e`、零参效应函数 `T ! {E}` 与调用 `Name!` 约定
- **命令系统重设计**：`Command` ADT、`cmd` 字面量四段式、`Cmd.exec`/`Cmd.execSafe`/`Cmd.stream` 显式执行三入口、`pipe` 纯函数 + `|>` 纯管道
- **语法重设计**：块表达式（原"单一表达式范式"）、`let in` 统一（废弃 `do`/`do in`）、`alias`/`type` 分离、`==` 浅比较
- **类型系统重设计**：`alias`/`type` 分离、`==` 浅比较、Nilable 嵌套禁止
- **标准库重设计**：7 个内置效应 + `Process` 标准库效应、`extern` FFI 块、`FfiBuffer` 不逃逸、录制/回放
- **单元测试系统**：`TestCase` Record、`Test` 效应 + 模块同名消歧、`testHandler`、`_test.kun` 约定
- **沙箱加固**：`PR_SET_NO_NEW_PRIVS` + capabilities drop + fd scrub + `CLONE_NEWIPC` + `--allow-ffi` + `--audit`

旧实现的核心语法（`do`/`do in`、`Cmd.<bin>`、`?`/`!` 后缀、`EffectFn`、`when`、`Newtype`）已全部废弃，与旧实现不兼容。继续在旧实现上打补丁成本高于重新实现，故决定撤销旧实现，待设计完全稳定后基于新设计重新实现。

## 下一步计划

| 行动项 | 责任 | 状态 |
|--------|------|------|
| 补建闭合文档（audit + retrospective + log） | 本次任务 | ✅ 完成 |
| 修复三处矛盾引用（project-context / codebase-map / system-baseline） | 本次任务 | ✅ 完成 |
| 设计完全稳定后基于新设计重新实现 `code/kun-lang/` | 未来任务 | ⏳ 待设计冻结后启动 |

## 涉及文件

### 新增（事后补建，本次任务）

- `docs/ai-agent/audits/audit-codebase-revocation-closure.md`
- `docs/ai-agent/retrospectives/retrospective-codebase-revocation.md`
- `docs/ai-agent/logs/log-2026-07-17-codebase-revocation.md`（本文件）

### 修改（事后修复，本次任务）

- `docs/ai-agent/context/project-context.md`（项目身份/活跃工作/验证命令/最近任务路由全部重写为反映撤销后的设计阶段状态）
- `docs/ai-agent/context/codebase-map.md`（源代码结构章节重写为反映 `code/` 当前组织）
- `docs/ai-agent/architecture/system-baseline.md`（Typed AST 注释改为反映设计规范定位）
- `docs/ai-agent/logs/index.md`（新增本日志索引行）
- `docs/ai-agent/retrospectives/index.md`（新增回顾索引行）
- `docs/ai-agent/audits/index.md`（新增闭合审计索引行）
