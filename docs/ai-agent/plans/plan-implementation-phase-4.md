# 执行计划：Phase 4 — 效应检查完成 + 命令系统 + HM 完备化

## 背景与目标

Phase 3 完成了基础设施（Primitive 表、ErrorType、typeName、generalize、Value 扩展、Stream 基础、模式穷举、Cmd ident 识别），306 测试全通过。Phase 4 的目标是补齐 Phase 3 推迟的全部功能，并对齐 MVP（v0.1）的完整交付。

## 基线数据

| 维度 | 值 |
|------|-----|
| Phase 3 测试 | **306**（均通过） |
| Phase 3 源码文件 | 10 新建/修改（primitive/value/eval/effect/constraint/error/env/pattern + test_main + 7 测试文件） |
| Phase 3 推迟项 | **12 类**（见下方） |
| 推迟的 effect 函数 | **12 个**（doLetExclusion/doInResult/effectCallback/cmdInDo/pipeCommand/implicitDo/streamConsumption/commandConsumption/unusedBindings/unusedResult/pureExprLast + pureFunctionBody 部分） |
| 未实现的功能 | i18n.zig、execCommand、Stream primitives、HM 约束合一、类型别名、TypedExpr 补全、Stream 变换、Cmd Record |

## Phase 3 推迟项清单

| # | 推迟项 | 备注 |
|---|--------|------|
| 1 | `checkDoLetExclusion` | do/let 互斥检查 |
| 2 | `checkDoInResult` | do-in 结果非 Unit |
| 3 | `checkEffectCallback` | `!` 回调参数匹配 |
| 4 | `checkCmdInDo` | Cmd 效应函数 do 约束 |
| 5 | `checkPipeCommand` | `|>` Command do 约束 |
| 6 | `checkImplicitDo` | 隐式 do 上下文识别 |
| 7 | `checkStreamConsumption` | Stream 消费检查 |
| 8 | `checkCommandConsumption` | Command 消费检查 |
| 9 | `checkUnusedBindings` | 未使用绑定告警 |
| 10 | `checkUnusedResult` | 未消费结果告警 |
| 11 | `checkPureExprLast` | 纯表达式最后语句告警 |
| 12 | `checkPureFunctionBody` | 纯函数体检查（返回 error 而非 emit TypeError） |
| 13 | `i18n.zig` | 错误消息格式化渲染 |
| 14 | `Stream.*` Primitive 注册 | lines/iter/fold/toList/string/bytes |
| 15 | `execCommand` | fork-exec 子进程 |
| 16 | call/lambda/record_access HM 合一 | 类型推断完整性 |
| 17 | 类型别名解析 | 递归展开 + recursive_alias_depth |
| 18 | `record_update` TypedExpr | 记录更新类型推断 |
| 19 | `range_literal` TypedExpr | 范围字面量类型推断 |
| 20 | `ternary` TypedExpr | 三元表达式类型推断 |
| 21 | Stream `mapped`/`filtered` 等变换 | Stream 变换操作 |
| 22 | Cmd Record 选项解析 | camelCase→kebab-case |
| 23 | 代码重复消除 | isKnownCmdApi/hasEffect/isEffectNamespaceCall 统一 |

## 变更范围

### 新建文件

| 文件 | 预估行数 | 说明 |
|------|---------|------|
| `code/kun-lang/src/typecheck/i18n.zig` | ~300 | 23 msgid 模板 + zh_CN/en 内嵌翻译 + TypeError→格式化消息渲染 |
| `code/kun-lang/src/runtime/cmd.zig` | ~200 | `execCommand` fork-exec + `isKnownCmdApi` 统一入口 + `known_cmd_apis` 单例 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `code/kun-lang/src/typecheck/effect.zig` | 12 个存根函数 → 完整实现（do/let 互斥、do-in 验证、! 回调匹配、Cmd do 约束、`\|>` Command 约束、隐式 do、Stream/Command 消费、告警系统） |
| `code/kun-lang/src/typecheck/constraint.zig` | 消除重复代码（hasEffect→effect_mod.hasEffectInExpr）；call/lambda/record_access HM 约束合一；if_expr 统一所有 unify 错误变体；类型别名解析；record_update/range_literal/ternary TypedExpr |
| `code/kun-lang/src/runtime/primitive.zig` | 注册 Stream.* 6 个 Primitive 函数签名 |
| `code/kun-lang/src/runtime/eval.zig` | pipe Command 执行（execCommand 调用）；消除重复 isKnownCmdApi（→ cmd.zig）；record_update/range_literal/ternary eval |
| `code/kun-lang/src/runtime/value.zig` | StreamFn 闭包调用集成 |
| `code/kun-lang/src/typecheck/env.zig` | 类型别名注册 + 递归展开 |

## 实施步骤

### Step 1: 代码重复消除

将 `isKnownCmdApi`、`known_cmd_apis`、`hasEffect`、`isEffectNamespaceCall`、`isEffectCall` 统一到单一模块：
- `constraint.zig` → 删除本地定义，`@import("effect.zig")`
- `eval.zig` → 删除本地 `isKnownCmdApi`，改用 `cmd.zig` 或 `primitive.zig`
- 新建 `cmd.zig` 作为 Cmd 相关工具的单一入口

### Step 2: i18n.zig — 错误消息格式化

实现 `typecheck/i18n.zig`：
- `formatError(allocator, err: TypeError, locale: Locale) ![]const u8`
- 23 msgid 内嵌翻译表（zh_CN + en）
- 21 种 type-system.md 已有模板 + 2 种新增（Empty Body / Duplicate Binding）
- `effect_in_pure` / `effect_in_let` 共用 msgid 含不同 hint
- 集成 `typeName` 递归格式化输出期望/实际类型

### Step 3: effect.zig — 补齐 12 个检查函数

| 函数 | 类型 | 输入 | 逻辑 |
|------|------|------|------|
| `checkDoLetExclusion` | Error | 函数体 AST | 递归遍历，scope 内 do↔let 互斥 |
| `checkDoInResult` | Error | do_block | result 类型非 Unit |
| `checkEffectCallback` | Error | call site | 实参类型 vs EffectFn 参数 |
| `checkCmdInDo` | Error | call site | Cmd.?/! 仅在 do 内 |
| `checkPipeCommand` | Error | pipe node | |> 左侧 Command 仅在 do 内 |
| `checkImplicitDo` | Infra | unbound case/if | 识别隐式 do 分支 |
| `checkStreamConsumption` | Error | do body | AST 穷举消费分析 |
| `checkCommandConsumption` | Error | do body | Command 消费检查 |
| `checkUnusedBindings` | Warn | binding list | 未引用绑定告警 |
| `checkUnusedResult` | Warn | stmt list | 未消费独立语句告警 |
| `checkPureExprLast` | Warn | do body | 最后语句为纯表达式告警 |
| `checkPureFunctionBody` | Error | 函数体 | emit `effect_in_pure` TypeError（替代 return error） |

### Step 4: HM 约束合一 — 类型推断完备化

在 `constraint.zig` 中：
- **call handler**: `unify(func_type ~ Fn(arg_type, result_id))`，emit `function_apply_arg` on mismatch
- **lambda handler**: `unify(param_type ~ ident_ref_type)` for each param used in body
- **record_access handler**: lookup field type + emit `unknown_field` if missing
- **if_expr**: 扩展 unify 错误处理到全部变体（`InfiniteType`/`NilToNonNilable`/`EffectFnPureMismatch` 等）

### Step 5: 类型别名解析

- `env.zig`: 类型别名注册 (`registerAlias`) + 递归展开（256 层上限）
- `constraint.zig`: `type_def` handler 绑定别名 → TypeId
- 到达上限时 emit `recursive_alias_depth`
- `occursCheck` 对 `type` 别名关闭

### Step 6: TypedExpr 补全 — record_update/range_literal/ternary

| 节点 | 类型推断 | 求值 |
|------|---------|------|
| `record_update` | 源 record 类型 + update 字段类型检查 | 构造新 Record value，替换指定字段 |
| `range_literal` | `from`/`to` 统一为 Int → `List Int` | 生成 `[from..to]` 列表 |
| `ternary` | `then`/`else` 类型统一 | 条件求值后选择分支 |

### Step 7: Stream 变换 + Cmd Record 选项

- Stream `mapped`/`filtered`/`taken`/`dropped`/`lines`/`parse_mapped`/`parse_mapped_keep` 构造器
- `Cmd.<bin> { options }` Record 选项解析 + camelCase→kebab-case CLI flag 映射
- `Cmd.ls { long = true } p"/tmp"` → `ls --long /tmp`

### Step 8: execCommand — fork-exec 实现

- `fn execCommand(bin, args, allocator) !*StreamNode`
- Linux `fork()` → child `execve()` + parent `pipe()` 捕获 stdout
- `O_NONBLOCK` fd 设置
- 错误传播：`fork`/`exec`/`pipe` 失败 → `EvalError`
- 在 `eval.zig` 的 pipe 分支集成：`Value.command` 左侧 → `execCommand` 创建 Stream → `apply(right, stream)`

### Step 9: Stream.* Primitive 注册

在 `primitive.zig` 编译期常量表中添加：
- `Stream.lines : Stream String -> Stream (Result String LineError)`
- `Stream.iter : (a -> Unit)! -> Stream a -> Unit`
- `Stream.fold : (b -> a -> b) -> b -> Stream a -> b`
- `Stream.toList : Stream a -> List a`
- `Stream.string : Stream String -> String`
- `Stream.bytes : Stream a -> Bytes`

### Step 10: 集成 + 测试

- 新增测试：effect_full、i18n、stream_transform、cmd_exec、type_alias、record_update/range/ternary
- 回归：306 现有测试全通过
- 闭合审计：独立子代理审查

## 分期里程碑

| 阶段 | 产出 | 验证标准 |
|------|------|---------|
| M1: 代码清理 | isKnownCmdApi/hasEffect 单源 | 编译通过，0 重复 |
| M2: i18n | 23 模板 + zh_CN/en 渲染 | `TypeError` → 格式化消息 |
| M3: 效应补齐 | 12 函数实现 | 纯函数调 IO.println → `effect_in_pure` 格式化错误 |
| M4: HM 完备 | call/lambda/record_access 合一 | `f 42` 类型错误 → `function_apply_arg` |
| M5: 类型别名 | 递归展开 + 深度限制 | `type Tree = { children: List Tree }` 类型推断 |
| M6: TypedExpr 补全 | record_update/range/ternary | `{ r \| x = 1 }` 求值 |
| M7: Stream 变换 | mapped/filtered/taken/dropped/lines | `Cmd.ls \|> Stream.lines \|> Stream.take 5` |
| M8: 命令系统 | execCommand + Record 选项 | `Cmd.ls { long = true } p"/tmp"` fork-exec |
| M9: 集成 | 306 + 新增约 150 测试通过 | `zig build test` 全通过 |

## 风险评估

| 风险 | 缓解措施 |
|------|---------|
| 效应检查复杂度（12 函数） | 逐函数独立实现 + 独立测试，编译错误 7 项优先 |
| fork-exec 子进程管理 | Linux pipe+waitpid+O_NONBLOCK，Phase 4 仅单命令 |
| HM 约束合一破坏性 | 对现有 306 测试保持回归，逐步添加合一约束 |
| 类型别名递归展开 | 256 层上限 + occurs check 选择性启用 |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.22 | 初始版本 |
