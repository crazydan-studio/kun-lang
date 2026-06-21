# 执行计划：Phase 2 — 类型检查器 + 运行时求值器 MVP

## 背景与目标

Phase 1 完成了词法分析器、语法分析器、AST 定义、CLI 骨架。Phase 2 的目标是实现**最小可行类型检查器**和**最小可行运行时求值器**，使 Kun 语言能够对简单程序执行完整的"源码→解析→类型检查→求值"流程。

**产出**：`kun` 可执行文件接受脚本文件，执行类型检查后运行，输出程序结果。

## 架构设计决策

> **Typed AST 结构选型**：`system-baseline.md§Typed AST` 定义 TypedExpr 为 wrapper（`expr: *const Expr` + `ty: TypeId`）。Phase 1 实现选择了**独立平行联合体**方案（TypedExpr 每种变体直接包含 typed 字段），优劣如下：
> - 优势：求值器单层 switch 分发（无二次解引用）、类型字段含义明确（无隐藏的 ty 字段）、Zig comptime 分支覆盖检查覆盖所有变体
> - 代价：TypedExpr 需独立维护变体集（与 Expr 同步更新）、内存占用略增（部分字段重复）
> - 结论：Phase 2 延续独立联合体方案。若后续 Expr 变体增长至 40+ 时，复查 wrapper vs 联合体方案

## 基线数据

| 维度 | 值 |
|------|-----|
| `Expr` 总变体 | **32**（`ast.zig`） |
| `TypedExpr` 现有变体 | **20**（`typed.zig`） |
| Phase 2 需补齐的 TypedExpr 变体 | **9**（`duration_literal`, `path_literal`, `regex_literal`, `bytes_literal`, `pipe_reverse`, `compose`, `compose_reverse`, `map_literal`, `set_literal`） |
| Phase 3+ 补齐的 TypedExpr 变体 | **3**（`record_update`, `range_literal`, `ternary`—对应 Expr 中 parser 尚未产生这些变体） |
| Phase 1 测试 | **75**（均通过） |

## 变更范围

### 新建文件

| 文件 | 预估行数 | 说明 |
|------|---------|------|
| `code/kun-lang/src/typecheck/env.zig` | ~200 | Type 联合体、TypeId、TypeEnv（类型池），补充 level 字段用于 HM 泛化 |
| `code/kun-lang/src/typecheck/unify.zig` | ~300 | 合一求解器：变量代换、occurs check、结构合一 |
| `code/kun-lang/src/typecheck/constraint.zig` | ~400 | 约束生成：遍历 AST 生成类型方程，Let 多态泛化/实例化 |
| `code/kun-lang/src/typecheck/effect.zig` | ~300 | 效应检查：do 块标记、纯函数约束、do/let 互斥、do in 验证、效应命名空间识别 |
| `code/kun-lang/src/typecheck/pattern.zig` | ~300 | 模式穷举检查、类型收窄 |
| `code/kun-lang/src/typecheck/infer.zig` | ~150 | 类型推断顶层入口：协调约束生成→合一→Typed AST 输出 |
| `code/kun-lang/src/typecheck/error.zig` | ~200 | 结构化错误类型 + 消息模板（10 个核心 MVP 模板） |
| `code/kun-lang/src/runtime/value.zig` | ~250 | Value 联合体（覆盖 Type 中所有有运行时表示的变体） |
| `code/kun-lang/src/runtime/env.zig` | ~150 | 帧栈：作用域链、变量查找 |
| `code/kun-lang/src/runtime/eval.zig` | ~550 | 标记 switch 求值器：TypedExpr 节点分发 |
| `code/kun-lang/src/runtime/defer.zig` | ~80 | defer LIFO 栈（嵌套 do 块）。每个 do_block 有独立 DeferStack，退出时 LIFO 逆序执行注册的 defer 表达式。panic 展开时也执行 defer。Frame 由 Arena 分配，无独立 deinit |

### 修改文件

| 文件 | 变更 |
|------|------|
| `code/kun-lang/src/ast/typed.zig` | 补全 9 个缺失的 TypedExpr 变体 + Type 表示重构（柯里化单参 function, variable 含 level）+ Stmt.kind 补 `defer_` 变体（`defer_: struct { expr: *const TypedExpr }`） + 所有 TypedExpr 变体添加 `span: Span` 字段 |
| `code/kun-lang/src/main.zig` | 集成类型检查 + 执行流程 |
| `code/kun-lang/src/lib.zig` | 导出 typecheck/runtime 模块 |
| `code/kun-lang/build.zig` | 依赖路径更新 |

### 暂不实现（Phase 3+）

- `runtime/primitive.zig`（Primitive 函数表）— 标准库绑定阶段
- Stream 惰性求值— Phase 3
- i18n 错误消息完整体系— Phase 3
- Cmd.\<bin\> 命令调用— Phase 3
- 完整标准库— Phase 3+
- Stream/Command 消费检查（效应分析）— Phase 3
- `map_literal`/`set_literal` 类型检查+求值— Value 表示推迟到 Phase 3+
- `record_update`, `range_literal`, `ternary` 类型检查+求值— 对应 parser 实现后

### 不在 MVP 的错误模板（10 个核心 vs 21 个完整模板）

Phase 2 MVP 实现以下 10 个核心**错误消息模板**。`type-system.md` 定义的其余 11 个模板（`FunctionApplyArg`, `IfBranchMismatch`, `TooManyArgs`, `EffectCallbackMismatch`, `NilableUsedAsT`, `RedundantPattern`, `TupleIndexOutOfRange`, `CommandNotConsumed`, `StreamNotConsumed`, `RecursiveAliasDepth`, `PureUnitReturn`）推迟到 Phase 3+。其中 `FunctionApplyArg`/`IfBranchMismatch` 在 MVP 中由通用 `Mismatch` 模板退化处理（span 定位到错误位置，缺失参数序号/分支名上下文）。

> **注**：`EffectInLet`（let in 含效应调用）、`EmptyBody`（do/let 空 body）、`DuplicateBinding`（变量重复绑定）三项的**检测逻辑**在 Step 5 中实现并报告编译错误，但使用通用错误消息。其专用错误消息模板推迟 Phase 3+。

## 实施步骤

### Step 1: 补全 Typed AST 定义 + 类型表示重构

**前置依赖**：无

#### 1.1 补充 9 个缺失的 TypedExpr 变体

```zig
duration_literal, path_literal, regex_literal, bytes_literal,
pipe_reverse, compose, compose_reverse,
map_literal, set_literal,
```

`record_update`, `range_literal`, `ternary` 对应 parser 尚未产生这些 Expr 变体，推迟到 Phase 3+。

#### 1.2 Type 联合体重构

对齐 `system-baseline.md` 的设计，移除 `void`（Kun 无 void 类型）。当前 `typed.zig` 的 `custom` 变体迁移为 `adt`（和类型定义）和 `record`（积类型定义），`custom` 不再保留——Phase 1 的 `type_def`/`type_alias` 声明在 Phase 2 统一由 `TypedDecl.function_def` 与内联 Record 类型替代，`custom` 的泛型参数由 HM 类型变量代换处理：

```zig
pub const Type = union(enum) {
    int, float, bool, string, char, bytes, unit,
    path, duration, regex, decimal_t, command_t, datetime_t,
    nilable: TypeId,
    list: TypeId,
    map: struct { key: TypeId, value: TypeId },
    set: TypeId,
    stream: TypeId,
    tuple: []const TypeId,
    record: []const RecordFieldType,
    function: struct { param: TypeId, result: TypeId },  // 柯里化单参
    effect_fn: struct { param: TypeId, result: TypeId },
    adt: struct { name: []const u8, variants: []const AdtVariant },
    variable: struct { id: u32, level: u32 },
    error_: void,  // 类型错误占位
};

pub const RecordFieldType = struct { name: []const u8, type_: TypeId };

pub const AdtVariant = struct { name: []const u8, payload: []const TypeId };
```

> `Unit` 仅用于函数签名中指代无返回值的效应函数。无字面量，不可绑定变量。纯函数返回类型不可为 `Unit`。

关键变更：
- 函数类型从多参 `params: []const Type` 改为柯里化 `param: TypeId, result: TypeId`
- `variable` 增加 `level: u32` 字段（HM Let 多态泛化的前提条件）
- 所有类型引用从 `*const Type` 改为 `TypeId`（Arena 索引），涉及：`Type.nilable`、`Type.list`、`Type.map`、`Type.set`、`Type.stream`、`Type.tuple`（元素类型）、`Type.function`/`Type.effect_fn`（参数/返回值）
- `nilable` 从 `*const Type` 改为 `TypeId`
- `Param.type_` 从 `Type` 改为 `TypeId`（同步 Type 表示重构）
- `Branch.type_`、`Stmt.type_`、`TypedExpr.type_` 从 `Type` 改为 `TypeId`
- `char_literal.value` 从 `u21` 改为 `u32`（对齐 `system-baseline.md§基础类型`：Char 运行时表示为 u32）

#### 1.3 TypedExpr 增加 Span 字段

所有 `TypedExpr` 变体增加 `span: Span` 字段（从对应 `Expr` 传播），用于错误报告中的源码位置定位。

#### 1.4 TypedDecl 定义

```zig
pub const TypedDecl = struct {
    kind: union(enum) {
        import: struct { module: []const u8, alias: ?[]const u8 },
        export_: struct { names: []const []const u8 },
        type_def: struct { name: []const u8, type_: TypeId },
        function_def: struct {
            name: []const u8,
            params: []const Param,    // Param.type_ 已重构为 TypeId
            body: *const TypedExpr,
            type_: TypeId,             // 在 TypeEnv 中分配的函数类型
            is_effect: bool,
        },
    },
    span: Span,
};
```

#### 1.5 pattern_type 确定规则

`pattern_type` 由 scrutinee 类型和模式结构共同确定：
- 字面量模式：`pattern_type := literal_type`（如 `42` → `Int`）
- 变体模式：`pattern_type := adt_variant_type`（如 `Ok v` → `Result T E` 中 v 的类型）
- 通配符模式：`pattern_type := scrutinee_type`
- 标识符模式（变量绑定）：`pattern_type := scrutinee_type`
- 元组模式 `(p1, p2, ...)`：每个位置根据该位置的值类型独立收窄。`Nil` 子模式收窄对应位置为 `Nil`；变量子模式在非 `Nil` 分支中收窄为 `T`（参考 `type-system.md§复合模式收窄`）
- Record 模式 `{f1 = p1, ...}`：每个字段根据其子模式独立收窄，规则同元组

### Step 2: 类型环境

`code/kun-lang/src/typecheck/env.zig`：
- `TypeId = u32`，前几个 ID 预留给内置类型：
```zig
pub const int_type: TypeId = 0;
pub const float_type: TypeId = 1;
pub const bool_type: TypeId = 2;
pub const string_type: TypeId = 3;
pub const char_type: TypeId = 4;
pub const bytes_type: TypeId = 5;
pub const unit_type: TypeId = 6;
pub const path_type: TypeId = 7;
pub const duration_type: TypeId = 8;
pub const regex_type: TypeId = 9;
```
- `TypeEnv`：`ArrayListUnmanaged(Type)` + 代换映射
- `init()`：在 ArrayList 中按上述顺序预注册所有内置类型（ID 0–9 固定）
- `newVar(level: u32)`：创建新类型变量（ID ≥ 10 动态分配）
- `freshInstance()`：实例化多态类型（新变量替换泛型变量，设置 level=∞）
- `generalize()`：泛化（自由变量→泛型变量）
- `typeName(TypeId)`：将 TypeId 转为用户可见的类型名（如 `TypeId(3)` → `"String"`），供错误消息格式化使用
- 非预置类型（`stream`、`adt`、`command_t`、`decimal_t`、`datetime_t`）在类型检查过程中按需 `TypeEnv` 动态分配 TypeId

### Step 3: 合一求解器

**前置依赖**：Step 2

`typecheck/unify.zig`：
- `Subst` 映射结构：`TypeId` → `TypeId`（目标类型须先在 TypeEnv 中注册）
- `unify(a: TypeId, b: TypeId)`：结构递归合一
- `occursCheck(var_id, type)`：在变量-具体类型合一时检查
- 递归类型展开深度上限 256
- `apply(subst, type)`：代换应用到类型
- `compose(s1, s2)`：代换组合

> **合一对称性**：表中规则方向为示意——合一函数 `unify(A, B)` 应对称处理（如 `unify(base, nilable(a))` 等价于 `unify(nilable(a), base)`，均触发 `nil_to_non_nilable` 错误）。

**核心合一规则**：
| LHS | RHS | 行为 |
|-----|-----|------|
| `var(a)` | `var(b)` | 代换 a→b |
| `var(a)` | `T` | occurs_check(a, T) → sub(a, T) |
| base | base | 相等则通过，不等则类型错误 |
| `nilable(a)` | `nilable(b)` | `unify(a, b)` |
| `nilable(a)` | base | 错误：`nil_to_non_nilable`（Nil 值用于非 Nilable 位置） |
| `list(a)` | `list(b)` | `unify(a, b)` |
| `set(a)` | `set(b)` | `unify(a, b)` |
| `stream(a)` | `stream(b)` | `unify(a, b)` |
| `map(k1, v1)` | `map(k2, v2)` | `unify(k1, k2)` + `unify(v1, v2)` |
| `tuple(elems1)` | `tuple(elems2)` | 长度相等时逐元素 `unify(elems1[i], elems2[i])` |
| `function(a, r)` | `function(b, s)` | `unify(a, b)` + `unify(r, s)` |
| `effect_fn(a, r)` | `effect_fn(b, s)` | `unify(a, b)` + `unify(r, s)` |
| `effect_fn(a, r)` | `function(b, s)` | 错误：效应/纯不兼容 |
| `adt(n1, vs1)` | `adt(n2, vs2)` | 名称相等时逐变体结构合一 |
| `record(fields1)` | `record(fields2)` | 字段数+名称+类型一一匹配 |
| 其他 | 其他 | 类型错误 |

### Step 4: 约束生成

**前置依赖**：Step 2, Step 3

`typecheck/constraint.zig`：
- 遍历已解析的 `Decl[]`，为每个顶层函数体生成约束
- 核心模式：对每个 `Expr` 生成其类型 `t`，递归生成子表达式约束

**关键规则**（表为代表性示例，所有未列出的字面量模式为 `t := LiteralType`）：

| 表达式 | 约束生成 |
|--------|---------|
| `int_literal(42)` | `t := Int` |
| `ident("x")` | 查环境得 `type_x`，`freshInstance(type_x)` |
| `call(f, a)` | `t_f ~ function(t_a, t)` 或 `t_f ~ effect_fn(t_a, t)`（新变量 t）。实现策略：`t_f` 经 `ident("f")` 查找时已实例化为具体 `function(...)` 或 `effect_fn(...)`（函数类型在 Let 泛化→实例化阶段已确定），直接使用对应构造器合一即可。`t_f` 为类型变量的路径在 Phase 2 中不会发生（递归/前向引用推迟 Phase 3+），预留两阶段合一以兼容 |
| `lambda(p, b)` | 若体 `b` 含 do 块或效应调用 → `t := effect_fn(t_p, t_b)`；否则 `t := function(t_p, t_b)`。分类规则与用户定义函数相同（见下方「效应分类」段）。**多参脱糖**：`\x y -> body` 脱糖为 `\x -> \y -> body`——约束生成前将 `params.len > 1` 的 lambda 展开为嵌套单参 lambda，保证 function/effect_fn 恒为单参柯里化 |
| `let_in(binds, body)` | 每个 binding `name = expr`：推断 `expr` 类型得 `t_expr`（若有类型标注则 `t_expr ~ t_annotation` 加隐式 nilable 提升）；`t_name := t_expr`；泛化后加入环境。然后为 `body` 生成约束，`t := t_body` |
| `if_expr(c, t, e)` | `t_c ~ Bool`, `t_t ~ t_e` |
| `case_expr(s, bs)` | 从 scrutinee `s` 推断 `t_s`；验证 `t_s` 支持模式匹配（ADT/Bool/List/Nilable 等）；所有分支 `b_i` 的类型 `t_bi` 互合一为统一类型 `t` |
| `binary_op(op, l, r)` | 按运算符类型生成：算术类（`+`/`-`/`*`/`/`/`%`）→ `t_l ~ Int`, `t_r ~ Int`, `t := Int`（Float 同理）；比较类（`==`/`/=` → `t_l ~ t_r`, `t := Bool`；`<`/`>`/`<=`/`>=` → `t_l ~ t_r`, `t := Bool`）；逻辑类（`&&`/`||` → `t_l ~ Bool`, `t_r ~ Bool`, `t := Bool`）；拼接类（`++` → `t_l ~ t_r` 且 `t_l ~ String|List(a)`, `t := t_l`）；Nil 合并（`??` → `t_l ~ ?t_r`, `t := t_r`）；`range` 运算符与 `range_literal` 一起推迟 Phase 3+ |
| `unary_op(op, o)` | `neg` → `t_o ~ Int|Float`, `t := t_o`；`not` → `t_o ~ Bool`, `t := Bool` |
| `nil_literal` | `t := ?a`（多态 Nil，新类型变量 a） |
| `list_literal(items)` | 普通 `items[i]` 类型全部合一为 `t_item`；spread 项 `..e` 约束为 `t_e ~ list(t_item)`。最终 `t := list(t_item)` |
| `tuple_literal(items)` | 各元素独立推断类型 `t_i`，`t := tuple([t_0, t_1, ...])` |
| `set_literal(items)` | `items[i]` 类型全部合一，`t := set(t_item)` |
| `map_literal(entries)` | 所有 key 类型合一为 `t_k`，所有 value 类型合一为 `t_v`，`t := map(t_k, t_v)` |
| `record_literal(fields)` | `t := record({field: types})` |
| `record_access(r, f)` | `t_r ~ record({f: t})`（新变量 t） |
| `do_block(body, result)` | body 所有 stmt 遍历检查：`.binding` stmt 同 let_in 绑定规则（推断 expr 类型 + 隐式提升）、`.expr` stmt 递归生成约束、`.defer_` stmt 递归检查表达式类型。`result` 存在时 `t := t_result`（do in），不存在时 `t := Unit`（裸 do） |
| `pipe(l, r)` | 脱糖为 `call(r, l)`：`t_r ~ function(t_l, t)` 或 `t_r ~ effect_fn(t_l, t)` |
| `pipe_reverse(l, r)` | 脱糖为 `call(l, r)`：`t_l ~ function(t_r, t)` 或 `t_l ~ effect_fn(t_r, t)` |
| `compose(f, g)` | 脱糖为 `\x -> g (f x)`：递归对 lambda 和 call 生成约束，效应分类由 lambda 约束处理（单组件为 `effect_fn` 则整个 lambda 为 `effect_fn`） |
| `compose_reverse(f, g)` | 脱糖为 `\x -> f (g x)`，其余同 compose |

**用户定义函数的效应分类**：函数体含 `do` 块或调用效应命名空间（`IO.*`/`File.*`/`Env.*`/`Process.*`/`Task.*`/`Random.*`/`Signal.on`/effectively `Cmd.<bin>?`/`Cmd.<bin>!`/`Cmd.exec`/`Cmd.which`/`Cmd.pipe?`/`Cmd.pipe!`/`Cmd.timeout`/`Cmd.retry`/`Cmd.execSafe`）→ 约束生成阶段为该函数赋予 `effect_fn` 内部类型。纯函数（无上述特征）→ 赋予 `function` 类型。Lambda 同理按体自动分类。

**Let 多态**：
1. `let x = e1 in e2`：为 `e1` 生成约束 → 求解 → `generalize(type_e1, env)` → 将泛化类型加入环境 → 为 `e2` 生成约束
2. 每次 `ident("x")` 引用：`freshInstance(generalized_type)`
3. 递归 let（`let x = e1 in e2` 中 `e1` 引用 `x`）：分配类型变量 → 合一引用时实例化 → Phase 3+ 支持

**隐式 nilable 提升**（实现 `type-system.md§Nilable 类型`）：值 `v : T` 赋值给 `?T` 类型变量/字段时，约束生成阶段自动插入提升——将 `t_v ~ ?t_target` 改写为 `t_v ~ t_target` 且 `t_target` 为 nilable 的内部类型（以 `unify(T, T_inner)` 替代 `unify(T, ?T_inner)` 使合一通过）。`Nil` 字面量本身类型为 `?a`，无需提升。

### Step 5: 效应检查

**前置依赖**：Step 4（与约束生成共享 AST 遍历）

`code/kun-lang/src/typecheck/effect.zig`：

**MVP 规则**（Phase 2 实现）：
1. **do 块标记**：扫描函数体 AST，含 do 块 → 标记为效应函数（内部类型 `effect_fn`）
2. **纯函数约束**：纯函数体中无效应函数调用 → 编译错误；纯函数体中无效应命名空间函数引用（`IO.*`, `File.*` 等）
3. **`do`/`let` 互斥**：同一函数 scope 内 `do` 与 `let` 不可互相嵌套
4. **`do in` 验证**：`in` 表达式结果非 `Unit`；`do`/`do in` body 非空
5. **`let in` 纯性约束**：体内无效应函数调用、定义、或效应命名空间函数引用
6. **效应命名空间识别**：通过模块名称前缀匹配——`IO.*`, `File.*`, `Env.*`, `Process.*`, `Task.*`, `Random.*`, `Signal.on`。`Cmd.*` 中的执行类函数（`<bin>?`, `<bin>!`, `exec`, `which`, `timeout`, `retry`, `pipe?`, `pipe!`, `execSafe`）为效应函数，构造/装饰类（`<bin>`, `withEnv`, `withStdin`, `withWorkDir`, `withRunAs`, `withRawOpt`, `mergeStderr`, `andThen`, `orElse`, `pipe`）为纯函数
7. **变量重复绑定检测**：同一 scope 内变量名重复 → 编译错误

**Phase 3+ 补充**：
- Stream/Command 消费检查
- 隐式 do 上下文识别（unbound case/if 分支）
- 无效应调用的 do 块告警
- `!` 回调参数效应匹配

### Step 6: 模式穷举检查

**前置依赖**：Step 4

`typecheck/pattern.zig`：
- 矩阵分解法：`case` 的 branches → 模式矩阵 → 检查未覆盖列
- 穷举性规则：ADT/Bool/List 强制穷举
- 类型收窄：`case` 的 Nilable scrutinee → `Nil` 分支 vs 值分支
- 守卫子句不改变穷举性判定——`guard` 模式在穷举分析时被视为与内部 `inner` 模式等价（guard 条件求值仅影响运行时分支选择，不改变类型覆盖范围）。守卫子句中的变量类型为 scrutinee 原始类型（不收窄），与 `type-system.md§复合模式收窄` 一致

### Step 7: 类型推断入口与错误报告

**前置依赖**：Step 2–6

`typecheck/infer.zig`：
```zig
pub fn infer(allocator, decls: []const Decl, env: *TypeEnv) ![]const TypedDecl
```
**执行流程**：
1. **遍历 Decls 生成约束**（调用 constraint.zig）：为每个顶层函数体生成 HM 约束方程，同时并行执行效应检查（effect.zig）和模式穷举检查（pattern.zig）。Let 多态要求增量求解——`let ... in` 绑定的值表达式在生成约束后立即调合一求解，泛化结果类型后加入环境再处理 body
2. **合一求解**：对生成的约束集调用 unify.zig 逐条求解，构建代换映射 `Subst`。Let 绑定的增量求解已在本阶段完成（非后续独立步骤）
3. **应用代换构建 Typed AST**：遍历 Decl 树，将代换中 `TypeId` 解析结果标注到每个表达式节点，构造 `TypedDecl`（含 `TypedExpr` 节点的 `type_: TypeId` 字段）。字面量节点的 `type_` 直接设为对应基础类型 ID；标识符节点的 `type_` 设为代换后的实例化类型；复合表达式逐层递归构建
4. **错误收集与报告**：所有模块（约束、合一、效应、模式）在检查过程中将错误追加到错误列表。`infer` 完成后若错误列表非空则返回 `error.TypeCheckFailed`（调用方通过 `typecheck.error` 模块的格式化函数输出错误报告）；否则返回构建好的 `[]const TypedDecl`
**错误恢复**：类型错误不阻断后续检查。遇到类型不匹配时：
1. 为失败节点分配占位类型 `error_`（仅内部使用，不暴露给用户）
2. 依赖该节点类型的后续节点使用 `error_` 继续约束生成（避免级联报错）
3. 最终过滤掉以 `error_` 为依赖的派生错误，仅报告独立根因错误
4. 实现参考 `type-system.md§错误恢复`

`typecheck/error.zig`：
```zig
pub const TypeError = union(enum) {
    mismatch: struct { expected: TypeId, found: TypeId, span: Span },
    not_a_function: struct { found: TypeId, span: Span },
    effect_in_pure: struct { span: Span },
    non_exhaustive: struct { missing: []const []const u8, span: Span },
    unknown_field: struct { name: []const u8, span: Span },
    missing_field: struct { name: []const u8, span: Span },
    nil_to_non_nilable: Span,
    unbound_variable: []const u8,
    unbound_type: []const u8,  // Phase 2 仅在类型标注中出现非基础类型名时触发（ADT/type alias 推迟 Phase 3+，但保护性预留）
    infinite_type: Span,
};
```

### Step 8: 运行时 Value 与环境 + 闭包

**前置依赖**：Step 1

`code/kun-lang/src/runtime/value.zig`（对齐 `Type` 联合体的运行时表示）：

```zig
pub const Value = union(enum) {
    int: i64,
    float: f64,
    bool: bool,
    char: u32,
    unit,
    nil,
    string: []const u8,  // Arena 分配，与脚本同生命周期
    bytes: []const u8,   // Arena 分配
    path: []const u8,    // Arena 分配
    duration: i64,
    list: struct { items: []const Value, cap: usize },
    tuple: struct { items: []const Value },
    record: struct { fields: []const RecordFieldValue },
    closure: Closure,
};

pub const RecordFieldValue = struct { name: []const u8, value: Value };
```

> `regex`, `decimal`, `command`, `map`, `set`, `adt`, `stream` 的运行时表示推迟到 Phase 3+。类型检查器可推断这些类型，但求值器遇到对应类型表达式时会 panic（`@panic("unimplemented")`）。`map_literal`/`set_literal` 的 TypedExpr 变体在 Phase 2 实现（以确保 eval switch 编译覆盖），但其 Value 表示在 Phase 3+。

**闭包表示**（Phase 2 MVP 使用 Arena 分配帧，避免 env 悬空指针）：
```zig
pub const Closure = struct {
    param_names: []const []const u8,  // 参数名列表（从 typed.Param.name 提取）
    body: *const TypedExpr,           // 函数体
    env: *Frame,                      // 捕获的环境帧（Arena 分配，与脚本同生命周期）
};
```

> Frame 由 ArenaAllocator 统一分配，不单独 `deinit`。闭包的 `env` 指针在脚本执行期间始终有效（Arena 在脚本执行结束时整体释放）。<br>
> `let_in`/`do_block` 中 `local.bindings` 不使用 `deinit`（由 Arena 管理），避免闭包逃逸后访问已释放的 HashMap 数据。<br>
> Closure 省略 `arity` 字段：Kun 采用柯里化单参模型，所有函数的 arity 恒为 1（多参函数为嵌套 Closure 链），运行时无区分。`system-baseline.md` 保留 arity 仅用于未来 C ABI 互操作，Phase 2 不需要。

`code/kun-lang/src/runtime/env.zig`：
```zig
pub const Frame = struct {
    bindings: std.StringHashMapUnmanaged(Value),
    parent: ?*Frame,
};

pub fn lookup(frame: *Frame, name: []const u8) ?Value
pub fn bind(frame: *Frame, name: []const u8, val: Value) !void
```

> Frame 由 Arena 统一分配，`bindings` 的 HashMap 数据在脚本生命周期结束时由 Arena 整体释放，不单独调用 `deinit`。闭包的 `env` 指针在整个执行期间有效。

### Step 9: 标记 switch 求值器

**前置依赖**：Step 8

`code/kun-lang/src/runtime/eval.zig`：使用 Zig 0.17 labeled switch 实现 TypedExpr 节点分发。

核心分发函数覆盖 TypedExpr 全部 29 个变体（20 现有 + 9 新增），未实现的变体（regex/decimal/map/set/adt/stream 等）标记 `@panic("unimplemented")`。

> `error.UnboundVariable` 是求值器内部保护性错误——类型检查器在正常情况下已杜绝未绑定变量。若运行时触发此错误，表示类型检查或闭包捕获实现有 bug，非面向用户的错误。<br>
> 以下伪代码为示意性核心分支（省略 `char_literal`/`float_literal`/`nil_literal`/`duration_literal`/`path_literal`/`bytes_literal`/`unit_literal` 等直通字面量——这些直接构造对应 `Value` 变体）。`pipe`/`pipe_reverse`/`compose`/`compose_reverse` 脱糖为 `call` 求值。

**闭包应用** (`apply`)：
```zig
fn apply(func: Value, arg: Value, allocator: std.mem.Allocator) !Value {
    return switch (func) {
        .closure => |c| {
            const frame = try allocator.create(Frame);   // Arena 分配，防止悬空指针
            frame.* = Frame{ .bindings = .empty, .parent = c.env };
            try frame.bindings.put(allocator, c.param_names[0], arg);
            return eval(c.body, frame, allocator);
        },
        else => error.NotAFunction,  // 类型检查器已杜绝此路径
    };
}
```

**模式匹配分发** (`.case_expr`)：
依次测试每个 branch 的 pattern 是否匹配 scrutinee 值。匹配成功时，将 pattern 中绑定的变量写入新 Frame，求值该 branch 的 body。ADT 变体匹配比较 `tag` 字段；Nilable 匹配区分 `nil` vs 非 nil；字面量匹配等值比较；元组/Record 模式递归匹配子模式。guard 条件在 pattern 匹配后、body 求值前检查。

**二元运算分发** (`.binary_op`)：
根据 `op` 分发：算术 (`+`/`-`/`*`/`/`/`%`) 对 Int/Float 分别处理（Int 除零 panic，Float 除零返回 ±Inf/NaN）；比较 (`==`/`/=`/`<`/`>`/`<=`/`>=`) 先求值两边再比较；逻辑 (`&&`/`||`) 短路求值——左侧确定结果时跳过右侧；`++` 对 String 拼接或 List 连接；`??` 左侧为 `nil` 时返回右侧。`range` 运算推迟 Phase 3+（以 `@panic` 标记）。

```zig
pub fn eval(expr: *const TypedExpr, env: *Frame, allocator: std.mem.Allocator) !Value {
    return switch (expr.*) {
        .int_literal => |v| Value{ .int = v.value },
        .bool_literal => |v| Value{ .bool = v.value },
        .string_literal => |v| Value{ .string = v.value },
        .ident => |v| lookup(env, v.name) orelse return error.UnboundVariable,
        .lambda => |v| {
            const names = try allocator.alloc([]const u8, v.params.len);
            for (v.params, 0..) |p, i| names[i] = p.name;
            return Value{ .closure = .{
                .param_names = names,
                .body = v.body,
                .env = env,
            }};
        },
        .call => |v| {
            const func = try eval(v.func, env, allocator);
            const arg = try eval(v.arg, env, allocator);
            return apply(func, arg, allocator);
        },
        .let_in => |v| {
            // Phase 2 MVP 使用立即求值（非延迟求值）。Frame 由 Arena 管理，不单独 deinit。
            const local = try allocator.create(Frame);
            local.* = Frame{ .bindings = .empty, .parent = env };
            for (v.bindings) |b| {
                const val = try eval(b.value, env, allocator);
                try local.bindings.put(allocator, b.name, val);
            }
            return eval(v.body, local, allocator);
        },
        .do_block => |v| {
            // do 块创建新帧，不单独 deinit（Arena 统一释放）
            const local = try allocator.create(Frame);
            local.* = Frame{ .bindings = .empty, .parent = env };
            var defers = DeferStack.init(allocator);  // 嵌套 do 块各持独立 DeferStack
            defer defers.deinit(allocator);
            for (v.body) |stmt| {
                switch (stmt.kind) {
                    .binding => |b| {
                        const val = try eval(b.value, local, allocator);
                        try local.bindings.put(allocator, b.name, val);
                    },
                    .defer_ => |d| try defers.push(d.expr),
                    .expr => |e| _ = try eval(e, local, allocator),
                }
            }
            // 先执行 defer LIFO 链，再求值 result
            while (defers.pop()) |deferred| _ = try eval(deferred, local, allocator);
            if (v.result) |r| return eval(r, local, allocator);
            return Value{ .unit = {} };
        },
        .if_expr => |v| {
            const cond = try eval(v.cond, env, allocator);
            if (cond.bool) return eval(v.then, env, allocator);
            return eval(v.else_, env, allocator);
        },
        .binary_op => |v| { /* ... */ },
        .unary_op => |v| { /* ... */ },
        .record_literal => |v| { /* ... */ },
        .record_access => |v| { /* ... */ },
        .tuple_literal => |v| { /* ... */ },
        .list_literal => |v| { /* ... */ },
        .pipe => |v| { /* ... */ },
        .case_expr => |v| { /* pattern match dispatch */ },
        else => error.Unimplemented,
    };
}
```

### Step 10: 入口集成

**前置依赖**：Step 1–9

修改 `code/kun-lang/src/main.zig`：
```zig
pub fn main(init: std.process.Init) !void {
    // Phase 1: 源码读取 → 词法分析 → 语法分析
    const allocator = init.arena.allocator();
    // ... Phase 1 code ...
    const decls = try parser.parseModule(allocator, tokens);
    // Phase 2: 类型推断 → 效应检查 → 求值执行
    var type_env = try typecheck.env.TypeEnv.init(allocator);
    const typed = try typecheck.infer.infer(allocator, decls, &type_env);
    try runtime.eval.evalModule(typed, allocator);
}
```

`runtime/eval.zig`：
```zig
/// 执行类型化 AST 模块。注册非入口函数定义，查找 main 入口并执行。
pub fn evalModule(decls: []const TypedDecl, allocator: std.mem.Allocator) !void {
    const global = try allocator.create(Frame);
    global.* = Frame{ .bindings = .empty, .parent = null };

    // 1. 注册所有函数定义（除 main 外）到全局帧
    for (decls) |decl| {
        if (decl.kind == .function_def) {
            const f = decl.kind.function_def;
            if (!std.mem.eql(u8, f.name, "main")) {
                const fn_val = try eval(f.body, global, allocator);
                try global.bindings.put(allocator, f.name, fn_val);
            }
        }
    }

    // 2. 查找 main 入口并执行（丢弃结果，入口函数返回 Unit）
    for (decls) |decl| {
        if (decl.kind == .function_def and std.mem.eql(u8, decl.kind.function_def.name, "main")) {
            _ = try eval(decl.kind.function_def.body, global, allocator);
            return;
        }
    }
    // 无 main 时：首个非 import/export/type 的函数体作为入口
    for (decls) |decl| {
        if (decl.kind == .function_def) {
            _ = try eval(decl.kind.function_def.body, global, allocator);
            return;
        }
    }
}
```
> **MVP 限制**：`main` 的 `List String -> Unit` 参数（CLI 参数传递）推迟 Phase 3+。Phase 2 的 main 为零参函数，脚本参数通过 `init.args` 传递的机制尚未实现。
```

## Type–Value 双向一致性清单

每个 Type 变体必须有对应的 Value 变体（或明确标记为"仅类型检查，求值时 panic"）：

| Type 变体 | Value 变体 | 状态 |
|-----------|-----------|------|
| int | Value.int | Phase 2 |
| float | Value.float | Phase 2 |
| bool | Value.bool | Phase 2 |
| string | Value.string | Phase 2 |
| char | Value.char | Phase 2 |
| bytes | Value.bytes | Phase 2 |
| unit | Value.unit | Phase 2 |
| path | Value.path | Phase 2 |
| duration | Value.duration | Phase 2 |
| nilable | Value.nil / Value.*（隐式提升） | Phase 2 |
| list | Value.list | Phase 2 |
| tuple | Value.tuple | Phase 2 |
| record | Value.record | Phase 2 |
| function | Value.closure | Phase 2 |
| effect_fn | Value.closure | Phase 2 |
| variable | 无（编译期） | — |
| error_ | 无（编译期） | — |
| regex | 无 | Phase 3+ |
| decimal_t | 无 | Phase 3+ |
| command_t | 无 | Phase 3+ |
| datetime_t | 无 | Phase 3+ |
| map | 无 | Phase 3+ |
| set | 无 | Phase 3+ |
| stream | 无 | Phase 3+ |
| adt | 无 | Phase 3+ |

## 验证方法

| 验证项 | 方法 |
|--------|------|
| 构建通过 | `zig build` |
| 单元测试 | `zig build test`（新增 typecheck + runtime 测试，遵循 `conventions.md`：`src/typecheck/test_env.zig`、`src/typecheck/test_unify.zig`、`src/typecheck/test_constraint.zig`、`src/runtime/test_eval.zig` 等，由 `test_main.zig` 统一引入） |
| 推断正确性 | 简单程序 `f = 42` 通过类型检查 |
| 类型错误检测 | `x = 1 + true` 报告类型错误 |
| 效应检查 | 纯函数调用 `IO.println` 报错 |
| 求值正确性 | `add 1 2` 求值得 `3` |
| `if` 求值 | `if true then 1 else 0` 求值得 `1` |
| `let in` 求值 | `let x = 1 in x + 1` 求值得 `2` |
| lambda 调用 | `(\x -> x) 42` 求值得 `42` |
| 回归 | Phase 1 的 75 个测试全部通过 |
| 嵌套 `let in` | `let x = (let y = 1 in y + 1) in x + 1` → `3` |
| 嵌套 `do` 块 defer | `do` 块内 `defer` 在退出时 LIFO 逆序执行，嵌套 `do` 各独立管理 |
| 穷举通过 | `case True of True -> "ok"` 视为穷举（单变体 Bool 全覆盖） |
| 类型收窄 | `case (Nil, 42) of (Nil, n) -> n + 1` 收窄 n 为 `Int`，求值得 `43` |

## 分期里程碑

| 阶段 | 产出 | 验证标准 |
|------|------|---------|
| M1: Typed AST | `typed.zig` 补全 + Type 表示重构 | 编译通过 |
| M2: 类型推断 | 整型/布尔/字符串字面量通过推断 | `x = 42` → `Type.int` |
| M3: 效应检查 | do 块标记 + 纯函数约束 + do/let 互斥 | 纯函数含效应调用报错 |
| M4: 模式穷举 | case 穷举检查 | 非穷举 case 报错 |
| M5: 运行时求值 | 字面量/if/let/lambda/call 求值 | `(\x -> x) 42` → 42 |
| M6: 集成 | 完整流程：解析→类型检查→求值 | `kun script.kun` 运行无报错 |

## 风险评估

| 风险 | 缓解措施 |
|------|---------|
| HM 算法 W 实现复杂（occurs check、Let 多态） | 先实现简单合一（无泛化），再逐步添加多态 |
| EffectFn 与 Fn 结构不相容导致复杂约束 | EffectFn 作为内部类型构造器，约束生成时直接生成两种类型 |
| 模式穷举矩阵分解实现量大 | 先实现 ADT + Bool 穷举，List 和嵌套模式后续迭代 |
| 运行时 Value 表示与类型系统一致性 | 保持 `runtime/value.zig` 与 `Type` 的映射关系文档化 |
| 标记 switch 的分支覆盖 | 编译期确保 `eval` 的 switch 覆盖 `TypedExpr` 所有变体 |
| 递归深度控制 | 默认 10,000 层限制，环境变量可覆盖 |

## 审计要点

1. Typed AST 变体是否完整覆盖 Phase 1 的所有 Expr 变体
2. 合一实现是否正确处理 occurs check
3. 效应检查规则是否与 `type-system.md` 设计一致
4. 模式穷举是否正确处理守卫子句
5. 求值器是否正确处理闭包和函数应用
6. 与 Phase 1 的 Lexer/Parser 集成是否正确
7. 测试是否覆盖核心路径和错误路径

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.21 | 第 9–10 轮审计修复（6 项）：Stmt.defer_ 补全、多参 lambda 柯里化脱糖、nilable~base 合一规则、Subst TypeId 一致性、char u21→u32 迁移 |
| 2026.06.21 | 第 7–8 轮审计修复（7 项）：apply 函数定义、case_expr 模式匹配分发策略、binary_op 类型分发描述、range 运算符推迟、case_expr 约束澄清、TypedDecl type_ 统一为 TypeId |
| 2026.06.21 | 第 5–6 轮审计修复（8 项）：效应命名空间统一补 Task.* 和移除不存在 exec?、list spread 约束、compose 效应传播、eval 伪代码完善、辅助类型定义补全 |
| 2026.06.21 | 第 1–3 轮审计修复（30 项）：错误模板计数一致化、Value.list 补 cap、Typed AST 架构决策文档化、效应分类规则补充、合一规则表补全 effect_fn/set/stream/map/tuple/adt 结构合一、call/lambda 效应函数类型支持、约束表补全 pipe/compose/tuple/set/map、do_block defer 执行流、pattern_type 复合收窄等 |
| 2026.06.21 | 初始版本 |
