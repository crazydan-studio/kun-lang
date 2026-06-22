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
| 缺失的效应检查 | **1 个**（checkPureUnitReturn——error.zig 已定义 `pure_unit_return` 变体，但无实现函数） |

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
| 26 | IO + File/Env/Process Primitive 实现 | 实现 `IO.println`（写 stdout）、`IO.readln`（读 stdin）、`File.readString`/`File.list`/`File.stat`、`Env.getenv`/`Env.contains`、`Process.exit`/`Process.pid`/`Process.uid`/`Process.gid`、`Cmd.which` 的函数体。`Env.list` 推迟 Phase 5（需 Map 哈希表基础设施） |
| 27 | 模块导入解析 | `import IO` / `import Cmd` → 绑定 Primitive 表到 Frame 的模块命名空间 |

## 变更范围

### 新建文件

| 文件 | 预估行数 | 说明 |
|------|---------|------|
| `code/kun-lang/src/typecheck/i18n.zig` | ~300 | 27 msgid 模板（21 错误类型 + 4 元数据标签 + 2 新增） + zh_CN/en 内嵌翻译 + TypeError→格式化消息渲染 |
| `code/kun-lang/src/runtime/cmd.zig` | ~200 | `execCommand` fork-exec + `isKnownCmdApi` 统一入口 + `known_cmd_apis` 单例 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `code/kun-lang/src/typecheck/effect.zig` | 11 个存根函数 → 完整实现；新增 `checkPureUnitReturn`（error.zig 已定义 `pure_unit_return` 但无实现）；`checkPureFunctionBody` 改造为 emit TypeError（替代 return error.EffectInPure） |
| `code/kun-lang/src/ast/typed.zig` | `TypedExpr` union 新增 `record_update`/`range_literal`/`ternary` 三个变体类型定义（AST Expr 中已存在对应 AST 节点，但 TypedExpr 尚未定义——当前 constraint.zig:505 遇到此三节点返回 `error.Unimplemented`） |
| `code/kun-lang/src/typecheck/constraint.zig` | 接线效应检查——在 `inferExpr` 的 `let_in`/`do_block`/`lambda`/`call`/`pipe` 分支插入 effect.zig 检查函数调用；消除重复代码（hasEffect→effect_mod.hasEffectInExpr）；call/lambda/record_access HM 约束合一；if_expr 统一所有 unify 错误变体；ident handler freshInstance 集成（Let 多态修复）；类型别名解析；record_update/range_literal/ternary 约束生成（替换 `error.Unimplemented`） |
| `code/kun-lang/src/runtime/primitive.zig` | `RuntimeEnv` 新增 `evalFn` 字段（供 `Stream.iter`/`Stream.fold` 调用闭包）；新增 File/Env/Process/Cmd PrimitiveBinding 条目（当前仅 IO.println/IO.readln 2 个）；注册 Stream.* 6 个 Primitive 函数签名；实现 IO.println/IO.readln/File.readString/File.list/File.stat/Env.getenv/Env.contains/Process.exit/Process.pid/Process.uid/Process.gid/Cmd.which 函数体（`Env.list` 推迟 Phase 5——需 Map 哈希表基础设施） |
| `code/kun-lang/src/runtime/eval.zig` | `evalModule` 签名扩展接收 `PrimitiveTable` 参数并赋值 Frame；ident handler PrimitiveTable 查询集成（`frame.lookup()` 失败后查 `frame.primitives`）；pipe Command 执行（execCommand 调用）；消除重复 isKnownCmdApi（→ cmd.zig）；record_update/range_literal/ternary eval |
| `code/kun-lang/src/runtime/env.zig` | `Frame` 结构体新增 `primitives: ?PrimitiveTable` 字段（需处理与 primitive.zig 的循环 import） |
| `code/kun-lang/src/main.zig` | 调用 `buildPrimitiveTable()` 构造表，传入 `evalModule` |
| `code/kun-lang/src/runtime/value.zig` | StreamNode 变换变体构造逻辑（mapped/filtered/taken/dropped/lines/parse_mapped/parse_mapped_keep）+ StreamFn Closure 调用集成。注：`mapped` 等非 `lines` 变体构造器为 Phase 5 PureKun 函数准备，Phase 4 仅 `lines` 被 Primitive 调用 |
| `code/kun-lang/src/typecheck/env.zig` | 类型别名注册 + 递归展开 |

## 实施步骤

### Step 0: subst allocator 修复

**前置依赖**：无（Phase 3 遗留 Bug）

修复 Phase 3 `typecheck/constraint.zig` 中 `subst.put` 使用 arena allocator 而 `deinit` 使用 test allocator 的不一致——导致 call handler 创建函数类型时触发 double-free。具体修复：统一 `subst` 的构造和销毁使用同一个 allocator 实例（arena），或确保 `deinit` 使用与 `subst.put` 配对的 allocator 引用。修复后运行 `zig build test` 确认无 allocator 相关 panic 后进入后续步骤。

### Step 1: Primitive 表运行时集成 + IO/File/Env 实现

**前置依赖**：Step 0（subst allocator 修复完成后测试可正常运行）

**现状**：Phase 3 定义了 `buildPrimitiveTable()`（comptime 构造 PrimitiveBinding 数组），但该函数仅在测试中调用，主代码路径（`main.zig` → `evalModule`）从未构造或传递 PrimitiveTable——`IO.println` 等所有 Primitive 函数均不可调用。

**实施**：

**1a. PrimitiveTable 接入运行时管道**（`main.zig` + `eval.zig` + `runtime/env.zig`）：
- `main.zig`：在 `infer()` 之后、`evalModule()` 之前，调用 `buildPrimitiveTable(int_t, string_t, unit_t, stream_string_t)` 构造表（comptime 常量，编译期完成），传入 `evalModule`
- `eval.zig:evalModule`：签名扩展为 `fn evalModule(decls, allocator, primitives: PrimitiveTable) !void`，将 `primitives` 赋值给全局 `Frame.primitives` 字段
- `runtime/env.zig:Frame`：新增 `primitives: ?PrimitiveTable` 字段。注：需在文件顶部通过 `@import("primitive.zig")` 导入 `PrimitiveTable` 类型，或使用指针间接避免循环依赖。`env.zig` 当前已导入 `value.zig`（`Value` 类型），`primitive.zig` 导入 `value.zig` 和 `env.zig`（`Frame`），新增 `primitives` 字段会导致循环 import。解决方案：将 `PrimitiveTable` 类型定义移至独立文件 `runtime/primitive_types.zig`，或使用 `?*anyopaque` + 运行时类型擦除

- `eval.zig` ident handler：`frame.lookup()` 失败后 → 若 `frame.primitives` 存在 → 将 ident 名（如 `"IO.println"`）按第一个 `.` 拆为 `module`（`"IO"`）和 `name`（`"println"`）→ 遍历 `primitives.bindings` 匹配 `module` + `name` → 返回 `Value{ .primitive = binding.fn_ptr }`
- 在 `runtime/primitive.zig` 的 `buildPrimitiveTable()` 中**新增** `File`、`Env`、`Process` 模块的 `PrimitiveBinding` 条目（当前仅含 `IO.println`/`IO.readln` 2 个，且 `_ = int_t; _ = stream_string_t;` 两个 typeId 闲置）
- 实现 `IO.println` 函数体（已实现，确认可工作）、`IO.readln`（读 stdin）
- 实现 `File.readString`/`File.list`/`File.stat` 函数体（Zig 文件系统 API，含 `Result` 返回类型封装）
- 实现 `Env.getenv`/`Env.contains` 函数体。`Env.list : Map String String` 需哈希表构造基础设施（`MapRepr` 的创建/插入），当前运行时无哈希表实现——推迟至 Phase 5（与 Map/Set 标准库 Primitive 一同实现）
- 实现 `Process.exit`/`Process.pid`/`Process.uid`/`Process.gid` 函数体。`Process.exit` 调用 `std.os.exit(n)` 立即终止进程——属破坏性操作，须在 `do` 块内使用（效应检查保证）。
- 实现 `Cmd.which` 函数体（PATH 查找，返回 `?Path`）
- 模块导入解析：`import Xxx` → 将 Primitive 表对应模块的 bindings 注册到全局 Frame（Phase 4 最小实现——仅处理 Primitive 表内模块，见注）

> **模块导入注**：Phase 4 的 import 为最小三层实现：
> 1. **类型检查层**（constraint.zig）：将 import 的模块名注册到类型环境的已知模块集合，ident 解析时若模块已导入，允许 PrimitiveTable 查找通过（否则报 `UnboundVariable`）
> 2. **运行时层**（eval.zig:evalModule）：`import` 声明在求值阶段为 no-op——模块绑定不注册到 Frame（Primitive 函数通过 ident handler 直接查 `frame.primitives`，无需 Frame 绑定中转）
> 3. **不涉及**：文件系统搜索路径、`.kun` 文件递归加载、循环依赖检测——完整模块系统推迟至 Phase 5。Phase 4 仅需支持 `import IO`/`import Env`/`import File`/`import Process`/`import Cmd`/`import Stream` 等 Primitive 模块的导入。
>
> **`apply` RuntimeEnv 脆弱性注**：`eval.zig:apply` 当前创建 `RuntimeEnv{ .frame = undefined, .primitives = undefined }` 后调用 primitive 函数。Phase 4 的 Primitive 函数（IO.println、Env.getenv 等）均为独立 syscall 包装、不访问 frame/primitives，此状态可接受。但若后续实现需访问 Frame 的 Primitive 函数（如 `Env.list` 需分配 Map 到 Arena），须重构 `apply` 传入有效的 frame/primitives 引用。Phase 4 确认当前函数集不触发 UB。

### Step 2: 效应检查补齐 — 11 存根 + 1 改造 + 1 新增 + constraint 接线

**前置依赖**：Step 1（效应检查依赖 Primitive 表的 `is_effect` 标记识别效应命名空间）

**现状**：Phase 3 在 `effect.zig` 中定义了全部效应检查函数签名，但全部 14 个函数（含已实现的 `checkDuplicateBindings`/`checkEmptyBody`/`checkLetInPurity`）在 constraint.zig 中均无调用点——它们从未被集成到类型检查流程中。

**实施**：分两层执行：
1. constrant.zig 接线——在 `inferExpr` 的 `let_in`/`do_block`/`lambda` 等分支中插入效应检查调用
2. 效应检查函数体实现——补齐 11 个存根 + `checkPureFunctionBody` 改造 + 新增 `checkPureUnitReturn`

> **类型依赖注**：下表中标注 ⚠️ 的检查（`checkDoInResult`/`checkEffectCallback`/`checkStreamConsumption`/`checkCommandConsumption`/`checkPureUnitReturn`）依赖 HM 推断产出的类型信息（如 do-in 结果类型、EffectFn vs Fn 区分、表达式的推断类型）。这些检查的函数体可在 Step 2 实现，但其 constraint.zig 接线应延后至 Step 3（HM 合一）完成后进行。AST 级检查（`checkDoLetExclusion`/`checkCmdInDo`/`checkPipeCommand`/`checkImplicitDo`/告警 3 项/`checkPureFunctionBody`）无此限制，可在 Step 2 中完全实施。

| 函数 | 类型 | 逻辑 | constraint.zig 接线点 |
|------|------|------|----------------------|
| `checkDoLetExclusion` | Error | 递归遍历函数体 AST，scope 内 do↔let 互斥 | `let_in` 和 `do_block` 分支入口 |
| `checkDoInResult` | Error ⚠️ | do_block result 类型非 Unit | `do_block` 分支推断 result 后 |
| `checkEffectCallback` | Error ⚠️ | 实参类型 vs EffectFn 参数 | `call` 分支：识别 `!` 参数位置 |
| `checkCmdInDo` | Error | Cmd.?/! 等效应函数仅在 do 内合法 | `call` 分支：识别效应函数名 |
| `checkPipeCommand` | Error | `|>` 左侧 Command 仅在 do 内合法 | `pipe` 分支 |
| `checkImplicitDo` | Infra | unbound case/if 分支识别为隐式 do | `do_block` 内 `case`/`if` 子分支 |
| `checkStreamConsumption` | Error ⚠️ | do body AST 穷举消费分析 | `do_block` 分支：遍历 body 后 |
| `checkCommandConsumption` | Error ⚠️ | do body Command 消费检查 | `do_block` 分支：遍历 body 后 |
| `checkUnusedBindings` | Warn | 未引用绑定告警 | `let_in`/`do_block` 作用域结束时 |
| `checkUnusedResult` | Warn | 未消费独立语句告警 | `do_block` 各语句后 |
| `checkPureExprLast` | Warn | do body 最后语句为纯表达式告警 | `do_block` 分支最后语句 |
| `checkPureFunctionBody` | Error | emit `effect_in_pure` TypeError（替代 return error） | `lambda` 分支：识别为纯函数时 |
| `checkPureUnitReturn` | Error ⚠️ | 纯函数返回 `Unit` 类型 → emit `pure_unit_return` TypeError（**新增**，error.zig 已定义 `pure_unit_return` 变体但无实现函数） | `lambda` 分支：推断返回类型后 |

> **告警覆盖率注**：type-system.md 共定义 7 项告警场景（lines 411-419）。Step 2 覆盖其中 5 项——`checkUnusedBindings`（未引用绑定 + 绑定到 `_`）、`checkUnusedResult`（未消费独立语句）、`checkPureExprLast`（纯表达式最后语句）。其余 2 项——顶级 `do` 无效应调用和隐式 `do` 分支无效应调用——是 `checkImplicitDo` 告警子规则的扩展，在本步骤中同函数实现。

### Step 3: HM 约束合一 — 类型推断完备化

**前置依赖**：Step 0（subst allocator 修复，否则 call handler 创建函数类型时 double-free）

- **call handler**: `unify(func_type ~ Fn(arg_type, result_id))`，emit `function_apply_arg` on mismatch
- **lambda handler**: `unify(param_type ~ ident_ref_type)` for each param used in body
- **record_access handler**: lookup field type + emit `unknown_field` if missing
- **if_expr**: 扩展 unify 错误处理到全部变体

### Step 4: Let 多态 — freshInstance 集成

**前置依赖**：Step 3（HM 合一完成后类型推断正确，freshInstance 才能获得正确的泛化类型）

- ident handler：若名称匹配 let 绑定 → local type env → `freshInstance()` 实例化
- 局部类型环境（`StringHashMapUnmanaged(TypeId)`）在 `let_in` 中存储泛化后类型

### Step 5: i18n.zig — 错误消息格式化

**前置依赖**：无（Phase 3 已定义全部 ErrorType 变体和 typeName，i18n 仅消费已有结构）

- `formatError(allocator, err: TypeError, locale: Locale) ![]const u8`
- 25 msgid 内嵌翻译表（type-system.md 21 错误类型 + 4 元数据标签 Expected/Found/Hint/Reason）+ 2 Phase 3 新增（Empty Body/Duplicate Binding）= 27 模板
- 集成 `typeName` 递归格式化

### Step 6: execCommand — fork-exec 实现

**前置依赖**：Step 1（eval.zig ident handler 已能查找 Primitive 表 + Cmd.<bin> ident 已识别为 command_t）

- `fn execCommand(bin, args, allocator) !*StreamNode`
- 系统契约（对齐 `system-baseline.md`「Command 执行的系统契约」章节）：
  - `fork()` → 子进程 `execve()` + 父进程 `pipe2()` 捕获 stdout
  - stderr 透传到父进程（`mergeStderr` 时合并到 stdout pipe）
  - stdin 继承父进程（`/dev/null` 或外部管道）
  - `O_NONBLOCK` fd 设置
  - `waitpid` 回收子进程
  - PATH 解析：运行时查找可执行文件（`NotFound` panic）
- 错误传播：`fork`/`exec`/`pipe` 失败 → `EvalError`。需在 `eval.zig` 的 `EvalError` 集合中新增 `CommandNotFound`、`CommandPermissionDenied`、`CommandFailed`、`IoError` 变体（当前仅有 `TypeMismatch`/`UnboundVariable`/`NotAFunction` 等 8 个变体，缺少命令相关错误）
- eval.zig pipe 分支：`Value.command` → `execCommand` → Stream → `apply(right, stream)`

### Step 7: Stream 变换 + Primitive 注册

**前置依赖**：Step 6（StreamNode 已有 `cmd` 变体，变换操作在其上包装新变体）

- **StreamNode 构造器实现**（runtime/value.zig）：Phase 3 已定义全部 8 个 `StreamNode` union 变体类型（`cmd`/`mapped`/`filtered`/`taken`/`dropped`/`lines`/`parse_mapped`/`parse_mapped_keep`）及 `StreamFn` 类型。Phase 4 仅需实现各变体的**构造逻辑**——创建新 `StreamNode`（Arena 分配）包装上游、填充对应字段。注：`mapped`/`filtered`/`taken`/`dropped`/`parse_mapped`/`parse_mapped_keep` 的构造器由 PureKun 函数（`Stream.map`/`Stream.filter` 等）调用——这些 PureKun 函数推迟至 Phase 5。Phase 4 仅 `lines` 构造器被 `Stream.lines` Primitive 函数使用，其余变体构造函数为 Phase 5 准备基础设施。
- **Primitive 函数注册**（runtime/primitive.zig）：注册 `Stream.lines`/`Stream.iter`/`Stream.fold`/`Stream.toList`/`Stream.string`/`Stream.bytes` 共 6 个 Primitive 签名并实现函数体。注意：`Stream.iter`（`(a -> Unit)! -> Stream a -> Unit`）和 `Stream.fold`（`(b -> a -> b) -> b -> Stream a -> b`）的回调参数为 Kun 闭包（`Closure`），需在 Primitive 内部调用闭包。当前 `PrimitiveFn` 无权访问 `eval()`。需在 `RuntimeEnv` 中新增 `evalFn` 函数指针字段，由 `eval.zig:apply` 注入，供 `Stream.iter`/`Stream.fold` 实现中调用闭包。

### Step 8: Cmd Record 选项解析

**前置依赖**：Step 6（execCommand 可用，选项解析为其构造 argv）

- `Cmd.<bin> { options }` → camelCase→kebab-case 映射（对齐 `command-system.md`「camelCase → kebab-case 选项映射」章节：多大写断词、全小写不断词、单字符短 flag、Bool=false/Nil 省略、List 重复 flag）
- argv 生成顺序：Record 选项 → `Cmd.withRawOpt` 追加 → `--` 分隔符 → 位置参数

### Step 9: TypedExpr 补全

**前置依赖**：Step 3（HM 合一完成，类型推断可生成 record_update/range_literal/ternary 节点的 TypedExpr）

- **typed.zig**：在 `TypedExpr` union 中新增 `record_update`/`range_literal`/`ternary` 变体类型定义（AST Expr 已存在对应节点，但 TypedExpr 未定义——当前 constraint.zig:505 遇此三节点返回 `error.Unimplemented`）
- `record_update`：constraint.zig 生成类型约束（原 Record 类型 + 更新字段类型合一）+ eval.zig 求值（复制源 Record、覆盖更新字段）
- `range_literal`：constraint.zig 约束为 `Stream Int`（委托 `Stream.range`）+ eval.zig 构造 Stream 值
- `ternary`：constraint.zig 约束 then/else 分支类型合一 + eval.zig 条件分发求值

### Step 10: 类型别名解析

**前置依赖**：Step 3（HM 合一完成后类型环境完整，别名解析在合一过程中进行递归展开）

- `env.zig`: `registerAlias` + 递归展开（256 层上限，含交叉递归别名 A→B→A 支持）
- occurs check 对 `type` 别名声明选择性关闭

### Step 11: 代码重复消除 + 集成测试

**前置依赖**：Steps 0-10 全部完成

- **`hasEffect`/`hasEffectInExpr`**: `constraint.zig:555` 与 `effect.zig:14` 为独立的 AST 递归遍历（~60 行重复），合并为 `effect.zig` 单一实现
- **`isKnownCmdApi`**: `eval.zig:163` 与 `constraint.zig:648` 完全重复（15 项 API 数组），移至 `cmd.zig` 单例
- **`isEffectNamespaceCall`**: 统一点为 `primitive.zig:isEffectBinding`（Phase 3 已实现 `effect.zig` 和 `constraint.zig` 委托于此，本步骤确认消除纯代码重复）
- 新增测试：runtime/test_primitive_full.zig (20)、typecheck/test_effect_full.zig (30)、typecheck/test_i18n.zig (25)、runtime/test_stream_transform.zig (15)、runtime/test_cmd_exec.zig (20)、typecheck/test_type_alias.zig (10)、typecheck/test_typed_expr.zig — record_update/range/ternary (15)、typecheck/test_hm_unify.zig (15)、typecheck/test_fresh_instance.zig (10)、typecheck/test_module_import.zig (10)、runtime/test_cmd.zig — code_dedup (5) — 合计 ~175 测试
- 回归 306 通过

## 验证方法

| 验证项 | 方法 |
|--------|------|
| 构建通过 | `zig build` |
| 单元测试 | `zig build test`（含新增 test_primitive_full/test_effect_full/test_i18n/test_stream_transform/test_cmd_exec/test_type_alias/test_typed_expr/test_hm_unify/test_fresh_instance/test_module_import 测试文件；需同步更新 `src/test_main.zig` 的 `@import` 列表） |
| 回归 | Phase 3 的 306 测试全通过 |
| IO.println | `kun --run` 执行含 `IO.println "hi"` 的脚本 |
| Cmd 执行 | `kun --run` 执行 `Cmd.echo "hi" \|> Stream.toList` 经 fork-exec 捕获 stdout |
| Cmd.? | `kun --run` 执行 `Cmd.echo? "hi"` 经 fork-exec 返回 Result |
| 效应检查 | 纯函数调用 IO.println → `effect_in_pure` 格式化错误输出 |
| 效应检查 | 纯函数返回 Unit 类型 → `pure_unit_return` 格式化错误输出 |
| HM 合一 | `f 42` 类型错误 → `function_apply_arg` 格式化错误输出 |
| Let 多态 | `let id = \x -> x in (id 42, id "hi")` 两个实例化类型不同 |
| i18n | `KUN_LOCALE=zh_CN kun --run` → 中文错误消息 |
| Stream | `Cmd.ls \|> Stream.lines \|> Stream.toList` 求值（注：`Stream.take`/`Stream.filter` 为 PureKun 函数推迟 Phase 5，Phase 4 仅上述 6 个 Primitive 可用） |
| Cmd Record | `Cmd.ls { long = true } p"/tmp"` → `--long` flag 生成 |
| 类型别名 | `type Tree = ...` 递归展开 256 层上限 |

## 分期里程碑

| 阶段 | 产出 | 验证标准 |
|------|------|---------|
| M0: subst 修复 | `subst.put` 与 `deinit` allocator 一致 | `zig build test` 无 allocator 相关 panic（double-free） |
| M1: 运行时集成 | Primitive 表 eval 查询 + IO/File/Env 实现 | `IO.println "hi"` 经 `kun --run` 输出 |
| M2: 效应补齐 | 11 存根 + 1 改造 + 1 新增 + constraint 接线 | 纯函数调 IO.println → `effect_in_pure` 格式化错误；纯函数返回 Unit → `pure_unit_return` 错误 |
| M3: HM 完备 | call/lambda/record_access 合一 | `f 42` 类型错误 → `function_apply_arg` |
| M4: Let 多态 | freshInstance + local type env | `let id = \x -> x in (id 42, id "hi")` 正确推断 |
| M5: i18n | 27 模板 + zh_CN/en 渲染 | `TypeError` → 格式化消息 |
| M6: 命令调用 | execCommand fork-exec | `Cmd.ls?` 子进程 stdout 捕获 |
| M7: Stream 变换 | lines 构造器 + 6 Primitive | `Cmd.ls \|> Stream.lines \|> Stream.toList` |
| M8: Cmd Record | camelCase→kebab-case 选项解析 | `Cmd.ls { long = true } p"/tmp"` 类型检查 |
| M9: TypedExpr | record_update/range/ternary eval | `{ r \| x = 1 }` 求值 |
| M10: 类型别名 | 递归展开 + 深度限制 | `type Tree = ...` 类型推断 |
| M11: 集成 | 306 + 新增 ~175 测试通过 | `zig build test` 全通过 |

## 风险评估

| 风险 | 缓解措施 |
|------|---------|
| subst allocator 不一致（Phase 3 遗留） | Step 0 独立处理——双分配器引用统一后 `zig build test` 验证无 double-free |
| env.zig ↔ primitive.zig 循环 import | `PrimitiveTable` 类型提取到独立文件 `primitive_types.zig`，或 `Frame.primitives` 使用 `?*anyopaque` + 运行时类型擦除 |
| 效应检查复杂度（13 函数 + constraint 接线） | 逐函数独立实现 + 独立测试 + constraint 接线按分支逐点集成，编译错误 8 项优先 |
| fork-exec 子进程管理 | Linux pipe+waitpid+O_NONBLOCK，Phase 4 仅单命令 |
| HM 约束合一破坏性 | 对现有 306 测试保持回归，逐步添加合一约束 |
| 类型别名递归展开 | 256 层上限 + occurs check 选择性启用 |
| Let 多态环境管理 | 局部类型环境仅在 `let_in` scope 内有效，不影响其他 ident 推断 |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.22 | Round 13 审计修复：发现 `typed.zig` 的 `TypedExpr` union 缺少 `record_update`/`range_literal`/`ternary` 变体定义（AST Expr 中存在但 TypedExpr 未定义，constraint.zig:505 当前返回 `error.Unimplemented`）→ 新增 `typed.zig` 到修改文件表 + Step 9 补充变体类型定义步骤 |
| 2026.06.22 | Round 7 审计修复：发现 Step 2（效应检查）中 5 项类型依赖检查（`checkDoInResult`/`checkEffectCallback`/`checkStreamConsumption`/`checkCommandConsumption`/`checkPureUnitReturn`）需 HM 推断类型，但 Step 2 排在 Step 3（HM 合一）之前 → 添加类型依赖注记，标注 ⚠️ 项的函数体可在 Step 2 实现但接线延后至 Step 3；验证测试计数精确求和 = 175 |
| 2026.06.22 | Round 6 审计修复：发现 `Stream.iter`/`Stream.fold` 需在 Primitive 内部调用 Kun 闭包，但当前 `PrimitiveFn` 无 `eval()` 访问权限 → Step 7 明确需 `RuntimeEnv.evalFn` 注入机制；确认 `hasEffect`/`hasEffectInExpr`/`isKnownCmdApi` 代码重复位置精确（constraint.zig:555 vs effect.zig:14，eval.zig:163 vs constraint.zig:648） |
| 2026.06.22 | Round 5 审计修复：发现 `buildPrimitiveTable()` 仅存在测试调用、主代码路径从未构造或传递 PrimitiveTable（evalModule 不含 primitives 参数、Frame 无 primitives 字段）→ Step 1 重写为 3 层（main.zig 构造表 → evalModule 传递 → Frame 字段存储 → ident 查询）；新增 `main.zig` 和 `runtime/env.zig` 修改；新增循环 import 风险及缓解方案 |
| 2026.06.22 | Round 4 审计修复：Step 1 补充 Primitive ident `module.name` 拆分逻辑 + `Process.exit` 破坏性语义 + `apply` RuntimeEnv 脆弱性注记；Step 6 补充 EvalError 缺失命令变体（需新增 `CommandNotFound` 等）；Step 7 澄清 StreamNode 类型定义已在 Phase 3 完成，仅需构造逻辑 |
| 2026.06.22 | Round 3 审计修复：发现效应检查函数零调用点（effect.zig 全部 14 个函数未被 constraint.zig 接线）→ 新增接线任务 + 接线点列；补充缺失的 `checkPureUnitReturn`（error.zig 已有 `pure_unit_return` 变体但无实现）；告警覆盖率说明（7→5+2 归并）；风险/里程碑数同步（12→13 函数） |
| 2026.06.22 | Round 2 审计修复：所有步骤添加前置依赖标注；澄清 Primitive 表新增 Entry（当前仅 2 个 IO 条目→新增 File/Env/Process/Cmd.which 条目）；新增 Cmd.which 实现到 Step 1；Step 7 分离 StreamNode 构造器与 Primitive 注册描述；Step 8 扩展 camelCase→kebab-case 映射设计引用；Step 9 详化 TypedExpr per-node 约束/求值分工；Step 10 补充交叉递归别名说明；模块导入范围添加限制说明（Phase 4 最小实现）；测试文件指定目录路径 |
| 2026.06.22 | Round 1 审计修复：Env.get/Env.set/Process.args → Env.getenv/Env.list/Env.contains/Process.uid/Process.gid（对齐 standard-library.md）；i18n 模板计数 23→27 统一；新增 Step 0 subst allocator 修复 + M0 里程碑；新增验证方法章节；精确化测试文件清单（10 文件 ~175 测试替代「约 200」）；修复脆弱行号引用；isEffectBinding 描述修正为 Phase 3 已完成 |
| 2026.06.22 | 初始版本 |
