# 执行计划：Phase 1-5 审计缺陷修复与补齐

## 背景与目标

Phase 1-5 审计发现 44 项缺陷：4 Critical、14 High、16 Medium、10 Low。514 测试全通过，但存在类型盲区、效应检查未完成、41% Primitive 存根、Parser 13 项语法缺失等问题。

本计划将缺陷按依赖关系和优先级组织为 10 个里程碑，每个里程碑独立可验证。

## 基线数据

| 维度 | 值 |
|------|-----|
| 测试 | **514**（均通过） |
| Phase 5 Primitive 注册 | **106**（41 个存根） |
| effect.zig 检查函数 | **18**（3 空存根 + 1 缺失 + 3 错误变体 + 9 未接线） |
| Parser 缺失语法 | **13** 项 |
| 类型检查盲区 | **4** 处（case_expr/compose/record_update/range） |

---

## M1：修复 Critical 缺陷

### 1.1 修复 Parser 运算符优先级反转

**文件**：`code/kun-lang/src/parser/parser.zig:245-268`

**问题**：`getPrecedence` 表将 `|>` 赋值为 0（最低值但算法中低值=紧绑定），导致 `a + b |> f` 解析为 `a + (b |> f)`。

**修复**：反转优先级值——高优先级给更松的运算符。`|>` 赋值最高数值（如 10），`*` 赋值最低数值（如 1）。

```zig
fn getPrecedence(kind: TokenKind) ?u8 {
    return switch (kind) {
        .star, .slash, .mod_op => 1,   // 最紧
        .plus, .minus, .concat => 2,
        .eq, .neq, .lt, .gt, .lte, .gte => 3,
        .and_op => 4,
        .nil_coal => 5,
        .or_op => 6,
        .compose, .compose_rev => 7,
        .pipe, .pipe_rev => 8,          // 最松
        else => null,
    };
}
```

同时更新 `parseBinaryOp` 中的循环条件：`while (getPrecedence(state.peek()) orelse 0 < min_prec)` → `while (getPrecedence(state.peek()) orelse 255 > min_prec)`。

**验证**：`zig build test` 中 parser 测试通过；新增测试 `a + b |> f` 应生成 `pipe(add(a, b), f)`。

### 1.2 修复 Duration `m` 后缀解析

**文件**：`code/kun-lang/src/parser/parser.zig:526`

**问题**：词法器产生 `m` 后缀，解析器检查 `"min"` → 不匹配 → 默认为秒。

**修复**：
```zig
if (std.mem.eql(u8, suffix, "min")) .min  →  if (std.mem.eql(u8, suffix, "m")) .min
```

**验证**：`5m` 解析为 `DurationUnit.min`，新增 Duration 解析测试。

### 1.3 修复 case_expr 分支类型未合一

**文件**：`code/kun-lang/src/typecheck/constraint.zig:365-380`

**问题**：仅取第一个分支类型，未将全部分支统一合一。

**修复**：在 line 378 遍历 branches[1..] 与 branches[0].type_ 调 unify：
```zig
var result_type = branches[0].type_;
for (branches[1..]) |b| {
    unify_mod.unify(env, allocator, result_type, b.type_) catch |err| {
        try errors.add(allocator, .{ .if_branch_mismatch = .{
            .then_type = result_type, .else_type = b.type_, .span = v.span } });
    };
}
```

**验证**：`case x of Ok -> 1, Err -> "str"` 应报 `if_branch_mismatch`。

### 1.4 实现 Map/Set 哈希表

**文件**：`code/kun-lang/src/runtime/value.zig`（value.zig:15-25 的 MapRepr/SetRepr 目前为空占位）

**实施**：
- 在 `value.zig` 中实现开地址哈希表（线性探测）：`fn mapInsert(allocator, key, value, map) !MapRepr` 等
- 支持 6 种 key 类型：`Int`、`String`、`Bool`、`Char`、`Path`、`Duration`（对齐 standard-library.md line 1353-1355）
- 实现 `Value` 的 `fn hash(v: Value) u64` 和 `fn keyEqual(a: Value, b: Value) bool`
- 更新 `data.zig` 中以下函数的存根为真实实现：
  - `mapInsertImpl` (line 119) — 哈希表插入（不可变语义：alloca new + copy）
  - `mapGetImpl` (line 120) — 哈希表查找
  - `mapRemoveImpl` (line 121) — alloc new，过滤该 key
  - `mapKeysImpl` (line 122) — 遍历 → List
  - `mapValuesImpl` (line 123) — 遍历 → List
  - `setContainsImpl` (line 135) — key-only 哈希表查找
  - `setInsertImpl` (line 136) — key-only 插入
  - `setRemoveImpl` (line 137) — key-only 删除
- 更新 `eval.zig` 的 `evalMapLiteral`/`evalSetLiteral`（lines 560-574）从空占位 → 真实填充
- 回补 `Env.list`（io.zig:126-130）从空 map → 遍历 `std.os.environ` 构造 Map

**新增文件**：`code/kun-lang/src/runtime/hash_map.zig`（~200 行）— 独立哈希表模块

**验证**：`Map.insert "k" v m |> Map.get "k"` 返回 v；`Set.insert 1 s |> Set.contains 1` 返回 true；`zig build test` 新增 test_map_set.zig。

---

## M2：修复类型检查器盲区

### 2.1 修复 compose/compose_reverse 约束生成

**文件**：`code/kun-lang/src/typecheck/constraint.zig:536-569`

**问题**：`f >> g` 无约束保证 `f` 输出类型与 `g` 输入类型一致。

**修复**：在脱糖后的 lambda+call 约束生成中，将 left 的返回类型变量与 right 的参数期望类型合一：
```zig
.compose => |v| {
    const typed_left = try inferExpr(allocator, v.left, env, errors);
    const typed_right = try inferExpr(allocator, v.right, env, errors);
    const left_result = try env.newVar(allocator, std.math.maxInt(u32));
    const right_param = try env.newVar(allocator, std.math.maxInt(u32));
    const right_result = try env.newVar(allocator, std.math.maxInt(u32));
    const left_fn_type = try env.registerFunctionType(allocator, false, right_param, left_result);
    const right_fn_type = try env.registerFunctionType(allocator, false, right_param, right_result);
    // unify left's actual type with left_fn_type
    unify_mod.unify(env, allocator, exprType(typed_left), left_fn_type) catch ...
    // unify right's actual type with right_fn_type  
    unify_mod.unify(env, allocator, exprType(typed_right), right_fn_type) catch ...
    // unify left output with right input
    unify_mod.unify(env, allocator, left_result, right_param) catch ...
    ...
}
```

**验证**：`(\x -> x + 1) >> (\y -> "str" ++ y)` 应报类型错误。

### 2.2 修复 record_update 字段类型验证

**文件**：`code/kun-lang/src/typecheck/constraint.zig:601-613`

**问题**：更新字段值与 Record 原字段类型不一致时静默通过。

**修复**：在约束生成时查找原 Record 类型的字段，将更新字段的值类型与原字段类型合一：
```zig
.record_update => |v| {
    const typed_record = try inferExpr(allocator, v.record, env, errors);
    const record_type = env.applySubst(exprType(typed_record));
    // resolve to record fields
    if (env.types.items[record_type] != .record) {
        try errors.add(... "not a record" ...);
        return;
    }
    const rec = env.types.items[record_type].record;
    for (v.fields) |f| {
        const typed_val = try inferExpr(allocator, f.value, env, errors);
        const field_type = lookupFieldType(rec, f.name);
        unify_mod.unify(env, allocator, exprType(typed_val), field_type) catch |err| {
            try errors.add(allocator, .{ .mismatch = ... });
        };
    }
}
```

**验证**：`{ r | name = 42 }` 当 `r.name : String` 时报告类型错误。

### 2.3 修复 range_literal 类型约束

**文件**：`code/kun-lang/src/typecheck/constraint.zig:614-622`

**问题**：from/to/step 无 Int 类型约束，结果类型为新变量。

**修复**：添加 `from ~ Int`、`to ~ Int`、`step ~ ?Int` 合一约束，结果类型设为 `stream_type(int_type)`。
```zig
.range_literal => |v| {
    const typed_from = try inferExpr(allocator, v.from, env, errors);
    const typed_to = try inferExpr(allocator, v.to, env, errors);
    unify_mod.unify(env, allocator, exprType(typed_from), int_type) catch ...
    unify_mod.unify(env, allocator, exprType(typed_to), int_type) catch ...
    if (v.step) |s| {
        const typed_step = try inferExpr(allocator, s, env, errors);
        unify_mod.unify(env, allocator, exprType(typed_step), int_type) catch ...
    }
    const result_ty = try env.registerCompoundType(allocator, .stream, int_type);
    ...
}
```

**验证**：`[1.."hi"]` 应报类型错误。

### 2.4 修复未绑定变量检测

**文件**：`code/kun-lang/src/typecheck/constraint.zig:214-224`

**问题**：`ident` handler 对未注册变量创建新鲜多态类型，无 `UnboundVariable` 错误。

**修复**：在 `ident` handler 中，当变量不在 `let_types` 且非 `Cmd.*` 时，emit `unbound_variable` error 而非创建新鲜变量。但需要区分"尚在绑定处理中"的前向引用和真正的未绑定变量。使用 `env.let_types.contains` 之外的查找机制——引入 `in_progress_bindings` 集合标记正在推导中的变量名。

对于 Phase 5 的简化方案：在 `inferFunction`/`let_in`/`do_block` 中维护一个 visible names 集合，ident handler 检查此集合；不在集合中且不在 `let_types`（Primitive/全局）中则 emit error。

```zig
.ident => |v| {
    if (std.mem.startsWith(u8, v.name, "Cmd.") and !isKnownCmdApi(v.name)) {
        ty = command_type;
    } else if (env.let_types.get(v.name)) |poly_id| {
        ty = try env.freshInstance(allocator, poly_id);
    } else if (env.isInScope(v.name)) {
        ty = try env.newVar(allocator, std.math.maxInt(u32));
    } else {
        try errors.add(allocator, .{ .unbound_variable = v.name });
        ty = error_type; // 占位类型，防止级联错误
    }
}
```

**验证**：未导入/未定义的变量引用应报 `UnboundVariable` 错误。

---

## M3：修复求值器缺陷

### 3.1 修复 ternary 非 Bool 条件

**文件**：`code/kun-lang/src/runtime/eval.zig:172-179`

**问题**：条件非 Bool 时静默返回 else 分支。

**修复**：将 `if (cond == .bool)` 的 else 分支改为返回错误：
```zig
.ternary => |v| {
    const cond = try eval(v.cond, frame, allocator);
    if (cond == .bool) {
        if (cond.bool) return eval(v.then, frame, allocator);
        return eval(v.else_, frame, allocator);
    }
    return error.TypeMismatch;  // 替代原来的 return eval(v.else_, ...)
}
```

**验证**：`42 ? "a" : "b"` 应报 `EvalError.TypeMismatch`。

### 3.2 补全 valueEqual 对复合类型

**文件**：`code/kun-lang/src/runtime/eval.zig:556-557`

**问题**：list/tuple/record/adt/map/set/closure 一律返回 false。

**修复**：为以下类型实现递归等值比较：
- `list`：长度相等 + 逐元素 `valueEqual`
- `tuple`：同 list
- `record`：字段数相等 + 逐字段名+值匹配
- `adt`：tag 相等 + payload `valueEqual`
- `map`：长度相等 + 逐 key 查找 value 并比较
- `set`：长度相等 + 逐元素 `setContains`
- `closure`：指针相等（保守正确）

```zig
.list => |l1| {
    if (b != .list) return false;
    const l2 = b.list;
    if (l1.items.len != l2.items.len) return false;
    for (l1.items, l2.items) |i1, i2| {
        if (!valueEqual(i1, i2)) return false;
    }
    return true;
},
```

**验证**：`[1, 2, 3] == [1, 2, 3]` 返回 true。

### 3.3 修复 matchPattern guard 忽略

**文件**：`code/kun-lang/src/runtime/eval.zig:513-523`

**问题**：`.guard => |g|` 仅匹配内部 pattern，不评估守卫条件。

**修复**：匹配 inner pattern 后，评估 guard 表达式；false 时返回 null（不匹配）：
```zig
.guard => |g| {
    if (matchPattern(allocator, scrutinee, g.inner, bindings)) |frame| {
        const cond = try eval(g.cond, frame, allocator);
        if (cond == .bool and cond.bool) return frame;
        // 守卫不满足 → 不匹配
        return null;
    }
    return null;
},
```

**验证**：`case 5 of x if x > 3 -> "big", _ -> "small"` 应匹配第一分支。

### 3.4 安全化 RuntimeEnv 创建

**文件**：`code/kun-lang/src/runtime/eval.zig:203`、`code/kun-lang/src/runtime/stream_consumer.zig:117`

**问题**：`RuntimeEnv{ .frame = undefined, .primitives = undefined }` 潜在 UB。

**修复**：在 `eval.zig` 和 `stream_consumer.zig` 的 `apply` 函数中，从当前 frame 继承 `primitives` 引用，创建有效的 RuntimeEnv：
```zig
// eval.zig apply()
var renv = RuntimeEnv{
    .frame = frame,
    .primitives = frame.primitives orelse @ptrCast(@alignCast(&empty_table)),
    .allocator = allocator,
};
// stream_consumer.zig applyStreamFn()
var renv: PrimitiveEnv = .{
    .frame = frame,
    .primitives = frame.primitives orelse @ptrCast(@alignCast(&empty_table)),
    .allocator = allocator,
};
```

同时在 `env.zig` 中定义全局 `empty_table: PrimitiveTable = .{ .bindings = &.{} }`。

**验证**：RuntimeEnv 字段不再为 undefined。

---

## M4：补齐效应检查器

### 4.1 实现 3 个空存根

**文件**：`code/kun-lang/src/typecheck/effect.zig`

**4.1a checkImplicitDo (lines 303-307)**
- 遍历 do block body，识别 unbound `case`/`if` 为隐式 do
- 验证隐式 do 分支内含有效应操作（否则告警）
- `defer` 在隐式 do 中的作用域为该分支

**4.1b checkStreamConsumption (lines 309-312)**
- 对 do block body 做 AST 级穷举消费分析
- 检测 `Cmd.<bin>`/`Cmd.pipe`/`Stream.*` 构造的 Stream
- 验证每个 Stream 被 toList/iter/fold/string/bytes 消费
- 条件路径（if/case 分支）全部路径均需消费
- `Cmd.timeout`/`retry` 的 `Ok` 分支 Stream 仍须消费

**4.1c checkCommandConsumption (lines 314-317)**
- 检测 `Cmd.<bin>`（无 `?`/`!`）构造的 Command
- 验证被 `|>` 或 `Cmd.exec` 或 `?`/`!` 消费
- 未被消费的 Command → `command_not_consumed` 错误

### 4.2 新增 checkPureUnitReturn

**文件**：`code/kun-lang/src/typecheck/effect.zig`（新增函数）

**问题**：`pure_unit_return` 错误变体在 error.zig 存在，但效应检查器无对应实现。

**修复**：新增函数检查纯函数返回类型为 Unit 时 emit 错误：
```zig
pub fn checkPureUnitReturn(allocator: std.mem.Allocator, func_name: []const u8, body_type: TypeId, env: *TypeEnv, span: Span, errors: *ErrorList) !void {
    const resolved = env.applySubst(body_type);
    if (resolved < env.types.items.len and env.types.items[resolved] == .unit) {
        try errors.add(allocator, .{ .pure_unit_return = .{ .func_name = func_name, .span = span } });
    }
}
```

在 `constraint.zig` 的 `inferFunction` 和 lambda handler 中调用（仅当 `is_effect = false` 时）。

### 4.3 接线效应检查到 constraint.zig

**文件**：`code/kun-lang/src/typecheck/constraint.zig`

将以下 9 个已实现但未调用的效应检查函数接入约束生成器：

| 函数 | constraint.zig 接入点 |
|------|----------------------|
| `checkEffectCallback` | `call` handler：识别 `!` 参数位置 |
| `checkCmdInDo` | `call` handler：效应函数识别 |
| `checkPipeCommand` | `pipe` handler：Command 左侧 |
| `checkImplicitDo` | `do_block` handler：遍历 body 子 case/if |
| `checkStreamConsumption` | `do_block` handler：遍历 body 后 |
| `checkCommandConsumption` | `do_block` handler：遍历 body 后 |
| `checkUnusedBindings` | `let_in`/`do_block` 作用域结束时 |
| `checkUnusedResult` | `do_block` 各语句后 |
| `checkPureExprLast` | `do_block` handler 最后语句 |
| `checkPureUnitReturn` | `inferFunction` + `lambda` handler（仅纯函数） |

### 4.4 修正错误变体

**文件**：`code/kun-lang/src/typecheck/effect.zig:319-338`

**问题**：`checkUnusedBindings`/`checkUnusedResult`/`checkPureExprLast` 使用 `effect_in_let` 变体。

**修复**：在 `error.zig` 中新增 3 个专用告警变体：
```zig
unused_binding: struct { name: []const u8, span: Span },
unused_result: Span,
pure_expr_last: Span,
```
更新 effect.zig 中 3 个函数使用新变体。更新 i18n.zig 添加对应双语消息。

---

## M5：补齐命令系统

### 5.1 实现 resolvePath（PATH 查找）

**文件**：`code/kun-lang/src/runtime/cmd.zig:106-108`

**修复**：
```zig
fn resolvePath(bin: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    if (std.mem.indexOfScalar(u8, bin, '/') != null) {
        return allocator.dupe(u8, bin);
    }
    const path_env = std.os.getenv("PATH") orelse "/usr/local/bin:/usr/bin:/bin";
    var it = std.mem.splitSequence(u8, path_env, ":");
    while (it.next()) |dir| {
        const full = std.fs.path.join(allocator, &.{ dir, bin }) catch continue;
        defer allocator.free(full);
        const full_z = try allocator.dupeZ(u8, full);
        defer allocator.free(full_z);
        if (std.os.linux.access(full_z, std.os.linux.X_OK) == 0) {
            return allocator.dupe(u8, full);
        }
    }
    return error.CommandNotFound;
}
```

**验证**：`Cmd.echo "hi"` 应找到 `/usr/bin/echo`（或 `PATH` 中其他位置）。

### 5.2 修复 pipe2 为非阻塞模式

**文件**：`code/kun-lang/src/runtime/cmd.zig:13`

**修复**：`.NONBLOCK = false` → `.NONBLOCK = true`

同时更新 `stream_consumer.zig` 中 `cmd` handler（line 17）处理 `EAGAIN`：当 `read` 返回 -1 且 `errno == EAGAIN` 时返回 null（无数据）。

### 5.3 添加子进程信号/signalfd 清理

**文件**：`code/kun-lang/src/runtime/cmd.zig:18-31`（fork 后 exec 前）

按 `system-baseline.md:632-637` 补充：
```zig
// 子进程 fork 后、exec 前
_ = std.os.linux.close(signalfd_fd);  // 关闭 signalfd
std.os.linux.sigaction(std.os.linux.SIG.INT, &.{ .handler = .{ .handler = std.os.linux.SIG.DFL }, ... });
std.os.linux.sigaction(std.os.linux.SIG.TERM, &.{ .handler = .{ .handler = std.os.linux.SIG.DFL }, ... });
// 恢复信号掩码
const empty_mask = std.os.linux.empty_sigset;
_ = std.os.linux.sigprocmask(std.os.linux.SIG.SETMASK, &empty_mask, null);
```

**注**：完整沙箱（Landlock/seccomp/rlimit）推迟 v0.2，Phase 5 仅实现信号清理保障子进程行为正确。

---

## M6：补齐 Stream 缺陷

### 6.1 修复 lines 缓冲区溢出

**文件**：`code/kun-lang/src/runtime/stream_consumer.zig:77-79`

**问题**：当 `l.pos + remaining > l.buf.len` 时数据静默丢弃。

**修复**：
- lines 变体在 value.zig 中初始分配 `max_len + 1` 大小的 buf（而非固定 4096）
- consumeNext 中，当缓冲区满时：截断当前行 → 返回 `Err(LineTruncated{partial_len: max_len})` → 丢弃剩余数据 → 继续下一行
- 正常行（≤ max_len）遇到 `\n` 时返回该行并重置 buf

**实现**（对齐 system-baseline.md:194）：
```zig
.lines => |l| {
    while (try consumeNext(l.upstream, allocator, eval_fn)) |chunk| {
        if (chunk != .bytes) continue;
        const data = chunk.bytes;
        for (data) |b| {
            if (b == '\n') {
                // 返回当前行
                const result = allocator.dupe(u8, l.buf[0..l.pos]) catch return ...
                l.pos = 0;
                return Value{ .string = result };
            }
            if (l.pos < l.max_len) {
                l.buf[l.pos] = b;
                l.pos += 1;
            }
            // 超过 max_len 时不增加 pos，丢弃字符
        }
    }
    // EOF 时返回最后一行（可能不含 \n）
    if (l.pos > 0) {
        const result = allocator.dupe(u8, l.buf[0..l.pos]) catch return ...
        l.pos = 0;
        return Value{ .string = result };
    }
    return null;
}
```

### 6.2 实现 Stream.iter / Stream.fold

**文件**：`code/kun-lang/src/runtime/primitive/stream.zig:16-17`

**问题**：两个函数为存根。

**修复**：
- `streamIterImpl`：循环 `consumeNext`，对每个元素调用闭包（通过 `eval_fn` 注入）
- `streamFoldImpl`：循环 `consumeNext`，累积结果
- 需要在 `RuntimeEnv` 中新增 `eval_fn` 字段（函数指针），由 `eval.zig` 注入

```zig
pub fn streamIterImpl(env: *RuntimeEnv, args: []const Value) Value {
    if (args.len < 2 or args[0] != .closure or args[1] != .stream) return Value{ .unit = {} };
    const callback = args[0].closure;
    var node = args[1].stream;
    while (consumeNext(node, env.allocator, env.eval_fn) catch null) |val| {
        const frame = env.allocator.create(Frame) catch return Value{ .unit = {} };
        frame.* = .{ .bindings = .empty, .parent = callback.env, .primitives = frame.primitives };
        frame.bindings.put(env.allocator, callback.param_names[0], val) catch return Value{ .unit = {} };
        _ = env.eval_fn.?(callback.body, frame, env.allocator) catch {};
    }
    return Value{ .unit = {} };
}
```

**注意**：`eval_fn` 注入引发 `primitive.zig ↔ eval.zig` 循环依赖。解决方案：在 `primitive.zig` 中 `RuntimeEnv` 添加 `eval_fn: ?*const fn (...) EvalError!Value = null`（可选字段），由 `eval.zig:apply` 设置为实际函数。

### 6.3 实现 Stream.range / Stream.iterate

**文件**：`code/kun-lang/src/runtime/primitive/stream.zig:68-69`

**修复**：
- `streamRangeImpl`：调用 `streamGenerate(start, addStep)` + `streamTake(count)`
- `streamIterateImpl`：调用 `streamGenerate(seed, f)`（无限流）

`addStep` 作为 PrimitiveFn 包装：`fn addStepImpl(env: *RuntimeEnv, args: []const Value) Value { return Value{ .int = args[0].int + args[1].int }; }`

使用 `Value.partial` currying 捕获 step 值。

---

## M7：Phase 5 Primitive 补齐 — Group E（加密/编码/解析/日期）

### 7.1 Regex 引擎

**不再自研**：原计划新建 `regex_engine.zig` 实现自研 NFA 引擎，现已改用 zig-regex 依赖（https://github.com/zig-utils/zig-regex）。

使用 zig-regex 提供以下能力：
- `isMatch(regex, input) bool`
- `firstMatch(regex, input) ?Match`
- `allMatches(regex, input) List Match`
- `replace(regex, input, replacement) String`
- `replaceAll(regex, input, replacement) String`
- `split(regex, input) List String`

**build.zig** 添加 zig-regex 包依赖。更新 `crypto.zig:55-61` 的 7 个 Regex 存根为 zig-regex 调用。

### 7.2 DateTime 格式化

**新建文件**：`code/kun-lang/src/runtime/datetime_fmt.zig`（~300 行）

实现自定义 strftime/strptime 子集：
- 支持 `%Y/%m/%d/%H/%M/%S` 格式符
- `format(fmt, timestamp_ms) String`
- `parse(fmt, s) ?i64`

更新 `crypto.zig:48-50` 的 3 个 DateTime 存根。

### 7.3 JSON 解析器

**新建文件**：`code/kun-lang/src/runtime/json_parser.zig`（~300 行）

非递归 JSON 解析器：
- 定义 `JsonValue` union（Object/Array/String/Number/Bool/Null）
- `fromString(s) Result JsonValue String`
- `toString(v) String`

更新 `crypto.zig:52-53` 的 2 个 JSON 存根。

### 7.4 Validator.regex

**文件**：`code/kun-lang/src/runtime/primitive/crypto.zig:62`

改为委托 zig-regex → Result。

### 7.5 Hash.sha256Stream

**文件**：`code/kun-lang/src/runtime/primitive/crypto.zig:28`

实现流式 SHA-256：循环 `consumeNext`，逐块 `Sha256.update`，最后 `final`。

---

## M8：Phase 5 Primitive 补齐 — Group F（文件流操作 + Cmd pipe）

### 8.1 File 流操作函数

**文件**：`code/kun-lang/src/runtime/primitive/fs.zig`

将以下 9 个存根替换为真实实现：

| 函数 | 实现 |
|------|------|
| `writeBytesImpl` (line 172) | openFile + writeAll |
| `appendBytesImpl` (line 186) | openFile + seek end + writeAll |
| `readLinesImpl` (line 187) | openFile → `.lines` StreamNode |
| `walkDirImpl` (line 188) | 递归目录遍历 → `.generate` StreamNode |
| `globImpl` (line 189) | glob 匹配引擎 → `List Path` |
| `copyImpl` (line 201) | `std.fs.cwd().copyFile` |
| `renameImpl` (line 202) | `std.fs.cwd().rename` |
| `removeAllImpl` (line 203) | `std.fs.cwd().deleteTree` |
| `atomicWriteImpl` (line 204) | temp file + rename |

**新建文件**：`code/kun-lang/src/runtime/glob_engine.zig`（~300 行）— 支持 `*`/`?`/`[abc]`。

### 8.2 File 部分实现修复

| 函数 | 修复 |
|------|------|
| `statImpl` (line 55-72) | 调用 `std.fs.cwd().statFile`，填充真实 size/mode/atime/mtime/uid/gid |
| `currentDirImpl` (line 145-148) | 调用 `std.process.getCwdAlloc` |
| `homeDirImpl` (line 150-153) | 调用 `std.os.getenv("HOME")` |
| `tempDirImpl` (line 155-158) | 调用 `std.os.getenv("TMPDIR")` |
| `createTempFileImpl` (line 190-194) | 使用 `std.fs.cwd().createFile` + 随机文件名 |
| `createTempDirImpl` (line 195-200) | 使用 `std.fs.cwd().makeOpenPath` + 随机目录名 |

### 8.3 Cmd.pipe / Cmd.pipe! 实现

**文件**：`code/kun-lang/src/runtime/primitive/stream.zig:89-90`

**修复**：实现单管道（2 命令）fork pipe 链：
- `cmdPipeImpl`：创建 pipe → fork 两个子进程 → stdout 通过 pipe 传递 → 返回 `Command`
- `cmdPipeBangImpl`：同上，丢弃输出返回 Unit

### 8.4 Env 函数真实化

**文件**：`code/kun-lang/src/runtime/primitive/io.zig`

| 函数 | 修复 |
|------|------|
| `getenvImpl` (line 105-117) | 调用 `std.os.getenv` 替代硬编码 |
| `containsEnvImpl` (line 119-124) | 调用 `std.os.getenv(key) != null` |
| `envListImpl` (line 126-130) | 需 M1 的 Map 哈希表就位 → 遍历 `std.os.environ` → 构造 Map |

---

## M9：Parser 语法补齐

### 9.1 实现 parseTernary

**文件**：`code/kun-lang/src/parser/parser.zig`

添加 `cond ? then : else` 解析：
- 在 `parseBinaryOp` 中，`nil_coal` (prec=5) 后处理 `question` token
- parsePrefix 中识别 `question` → 解析 then 表达式 → consume `colon` → 解析 else 表达式
- 产生 `Expr.ternary` 节点

**优先级**：`??` > `? :` > `>>`（在 `getPrecedence` 表中 `question` = 7.5）。

### 9.2 实现 parseRangeLiteral

**文件**：`code/kun-lang/src/parser/parser.zig`

添加 `[from..to]` / `[from..to..step]` 解析：
- 在 `parsePrefix` 的 `lbrack` handler 中，解析完第一个表达式后检查 `..` token
- 若 `..` 后跟表达式（非 `]`），解析为范围字面量
- 产生 `Expr.range_literal` 节点

**需要**： Lexer 中添加 `range` token（`..` 双点），目前 `..` 在 lexer 中未作为独立 token。可复用 list spread 中的 `..` 检测逻辑。

### 9.3 实现 parseRecordUpdate

**文件**：`code/kun-lang/src/parser/parser.zig`

添加 `{ record | field = value }` 解析：
- 在 `parsePrefix` 的 `lbrace` handler 中，识别 `|` token
- 若 record_expr `|` fields `}` → 产生 `Expr.record_update`

### 9.4 实现可选链 `?.`

**文件**：`code/kun-lang/src/parser/parser.zig`

在 `getPrecedence` 表中添加 `.opt_chain` → prec=10（最高，与 `.` 同级）；在 `.dot` handler 中区分 `.field` 和 `?.field`。

### 9.5 实现 Lambda 解构参数

支持 `\(x, y) ->`、`\{name, age} ->`、`\[head, ..tail] ->`：
- 在 `parseLambda` 中，`(` 后解析多个 ident → tuple pattern
- `{` 后解析 field names → record pattern
- `[` 后解析 list pattern 含 `..rest`

### 9.6 实现 Record 模式匹配

在 `parsePattern` 中添加 `.lbrace` → 解析 `{ field1 = pat1, ... }` → `Pattern.record`。

### 9.7 实现 or-pattern 和 else-if 链

- or-pattern：`pat1 | pat2 -> body` → 在 `parsePattern` 中检查 `|` → `Pattern.or(...)`
- else-if：`if ... else if ...` → 在 `parseIfExpr` 中递归处理

### 9.8 修复 import 点路径

支持 `import Foo.Bar` → 解析 `Foo` 后检查 `.` + ident 链，连接为 `"Foo.Bar"`。

---

## M10：质量加固

### 10.1 补全 --dump-ast 为递归 AST 树

**文件**：`code/kun-lang/src/main.zig:66-85`

重写 `dumpAST` 为递归遍历：显示每个声明内部的表达树（缩进表示嵌套），展示节点类型、字面量值、span。

### 10.2 添加 --help 显式标志和 --version

**文件**：`code/kun-lang/src/main.zig`

```zig
if (std.mem.eql(u8, args[1], "--help")) { usage(); return; }
if (std.mem.eql(u8, args[1], "--version")) { std.log.info("kun 0.1.0-dev", .{}); return; }
```

### 10.3 补全 error.zig 的 span 信息

**文件**：`code/kun-lang/src/typecheck/error.zig:14-15`

将 `unbound_variable: []const u8` → `unbound_variable: struct { name: []const u8, span: Span }`
将 `unbound_type: []const u8` → `unbound_type: struct { name: []const u8, span: Span }`

更新 constraint.zig 中所有 emit 位置传入 span。更新 i18n.zig 使用 span 而非 "0:0"。

### 10.4 补全 valueEqual 对 map/set/command

**文件**：`code/kun-lang/src/runtime/eval.zig:556-557`

添加 map/set 的递归等值比较（见 M3.2）；command 使用 bin 名等值（保守）。

### 10.5 修复 lexer 小缺陷

| 缺陷 | 修复 |
|------|------|
| bytes 阈值 (lexer.zig:512-517) | 将 `>16` 改为 `>0` 或使用 `0x` 前缀长度无关 |
| 空 char (lexer.zig:622-643) | `''` → `.invalid` 而非 `.char_literal(0)` |
| 数字尾随 `_` (lexer.zig:402-438) | 检查最后一位，若为 `_` → `.invalid` |

### 10.6 修复 lib.zig API 对齐

**文件**：`code/kun-lang/src/lib.zig`

添加计划中的函数级导出：
```zig
pub const tokenize = lexer.tokenize;
pub const parseModule = parser.parseModule;
```

### 10.7 更新过期文档

**文件**：`docs/ai-agent/architecture/system-baseline.md:320-390`

将 Typed AST 段与实际 `ast.zig`/`typed.zig` 实现同步。

### 10.8 修复 main.zig duplicate string_type

**文件**：`code/kun-lang/src/main.zig:44,46`

将第 4 个参数改为正确类型 ID（检查 `buildPrimitiveTable` 签名——第 4 参数应为 stream 所需类型）。

---

## 依赖关系图

```
M1 (Critical)
├── M1.1 优先级反转 ────────────────────────── 独立
├── M1.2 Duration 后缀 ──────────────────────── 独立
├── M1.3 case 分支合一 ──────────────────────── 独立
└── M1.4 Map/Set 哈希表 ─────────────────────── 独立（阻塞 M8.4）
       │
       └── M8.4 (Env.list) ─── 依赖 M1.4
       
M2 (类型盲区)
├── M2.1 compose 约束 ───────────────────────── 独立
├── M2.2 record_update 字段验证 ─────────────── 独立
├── M2.3 range 类型约束 ─────────────────────── 独立
└── M2.4 未绑定变量 ─────────────────────────── 独立

M3 (求值器)
├── M3.1 ternary 修复 ───────────────────────── 独立
├── M3.2 valueEqual ─────────────────────────── 独立
├── M3.3 guard 修复 ─────────────────────────── 独立
└── M3.4 RuntimeEnv 安全化 ──────────────────── 独立

M4 (效应检查器)
├── M4.1 3 存根实现 ─────────────────────────── 几乎独立（需 TypeEnv 类型信息）
├── M4.2 checkPureUnitReturn ────────────────── 独立
├── M4.3 接线到 constraint ──────────────────── 依赖 M4.1/4.2
└── M4.4 错误变体修正 ───────────────────────── 独立

M5 (命令系统)
├── M5.1 resolvePath ────────────────────────── 独立
├── M5.2 pipe2 非阻塞 ───────────────────────── 独立
└── M5.3 信号清理 ───────────────────────────── 独立

M6 (Stream)
├── M6.1 lines 缓冲区 ───────────────────────── 独立
├── M6.2 iter/fold ──────────────────────────── 独立
└── M6.3 range/iterate ──────────────────────── 独立

M7 (Group E Primitives)
├── M7.1 Regex ──────────────────────────────── 独立（使用 zig-regex 依赖，无新代码文件）
├── M7.2 DateTime ───────────────────────────── 独立（~300 行新代码）
├── M7.3 JSON ───────────────────────────────── 独立（~300 行新代码）
├── M7.4 Validator ──────────────────────────── 依赖 M7.1
└── M7.5 sha256Stream ───────────────────────── 依赖 M6 (stream_consumer)

M8 (Group F Primitives)
├── M8.1 File 流操作 ────────────────────────── 部分依赖 M6
├── M8.2 File 部分实现 ──────────────────────── 独立
├── M8.3 Cmd pipe ───────────────────────────── 依赖 M5
└── M8.4 Env 函数 ───────────────────────────── 依赖 M1.4

M9 (Parser 补齐) ──────────────────────────────── 独立（纯解析器改动）

M10 (质量加固) ─────────────────────────────────── 几乎全独立
```

---

## 里程碑顺序建议

| 阶段 | 里程牌 | 预估变更 | 依赖 |
|------|--------|---------|------|
| 1 | M1.1 + M1.2 | ~20 行 | 无 |
| 2 | M1.3 | ~15 行 | 无 |
| 3 | M2.1–M2.4 | ~60 行 | 无 |
| 4 | M3.1–M3.4 | ~80 行 | 无 |
| 5 | M5.1–M5.3 | ~60 行 | 无 |
| 6 | M6.1–M6.3 | ~100 行 | 无 |
| 7 | M4.1–M4.4 | ~200 行 | 无（效应检查独立于其他模块） |
| 8 | M1.4 (哈希表) + M8.4 | ~300 行 | 无 |
| 9 | M8.1–M8.3 | ~200 行 | M5, M6, M1.4 |
| 10 | M7.1–M7.5 | ~800 行（zig-regex 依赖取代 ~600 行自研引擎） | M6 |
| 11 | M9.1–M9.8 | ~200 行 | 无 |
| 12 | M10.1–M10.8 | ~150 行 | 无 |

**总预估变更**：~2100 行新增/修改代码（因改用 zig-regex 替代自研 ~600 行引擎），12 个阶段，每阶段独立可验证。

---

## 验证方法

| 验证项 | 方法 |
|--------|------|
| 构建通过 | `zig build` |
| 全部测试 | `zig build test`（514 基测 + 每里程碑新增测试） |
| 回归 | 现有 514 测试全通过 |
| 类型安全 | 新增测试验证 M2/M4 修复后的类型错误正确报告 |
| 运行时正确性 | 新增测试验证 M3/M6/M7/M8 修复后的函数行为 |
| 内存安全 | 零内存泄漏（修复 M3.4 和现有的 12 泄漏日志） |

---

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.24 | 初始版本：基于 Phase 1-5 审计 44 项缺陷的修复计划 |

