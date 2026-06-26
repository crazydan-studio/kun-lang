# 执行计划：Phase 3 — 标准库基础 + 效应检查补齐 + 错误消息完整化

## 背景与目标

Phase 2 完成了类型检查器和运行时求值器 MVP（244 测试全通过）。Phase 3 的目标是补齐 Phase 2 的已知限制，并为后续命令系统/标准库提供基础设施。

**核心产出**：
1. **Primitive 函数表** — `runtime/primitive.zig`，含 `PrimitiveBinding.is_effect`，效应识别从硬编码命名空间迁移到编译期常量
2. **错误消息完整化** — 补齐 14 种 TypeError 变体 + typeName 递归格式化
3. **Let 多态泛化** — `typecheck/env.zig generalize()` 实现，支持多绑定互递归
4. **效应检查补齐** — 18 项检查（含 Stream/Command 消费检查 + 告警系统），全面对齐 `type-system.md`
5. **Value 扩展** — map、set、stream、command、regex、decimal、datetime、adt 运行时表示
6. **map/set literal eval** — `#[...]` 和 `#{...}` 求值
7. **模式穷举补齐** — ADT/Bool 穷举 + Nil 类型收窄
8. **Cmd.\<bin\> 裸命令调用基础** — 所有 `Cmd.<bin>`（含 `Cmd.echo`/`Cmd.ls` 等）统一通过 fork-exec 执行

## 基线数据

| 维度 | 值 |
|------|-----|
| Phase 2 测试 | **244**（均通过） |
| Phase 2 测试文件 | **13** |
| Phase 2 源码文件 | **17**（typecheck 7 + runtime 4 + lexer 1 + parser 1 + ast 2 + lib/main 2） |
| 推迟的语义/效应检查 | **22 项**（含 14 ErrorType 变体 + 3 效应场景 + 5 结构性检查） |
| 推迟的 Value 变体 | **8**（map/set/stream/command/regex/decimal/datetime/adt） |
| 未实现的 Expr→TypedExpr | **3**（record_update/range_literal/ternary）——均明确推迟至 Phase 4 |

## 变更范围

### 新建文件

| 文件 | 预估行数 | 说明 |
|------|---------|------|
| `code/kun-lang/src/runtime/primitive.zig` | ~300 | PrimitiveBinding 表、PrimitiveFn 类型、`is_effect: bool`、预注册内置函数签名 |
| `code/kun-lang/src/typecheck/i18n.zig` | ~300 | 错误消息格式化（msgid→zh_CN/en 内嵌翻译表）、TypeError→消息渲染——Phase 2 已有 10 种 + Phase 3 新增 14 种 = 24 种 Type 错误变体，其中 `effect_in_pure`/`effect_in_let` 共用 `"Effect In Pure Function"` msgid（不同 hint），`empty_body`/`duplicate_binding` 使用新增模板 `"Empty Body"` 和 `"Duplicate Binding"`，实际 msgid 模板数为 **23**（type-system.md 已有 21 + Phase 3 新增 `"Empty Body"`/`"Duplicate Binding"` 2 个） |

### 修改文件

| 文件 | 变更 |
|------|------|
| `code/kun-lang/src/runtime/value.zig` | 新增 map/set/stream/command/regex/decimal/datetime/adt 变体 |
| `code/kun-lang/src/runtime/env.zig` | 新增 `RuntimeEnv` 结构体（包装 `Frame` + `PrimitiveTable` + `allocator`），供 `PrimitiveFn` 回调使用 |
| `code/kun-lang/src/runtime/eval.zig` | map_literal/set_literal eval、Pipe 命令触发（`Cmd.<bin>` 左操作数 — `ident` 前缀为 `Cmd.` 的 `call` 节点 — fork-exec 创建 Stream）、regex panics 保留（正则引擎推迟）、compose/pipe_reverse panics 保留（语法糖应在 Parser 层脱糖）；在处理 `call` 分支的 `apply()` 中新增 `.command` 分发（构造 CommandPayload） |
| `code/kun-lang/src/typecheck/effect.zig` | 新增完整效应检查函数（纯性约束、do/let 互斥、do-in 验证、! 回调匹配、隐式 do 识别、Cmd do 约束、`\|>` Command do 约束、Lambda 效应约束、Stream 消费、Command 消费、告警系统）——共计 18 项（12 编译错误 + 5 告警 + 1 隐式 do 识别机制） |
| `code/kun-lang/src/typecheck/pattern.zig` | 矩阵分解法穷举检查 + Nil/nilable 类型收窄 |
| `code/kun-lang/src/typecheck/constraint.zig` | 集成 effect enforcement 调用（消除与 effect.zig 的重复代码，统一使用 effect.zig）；使用 PrimitiveBinding.is_effect 替代硬编码命名空间；`pipe` 对 Command 左侧保留原始节点不脱糖（非 Command 保持原有 `pipe→call` 脱糖）；`if_expr` 分支类型合一；在 `let_in`/`do_block` 绑定处理中调用 `checkDuplicateBindings` 并 emit `duplicate_binding` TypeError；`ident` 分支新增 `Cmd.\<bin\>` 裸命令类型推断——`Cmd.ls` 识别为 `command_t`，`Cmd.ls arg` 的 call 约束为 `String -> command_t` |
| `code/kun-lang/src/typecheck/error.zig` | 补齐 14 种 deferred TypeError 变体（含 3 效应场景） |
| `code/kun-lang/src/typecheck/env.zig` | `typeName()` 格式化递归复合类型；`generalize()` 实现（Let 多态，含多绑定互递归泛化）；`init()` 补注册 `decimal_t`/`command_t`/`datetime_t` 内置类型常量；`freshInstance()` 扩展 `set`/`stream`/`map` 参数化类型实例化 |

## 实施步骤

### Step 1: Primitive 函数表

**前置依赖**：无

`code/kun-lang/src/runtime/primitive.zig`：

```zig
// RuntimeEnv 包装运行时状态（定义在 runtime/env.zig，Phase 3 新增）
// pub const RuntimeEnv = struct {
//     frame: *Frame,
//     primitives: PrimitiveTable,
//     allocator: std.mem.Allocator,
// };

pub const PrimitiveFn = *const fn (env: *RuntimeEnv, args: *const Value) Value;

pub const PrimitiveBinding = struct {
    module: []const u8,
    name: []const u8,
    fn_ptr: PrimitiveFn,
    signature: TypeId,     // comptime 解析：Primitive 表在编译期构造，TypeId 为编译期常量
    is_effect: bool,       // 效应标记——替代硬编码命名空间匹配
};

pub const PrimitiveTable = struct {
    bindings: []const PrimitiveBinding,
};
```

`signature: TypeId` 为 **comptime 常量**——整个 Primitive 表在编译期通过 Zig comptime 代码构造。`TypeId` 值引用 `TypeEnv` 中预注册的内置类型常量（`int_type`/`string_type`/`unit_type` 等），编译期即确定。

**Phase 3 注册的内置 Primitive**（编译期常量表）：
- `IO.println : String -> Unit` (is_effect=true)
- `IO.readln : -> String` (is_effect=true)
- `Stream.lines : Stream String -> Stream (Result String LineError)` (is_effect=false)
- `Stream.iter : (a -> Unit)! -> Stream a -> Unit` (is_effect=true)  // 签名含 !，自身为效应函数
- `Stream.fold : (b -> a -> b) -> b -> Stream a -> b` (is_effect=false)
- `Stream.toList : Stream a -> List a` (is_effect=false)
- `Stream.string : Stream String -> String` (is_effect=false)
- `Stream.bytes : Stream a -> Bytes` (is_effect=false)
- 其余 IO/File/Env/Process/Task/Random/Signal.on 签名占位（`is_effect=true`，函数体为 `@panic("unimplemented")`）

**不在 Primitive 表中注册的函数**（均为运行时裸命令调用——详见 Step 8）：
- **规则**：_在 `Cmd` 模块中，除以下明确定义的 API 函数外，其余均为裸命令调用_：
  - 明确纯操作 API（已定义签名，推迟实现）：`Cmd.pipe`、`Cmd.withEnv`、`Cmd.withWorkDir`、`Cmd.withStdin`、`Cmd.withStdinFile`、`Cmd.withRawOpt`、`Cmd.mergeStderr`、`Cmd.withRunAs`、`Cmd.andThen`、`Cmd.orElse`
  - 明确效应 API（已定义签名，推迟实现）：`Cmd.exec`、`Cmd.pipe?`、`Cmd.pipe!`、`Cmd.timeout`、`Cmd.retry`、`Cmd.execSafe`
  - `Cmd.which` 为效应函数（需文件系统访问），独立于 Command/Stream 管道
  - 裸命令：`Cmd.echo`、`Cmd.ls`、`Cmd.date`、`Cmd.grep` 等所有其他 `<bin>`——无 `?`/`!` 后缀时为纯操作（构造 Command 值），有后缀时为效应函数（立即执行），均不在 Primitive 表中注册
- 裸命令的效应性通过命名空间前缀 `Cmd.` + 排除明确 API 名单识别，`?`/`!` 后缀单独判断

**效应识别迁移**：`constraint.zig` 和 `effect.zig` 中的效应命名空间识别替换为查询 `PrimitiveBinding.is_effect` 字段。`do` 块扫描 + `!` 回调标注保持。硬编码命名空间列表保留作为编译期 fallback（Phase 5 移除），所有新增检查通过 Primitive 表查询。

**测试策略**：新增 `runtime/test_primitive.zig`——验证 Primitive 表构造通过 comptime 编译、`is_effect` 字段查询正确、`IO.println` 绑定可调用。

### Step 2: 错误消息完整化

**前置依赖**：Step 1

#### 2.1 补齐 ErrorType 变体

在 `typecheck/error.zig` 中新增（Phase 2 已实现 10 种变体，需补齐 14 种）：

```zig
// Phase 2 已实现: mismatch, not_a_function, effect_in_pure, non_exhaustive,
//               unknown_field, missing_field, nil_to_non_nilable,
//               unbound_variable, unbound_type, infinite_type
// （注：effect_in_pure 需扩展为 struct { called_func: []const u8, span } 以携带调用目标信息）

// Phase 3 新增（14 种）：
function_apply_arg,        // 函数参数类型不匹配
if_branch_mismatch,        // if 分支类型不一致——需在 constraint.zig `if_expr` 处理中新增 `unify(then_type, else_type)` 调用
too_many_args,             // 函数参数过多
effect_callback_mismatch,  // ! 参数传入纯函数——含 `func_name: []const u8`
nilable_used_as_t,         // ?T 用于非 Nilable 位置
redundant_pattern,         // 冗余模式分支（Step 7 穷举检查同时检测）
tuple_index_out_of_range,  // 元组索引越界——编译期常量为 Phase 4 占位（当前无 tuple 索引语法）
command_not_consumed,      // Command 未消费
stream_not_consumed,       // Stream 未消费
recursive_alias_depth,     // 递归别名展开超限——Phase 3 仅定义变体，类型别名解析推迟 Phase 4
pure_unit_return,          // 纯函数返回 Unit
effect_in_let,             // let in 内出现效应操作（效应场景——含 `called_func: []const u8`）
empty_body,                // do/do in/let in 空 body（效应场景）
duplicate_binding,         // 变量重复绑定（效应场景）
```

#### 2.2 typeName 完整化

扩展 `env.typeName()` 以支持递归格式化复合类型（`list(Int)`、`function(Int, Bool)` 等）。签名为：
```zig
pub fn typeName(self: *const TypeEnv, allocator: std.mem.Allocator, id: TypeId) ![]const u8;
```
递归实现：对 `list(inner)` 递归调用 `typeName(allocator, inner)` 后拼接 `"list(" ++ inner_name ++ ")"`。当前实现仅返回 `@tagName(resolved)`（如 `"list"`），需升级为递归参数解析。

### Step 3: 效应检查补齐

**前置依赖**：Step 1, Step 2

在 `effect.zig` 中新增校验函数，并在 `constraint.zig` 中集成（`infer.zig` 为 `constraint.zig` 的薄封装，签名不变时可自动适配，不需额外修改）。共 **18 项**（编译错误 12 项 + 告警 5 项 + 隐式 do 识别机制 1 项）：

**编译错误（10 项 + Stream/Command 消费检查 = 12 项）：**

1. **纯函数调用效应函数**：已有 `effect_in_pure` 检查；扩展为遍历全函数体 AST 的递归验证
2. **纯函数签名含 `!` 参数**：纯函数声明 `(a -> b)!` 参数是编译错误
3. **纯函数返回 `Unit`**：纯函数返回类型 `Unit` 是编译错误（`pure_unit_return`）
4. **`let in` 纯性约束**：验证 `let in` body 内无效应函数调用、无效应函数定义、无效应对名空间函数引用——含值绑定引用场景（`f = IO.println` 在 `let in` 内为编译错误）
5. **`do`/`let` 互斥检查**：遍历函数体 AST，同一 scope 内 `do` 与 `let` 不可互相嵌套
6. **空 body 检查**：`do`/`do in` body 非空——空 body 为编译错误；`let in` body 非空——空 body 为编译错误
7. **`do in` 的 `in` 结果非 `Unit`**：`in` 表达式结果类型为 `Unit` 是编译错误
8. **`!` 回调参数匹配**：`(a -> b)!` 的实参必须为 `EffectFn` 类型——传入纯 `Fn` 是编译错误
9. **`Cmd.<bin>?/!` / `Cmd.pipe?/!` / `Cmd.exec` / `Cmd.timeout` / `Cmd.retry` / `Cmd.execSafe` / `Cmd.which` do 约束**：这些效应函数仅在 `do` 块内合法
10. **`|>` 管道 Command 约束**：`|>` 左侧为 `Command` 类型时仅在 `do` 块内合法

**告警（5 项）：**

12. **无效应调用的顶级 `do`/`do in`**：`do` 块不含效应操作为告警
13. **无效应调用的隐式 `do` 分支**：隐式 `do` 分支内仅有纯操作为告警
14. **`do` body 最后一条语句为纯表达式**：纯表达式结果不被使用则浪费，告警
15. **未消费的纯函数调用结果**：计算结果被绑定到变量后未引用、显式绑定到 `_`、或作为独立语句结果未消费时告警（合并 type-system.md 告警清单中「纯函数调用结果绑定到变量后未引用」「纯函数调用结果绑定到 `_`」「非效应表达式作为独立语句且结果未消费」三项）
16. **已绑定变量未被使用**：变量绑定后后续无引用告警

**隐式 `do` 上下文识别机制**（基础设施——非告警）：
11. unbound `case`/`if` 分支识别为隐式 `do`；`defer` 在隐式分支中的作用域为该分支自身的隐式 `do`

**Stream 消费检查**（与效应检查共享 AST 遍历）：
- `do` 块内通过 `Cmd.<bin>`/`Cmd.pipe`/`Stream.*` 构造的 Stream 值执行 AST 级穷举消费分析
- 条件消费路径（`if`/`case` 分支）的所有分支均需消费
- `Cmd.timeout`/`retry` 返回 `Result` 的 `Ok` 分支 Stream 仍须消费
- `defer` 块内操作不计入消费

**Command 消费检查**（与效应检查共享 AST 遍历）：
- `do` 块内未被 `Cmd.exec`/`|>`/`?` 消费的 `Command` 值是编译错误
- `Cmd.exec` 返回 `Unit`，不作消费路径分析——不存在 `Result` 分支豁免

**效应识别迁移**：`constraint.zig` 中现有的 `isEffectNamespaceCall` 和 `hasEffect` 内部实现替换为查询 `PrimitiveBinding.is_effect` 字段。`effect.zig` 中硬编码命名空间列表保留作为 fallback（Phase 5 移除），但新增检查均通过 Primitive 表查询。

### Step 4: Let 多态泛化

**前置依赖**：Step 2（ErrorType 变体完整）、Step 3（效应检查可识别纯/效应函数边界）

在 `typecheck/env.zig` 中实现 `generalize()`：

```zig
pub fn generalize(env: *TypeEnv, allocator: std.mem.Allocator, ty: TypeId, level: u32) TypeId;
```

功能：
1. 遍历类型结构中所有自由类型变量（`level > 当前泛化 level`）
2. 将这些类型变量替换为多态类型变量（`level = POLYMORPHIC_LEVEL`，即 `maxInt(u32)`）
3. 多 Binding 互递归：`let even = ...; odd = ... in ...` 的绑定组中所有函数类型变量**同时泛化**——先为每个绑定推断类型，再对绑定组全体统一执行 `generalize()`，最后在 `in` body 中各自实例化

`freshInstance()` 已有（用于实例化多态类型），`generalize()` 是反向操作（从具体类型中提取多态方案）。二者配对实现 Let 多态。`generalize()` 需要遍历所有复合类型变体（`function`/`effect_fn`/`nilable`/`list`/`set`/`stream`/`map`/`tuple`/`record`/`adt`）以确保互递归绑定组中所有类型引用被泛化。

**集成点**：修改 `constraint.zig` 的 `let_in` 处理（`inferExpr` 中 `let_in` 分支，当前行 208-220）。HM 算法中，`generalize()` 应在每个 binding 的**合一完成后**调用（而非约束生成时——约束生成阶段的类型仍含未合一自由变量）。Phase 3 采用简化两阶段方案：(1) 约束生成阶段推断每个 binding 的类型并记录 TypeId；(2) 内部调用 `unify` 完成 binding 类型合一；(3) 对合一后的类型调用 `generalize()`；(4) 用泛化类型推断 body。多绑定 `let_in` 对所有 bindings 的类型同步泛化后，再推断 body。

### Step 5: Value 扩展

**前置依赖**：Step 1（Primitive 表定义了 Command 等类型签名的运行时对应关系）

在 `runtime/value.zig` 中新增：

```zig
pub const MapEntryValue = struct { key: Value, value: Value };

// 哈希表运行时表示（对齐 system-baseline.md §Map/Set C ABI）
pub const MapRepr = struct {
    entries: [*]u8,  // 桶数组：{ hash: u64, key: Value, value: Value, occupied: bool }
    len: u64,
    cap: u64,
};
pub const SetRepr = struct {
    entries: [*]u8,  // 桶数组：{ hash: u64, key: Value, occupied: bool }
    len: u64,
    cap: u64,
};

// 在 value.zig 的 Value union 中新增：
map: MapRepr,
set: SetRepr,
stream: *StreamNode,     // tagged union 指针（见 Step 6）
command: CommandPayload,
regex: *const regex.Regex, // 推迟实现，改用 zig-regex
decimal: struct { mantissa: i64, exponent: i32 },
datetime: i64,           // Int newtype
adt: struct { tag: u8, payload: [*]u8 },  // 对齐 system-baseline.md ADTRepr C ABI
```

`map`/`set` 字面量求值在 `eval.zig` 中实现：遍历 AST `map_literal`/`set_literal` 节点的元素列表，对每个元素求值后插入哈希表（开地址法），构造 `Value.map`/`Value.set`。`map`/`set` 采用与 `list`/`tuple` 相同的 Arena 分配策略。类型检查阶段在 `constraint.zig` 中对 `map_literal` 的 entry 和 `set_literal` 的元素施加类型合一约束——map 所有 key 类型统一为 `K`，所有 value 类型统一为 `V`；set 所有元素类型统一为 `T`。

**`valueEqual()` 扩展**：新增 `map`/`set`/`datetime`/`decimal` 的等值比较分支；`stream` 使用指针相等（`a.stream == b.stream`）；`command`（不透明）走 `else => false`——Phase 3 不要求 Command 模式匹配。

**PrimitiveFn 运行时集成**：在 `Value` 中新增 `primitive` 变体：
```zig
primitive: PrimitiveFn,
```
在 `eval.zig` 的 `apply()` 函数中新增 `primitive` 分支——调用 `primitive_fn(env, &arg)` 并返回结果。

`CommandPayload` 定义（对齐 `system-baseline.md`）：
```zig
pub const CommandPayload = struct {
    tag: u8,
    _payload: [32]u8,  // 内联或堆指针，编译器/运行时透明处理
};
```

### Step 6: Stream 基础表示

**前置依赖**：Step 5

在 `runtime/value.zig` 中定义：

```zig
const PrimitiveFn = @import("primitive.zig").PrimitiveFn;
const Closure = @import("value.zig").Closure;

pub const StreamFn = union(enum) {
    primitive: PrimitiveFn,  // Zig 原生函数（如 Stream.lines 内部实现）
    closure: *const Closure, // Kun 用户定义函数（如 \x -> x + 1）
};

pub const StreamNode = union(enum) {
    cmd: struct { fd: i32, pid: i32, buf: []u8 },
    mapped: struct { upstream: *StreamNode, f: StreamFn },
    filtered: struct { upstream: *StreamNode, pred: StreamFn },
    taken: struct { upstream: *StreamNode, remaining: usize },
    dropped: struct { upstream: *StreamNode, remaining: usize },
    lines: struct { upstream: *StreamNode, buf: []u8, pos: usize, max_len: usize },
    parse_mapped: struct { upstream: *StreamNode, f: StreamFn },
    parse_mapped_keep: struct { upstream: *StreamNode, f: StreamFn },
};
```

Phase 3 仅实现 `cmd` 变体（通过 `Cmd.<bin>` 创建）；`mapped`/`filtered` 等变换操作推迟 Phase 4。`StreamNode` 结构体定义与 `system-baseline.md` 中 Stream tagged union 保持一致——所有变体在此声明但仅 `cmd` 有运行时构造路径。

**内存所有权**：`StreamNode` 分配在脚本级 Arena 上；`cmd.buf` 由 fork-exec 后在 Arena 上分配，`cmd.fd` 在 Stream 消费完成后或 `do` 块退出时由运行时显式 `close()`（对齐 `system-baseline.md` 资源释放阶段）。`execCommand` 中的 fork/exec/pipe 错误通过 `EvalError` 传播到 `do` 块级别。

`StreamFn` 类型统一表示 Stream 变换回调——支持 Zig 原生函数（`PrimitiveFn`）和 Kun 用户定义函数（`Closure`），避免 `PrimitiveFn` 无法表达闭包捕获的限制。

### Step 7: 模式穷举补齐

**前置依赖**：Step 2, Step 5（ADT Value 变体）

重写 `pattern.zig`（当前 `checkExhaustive` 已实现基础通配符/小写变量穷举、`narrowType` 为 stub）：

1. **矩阵分解法**：ADT 变体枚举 → 逐列检查未覆盖；替换当前仅检查通配符/变量的简易实现。同时检测冗余模式——例如 `_` 分支在 `True`/`False` 之后的 `case` 中永不到达
2. **Bool 强制穷举**：`True | False` 全覆盖 → 穷举；单分支 → 非穷举
3. **Nilable 类型收窄**：`Nil` 分支 vs 值分支（`n : T`）——`narrowType` 从 stub 升级为实际类型收窄算法

### Step 8: Cmd.\<bin\> 裸命令调用

**前置依赖**：Step 1, Step 5, Step 6

**规则**：在 `Cmd` 模块中，除明确 API 函数外，其余均为裸命令。

**效应分类**：
- **裸命令构造**（`Cmd.echo`/`Cmd.ls`/`Cmd.date` 等，无 `?`/`!` 后缀）→ **纯操作**——返回 `Command` 值，不触发 fork-exec
- **裸命令立即执行**（`Cmd.<bin>?`/`Cmd.<bin>!` 后缀）→ **效应函数**——须在 `do` 块内使用

在运行时中实现裸命令调用调度：

1. **效应识别**：类型检查阶段，`Cmd.<bin>` 若不在明确 API 名单中，识别为裸命令。无 `?`/`!` 后缀时构造 Command 值（纯操作）；有后缀时立即执行（效应函数）
2. **求值链路**：
   - **识别机制**：`eval.zig` 的 `ident` 处理器在当前 Frame 查找失败后，新增 `Cmd.` 前缀 fallback——若 ident 名以 `"Cmd."` 开头且不在明确 API 名单中，不返回 `UnboundVariable`，而是返回 `Value{ .command = CommandPayload{ .tag = 0, ._payload = ... } }`（存储 bin 名）。后续 `call` 分支的 `apply()` 新增 `.command` 分发：接收 Command 值与参数，将参数写入 CommandPayload 的 args 区，返回完整 Command 值（不 fork）
   - 构造阶段：`Cmd.ls` → `Value.command`（仅 bin 名）；`Cmd.ls "/tmp"` 经 `call` + `apply(.command, ...)` → `Value.command`（bin + args）
   - 执行阶段：`Cmd.ls?` 或 `Cmd.ls |>` 触发 fork-exec → 构造 `StreamNode{ .cmd = { fd, pid, buf } }` → 包装为 `Value{ .stream = &stream_node }`
   - 实现函数：`fn execCommand(bin: []const u8, args: []const []const u8, allocator: Allocator) !*StreamNode`
3. **`|>` 管道触发**：`Cmd.<bin> |>` 在 `do` 块内触发命令执行。当前 `constraint.zig` 已对 `|>` 做脱糖为 `call`——Phase 3 对 Command 类型**保留 pipe 节点不脱糖**，改为在 `eval.zig` 的 `pipe` 分支处理：先求值左右操作数，若左侧为 `Value.command` 则调用 `execCommand` 创建 Stream，再将 Stream 值作为参数 `apply(right_value, stream_value)`；左右非 Command 时执行 `apply(right_value, left_value)` 保持纯函数组合语义。注意：当前 `eval.zig:92-96` 的 pipe 分支**丢弃左值**（`_ = left`），需修复为上述语义。

**明确 API 函数**（已定义签名，推迟实现）：
- 纯操作（返回修饰后 Command）：`Cmd.withEnv`、`Cmd.withWorkDir`、`Cmd.withStdin`、`Cmd.withStdinFile`、`Cmd.withRawOpt`、`Cmd.mergeStderr`、`Cmd.withRunAs`、`Cmd.andThen`、`Cmd.orElse`、`Cmd.pipe`
- 效应函数（须在 `do` 块内）：`Cmd.exec`、`Cmd.pipe?`、`Cmd.pipe!`、`Cmd.timeout`、`Cmd.retry`、`Cmd.execSafe`
- `Cmd.which : String -> ?Path` 为效应函数（需文件系统访问），但不参与 Command/Stream 消费管道——独立分类

Phase 3 MVP 仅支持无选项裸命令调用（无 Record 选项参数、无 camelCase→kebab-case 映射）。Record 选项解析推迟 Phase 4。裸命令通过现有 `call(ident("Cmd.<bin>"), arg)` AST 节点工作——Phase 3 不引入 `cmd_call` AST 节点（该节点为未来 options Record 语法预留）。

## 分期里程碑

| 阶段 | 产出 | 验证标准 |
|------|------|---------|
| M1: Primitive 表 | `primitive.zig` + `is_effect` 迁移 | 编译通过，IO.println 可调用 |
| M2: 错误消息 | 14 种新增 TypeError + typeName 格式化 | 错误输出含期望/实际类型 |
| M3: 效应补齐 | 18 项效应检查 + Stream/Command 消费 | 纯函数调用 IO.println → 报错 |
| M4: Let 多态 | `generalize()` 实现 | 多态函数在多调用点推断不同实例化类型 |
| M5: Value 扩展 | map/set eval 可用 + 8 种新变体 | `#[1,2,3]` → Value.set |
| M6: 模式穷举 | ADT/Bool 穷举 + Nil 收窄 | `case True of True -> "ok"` 穷举通过 |
| M7: Stream 基础 | `StreamNode` + `cmd` 变体 | 类型定义编译通过 |
| M8: 命令调用 | 裸命令 `Cmd.echo` / `Cmd.ls` 可执行 | fork-exec 子进程，stdout 捕获 |
| M9: 集成 | 现有 244 + 新增约 100 测试通过 | `zig build test` 全通过 |

## 风险评估

| 风险 | 缓解措施 |
|------|---------|
| Primitive 表复杂度 | 先实现 2 个核心函数（IO.println + IO.readln），其余占位 |
| 效应检查规则多（18 项） | 分两批实现——编译错误 12 项优先，告警 5 项次之；每项独立测试 |
| 模式穷举矩阵分解 | 先 ADT+Bool，后 list/嵌套 |
| fork-exec 子进程管理 | Linux pipe+waitpid + `O_NONBLOCK`，Phase 3 仅单命令 |
| pipe 操作符求值重构 | 原来 pipe 为 no-op，改为左侧 `Command` 时触发 `execCommand` 创建 Stream；左右非 Command 时保持原行为（纯函数组合） |
| 效应检查与约束生成耦合 | 共享 AST 遍历，按步骤 3 集成 |
| 向后兼容 | 所有修改保持 Phase 2 测试通过 |
| `generalize()` 多绑定互递归 | 先实现单绑定泛化，再扩展到绑定组同时泛化 |
| primitive.zig ↔ value.zig ↔ env.zig 循环 import | Zig 允许模块间循环引用（编译期类型不依赖完整定义）；`StreamFn` 等类型使用指针间接消除编译依赖 |

## 验证方法

| 验证项 | 方法 |
|--------|------|
| 构建通过 | `zig build` |
| 单元测试 | `zig build test`（新增 test_primitive/test_effect_full/test_i18n/test_value/test_pattern_full/test_stream/test_cmd 测试；需同步更新 `src/test_main.zig` 的 `@import` 列表） |
| 回归 | Phase 2 的 244 测试全通过（开发中使用 `zig build test --test-filter "constraint"` 等按需筛选） |
| IO.println | `kun --run` 执行含 `IO.println "hi"` 脚本 |
| Cmd.echo | `kun --run` 执行 `Cmd.echo "hi" \|>` 经 fork-exec 输出 |
| Cmd.ls | `kun --run` 执行 `Cmd.ls \|>` 经 fork-exec 捕获 stdout |
| Cmd.?\ | `kun --run` 执行 `Cmd.echo? "hi"` 经 fork-exec 输出 |
| 效应检查 | 纯函数调用 `IO.println` 报 `effect_in_pure` 错误 |
| 效应检查 | `let in` 内引用 `IO.println` 报 `effect_in_let` 错误 |
| Let 多态 | `let id = \x -> x in (id 42, id "hi")` 两个实例化类型不同 |

## 审计要点

1. PrimitiveBinding.is_effect 是否正确替代硬编码命名空间（MVP fallback 是否保留）
2. 效应检查 18 项规则是否与 `type-system.md` 设计一致
3. Stream 消费检查是否正确处理分支路径与 `Cmd.timeout` Result 交互
4. `generalize()` 是否正确处理多绑定互递归场景
5. 模式穷举是否正确处理 Bool/ADT/Nilable 收窄
6. Cmd 命令调用是否正确 fork-exec
7. 所有 Phase 2 测试是否仍通过

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.22 | Round 10 审计修复：Map/Set 改为哈希表表示对齐 system-baseline.md；新增 `cmd_call` 类型推断/求值分支；明确 `generalize()` 集成点（`let_in` 分支）；StreamNode 使用 `StreamFn`（PrimitiveFn | Closure）；pipe 分析保留原始节点不脱糖；注册 Stream.* Primitive 函数；`Cmd.which` 独立分类；告警重分类为 5+1；typeName 添加 allocator 签名；i18n 模板计数修正；valueEqual 扩展；`tuple_index_out_of_range`/`recursive_alias_depth` 推迟 Phase 4 |
| 2026.06.22 | Round 7 审计修复：验证方法区分裸命令构造 vs 触发执行（`|>`/`?`）；补全 `Cmd.withStdinFile` 到明确 API 列表 |
| 2026.06.22 | Round 6 审计修复：修正裸命令效应分类——`Cmd.<bin>` 裸构造为纯操作（对齐 `type-system.md`/`standard-library.md`），仅 `?`/`!` 后缀为效应函数；API 列表按纯/效应分类 |
| 2026.06.22 | Round 5 审计修复：`Cmd.echo` 从 Primitive 表移除，归入裸命令（统一 fork-exec）；明确 Cmd 模块 API 函数 vs 裸命令的分界规则 |
| 2026.06.22 | Round 3 审计修复：统一 PrimitiveFn 类型签名；修正 eval.zig 修改描述（pipe/regex/compose/pipe_reverse 遗留处理） |
| 2026.06.22 | Round 2 审计修复：消除 Step 1/Step 8 对 Cmd 命令注册位置的矛盾；StreamNode 使用 PrimitiveFn 替代未定义 FnPtr；补全 MapEntryValue/CommandPayload 定义 |
| 2026.06.22 | Round 1 审计修复：补齐 generalize() Step；效应检查从 6 项扩展到 16 项（含 Stream/Command 消费）；StreamNode 对齐 system-baseline.md 定义；修正依赖关系与步骤编号；测试计数统一为 244；里程碑从 7 项扩展为 9 项 |
| 2026.06.21 | 初始版本 |
