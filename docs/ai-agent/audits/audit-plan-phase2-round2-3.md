# 审计记录：Plan Phase 2 第 2–3 轮

## 基本信息

| 字段 | 值 |
|------|-----|
| 审计对象 | `docs/ai-agent/plans/plan-implementation-phase-2.md`（第 1 轮修复后） |
| 审计类型 | 计划审计（第 2–3 轮） |
| 审计日期 | 2026-06-21 |
| 审计者 | AI Agent |
| 对照基线 | `system-baseline.md`, `type-system.md`, `syntax.md`, `conventions.md`, 当前源码 |
| 审计技能 | `skills/plan-audit-prompt.md` |

## 第 2 轮发现（6 项）

| ID | 严重度 | 问题 | 修复 |
|----|--------|------|------|
| R2-1 | P0 | 新建文件表 error.zig 行仍写 `12 个核心`，与 P0-1 修复不一致 | 改为 `10 个核心` |
| R2-2 | P0 | 修改文件表 typed.zig 行写 `7 个缺失`，与基线数据(9个)和 Step 1.1(9个)矛盾 | 改为 `9 个缺失` |
| R2-3 | P1 | `case_expr` 约束 `t_bi 合一` 表意不清 | 改为「所有分支 b_i 的类型 t_bi 互合一为统一类型 t」 |
| R2-4 | P1 | `do_block` 约束未指定类型赋值 | 补充 `result` 存在→`t_result`，不存在→`Unit` |
| R2-5 | P1 | 合一规则表遗漏 `nilable(a) ~ nilable(b)` 结构递归 | 补充该行 |
| R2-6 | P2 | TypeId 预置 0–9 后未说明非预置类型的分配策略 | 补充 `newVar` 从 ID≥10 分配、非预置类型按需动态分配说明 |

## 第 3 轮发现（6 项）

| ID | 严重度 | 问题 | 修复 |
|----|--------|------|------|
| R3-1 | P0 | `call(f, a)` 约束只用 `function(t_a, t)`，效应函数调用时 `effect_fn ~ function` 合一失败 → 所有效应函数调用被拒绝 | 改为两步合一：已实例化则用对应构造器，变量则尝试 function 再 effect_fn |
| R3-2 | P0 | `lambda(p, b)` 约束总是 `function(t_p, t_b)`，效应 Lambda 体应产生 `effect_fn` | 按函数体效应性自动选择 function/effect_fn |
| R3-3 | P0 | 合一规则表遗漏 6 种结构类型自身递归规则：`set`/`stream`/`map`/`tuple`/`effect_fn(:self)`/`adt` | 补充全部遗漏的结构合一规则 |
| R3-4 | P0 | `effect_fn ~ fn` 命名不一致（表用 `fn`，Type 用 `function`） | 统一为 `function` |
| R3-5 | P1 | 约束表未覆盖 `pipe`/`pipe_reverse`/`compose`/`compose_reverse`/`tuple_literal`/`set_literal`/`map_literal` | 全部补充（pipe 脱糖为 call，compose 为组合函数类型，tuple/map/set 为结构约束） |
| R3-6 | P2 | 约束表中的 `++` 规则 `t_l ~ String\|List(a)` 为析取约束，标准 HM 不直接支持 | 保留为意图表达，实现时按两阶段合一处理（先试 String，再试 List） |

## 结论

第 1–3 轮共计发现 30 项问题（R1:18 + R2:6 + R3:6），全部已修复。第 4 轮（最终扫视）零新问题，markdownlint 通过。计划现可进入实施阶段。
