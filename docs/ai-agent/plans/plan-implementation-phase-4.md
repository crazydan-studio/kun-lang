# 执行计划：Phase 4 — 效应检查完成 + 命令系统 + HM 完备化

## 背景与目标

Phase 3 完成了基础设施（Primitive 表、ErrorType、typeName、generalize、Value 扩展、Stream 基础、模式穷举、Cmd ident 识别），306 测试全通过。Phase 4 的目标是补齐 Phase 3 推迟的核心功能——效应检查完成 + 命令系统 + HM 完备化。注意：完整 MVP（v0.1）还包含 ~50 项标准库 Primitive 实现（List/Map/Set/String/Int/Float/Regex/Hash 等）和 CLI 沙箱，这些推迟至 Phase 5。

## 基线数据

| 维度 | 值 |
|------|-----|
| Phase 3 测试 | **306**（均通过） |
| Phase 3 推迟项 | **27 项**（11 effect 存根 + 1 effect 部分实现 + 15 功能模块） |
| 推迟的 effect 存根 | **11 个**（doLetExclusion/doInResult/effectCallback/cmdInDo/pipeCommand/implicitDo/streamConsumption/commandConsumption/unusedBindings/unusedResult/pureExprLast） |
| 推迟的 effect 部分实现 | **1 个**（checkPureFunctionBody——returns error.EffectInPure，需改为 emit TypeError） |

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
| 16 | call/lambda/record_access HM 合一 | 类型推断完整性——注：需先修复 Phase 3 中 `subst.put` 与 `deinit` 的 allocator 不一致（subst 用 arena allocator、deinit 用 test allocator），否则 call handler 创建函数类型时触发 double-free |
| 17 | 类型别名解析 | 递归展开 + recursive_alias_depth |
| 18 | `record_update` TypedExpr | 记录更新类型推断 |
| 19 | `range_literal` TypedExpr | 范围字面量类型推断 |
| 20 | `ternary` TypedExpr | 三元表达式类型推断 |
| 21 | Stream `mapped`/`filtered` 等变换 | Stream 变换操作 |
| 22 | Cmd Record 选项解析 | camelCase→kebab-case |
| 23 | 代码重复消除 | isKnownCmdApi/hasEffect/isEffectNamespaceCall 统一 |
| 24 | `freshInstance` 集成到 ident 查找 | Phase 3 中 `generalize()` 已实现但 ident handler 从未调用 `freshInstance()`——Let 多态仅靠巧合工作，需在 ident handler 中查本地类型环境并实例化泛化类型 |
| 25 | Primitive 表 → eval.zig ident 查找 | Phase 3 注册了 Primitive 函数签名，但 eval.zig ident handler 仅查 Frame（`frame.lookup`），从未查询 PrimitiveTable——`IO.println` 等注册后不可调用 |
| 26 | IO + File/Env/Process Primitive 实现 | 实现 `IO.println`（写 stdout）、`IO.readln`（读 stdin）、`File.readString`/`File.list`/`File.stat` 等体的函数体 |
| 27 | 模块导入解析 | `import IO` / `import Cmd` → 绑定 Primitive 表到 Frame 的模块命名空间 |

## 变更范围

### 新建文件

| 文件 | 预估行数 | 说明 |
|------|---------|------|
| `code/kun-lang/src/typecheck/i18n.zig` | ~300 | 23 msgid 模板 + zh_CN/en 内嵌翻译 + TypeError→格式化消息渲染 |
| `code/kun-lang/src/runtime/cmd.zig` | ~200 | `execCommand` fork-exec + `isKnownCmdApi` 统一入口 + `known_cmd_apis` 单例 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `code/kun-lang/src/typecheck/effect.zig` | 11 个存根函数 → 完整实现；`checkPureFunctionBody` 改造为 emit TypeError（替代 return error.EffectInPure） |
| `code/kun-lang/src/typecheck/constraint.zig` | 消除重复代码（hasEffect→effect_mod.hasEffectInExpr）；call/lambda/record_access HM 约束合一；if_expr 统一所有 unify 错误变体；ident handler freshInstance 集成（Let 多态修复）；类型别名解析；record_update/range_literal/ternary TypedExpr |
| `code/kun-lang/src/runtime/primitive.zig` | 注册 Stream.* 6 个 Primitive 函数签名；实现 IO.println/IO.readln/File.readString/File.list/File.stat/Env.get/Process.exit 函数体 |
| `code/kun-lang/src/runtime/eval.zig` | ident handler PrimitiveTable 查询集成（`frame.lookup()` 失败后查 Primitive 表）；pipe Command 执行（execCommand 调用）；消除重复 isKnownCmdApi（→ cmd.zig）；record_update/range_literal/ternary eval |
| `code/kun-lang/src/runtime/value.zig` | StreamFn 闭包调用集成 |
| `code/kun-lang/src/typecheck/env.zig` | 类型别名注册 + 递归展开 |

## 实施步骤

### Step 1: Primitive 表运行时集成 + IO/File/Env 实现

Phase 3 注册了 Primitive 签名但 eval.zig 从未查询——所有 Primitive 函数不可调用。
- `eval.zig` ident handler：`frame.lookup()` 失败后 → 查询 PrimitiveTable（按 `module.name` 匹配）→ 返回 `Value{ .primitive = binding.fn_ptr }`
- 实现 `IO.println` 函数体（写 stdout）、`IO.readln`（读 stdin）
- 实现 `File.readString`/`File.list`/`File.stat` 函数体（Zig 文件系统 API）
- 实现 `Env.get`/`Env.set` 函数体
- 实现 `Process.exit`/`Process.pid`/`Process.args` 函数体
- 模块导入解析：`import Xxx` → 将 Primitive 表对应模块的 bindings 注册到全局 Frame

### Step 2: 效应检查补齐 — 11 存根 + 1 改造

| 函数 | 类型 | 逻辑 |
|------|------|------|
| `checkDoLetExclusion` | Error | 递归遍历函数体 AST，scope 内 do↔let 互斥 |
| `checkDoInResult` | Error | do_block result 类型非 Unit |
| `checkEffectCallback` | Error | 实参类型 vs EffectFn 参数 |
| `checkCmdInDo` | Error | Cmd.?/! 等效应函数仅在 do 内合法 |
| `checkPipeCommand` | Error | `|>` 左侧 Command 仅在 do 内合法 |
| `checkImplicitDo` | Infra | unbound case/if 分支识别为隐式 do |
| `checkStreamConsumption` | Error | do body AST 穷举消费分析 |
| `checkCommandConsumption` | Error | do body Command 消费检查 |
| `checkUnusedBindings` | Warn | 未引用绑定告警 |
| `checkUnusedResult` | Warn | 未消费独立语句告警 |
| `checkPureExprLast` | Warn | do body 最后语句为纯表达式告警 |
| `checkPureFunctionBody` | Error | emit `effect_in_pure` TypeError（替代 return error） |

### Step 3: HM 约束合一 — 类型推断完备化

- **call handler**: `unify(func_type ~ Fn(arg_type, result_id))`，emit `function_apply_arg` on mismatch
- **lambda handler**: `unify(param_type ~ ident_ref_type)` for each param used in body
- **record_access handler**: lookup field type + emit `unknown_field` if missing
- **if_expr**: 扩展 unify 错误处理到全部变体
- 前置：修复 Phase 3 `subst.put`（arena allocator）与 `deinit`（test allocator）不一致

### Step 4: Let 多态 — freshInstance 集成

- ident handler：若名称匹配 let 绑定 → local type env → `freshInstance()` 实例化
- 局部类型环境（`StringHashMapUnmanaged(TypeId)`）在 `let_in` 中存储泛化后类型

### Step 5: i18n.zig — 错误消息格式化

- `formatError(allocator, err: TypeError, locale: Locale) ![]const u8`
- 25 msgid 内嵌翻译表（type-system.md 21 错误类型 + 4 元数据标签 Expected/Found/Hint/Reason）+ 2 Phase 3 新增（Empty Body/Duplicate Binding）= 27 模板
- 集成 `typeName` 递归格式化

### Step 6: execCommand — fork-exec 实现

- `fn execCommand(bin, args, allocator) !*StreamNode`
- 系统契约（对齐 `system-baseline.md:630-639`）：
  - `fork()` → 子进程 `execve()` + 父进程 `pipe2()` 捕获 stdout
  - stderr 透传到父进程（`mergeStderr` 时合并到 stdout pipe）
  - stdin 继承父进程（`/dev/null` 或外部管道）
  - `O_NONBLOCK` fd 设置
  - `waitpid` 回收子进程
  - PATH 解析：运行时查找可执行文件（`NotFound` panic）
- 错误传播：`fork`/`exec`/`pipe` 失败 → `EvalError`
- eval.zig pipe 分支：`Value.command` → `execCommand` → Stream → `apply(right, stream)`

### Step 7: Stream 变换 + Primitive 注册

- `mapped`/`filtered`/`taken`/`dropped`/`lines`/`parse_mapped`/`parse_mapped_keep` 构造器
- 注册 `Stream.*` 6 个 Primitive 签名

### Step 8: Cmd Record 选项解析

- `Cmd.<bin> { options }` → camelCase→kebab-case 映射

### Step 9: TypedExpr 补全

- `record_update` / `range_literal` / `ternary` 类型推断 + 求值

### Step 10: 类型别名解析

- `env.zig`: `registerAlias` + 递归展开（256 层上限）

### Step 11: 代码重复消除 + 集成测试

- **`hasEffect`/`hasEffectInExpr`**: `constraint.zig:555` 与 `effect.zig:14` 为独立的 AST 递归遍历（~60 行重复），合并为 `effect.zig` 单一实现
- **`isKnownCmdApi`**: `eval.zig:163` 与 `constraint.zig:648` 完全重复（15 项 API 数组），移至 `cmd.zig` 单例
- **`isEffectNamespaceCall`**: 统一点为 `primitive.zig:isEffectBinding`（`effect.zig` 和 `constraint.zig` 均委托于此）
- 新增测试：primitive_full、effect_full、i18n、stream_transform、cmd_exec、type_alias、record_update/range/ternary
- 回归 306 通过

## 分期里程碑

| 阶段 | 产出 | 验证标准 |
|------|------|---------|
| M1: 运行时集成 | Primitive 表 eval 查询 + IO/File/Env 实现 | `IO.println "hi"` 经 `kun --run` 输出 |
| M2: 效应补齐 | 11 存根 + 1 改造函数实现 | 纯函数调 IO.println → `effect_in_pure` 格式化错误 |
| M3: HM 完备 | call/lambda/record_access 合一 | `f 42` 类型错误 → `function_apply_arg` |
| M4: Let 多态 | freshInstance + local type env | `let id = \x -> x in (id 42, id "hi")` 正确推断 |
| M5: i18n | 23 模板 + zh_CN/en 渲染 | `TypeError` → 格式化消息 |
| M6: 命令调用 | execCommand fork-exec | `Cmd.ls?` 子进程 stdout 捕获 |
| M7: Stream 变换 | mapped/filtered + 6 Primitive | `Cmd.ls \|> Stream.lines \|> Stream.take 5` |
| M8: Cmd Record | camelCase→kebab-case 选项解析 | `Cmd.ls { long = true } p"/tmp"` 类型检查 |
| M9: TypedExpr | record_update/range/ternary eval | `{ r \| x = 1 }` 求值 |
| M10: 类型别名 | 递归展开 + 深度限制 | `type Tree = ...` 类型推断 |
| M11: 集成 | 306 + 新增约 200 测试通过 | `zig build test` 全通过 |

## 风险评估

| 风险 | 缓解措施 |
|------|---------|
| 效应检查复杂度（12 函数） | 逐函数独立实现 + 独立测试，编译错误 7 项优先 |
| fork-exec 子进程管理 | Linux pipe+waitpid+O_NONBLOCK，Phase 4 仅单命令 |
| HM 约束合一破坏性 | 对现有 306 测试保持回归，逐步添加合一约束；先修复 subst allocator 不一致 |
| 类型别名递归展开 | 256 层上限 + occurs check 选择性启用 |
| Let 多态环境管理 | 局部类型环境仅在 `let_in` scope 内有效，不影响其他 ident 推断 |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.22 | 初始版本 |
