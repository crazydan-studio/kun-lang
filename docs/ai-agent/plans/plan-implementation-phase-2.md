# 执行计划：Phase 2 — 类型检查器 + 运行时求值器 MVP

## 背景与目标

Phase 1 完成了词法分析器、语法分析器、AST 定义、CLI 骨架。Phase 2 的目标是实现**最小可行类型检查器**和**最小可行运行时求值器**，使 Kun 语言能够对简单程序执行完整的"源码→解析→类型检查→求值"流程。

**产出**：`kun` 可执行文件接受脚本文件，执行类型检查后运行，输出程序结果。

## 基线数据

| 维度 | 值 |
|------|-----|
| `Expr` 总变体 | **32**（`ast.zig`） |
| `TypedExpr` 现有变体 | **20**（`typed.zig`） |
| Phase 2 需补齐的 TypedExpr 变体 | **7**（`duration_literal`, `path_literal`, `regex_literal`, `bytes_literal`, `pipe_reverse`, `compose`, `compose_reverse`） |
| Phase 3+ 补齐的 TypedExpr 变体 | **5**（`record_update`, `map_literal`, `set_literal`, `range_literal`, `ternary`—对应 Expr 中 parser 未实现的变体） |
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
| `code/kun-lang/src/typecheck/error.zig` | ~200 | 结构化错误类型 + 消息模板（12 个核心 MVP 模板） |
| `code/kun-lang/src/runtime/value.zig` | ~250 | Value 联合体（覆盖 Type 中所有有运行时表示的变体） |
| `code/kun-lang/src/runtime/env.zig` | ~150 | 帧栈：作用域链、变量查找 |
| `code/kun-lang/src/runtime/eval.zig` | ~550 | 标记 switch 求值器：TypedExpr 节点分发 |
| `code/kun-lang/src/runtime/defer.zig` | ~80 | defer LIFO 栈（嵌套 do 块） |

### 修改文件

| 文件 | 变更 |
|------|------|
| `code/kun-lang/src/ast/typed.zig` | 补全 7 个缺失的 TypedExpr 变体 + Type 表示重构（柯里化单参 function, variable 含 level） |
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
- `record_update`, `map_literal`, `set_literal`, `range_literal`, `ternary` 类型检查+求值— 对应 parser 实现后

### 不在 MVP 的错误模板（12 个核心 vs 21 个完整）

Phase 2 MVP 实现以下 10 个核心错误模板，其余 12 个（`TooManyArgs`, `RedundantPattern`, `TupleIndexOutOfRange`, `RecursiveAliasDepth`, `PureUnitReturn`, `CommandNotConsumed`, `StreamNotConsumed`, `EffectCallbackMismatch`, `NilableUsedAsT`, `EffectInLet`, `EmptyBody`, `DuplicateBinding`）在 Phase 3+ 补充。

## 实施步骤

### Step 1: 补全 Typed AST 定义 + 类型表示重构

**前置依赖**：无

#### 1.1 补充 7 个缺失的 TypedExpr 变体

```zig
// 新增：
duration_literal, path_literal, regex_literal, bytes_literal,
pipe_reverse, compose, compose_reverse,
```

`record_update`, `map_literal`, `set_literal`, `range_literal`, `ternary` 对应 parser 尚未实现的 Expr 变体，推迟到 Phase 3+。

#### 1.2 Type 联合体重构

对齐 `system-baseline.md` 的设计：

```zig
pub const Type = union(enum) {
    int, float, bool, string, char, bytes, unit, void,
    path, duration, regex, decimal_t, command_t, datetime_t,
    nilable: TypeId,           // ?T
    list: TypeId,              // List T
    map: struct { key: TypeId, value: TypeId },  // Map K V
    set: TypeId,               // Set T
    stream: TypeId,            // Stream T
    tuple: []const TypeId,     // (T1, T2, ...)
    record: []const RecordFieldType,  // { f1: T1, f2: T2 }
    function: struct { param: TypeId, result: TypeId },  // 柯里化单参
    effect_fn: struct { param: TypeId, result: TypeId }, // 效应函数
    adt: struct { name: []const u8, variants: []const AdtVariant },
    variable: struct { id: u32, level: u32 },  // level 用于 HM 泛化
    error_: void,                  // 类型错误占位
};
```

> `void` 是为 `Process.exit` 等无返回值函数预留的类型，与 `unit` 不同——`unit` 有值 `()`, `void` 无值。`void` 类型变量不能被绑定或返回。`void` 在 `system-baseline.md` 中尚未定型，Phase 2 将其加入 Type 环境供类型检查用，求值器遇到 `void` 类型表达式时 panic。

关键变更：
- 函数类型从多参 `params: []const Type` 改为柯里化 `param: TypeId, result: TypeId`（柯里化单参，对齐 HM 模型）
- `variable` 增加 `level: u32` 字段（HM Let 多态泛化的前提条件）
- 所有类型引用从 `*const Type` 改为 `TypeId`（Arena 索引）
- `nilable` 从 `*const Type` 改为 `TypeId`

### Step 2: 类型环境

`code/kun-lang/src/typecheck/env.zig`：
- `TypeId = u32`
- `TypeEnv`：`ArrayListUnmanaged(Type)` + 代换映射
- `newVar(level: u32)`：创建新类型变量
- `freshInstance()`：实例化多态类型（新变量替换泛型变量，设置 level=∞）
- `generalize()`：泛化（自由变量→泛型变量）

### Step 3: 合一求解器

**前置依赖**：Step 2

`typecheck/unify.zig`：
- `Subst` 映射结构：`TypeId` → `Type`
- `unify(a: TypeId, b: TypeId)`：结构递归合一
- `occursCheck(var_id, type)`：在变量-具体类型合一时检查
- 递归类型展开深度上限 256
- `apply(subst, type)`：代换应用到类型
- `compose(s1, s2)`：代换组合

**核心合一规则**：
| LHS | RHS | 行为 |
|-----|-----|------|
| `var(a)` | `var(b)` | 代换 a→b |
| `var(a)` | `T` | occurs_check(a, T) → sub(a, T) |
| base | base | 相等则通过，不等则类型错误 |
| `list(a)` | `list(b)` | `unify(a, b)` |
| `function(a, r)` | `function(b, s)` | `unify(a, b)` + `unify(r, s)` |
| `record(fields1)` | `record(fields2)` | 字段数+名称+类型一一匹配 |
| `effect_fn(a, r)` | `fn(a, r)` | 错误：效应/纯不兼容 |
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
| `call(f, a)` | `t_f ~ function(t_a, t)`（新变量 t） |
| `lambda(p, b)` | `t := function(t_p, t_b)` |
| `let_in(binds, body)` | 为每个 binding 生成约束 + 泛化 + 实例化 |
| `if_expr(c, t, e)` | `t_c ~ Bool`, `t_t ~ t_e` |
| `case_expr(s, bs)` | `t_s ~ pattern_type`, `t_bi` 合一 |
| `binary_op(op, l, r)` | 按 op 生成：`+`→`t_l ~ Int`, `t_r ~ Int`, `t := Int` |
| `list_literal(items)` | `items[i]` 类型全部合一，`t := list(t_item)` |
| `record_literal(fields)` | `t := record({field: types})` |
| `record_access(r, f)` | `t_r ~ record({f: t})`（新变量 t） |
| `do_block(body, result)` | body 所有 stmt 检查 → effect 标记 |

**Let 多态**：
1. `let x = e1 in e2`：为 `e1` 生成约束 → 求解 → `generalize(type_e1, env)` → 将泛化类型加入环境 → 为 `e2` 生成约束
2. 每次 `ident("x")` 引用：`freshInstance(generalized_type)`
3. 递归 let（`let x = e1 in e2` 中 `e1` 引用 `x`）：分配类型变量 → 合一引用时实例化 → Phase 3+ 支持

### Step 5: 效应检查

**前置依赖**：Step 4（与约束生成共享 AST 遍历）

`code/kun-lang/src/typecheck/effect.zig`：

**MVP 规则**（Phase 2 实现）：
1. **do 块标记**：扫描函数体 AST，含 do 块 → 标记为效应函数（内部类型 `effect_fn`）
2. **纯函数约束**：纯函数体中无效应函数调用 → 编译错误；纯函数体中无效应命名空间函数引用（`IO.*`, `File.*` 等）
3. **`do`/`let` 互斥**：同一函数 scope 内 `do` 与 `let` 不可互相嵌套
4. **`do in` 验证**：`in` 表达式结果非 `Unit`；`do`/`do in` body 非空
5. **`let in` 纯性约束**：体内无效应函数调用、定义、或效应命名空间函数引用
6. **效应命名空间识别**：`IO.*`, `File.*`, `Env.*`, `Process.*`, `Cmd.*`（仅执行类函数）
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
- 守卫子句不改变穷举性判定

### Step 7: 类型推断入口与错误报告

**前置依赖**：Step 2–6

`typecheck/infer.zig`：
```zig
pub fn infer(allocator, decls: []const Decl, env: *TypeEnv) ![]const TypedDecl
```

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
    unbound_type: []const u8,
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
    string: []const u8,
    bytes: []const u8,
    path: []const u8,
    duration: i64,
    list: struct { items: []const Value },
    tuple: struct { items: []const Value },
    record: struct { fields: []const RecordFieldValue },
    closure: Closure,
};
```

> `regex`, `decimal`, `command`, `map`, `set`, `adt`, `stream` 的运行时表示推迟到 Phase 3+。类型检查器可推断这些类型，但求值器遇到时会 panic（`@panic("unimplemented")`）。

**闭包表示**（Phase 2 MVP 使用环境指针浅捕获策略）：
```zig
pub const Closure = struct {
    params: []const ast.Param,  // 参数列表
    body: *const TypedExpr,     // 函数体
    env: *Frame,                // 捕获的环境帧（浅拷贝指针）
};
```

`code/kun-lang/src/runtime/env.zig`：
```zig
pub const Frame = struct {
    bindings: std.StringHashMapUnmanaged(Value),
    parent: ?*Frame,
};

pub fn lookup(frame: *Frame, name: []const u8) ?Value
pub fn bind(frame: *Frame, name: []const u8, val: Value) !void
```

### Step 9: 标记 switch 求值器

**前置依赖**：Step 8

`code/kun-lang/src/runtime/eval.zig`：使用 Zig 0.17 labeled switch 实现 TypedExpr 节点分发。

核心分发函数覆盖 TypedExpr 全部 27 个变体（20 现有 + 7 新增），未实现的变体（regex/decimal/map/set/adt/stream 等）标记 `@panic("unimplemented")`。

```zig
pub fn eval(expr: *const TypedExpr, env: *Frame, allocator: std.mem.Allocator) !Value {
    return switch (expr.*) {
        .int_literal => |v| Value{ .int = v.value },
        .bool_literal => |v| Value{ .bool = v.value },
        .string_literal => |v| Value{ .string = v.value },
        .ident => |v| lookup(env, v.name) orelse return error.UnboundVariable,
        .lambda => |v| Value{ .closure = .{
            .params = v.params,
            .body = v.body,
            .env = env,
        }},
        .call => |v| {
            const func = try eval(v.func, env, allocator);
            const arg = try eval(v.arg, env, allocator);
            return apply(func, arg, allocator);
        },
        .let_in => |v| {
            var local = Frame{ .bindings = .{}, .parent = env };
            defer local.bindings.deinit(allocator);
            for (v.bindings) |b| {
                const val = try eval(b.value, env, allocator);
                try local.bindings.put(allocator, b.name, val);
            }
            return eval(v.body, &local, allocator);
        },
        .do_block => |v| {
            var local = Frame{ .bindings = .{}, .parent = env };
            defer local.bindings.deinit(allocator);
            for (v.body) |stmt| { /* execute statement */ }
            if (v.result) |r| return eval(r, &local, allocator);
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
    // Phase 2: 类型推断 → 效应检查 → 求值执行
    const tokens = try lexer.tokenize(arena_alloc, source);
    const decls = try parser.parseModule(arena_alloc, tokens);
    var type_env = try typecheck.env.TypeEnv.init(arena_alloc);
    const typed = try typecheck.infer.infer(arena_alloc, decls, &type_env);
    if (typed.len > 0) {
        _ = try runtime.eval.evalModule(typed, arena_alloc);
    }
}
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
| void | 无 | Phase 3+ |
| map | 无 | Phase 3+ |
| set | 无 | Phase 3+ |
| stream | 无 | Phase 3+ |
| adt | 无 | Phase 3+ |

## 验证方法

| 验证项 | 方法 |
|--------|------|
| 构建通过 | `zig build` |
| 单元测试 | `zig build test`（新增 typecheck + runtime 测试） |
| 推断正确性 | 简单程序 `f = 42` 通过类型检查 |
| 类型错误检测 | `x = 1 + true` 报告类型错误 |
| 效应检查 | 纯函数调用 `IO.println` 报错 |
| 求值正确性 | `add 1 2` 求值得 `3` |
| `if` 求值 | `if true then 1 else 0` 求值得 `1` |
| `let in` 求值 | `let x = 1 in x + 1` 求值得 `2` |
| lambda 调用 | `(\x -> x) 42` 求值得 `42` |
| 回归 | Phase 1 的 75 个测试全部通过 |

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
| 2026.06.21 | 初始版本 |
