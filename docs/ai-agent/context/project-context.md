# 项目上下文

## 项目身份

| 字段 | 值 |
|---|---|
| 项目名称 | Kun（鲲） |
| 项目类型 | 编程语言设计与实现 |
| 当前版本 | 0.1.0（Phase 4 实现完成） |
| 目标用户 | Linux 系统管理员、DevOps 工程师、需要编写 Shell 脚本的开发者 |
| 里程碑 | 架构重设计完成，语言设计定型，Phase 1-4 实现完成（Lexer→Parser→TypeCheck→Eval→Primitive→Effect→i18n→Cmd 全管线） |
| 宿主语言 | Zig（锁定 0.17.0-dev，版本包 `/opt/ai-agent/tools/zig-x86_64-linux-0.17.0-dev.387+31f157d80.tar.xz`） |
| 目标平台 | Linux |
| 许可证 | Apache 2.0 |

## 活跃工作

| 维度 | 当前值 |
|---|---|---|
| 活跃需求 | 语言核心设计与类型系统定义（定型）、语法设计（定型 — 单一表达式范式定稿）、标准库类型设计（定型）、运行时架构设计（定型）、命令调用系统设计（定型）、安全隔离设计（定型 — 实现推迟 v0.2）、Kun Shell 设计（定型）[推迟 v2.0]、类型检查算法设计（定型）、CLI 工具功能（定型）、模块系统搜索路径设计（定型 — Phase 6 实施） |
| Owner Doc | `docs/ai-agent/design/type-system.md`、`docs/ai-agent/design/syntax.md`、`docs/ai-agent/design/standard-library.md`、`docs/ai-agent/architecture/system-baseline.md`、`docs/ai-agent/architecture/module-boundaries.md`、`docs/ai-agent/design/kun-shell.md`、`docs/ai-agent/design/kun-cli-tool.md` |
| 活跃计划 | Phase 5 进行中：标准库 Primitives 补全 + Stream 函数体；Phase 6 待启动：模块系统搜索路径；CLI 沙箱推迟至 v0.2 |
| 最近完成 | Phase 4 实现：PrimitiveTable 管道 + 12 Primitive 实现 + 效应检查接线（8/11 函数）+ i18n.zig（24 msgid 中英双语）+ cmd.zig（isKnownCmdApi 去重）+ TypedExpr 补全（record_update/range_literal/ternary）+ Phase 1-3 深度审计修复（44 项缺陷）+ 双代理测试审计（314→545 测试，7 轮收敛） |
| AI 自治级别 | `implement` |
| 阻塞项 | 无 |

## 技术基线

| 层 | 技术栈 |
|---|---|
| 语言实现 | Zig 0.17.0-dev（宿主语言，版本锁定，版本包 `/opt/ai-agent/tools/`） |
| 运行时 | fork-exec + pipe 捕获 stdout/stderr |
| 二进制产物 | `kun`（脚本执行器）+ `libkunlang.so`（共享解释器核心）；`kun-shell`（交互式环境）[推迟 v2.0] |
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
| 单元测试 | `cd code/kun-lang && zig build test` |
| 解析验证 | `cd code/kun-lang && zig build dump-ast -- <file.kun>` |

## 最近任务路由

| 日期 | 任务 | 分类 | Owner Docs 检查 | Skills 检查 | 路由决策 |
|------|------|------|----------------|------------|---------|
| 2026-06-23 | Phase 5 计划编写：标准库 Primitives 补全（106 函数）+ Stream 函数体 + StreamNode 构造器/消费者 + 类型环境签名注册 | 计划 | ✅ 全部 owner docs | ✅ plan-audit（待执行） | `plan-first` |
| 2026-06-23 | Phase 4 实现 + 计划审计（18 轮 52 项修复）+ Phase 1-3 深度审计修复（44 项缺陷）+ 双代理测试审计（314→545 测试 7 轮收敛）+ i18n 重构 | 实现+审计 | ✅ 全部 owner docs | ✅ plan-audit、closure-audit | `implement` |
| 2026-06-22 | Phase 3 实现：Primitive 函数表 + 效应识别迁移 + 14 TypeError + recursive typeName + generalize()/freshInstance + 18 项效应检查 + Value 9 变体 + StreamNode + map/set eval + Cmd ident + 模式穷举升级 | 实现 | ✅ 全部 owner docs | ✅ plan-audit、closure-audit | `implement` |
| 2026-06-22 | Phase 3 计划 23 轮审计（77 项修复）+ 双代理测试审计（+59 测试 → 306 全通过）+ 3 轮实现审计（修复 20 项） | 审计+测试 | ✅ 全部 owner docs | ✅ plan-audit、closure-audit、multi-dim | `implement` |
| 2026-06-21 | Phase 2 实现：类型检查器 + 运行时求值器 + 12 测试文件（229 测试全通过）；效应识别方案 C；构建打包脚本 | 实现 | ✅ 全部 owner docs | ✅ plan-audit、closure-audit | `implement` |
| 2026-06-21 | Phase 2 计划 15 轮审计（67 项修复）+ 5 份审计记录 + 活跃文档同步 | 审计+文档 | ✅ 全部 owner docs | ✅ plan-audit、document-audit | `implement` |
| 2026-06-20 | 第 8 轮审计修复：skipTypeAnn 停止消费 ident（修复跨行类型标注+函数定义） | 审计+修复 | ✅ syntax、zig-patterns | ✅ plan-audit | `implement` |
| 2026-06-20 | 文档元审计（第7轮）：同步 backlog/导航/版本历史 | 文档 | ✅ - | ✅ writing-conventions | `implement` |
| 2026-06-20 | 第 6 轮审计：移除死函数 exprSpan + typed.zig 接入编译 | 清理 | ✅ - | ✅ closure-audit | `implement` |
| 2026-06-20 | 第 5 轮深度审计修复：大写进制前缀/MapSet/联合变体/双行函数/case终结 | 审计+修复 | ✅ syntax、zig-patterns | ✅ plan-audit | `implement` |
| 2026-06-20 | 第 4 轮构建修复：dump-ast cwd | 修复 | ✅ - | ✅ - | `implement` |
| 2026-06-20 | 第 3 轮审计修复：export 语法/??语义/优先级表全对齐 | 审计+修复 | ✅ syntax、type-system | ✅ plan-audit | `implement` |
| 2026-06-20 | 双代理审计循环（第2轮源码实现审计）→ 修复 P0×3+P1×6：整数前缀/??/字符串转义/? token/Duration 溢出等 | 审计+修复 | ✅ syntax、type-system、zig-patterns | ✅ plan-audit | `implement` |
| 2026-06-20 | 双代理审计循环（第1轮测试审计）→ 测试从 51 增至 68，零泄漏 | 审计+修复 | ✅ syntax、system-baseline、zig-patterns | ✅ plan-audit、closure-audit | `plan-first` → `implement` |
| 2026-06-20 | 首阶段 Zig 代码实现 — build.zig + Lexer + AST + Parser + CLI dump-ast | 实现 | ✅ system-baseline、syntax、module-boundaries、zig-patterns | ✅ writing-conventions、plan-audit | `plan-first` → `implement` |
| 2026-06-20 | 首阶段实现计划（骨架 + Lexer + Parser + AST）编写 | 计划 | ✅ system-baseline、module-boundaries、syntax、zig-patterns | ✅ writing-conventions | `plan-first` |
| 2026-06-19 | 单一表达式范式全面定稿——设计讨论、7 份文档重写、跨文档一致性修复、Test 模块效应分类修正、9 示例文件迁移 | 设计+重构 | ✅ 全部 owner docs | ✅ writing-conventions | `implement` |
| 2026-06-17 | File 模块 API 精简（移除 `isDir`/`isFile`/`isSymlink`/`exists`→`Stat` 纯访问器）；示例修复（Verifier.kun `let…in`+`do`、Builder.kun+Dockerizer.kun `File.stat` 适配） | 设计+修复 | ✅ standard-library、syntax、examples | ✅ writing-conventions | `implement` |
| 2026-06-16 | 标准库模块必要性分析与精简（移除 5 模块 + 19 函数、新增 4 项 P0、跨 14 文件传播） | 设计+重构 | ✅ 全部 owner docs | ✅ writing-conventions、closure-audit | `implement` |
| 2026-06-15 | Zig 0.13 → 0.17 宿主语言升级——分析版本文档、更新所有版本引用、重写 zig-patterns.md 惯用模式指南 | 配置+文档 | ✅ zig-patterns、system-baseline、language-evaluation、project-context | ✅ writing-conventions | `implement` |
| 2026-06-15 | 错误消息国际化（i18n）子系统设计——msgid 体系、.po 文件管理、构建时代码生成、运行时 locale 检测、消息格式化 API | 设计 | ✅ system-baseline、module-boundaries、type-system、i18n | ✅ writing-conventions | `plan-first`（先计划后实施） |
| 2026-06-15 | 标准库内置函数绑定机制设计——Primitive 函数表结构、模块加载绑定规则、安全防护（防同名覆盖/防篡改）、逐函数实现类别标注 | 设计 | ✅ system-baseline、module-boundaries、standard-library | ✅ writing-conventions | `plan-first`（先计划后实施） |
| 2026-06-13 | 八轮跨文档一致性审计（52+ 项修复）；REPL → Kun Shell 独立文档；kun doc/--trace 设计；类型检查算法补充；libkunlang.so 共享库架构 | 设计+审计 | ✅ 全部 owner docs | ✅ document-audit、closure-audit | `implement` |
| 2026-06-10 | 架构重设计——架构/设计/示例文档全面重写 | 设计+重构 | ✅ 全部 owner docs | ✅ document-audit-prompt、closure-audit-prompt | `plan-first` → `implement`（先审后实施） |
| 2026-06-07 | AGENTS.md 完整性修订（补齐全目录索引 + 跨文档一致性修复 10 项） | 文档+修复 | ✅ AGENTS.md、context/、process/、skills/ | ✅ writing-conventions、closure-audit | `implement` 直接执行 |
| 2026-06-07 | 架构与设计文档全面分析评审（12 份文档/5500 行交叉分析） | 分析+审计 | ✅ system-baseline、type-system、syntax | ✅ document-audit、multi-dimensional-audit | `implement` 直接执行 |
| 2026-06-07 | 示例代码未定义函数修复 + Path 模块文档化 | 修复 | ✅ syntax、standard-library、examples | ✅ writing-conventions | `implement` 直接执行 |
| 2026-06-07 | 目录索引完整性检查补齐（5 个目录/16 项） | 文档 | ✅ 全部 index.md | ✅ writing-conventions | `implement` 直接执行 |

## AI 阻塞条件

- `project-context.md` 中的活跃需求为空时，AI 不应实施任何代码变更
- 涉及类型系统核心（ADT、模式匹配、类型推断）变更需先更新 `docs/ai-agent/architecture/` 下的设计文档
- 运行时安全模型（沙箱、Landlock/seccomp）变更需人工确认

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.23 | 版本路线图重构：模块系统搜索路径提升至 v0.1；CLI 沙箱推迟至 v0.2；Cli.parse/show + Parser.Record + Random.* + 类型化命令模块 + Hash.md5 提升至 v0.3；Task.spawn/all 提升至 v0.4；kun doc 推迟至 v0.5；Test 推迟至 v1.2；移除 PlantUML 图表任务 |
| 2026.06.23 | Phase 4 实现完成：PrimitiveTable 管道 + 12 Primitive + 效应接线（8/11）+ i18n.zig（24 msgid）+ cmd.zig + TypedExpr 补全 + Phase 1-3 深度审计（44 项修复）+ 双代理测试审计（545 测试收敛） |
| 2026.06.22 | Phase 3 实现完成：Primitive 表 + 效应迁移 + 14 ErrorType + typeName/generalize + 效应检查 + Value 9 变体 + StreamNode + map/set eval + Cmd ident + 模式穷举；计划 23 轮审计（77 项修复）；双代理测试审计（306 全通过）；3 轮实现审计（20 项修复） |
| 2026.06.21 | Phase 2 实现完成（typecheck + runtime + 229 测试）+ 效应识别方案 C + Phase 1 审计修复 + 构建打包脚本 |
| 2026.06.20 | Phase 1 全部 8 轮审计完成：skipTypeAnn 修复；75 测试全通过零泄漏 |
| 2026.06.20 | 第 7 轮元审计：文档基础设施同步（backlog/导航/版本历史） |
| 2026.06.20 | 第 6 轮清理：移除死函数 exprSpan + typed.zig 接入编译 |
| 2026.06.20 | 第 5 轮深度审计：6 项 P0 修复（大写进制前缀/MapSet/联合变体/双行函数/case终结） |
| 2026.06.20 | 第 4 轮构建修复：dump-ast cwd |
| 2026.06.20 | 第 3 轮审计：export 语法/??语义/优先级表全对齐 + 8 新测试 |
| 2026.06.20 | 双代理审计第2轮（源码实现审计）— 修复整数前缀/??/字符串转义/? token/Duration 溢出等 11 项；68 测试全通过零泄漏 |
| 2026.06.20 | 双代理审计第1轮（测试审计）— 测试从 51 增至 68；修复运算符优先级/.. spread/! token/全局 arena/测试泄漏 |
| 2026.06.20 | 首阶段 Zig 代码实现完成 — build.zig/Lexer/AST/Parser/CLI dump-ast；项目进入可构建状态 |
| 2026.06.20 | 首阶段实现计划创建（骨架+Lexer+Parser+AST）——活跃计划更新、验证命令补充 |
| 2026.06.19 | 单一表达式范式全面定稿——活跃工作/最近完成/任务路由更新 |
| 2026.06.18 | Kun Shell 标注 [推迟 v2.0]，二进制产物更新（`kun-shell` 标记推迟） |
| 2026.06.17 | File 模块 API 精简（移除 `isDir`/`isFile`/`isSymlink`/`exists`）；示例重构（`File.stat` 替代多函数） |
| 2026.06.17 | 标准库精简 + 跨文档一致性传播 |
| 2026.06.16 | 持续设计审计与修复——活跃工作/任务路由更新 |
| 2026.06.10 | 初始版本 |
