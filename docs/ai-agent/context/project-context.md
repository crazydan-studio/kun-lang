# 项目上下文

## 项目身份

| 字段 | 值 |
|---|---|
| 项目名称 | Kun（鲲） |
| 项目类型 | 编程语言设计与实现 |
| 当前版本 | 0.1.0（设计阶段，代码实现已撤销待重写） |
| 目标用户 | Linux 系统管理员、DevOps 工程师、需要编写 Shell 脚本的开发者 |
| 里程碑 | 效应委派与命令系统重设计完成，语言设计定型中；`code/kun-lang/` 实现已撤销（commit `559180a`，2026-07-17），待设计完全稳定后基于新设计重新实现 |
| 宿主语言 | Zig（锁定 0.16.0 稳定版，版本包 `/opt/ai-agent/tools/zig-x86_64-linux-0.16.0.tar.xz`） |
| 目标平台 | Linux |
| 许可证 | Apache 2.0 |

## 活跃工作

| 维度 | 当前值 |
|---|---|
| 活跃需求 | 语言设计稳定化（效应委派 / 命令系统 / 测试系统 / 沙箱等重设计落地） |
| Owner Doc | `docs/ai-agent/design/type-system.md`、`docs/ai-agent/design/syntax.md`、`docs/ai-agent/design/standard-library.md`、`docs/ai-agent/architecture/system-baseline.md`、`docs/ai-agent/architecture/module-boundaries.md`、`docs/ai-agent/design/kun-shell.md`、`docs/ai-agent/design/kun-cli-tool.md` |
| 活跃计划 | 无活跃实现计划（设计稳定后重新实现） |
| 最近完成 | `code/kun-lang/` 实现撤销（commit `559180a`，设计大改动导致旧实现不可维护）；效应委派与命令系统重设计（`effect`/`handler`/`handle with`、`cmd` 字面量、显式执行、`TestCase` 测试系统、沙箱加固等）；设计与架构文档同步重写；`.kun` 示例与 README 迁移到新语法 |
| 推迟项 | 沙箱（Landlock/seccomp/rlimit，设计已定型）；Kun Shell（未来版本）；等递归类型；Cli 模块 + Parser.Record；String/List/Map/Set PureKun 实现 |
| AI 自治级别 | `plan-first`（设计阶段，设计文档变更需先审后实施） |
| 阻塞项 | 无 |

## 技术基线

| 层 | 技术栈 |
|---|---|
| 语言实现 | Zig 0.16.0（宿主语言，版本锁定，版本包 `/opt/ai-agent/tools/`） |
| 运行时 | fork-exec + pipe 捕获 stdout/stderr |
| 二进制产物 | `kun`（脚本执行器）+ `libkunlang.so`（共享解释器核心）；`kun-shell`（交互式环境，未来版本） |
| 安全模型 | CLI 参数（`--allow-path`/`--allow-net`）+ Landlock + mount namespace 兜底 + seccomp + rlimit |
| 文档构建 | VitePress + pnpm |
| 版本控制 | Git + GitHub |

## 验证命令

| 操作 | 命令 |
|---|---|
| 安装依赖 | `cd docs && pnpm install` |
| 构建文档 | `cd docs && pnpm build` |
| 本地预览 | `cd docs && pnpm dev` |
| 检查 Markdown 语法 | `cd docs && pnpm lint` |

> **注**：`code/kun-lang/` 实现已撤销（commit `559180a`，2026-07-17），不再有 `zig build test` / `zig build dump-ast` 等命令。待设计完全稳定后基于新设计重新实现时，再补充验证命令。

## 最近任务路由

> **注**：2026-06-20 至 2026-06-26 的实现期任务（Phase 1-8）已随 `code/kun-lang/` 撤销一并清理（commit `559180a`），其历史路由条目不再保留于本表。下方仅保留撤销后的设计期路由，以及撤销前的设计阶段关键节点（用于追溯设计演进）。

| 日期 | 任务 | 分类 | Owner Docs 检查 | Skills 检查 | 路由决策 |
|------|------|------|----------------|------------|---------|
| 2026-07-18 | 活跃文档冲突与不一致审计 + 修复（13 项问题：Zig 版本统一 / `Process` 效应声明 / `newtype` 术语清理 / 5 失效锚点 / 安全参数补全 等） | 审计+修复 | ✅ 全部 owner docs | ✅ document-audit、closure-audit | `implement` |
| 2026-07-18 | `.kun` 示例与 README 迁移到新语法（cmd 字面量 / `let in` / 效应集 `! {E}` / 零参效应函数 `!` 后缀 / `pipe` 纯函数 / 显式执行 / `|>` 纯管道）——15 文件 | 重构 | ✅ syntax、command-system、standard-library、examples | ✅ writing-conventions | `implement` |
| 2026-07-18 | `Process.sleep` 从 DateTime 模块移回 Process 模块（设计纠错） | 重构 | ✅ standard-library、examples | ✅ writing-conventions | `implement` |
| 2026-07-18 | 恢复 `docs/ai-agent/logs/` 目录与索引（撤销期间误删恢复 + 跨文档一致性修复） | 文档 | ✅ logs/index | ✅ writing-conventions | `implement` |
| 2026-07-18 | 清理：移除版本历史与推迟标注，更新 git author 为 AI 码农 | 清理 | ✅ 全部 owner docs | ✅ writing-conventions | `implement` |
| 2026-07-18 | `Test.body` → `TestCase.body` 跨文档同步重命名（入口级 `handle with` 目标） | 重构 | ✅ 全部 owner docs | ✅ writing-conventions | `implement` |
| 2026-07-18 | `Test` 类型 → `TestCase` Record 重命名 + 新增 `Test` 模块（`test` / `Test.with` / `Test.timeout` / `Test.describe`） | 重构 | ✅ type-system、syntax、standard-library、testing | ✅ writing-conventions | `implement` |
| 2026-07-18 | `handle with` 入口级从 `main` / `test*` 改为 `main` / `TestCase.body` | 重构 | ✅ type-system、syntax、testing | ✅ writing-conventions | `implement` |
| 2026-07-18 | 现有设计文档同步单元测试系统——`Test` 类型值替代 `test*` 函数 | 重构 | ✅ 全部 owner docs | ✅ writing-conventions | `implement` |
| 2026-07-18 | 单元测试系统设计——`Test` 类型值、`_test.kun` 约定、handler 隔离、无黑魔法 | 设计 | ✅ type-system、syntax、standard-library、testing | ✅ writing-conventions | `plan-first` |
| 2026-07-18 | `--audit` JSON 审计记录选项新增（CI / 合规场景追溯） | 设计 | ✅ kun-cli-tool、system-baseline | ✅ writing-conventions | `implement` |
| 2026-07-18 | 沙箱加固——参考 Z-Jail 补齐防御缺口（capabilities drop / fd scrub / dumpable / `CLONE_NEWIPC`） | 重构 | ✅ system-baseline、kun-cli-tool | ✅ writing-conventions | `implement` |
| 2026-07-18 | 效应与模块同名消歧规则新增（如 `Cmd` 既是效应又是模块） | 设计 | ✅ type-system、syntax、standard-library | ✅ writing-conventions | `implement` |
| 2026-07-18 | Zig 0.16.0 稳定版锁定（替换原 0.17.0-dev） | 配置+文档 | ✅ zig-patterns、system-baseline | ✅ writing-conventions | `implement` |
| 2026-07-17 | 零参效应函数约定——声明 `T ! {E}`、调用 `Name!`、区分 `Command !` | 重构 | ✅ type-system、syntax、standard-library | ✅ writing-conventions | `implement` |
| 2026-07-17 | 类型标注与值绑定支持同行形式 `name : Type = expr` | 设计 | ✅ syntax、type-system | ✅ writing-conventions | `implement` |
| 2026-07-17 | 守卫子句改用 `if` 关键字，移除 `when` | 重构 | ✅ syntax、type-system | ✅ writing-conventions | `implement` |
| 2026-07-17 | 设计目录索引更新——文件说明与设计原则同步新设计 | 文档 | ✅ design/index | ✅ writing-conventions | `implement` |
| 2026-07-17 | 工具链与格式化规范更新——`let in` / `--allow-ffi` / `kun test` / 单表达式格式 | 文档 | ✅ kun-cli-tool、code-formatting | ✅ writing-conventions | `implement` |
| 2026-07-17 | 应用概览与功能清单更新——效应系统 / FFI / 录制回放概览、功能状态刷新 | 文档 | ✅ app-overview、feature-inventory | ✅ writing-conventions | `implement` |
| 2026-07-17 | 标准库重设计——7 个内置效应 + `Process` 标准库效应 / `extern` FFI 模块 / Int 位运算 / 录制 / 回放 | 重构 | ✅ standard-library、type-system | ✅ writing-conventions | `plan-first` |
| 2026-07-17 | 命令系统重设计——`Command` ADT / `cmd` 字面量 / 显式执行三入口 | 重构 | ✅ command-system、syntax、standard-library | ✅ writing-conventions | `plan-first` |
| 2026-07-17 | 语法重设计——单表达式 / `let in` 统一 / `effect`/`handler`/`handle` / `cmd` 字面量 | 重构 | ✅ syntax | ✅ writing-conventions | `plan-first` |
| 2026-07-17 | 类型系统重设计——`alias`/`type` 分离 / `==` 浅比较 / 代数效应类型 | 重构 | ✅ type-system | ✅ writing-conventions | `plan-first` |
| 2026-07-17 | **code/kun-lang/ 实现撤销（commit `559180a`）** —— 设计大改动（代数效应 / 命令系统 / `alias`/`type` 分离 / TestCase 测试系统等）导致旧实现不可维护；删除全部源码 + 清理实现相关 logs/plans/audits；保留设计文档；更新 `code/README.md` | 撤销 | ✅ - | ✅ closure-audit | `plan-first` → `research-only` |

## AI 阻塞条件

- `project-context.md` 中的活跃需求为空时，AI 不应实施任何代码变更
- 涉及类型系统核心（ADT、模式匹配、类型推断）变更需先更新 `docs/ai-agent/architecture/` 下的设计文档
- 运行时安全模型（沙箱、Landlock/seccomp）变更需人工确认

