# 审计记录：Plan Phase 2 第 7–8 轮

## 基本信息

| 字段 | 值 |
|------|-----|
| 审计对象 | `docs/ai-agent/plans/plan-implementation-phase-2.md`（第 1–6 轮修复后） |
| 审计类型 | 计划审计（第 7–8 轮） |
| 审计日期 | 2026-06-21 |
| 审计者 | AI Agent |
| 对照基线 | `system-baseline.md`, `type-system.md`, `syntax.md`, `conventions.md`, `zig-patterns.md`, 当前源码 |
| 审计技能 | `skills/plan-audit-prompt.md` |

## 第 7 轮发现（7 项）

| ID | 严重度 | 问题 | 修复 |
|----|--------|------|------|
| R7-1 | P1 | `apply` 函数在 eval.zig 的 `call` 分支中使用但完全未定义。闭包应用逻辑（创建新帧、绑定参数、求值函数体）是求值器核心机制 | 新增 `apply` 函数签名与实现伪代码 |
| R7-2 | P1 | `case_expr` 求值仅标注 `/* pattern match dispatch */`，未描述模式匹配分发策略（逐 branch 测试、变量绑定、ADT/Nilable/字面量/元组/Record 匹配） | 新增模式匹配分发策略高层次描述 |
| R7-3 | P1 | `binary_op` 求值标注 `/* ... */`，未描述类型感知的分发逻辑（Int/Float 算术、Bool 逻辑短路、String 拼接、比较、nil 合并短路） | 新增二元运算分发策略描述 |
| R7-4 | P1 | `BinaryOp.range`（`..` 运算符）在约束表和 eval 中均未提及。与 `range_literal` 一起应推迟 Phase 3+ | 在 binary_op 约束规则中添加 `range` 推迟说明 |
| R7-5 | P2 | `case_expr` 约束使用 `t_s ~ pattern_type` 但 `pattern_type` 非独立类型——scrutinee 类型由表达式推断得出 | 改为「从 scrutinee s 推断 t_s；验证 t_s 支持模式匹配」 |
| R7-6 | P2 | `TypedDecl.function_def.type_: Type` 与全局 TypeId 表示不一致（其余类型引用均为 TypeId） | 改为 `type_: TypeId` |
| R7-7 | P2 | `TypedDecl.type_def.type_: Type` 同样与 TypeId 方案不一致 | 改为 `type_: TypeId` |

## 第 8 轮发现（0 项）

第 8 轮进行全面扫描：markdownlint 通过、约束规则语义验证、eval 逻辑完整性检查、TypeId 一致性验证、Arena 生命周期验证、Zig 0.17 API 一致性验证。**零新问题**。

## 结论

第 7 轮发现 7 项（P1×4, P2×3），全部已修复。第 8 轮零新问题。累计 6 轮审计共修复 45 项问题（R1:18 + R2:6 + R3:6 + R5:7 + R6:1 + R7:7）。计划可进入实施阶段。
