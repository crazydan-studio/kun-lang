# 执行计划：Phase 3 — 标准库基础 + 效应检查补齐 + 错误消息完整化

## 背景与目标

Phase 2 完成了类型检查器和运行时求值器 MVP（229 测试全通过）。Phase 3 的目标是补齐 Phase 2 的已知限制，并为后续命令系统/标准库提供基础设施。

**核心产出**：
1. **Primitive 函数表** — `runtime/primitive.zig`，含 `PrimitiveBinding.is_effect`，效应识别从硬编码命名空间迁移到编译期常量
2. **错误消息完整化** — 补齐 Phase 2 推迟的 11 个模板 + 3 个效应场景，实现 `typeName` 格式化
3. **效应检查补齐** — do/let 互斥、do-in 验证、let-in 纯性约束、`!` 回调参数匹配、隐式 do 识别
4. **Value 扩展** — map、set、stream、command、regex、decimal、datetime、adt 运行时表示
5. **map/set literal eval** — `#[...]` 和 `#{...}` 求值
6. **模式穷举补齐** — ADT/Bool 穷举 + Nil 类型收窄
7. **Cmd.\<bin\> 命令调用基础** — `Cmd.echo` / `Cmd.ls` 等裸调用（无选项 Record）

## 基线数据

| 维度 | 值 |
|------|-----|
| Phase 2 测试 | **244**（均通过） |
| Phase 2 源码文件 | **19**（typecheck 8 + runtime 4 + lexer 1 + parser 1 + ast 2 + others） |
| 推迟的模板/场景 | **14**（11 模板 + 3 效应场景） |
| 推迟的 Value 变体 | **8**（map/set/stream/command/regex/decimal/datetime/adt） |
| 未实现的 Expr→TypedExpr | **3**（record_update/range_literal/ternary） |

## 变更范围

### 新建文件

| 文件 | 预估行数 | 说明 |
|------|---------|------|
| `code/kun-lang/src/runtime/primitive.zig` | ~300 | PrimitiveBinding 表、PrimitiveFn 类型、`is_effect: bool`、预注册内置函数签名 |
| `code/kun-lang/src/typecheck/i18n.zig` | ~150 | 错误消息格式化（msgid→zh_CN/en 翻译）、typeName 完整化 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `code/kun-lang/src/runtime/value.zig` | 新增 map/set/stream/command/regex/decimal/datetime/adt 变体 |
| `code/kun-lang/src/runtime/eval.zig` | map_literal/set_literal eval、移除 `@panic("unimplemented")` for map/set |
| `code/kun-lang/src/typecheck/effect.zig` | 新增 effect enforcement 函数（checkDoLetExclusion/checkDoInValidation/checkLetInPurity/checkEffectCallback） |
| `code/kun-lang/src/typecheck/pattern.zig` | 矩阵分解法穷举检查 + Nil/nilable 类型收窄 |
| `code/kun-lang/src/typecheck/constraint.zig` | 集成 effect enforcement 调用、使用 PrimitiveBinding.is_effect 替代硬编码命名空间 |
| `code/kun-lang/src/typecheck/error.zig` | 补齐 11 种 deferred TypeError 变体 |
| `code/kun-lang/src/typecheck/env.zig` | `generalize()` 实现（Let 多态） |

## 实施步骤

### Step 1: Primitive 函数表

**前置依赖**：无

`code/kun-lang/src/runtime/primitive.zig`：

```zig
pub const PrimitiveFn = *const fn (env: *RuntimeEnv, args: *const Value) Value;

pub const PrimitiveBinding = struct {
    module: []const u8,
    name: []const u8,
    fn_ptr: PrimitiveFn,
    signature: TypeId,     // 编译期预解析的类型
    is_effect: bool,       // 效应标记——替代硬编码命名空间匹配
};

pub const PrimitiveTable = struct {
    bindings: []const PrimitiveBinding,
};
```

**Phase 3 注册的内置 Primitive 签名**（编译期常量表）：
- `IO.println : String -> Unit` (is_effect=true)
- `IO.readString : -> String` (is_effect=true)
- 其余 IO/File/Env/Process/Task/Random/Signal.on 签名占位（`is_effect=true`，函数体为 `@panic("unimplemented")`）

**效应识别迁移**：删除 `constraint.zig` 和 `effect.zig` 中的硬编码命名空间列表，改为在 Primitive 表初始化后，通过 `PrimitiveBinding.is_effect` 字段查询。`do` 块扫描 + `!` 回调标注保持。

### Step 2: 错误消息完整化

**前置依赖**：Step 1

#### 2.1 补齐 ErrorType 变体

在 `typecheck/error.zig` 中新增：

```zig
not_a_function,        // 已有
function_apply_arg,    // 新增
if_branch_mismatch,    // 新增
too_many_args,         // 新增
effect_callback_mismatch, // 新增
nilable_used_as_t,     // 新增
redundant_pattern,     // 新增
tuple_index_out_of_range, // 新增
command_not_consumed,  // 新增
stream_not_consumed,   // 新增
recursive_alias_depth, // 新增
pure_unit_return,      // 新增
effect_in_let,         // 新增（效应场景）
empty_body,            // 新增（效应场景）
duplicate_binding,     // 新增（效应场景）
```

#### 2.2 typeName 完整化

扩展 `env.typeName()` 以递归格式化复合类型（`list(Int)`、`function(Int, Bool)` 等）。

### Step 3: 效应检查补齐

**前置依赖**：Step 1, Step 2

在 `effect.zig` 中新增并在 `constraint.zig`/`infer.zig` 中集成：

1. **do/let 互斥检查**：遍历函数体 AST，同一 scope 内 `do` 与 `let` 不可互相嵌套
2. **do-in 验证**：`in` 表达式结果类型非 `Unit`；`do`/`do in` body 非空
3. **let-in 纯性约束**：`let in` body 内无效应函数调用/定义/引用
4. **`!` 回调参数匹配**：`(a -> b)!` 的实参必须为 `effect_fn` 类型
5. **隐式 do 上下文识别**：unbound `case`/`if` 分支识别为隐式 do
6. **变量重复绑定**：已有 `checkDuplicateBindings`，集成到约束生成

### Step 4: Value 扩展

**前置依赖**：无

在 `runtime/value.zig` 中新增：

```zig
map: struct { entries: []const MapEntryValue, cap: usize },
set: struct { items: []const Value, cap: usize },
stream: *StreamNode,     // tagged union 指针（见 Step 5）
command: CommandPayload,
regex: *const RegexHandle, // 推迟实现，保留占位
decimal: struct { mantissa: i64, exponent: i32 },
datetime: i64,           // Int newtype
adt: struct { tag: u8, payload: []Value },
```

`map`/`set` 评估器实现：构造 `Value.map`/`Value.set`，字面量求值。

### Step 5: Stream 基础表示

**前置依赖**：Step 4

在 `runtime/value.zig` 中定义：

```zig
pub const StreamNode = union(enum) {
    cmd: struct { fd: i32, pid: i32, buf: []u8 },
    mapped: struct { upstream: *StreamNode, f: FnPtr },
    filtered: struct { upstream: *StreamNode, pred: FnPtr },
};
```

Phase 3 仅实现 `cmd` 变体（通过 `Cmd.<bin>` 创建）；`mapped`/`filtered` 推迟 Phase 4。

### Step 6: 模式穷举补齐

**前置依赖**：Step 2

重构 `pattern.zig`：

1. **矩阵分解法**：ADT 变体枚举 → 逐列检查未覆盖
2. **Bool 强制穷举**：`True | False` 全覆盖 → 穷举；单分支 → 非穷举
3. **Nilable 类型收窄**：`Nil` 分支 vs 值分支（`n : T`）

`checkExhaustive` 从 stub 升级为实际算法，`narrowType` 实现 Nil→T 收窄。

### Step 7: Cmd.\<bin\> 命令调用基础

**前置依赖**：Step 1, Step 4

在 `runtime/primitive.zig` 中注册 `Cmd` 模块 Primitive 函数：

1. **`Cmd.echo`** — 内建命令（非 fork-exec），输出到 stdout
2. **裸命令调用** — `Cmd.ls` / `Cmd.date` 等（无选项 Record），fork-exec + stdout 捕获为 `Stream String`

Phase 3 MVP 仅支持无选项命令调用。Record 选项解析推迟 Phase 4。

## 分期里程碑

| 阶段 | 产出 | 验证标准 |
|------|------|---------|
| M1: Primitive 表 | `primitive.zig` + `is_effect` 迁移 | 编译通过，IO.println 可调用 |
| M2: 错误消息 | 14 种 TypeError + typeName 格式化 | 错误输出含期望/实际类型 |
| M3: 效应补齐 | do/let 互斥、do-in 验证 | 纯函数调用 IO.println → 报错 |
| M4: Value 扩展 | map/set eval 可用 | `#[1,2,3]` → Value.set |
| M5: 模式穷举 | ADT/Bool 穷举 + Nil 收窄 | `case True of True -> "ok"` 穷举通过 |
| M6: 命令调用 | `Cmd.echo "hi"` / `Cmd.ls` 可执行 | fork-exec 子进程，stdout 捕获 |
| M7: 集成 | 所有 244 + 新增测试通过 | `zig build test` 全通过 |

## 风险评估

| 风险 | 缓解措施 |
|------|---------|
| Primitive 表复杂度 | 先实现 5 个核心函数，其余占位 |
| 模式穷举矩阵分解 | 先 ADT+Bool，后 list/嵌套 |
| fork-exec 子进程管理 | Linux pipe+waitpid，Phase 3 仅单命令 |
| 效应检查与约束生成耦合 | 共享 AST 遍历，按步骤 3 集成 |
| 向后兼容 | 所有修改保持 Phase 2 测试通过 |

## 验证方法

| 验证项 | 方法 |
|--------|------|
| 构建通过 | `zig build` |
| 单元测试 | `zig build test`（新增 test_primitive/test_i18n/test_cmd 测试） |
| 回归 | Phase 2 的 244 测试全通过 |
| IO.println | `kun --run` 执行含 `IO.println "hi"` 脚本 |
| Cmd.echo | `kun --run` 执行 `Cmd.echo "hi"` 输出 |
| 效应检查 | 纯函数调用 `IO.println` 报类型错误 |

## 审计要点

1. PrimitiveBinding.is_effect 是否正确替代硬编码命名空间
2. 效应检查规则是否与 `type-system.md` 设计一致
3. 模式穷举是否正确处理 Bool/ADT
4. Cmd 命令调用是否正确 fork-exec
5. 所有 Phase 2 测试是否仍通过

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.21 | 初始版本 |
