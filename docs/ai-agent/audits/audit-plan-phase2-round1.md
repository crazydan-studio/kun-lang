# 审计记录：Plan Phase 2 第 1 轮

## 基本信息

| 字段 | 值 |
|------|-----|
| 审计对象 | `docs/ai-agent/plans/plan-implementation-phase-2.md` |
| 审计类型 | 计划审计 |
| 审计日期 | 2026-06-21 |
| 审计者 | AI Agent |
| 对照基线 | `system-baseline.md`, `type-system.md`, `syntax.md`, `zig-patterns.md`, `conventions.md`, 当前源码 |
| 审计技能 | `skills/plan-audit-prompt.md` |

## 发现汇总

共 18 项：P0×6, P1×6, P2×6

### P0（必须修复——已全部修复）

| ID | 问题 | 修复 |
|----|------|------|
| P0-1 | 错误模板数量不一致：表头"12" vs 正文"10"，deferred 列表 12 项 vs 实际应为 14 项 | 重写为清晰的 10/21+3 分类，补充遗漏的 `FunctionApplyArg`/`IfBranchMismatch` 项 |
| P0-2 | Value.list 缺 `cap` 字段（`system-baseline.md` 要求 `Array { ptr, len, cap }`） | 添加 `cap: usize` |
| P0-3 | Typed AST 架构与 system-baseline wrapper 设计不一致，未说明 | 新增「架构设计决策」节，说明独立联合体方案的优劣与选型理由 |
| P0-4 | 约束生成未覆盖用户定义函数的 effect_fn/function 自动分类规则 | 在 Step 4 新增「用户定义函数的效应分类」规则节 |
| P0-5 | Value.tuple 缺少元素数量信息 | 经复查不成立：`items: []const Value` 通过 `items.len` 提供元素数量，无需额外字段 |
| P0-6 | Mismatch 模板不能完全覆盖 FunctionApplyArg/IfBranchMismatch 的上下文信息 | 在错误模板节中添加退化处理说明（MVP 用通用 Mismatch + span 定位，参数序号/分支名推迟 Phase 3+） |

### P1（应修复——已全部修复）

| ID | 问题 | 修复 |
|----|------|------|
| P1-1 | `custom` 变体从 Type 中消失，迁移到 `adt`/`record` 的路径未说明 | 在 Step 1.2 添加迁移路径说明 |
| P1-2 | 模式穷举检查未覆盖 `guard` 变体交互 | 在 Step 6 补充 guard 模式的穷举判定规则（等价于 inner 模式，条件不影响覆盖） |
| P1-3 | `unbound_type` 错误在 Phase 2 可能无触发场景 | 添加注释：只在使用类型标注且引用非基础类型时触发，为 Phase 3+ 保护性预留 |
| P1-4 | do_block 伪代码未展示 defer 执行 | 重写 do_block 伪代码，包含完整 DeferStack LIFO 执行流 |
| P1-5 | 未指定测试文件组织结构 | 在验证方法表中添加测试文件路径（`test_env.zig`, `test_unify.zig` 等） |
| P1-6 | 错误恢复机制未在实施步骤中描述 | 在 Step 7 新增错误恢复流程 4 步骤描述 |

### P2（建议修复——已全部修复）

| ID | 问题 | 修复 |
|----|------|------|
| P2-1 | pattern_type 规则过于简略，未覆盖复合模式收窄 | 扩展为 6 条规则，补充标识符模式、元组模式逐位置收窄、Record 模式逐字段收窄 |
| P2-2 | Value 的 string/bytes/path 未标注 Arena 生命周期 | 添加注释标注 Arena 分配与脚本同生命周期 |
| P2-3 | Closure 缺 `arity` 字段 | 添加说明：省略 arity（柯里化单参恒为 1），system-baseline 保留 arity 仅用于未来 C ABI |
| P2-4 | 验证方法覆盖场景不足 | 新增 4 个验证场景：嵌套 let in、嵌套 do 块 defer、穷举通过、类型收窄 |
| P2-5 | binary_op 的 `++` 约束规则表述歧义 | 修正为 `t_l ~ t_r` 且 `t_l ~ String|List(a)`, `t := t_l`，消除歧义 |
| P2-6 | 基线数据表 Phase 2/Phase 3+ 边界不够清晰 | 问题轻微，已在 P0-3 的架构决策节中补充说明 |

## 结论

第 1 轮审计 18 项问题已全部修复。计划可进入第 2 轮审计。
