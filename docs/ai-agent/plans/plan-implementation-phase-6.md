# 执行计划：Phase 6 — 审计缺陷收官 + 基础设施补齐

## 背景与目标

Phase 1-5 首次审计发现 44 项缺陷，随后修复了 18 项（514 测试全通过）。当前剩余 26 项缺陷类别，其中 Map/Set 哈希表基础设施缺失是核心阻塞项，效应检查器 3 空存根 + 10 未接线次之，Parser 10 种语法缺失影响语言完整性，48 个 Primitive 存根/部分实现限制标准库可用性。

本计划将剩余工作组织为 7 个 Step，按依赖关系排序，每步独立可验证。跨 do_block defer unwind 和子进程信号/signalfd 清理属 v0.2 沙箱范围，标记推迟；checkImplicitDo 标记推迟（需 Parser 支持 bound/unbound 区分）。

## 基线数据

| 维度 | 值 |
|------|-----|
| 测试 | **514**（均通过） |
| 剩余缺陷总数 | **26 个类别**（本计划通过 7 个 Step 全部覆盖，其中 4 项推迟至后续版本） |
| 空存根（effect.zig） | **3**（本计划覆盖 2 个，1 个推迟） |
| 效应函数未接线 | **10**（见 Step 3） |
| Parser 语法缺失 | **10**（见 Step 2） |
| Primitive 存根 | **48**（Step 1：8 个 Map/Set；Step 4-6：40 个 Stream/File/IO/Crypto） |
| Map/Set 基础设施 | **零实现**（MapRepr/SetRepr 为 `[*]u8` 空壳） |

**推迟项（不在本计划范围）**：

| 项 | 原因 |
|----|------|
| 跨 do_block defer unwind（`eval.zig:96-109`） | 需 panic 传播机制大改，v0.2 |
| 子进程信号/signalfd 清理（`cmd.zig:18-31`） | 属 v0.2 沙箱子系统 |
| `checkImplicitDo`（`effect.zig:310`） | 需 Parser 区分 bound/unbound case/if 分支 |
| 等递归类型支持（`unify.zig`） | 需 TypeEnv 别名集合 + occurs check 选择性关闭 |

---

## Step 1：Map/Set 哈希表与 Env.list

### 1.1 新建哈希表模块

**新建文件**：`code/kun-lang/src/runtime/hash_map.zig`（~250 行）

**build.zig 更新**：确保 `hash_map.zig` 被包含在编译图中（与 `value.zig` 同级模块，Zig 的 `@import` 机制会自动处理，但需确认文件路径正确）。

实现开地址哈希表（线性探测），不可变语义（操作返回新哈希表）。

**桶结构**（使用 `[*]u8` 原始字节数组 + 手动偏移计算访问字段，而非 `extern struct`——因为 `extern struct` 不支持 tagged union 字段）：

```zig
// 内部桶布局（以 MapBucket 为例），通过指针计算访问而非直接声明为 extern struct
// bucket_size = @sizeOf(u64) + @sizeOf(Value) * 2 + @sizeOf(bool) + padding
// hash_offset  = 0
// key_offset   = @sizeOf(u64)
// value_offset = @sizeOf(u64) + @sizeOf(Value)
// occ_offset   = @sizeOf(u64) + @sizeOf(Value) * 2
const map_bucket_size = @sizeOf(u64) + @sizeOf(Value) * 2 + @sizeOf(bool) + 7; // comptime
const MAP_BUCKET_SIZE = map_bucket_size - (map_bucket_size % @alignOf(Value)); // 对齐到 Value 对齐边界
```

实际实现中使用 `[*]u8` + 手动偏移读写，或使用 Zig 的 `@ptrCast` 将 `&entries[i * bucket_size]` reinterpret 为指向 bucket struct 的指针。

**核心函数**：

```zig
pub fn hashKey(key: Value) u64 { ... }
// 支持 Int/String/Bool/Char/Path/Duration 六种 key 类型
// 不支持的 key 类型返回 0 并记录 warn 日志（不 panic，由类型检查器保证不会到达）

pub fn keyEqual(a: Value, b: Value) bool { ... }  // 委托 valueEqual

pub fn mapGet(entries: [*]u8, len: u64, cap: u64, key: Value) ?Value { ... }
pub fn mapInsert(allocator, entries: [*]u8, len: u64, cap: u64, key: Value, value: Value) !MapRepr { ... }
pub fn mapRemove(allocator, entries: [*]u8, len: u64, cap: u64, key: Value) !MapRepr { ... }
pub fn mapKeys(allocator, entries: [*]u8, len: u64, cap: u64) ![]Value { ... }
pub fn mapValues(allocator, entries: [*]u8, len: u64, cap: u64) ![]Value { ... }
pub fn setContains(entries: [*]u8, len: u64, cap: u64, key: Value) bool { ... }
pub fn setInsert(allocator, entries: [*]u8, len: u64, cap: u64, key: Value) !SetRepr { ... }
pub fn setRemove(allocator, entries: [*]u8, len: u64, cap: u64, key: Value) !SetRepr { ... }
```

加载因子 0.7 触发扩容（`cap * 2`，最小初始 cap = 8），不可变语义下扩容返回新 `MapRepr`/`SetRepr`。

### 1.2 替换 Map/Set Primitive 存根

**文件**：`code/kun-lang/src/runtime/primitive/data.zig`

将以下 8 个存根（**函数名**，非行号，防止行号偏移）替换为真实实现：

| 函数 | 新实现 |
|------|--------|
| `mapInsertImpl` | 调用 `hash_map.mapInsert`，alloc new + copy all entries |
| `mapGetImpl` | 调用 `hash_map.mapGet` |
| `mapRemoveImpl` | 调用 `hash_map.mapRemove`，alloc new |
| `mapKeysImpl` | 遍历所有 occupied bucket → `Value.list` |
| `mapValuesImpl` | 遍历所有 occupied bucket → `Value.list` |
| `setContainsImpl` | 调用 `hash_map.setContains` |
| `setInsertImpl` | 调用 `hash_map.setInsert`，alloc new |
| `setRemoveImpl` | 调用 `hash_map.setRemove`，alloc new |

### 1.3 修复 Map/Set 字面量求值

**文件**：`code/kun-lang/src/runtime/eval.zig`

`evalMapLiteral` 和 `evalSetLiteral` 当前返回空集合（`entries = &[0]u8{}`）。改为遍历 entries/items，逐一求值键值对并插入哈希表：

```zig
fn evalMapLiteral(entries: []const MapEntry, frame: *Frame, allocator: std.mem.Allocator) EvalError!Value {
    _ = frame;
    var result = Value{ .map = .{ .entries = @constCast(&[0]u8{}), .len = 0, .cap = 0 } };
    for (entries) |e| {
        const k = try eval(e.key, frame, allocator);
        const v = try eval(e.value, frame, allocator);
        const new_rep = try hash_map.mapInsert(allocator, result.map.entries, result.map.len, result.map.cap, k, v);
        result.map = new_rep;
    }
    return result;
}
```

### 1.4 实现 Env.list

**文件**：`code/kun-lang/src/runtime/primitive/io.zig`

```zig
pub fn envListImpl(env: *RuntimeEnv, args: []const Value) Value {
    _ = args;
    var result = Value{ .map = .{ .entries = @constCast(&[0]u8{}), .len = 0, .cap = 0 } };
    // 使用 std.process.Environ 遍历系统环境变量
    // 对每个 "KEY=VALUE" 字符串，按第一个 '=' 拆分为 key 和 value
    // 调用 hash_map.mapInsert 插入到 result 中
    ...
    return result;
}
```

**验证**：`zig build test` 新增 `runtime/test_map_set.zig`（~20 测试）；`Map.insert "k" v m |> Map.get "k"` 返回 v；`#{k = v}` 字面量求值正常；`Env.list` 返回非空 Map。

---

## Step 2：Parser 语法补齐（10 项）

### 2.1 三元表达式 `? :`

**文件**：`code/kun-lang/src/parser/parser.zig`

- 三元在 `parseExpr`（实际是 `parseBinaryOp` 的循环中）处理：解析完左侧表达式后，若 peek 到的 token 是 `.question` → 手动消费 `?` → 递归调用 `parseExpr` 解析 then 表达式 → expect `.colon` → 递归调用 `parseExpr` 解析 else 表达式 → 产生 `Expr.ternary`
- 三元不在 `getPrecedence` 表中（不是二元运算符，是三元运算符）；实现为 `parseBinaryOp` 循环中的特殊分支，使用 `parseExpr` 递归解析 then/else 部分以正确处理内部优先级
- 右结合通过递归调用 `parseExpr` 自然实现（`a ? b : c ? d : e` → `a ? b : (c ? d : e)`）

### 2.2 范围字面量 `[from..to]` / `[from..to..step]`

**文件**：`code/kun-lang/src/parser/parser.zig`

- 在 `lbrack` handler 中：解析完第一个表达式后，**先检查是否有逗号**。若下一个 token 是 `.comma` → 继续作为列表字面量处理（现有行为）
- 若下一个 token 是两个连续 `.dot`（`dot_dot`），且后面跟随表达式（非 `]`），**识别为范围**：`[1..10]` → `Expr.range_literal`；`[1..10..2]` → step 可选
- 区分逻辑：`[a, b]` 是列表（有逗号），`[a..b]` 是范围（无逗号，有 dot_dot）。`[a, ..b]` 是列表 spread（有逗号 + dot_dot）
- **Lexer 修改**：添加 `TokenKind.dot_dot`。修改 `tryReadMultiCharOp` 或添加专门的 `..` 检测（两个连续 dot 合并为一个 dot_dot token）

### 2.3 Record 更新 `{ rec | f = v }`

- 在 `lbrace` handler 中：解析完第一个表达式后检查 `pipe_pat`
- 若 `pipe_pat` → 后续为 field updates → 产生 `Expr.record_update`

### 2.4 可选链 `?.`

- `.opt_chain` 不在 `getPrecedence` 表中（`.dot` 也不在，两者均在 `ident` handler 的链式访问循环中处理）
- 在 `ident` handler 中：当前 `.dot` 循环仅识别 `.dot` token。扩展为同时识别 `.dot`（普通字段访问 → `.record_access`）和 `.opt_chain`（可选链访问）。可选链语义：若 record 为 `nil` → 返回 `nil`，否则正常访问
- 可选链的结果类型为 `?(field_type)`（自动包装为 nilable）

### 2.5 Lambda 解构参数

在 `parseLambda` 中扩展参数处理：
- `.ident` → 当前行为，不变
- `.lparen` → 解析 `(x, y)` 为多个参数名 → 展开为嵌套单参 lambda：`\(x, y) -> body` → `\x -> \y -> body`
- `.lbrace` → 解析 `{n, a}` → 展开为嵌套 lambda + record pattern 匹配
- `.lbrack` → 解析 `\[x, ..rest]` → 同理展开

**注意**：展开为嵌套单参 lambda 与 Kun 的柯里化模型完全一致，不改变类型语义。

### 2.6 Record 模式匹配

在 `parsePattern` 中添加 `.lbrace` case → 解析 `{ field = pat, ... }` → `Pattern.record`

### 2.7 or-pattern

在 `parseCaseExpr` 的 branch 解析中，解析完第一个 pattern 后循环检查 `pipe_pat`：若存在 → 继续解析下一个 pattern → 将所有 pattern 包裹为 or-pattern（或在 `Pattern` 枚举中新增 `.or` 变体）

### 2.8 import 点路径

在 `.kw_import` handler 中：解析第一个 ident → 循环检查 `.dot` → 继续解析后续 ident → 拼接为 `"Foo.Bar.Baz"`

### 2.9 其他语法项

- **else-if 链**：已通过递归 parseExpr 支持，无需改动
- **`.name` 简写 lambda**：在 parsePrefix 中添加 `.dot` case → 解析 `\x -> x.name` 脱糖
- **中置列表 spread**：while 循环中遇到 `..` 不 break，继续解析后续元素

**验证**：`zig build test` 新增 `parser/test_parser_syntax.zig`（~30 测试）；`zig build dump-ast -- <examples/*.kun>` 解析通过。

---

## Step 3：效应检查器完成

### 3.1 实现 checkStreamConsumption 和 checkCommandConsumption

**文件**：`code/kun-lang/src/typecheck/effect.zig`

**注意**：当前这两个函数的签名为 `fn (allocator, errors) !void`（2 参）。实施时将其改为 `fn (allocator, body: *const ast.Expr, errors) !void`（3 参），因为消费分析需要对 AST body 做遍历。

**checkStreamConsumption**：
```
- 遍历 do block body 的每条语句
- 识别 Stream 构造点：`Cmd.<bin> |>`（piped Command 产生 Stream）、`Stream.*` 构造器（如 `Stream.lines`、`Stream.fromList`）
- 识别方式：AST 中 `pipe` 节点左侧为 Command ident、或 `call` 节点目标为 "Stream.*" ident
- 对每个 Stream 变量，验证随后存在消费操作：
  - 直接消费：|> + Stream.toList/iter/fold/string/bytes
  - 传递消费：作为函数参数传递（视为已消费，跨边界不追踪）
- if/case 条件路径：全部路径均需消费
- defer 块内操作不计入消费分析
- 未消费的 Stream → emit stream_not_consumed 错误
```

**checkCommandConsumption**：
```
- 遍历 do block body 的每条语句
- 识别 Command 构造点：Cmd.<bin>（无 ?/!）返回 Command 值
- 验证随后被 |> / Cmd.exec / Cmd.execSafe / ? / ! 消费
- 未消费 → emit command_not_consumed 错误
```

### 3.2 接线效应检查函数到 constraint.zig

在 `constraint.zig` 中插入以下调用：

| 函数 | 接入点 | 说明 |
|------|--------|------|
| `checkCmdInDo` | `call` handler | 识别效应函数名在 do 外调用 |
| `checkPipeCommand` | `pipe` handler | 左侧为 Command 时检查 do 上下文 |
| `checkStreamConsumption` | `do_block` handler | do block 所有语句处理后 |
| `checkCommandConsumption` | `do_block` handler | do block 所有语句处理后 |
| `checkUnusedBindings` | `let_in` / `do_block` handler | 作用域结束时 |
| `checkUnusedResult` | `do_block` handler | 每条表达式语句后 |
| `checkPureExprLast` | `do_block` handler | 最后一条语句 |
| `checkEffectCallback` | `call` handler | 识别 `!` 参数位置 |

### 3.3 修正告警函数错误变体

在 `error.zig` 中新增 3 个专用告警变体：
```zig
unused_binding: struct { name: []const u8, span: Span },
unused_result: Span,
pure_expr_last: Span,
```

更新 `effect.zig` 中 `checkUnusedBindings`/`checkUnusedResult`/`checkPureExprLast` 使用新变体（替换当前的 `effect_in_let`）。更新 `i18n.zig` 添加对应双语消息（告警级别，不影响编译通过）。

**验证**：`zig build test` 新增 `typecheck/test_effect_full.zig`（~25 测试）；Stream 未消费/Command 未消费正确报 `stream_not_consumed`/`command_not_consumed`；纯函数返回 Unit 正确报 `pure_unit_return`；未使用绑定告警。

---

## Step 4：Primitive 存根替换 — Group A（Stream + Cmd pipe）

### 4.1 Stream.iter / Stream.fold 的 eval_fn 注入

**问题**：`Stream.iter`/`Stream.fold` 的 Primitive 实现需要调用 Kun 闭包，但 `PrimitiveFn` 无权访问 `eval()` 函数。当前 `RuntimeEnv`（`primitive.zig:15-23`）不包含 `eval` 引用。

**方案**：在 `RuntimeEnv` 中新增可选字段（使用 `?*anyopaque` 避免循环依赖，与 `Frame.primitives` 一致）：
```zig
eval_fn: ?*anyopaque = null,  // 实际类型：*const fn (*const TypedExpr, *Frame, std.mem.Allocator) EvalError!Value
```
在 `eval.zig` 的 `apply()` 中通过 `@ptrCast` 注入实际函数指针。

**注意**：`eval_fn` 为 `?*anyopaque`，调用前需要解包和类型转换。实现时在 `primitive.zig` 中封装一个 `callEval` helper：
```zig
fn callEval(env: *RuntimeEnv, expr: *const TypedExpr, frame: *Frame) EvalError!Value {
    const fn_ptr: *const fn (*const TypedExpr, *Frame, std.mem.Allocator) EvalError!Value = @ptrCast(@alignCast(env.eval_fn.?));
    return fn_ptr(expr, frame, env.allocator);
}
```
```
- 解析参数：callback (closure) + stream
- 循环 consumeNext
- 对每个元素：创建 Frame，bind 参数，通过 `callEval` 调用回调
```

**`streamFoldImpl`**：
```
- 解析参数：folder (closure) + initial + stream
- 循环 consumeNext，累加器更新为 folder(acc, elem)
```

### 4.2 Stream.range / Stream.iterate

- `streamRangeImpl`：使用 `streamGenerate(start, addStep)` + `streamTake(count)`。`addStep` 作为 `StreamFn.primitive` 包装，通过 `Value.partial` currying 捕获 step 值
- `streamIterateImpl`：`streamGenerate(seed, f)`，无限流

### 4.3 Cmd.pipe / Cmd.pipe!

- 单管道（2 命令）fork pipe 链
- `cmdPipeImpl` → 返回 `Result (Stream String) CommandError`
- `cmdPipeBangImpl` → 消费输出，失败 panic，返回 Unit

**验证**：`zig build test` 新增 `runtime/test_stream_full.zig`（~15 测试）。

---

## Step 5：Primitive 存根替换 — Group B（File 流 + Env + IO）

### 5.1 File 流操作

**文件**：`code/kun-lang/src/runtime/primitive/fs.zig`

将 9 个存根替换为真实实现：

| 函数 | 实现 |
|------|------|
| `writeBytesImpl` | openFile + writeAll |
| `appendBytesImpl` | openFile + lseek(END) + writeAll |
| `readLinesImpl` | openFile → `.lines` StreamNode → 包装为 Result |
| `walkDirImpl` | 递归目录遍历 → `.generate` StreamNode。seed=初始路径；step 函数前进到下一个条目（使用 Dir iterator 或手动栈遍历） |
| `globImpl` | 先 `listDir`（或 walkDir），对每个文件名调用 `glob_engine.match(pattern, filename)` 过滤，收集到 `List Path` |
| `copyImpl` | `std.fs.cwd().copyFile` |
| `renameImpl` | `std.fs.cwd().rename` |
| `removeAllImpl` | `std.fs.cwd().deleteTree` |
| `atomicWriteImpl` | openFile(temp) → writeAll → rename |

### 5.2 File 部分实现修复

| 函数 | 修复 |
|------|------|
| `statImpl` | 调用 `std.fs.cwd().statFile`（验证 Zig 0.17-dev 中实际 API 名称），填充 size/mode/type/atime/mtime/ctime/uid/gid |
| `currentDirImpl` | 改为 `std.process.getCwdAlloc` |
| `homeDirImpl` | 改为 `std.process.getEnvVarOwned("HOME")`（使用 Zig 0.17-dev 中可用的环境变量 API，具体函数名以实际 std lib 为准） |
| `tempDirImpl` | 改为环境变量 API 获取 `"TMPDIR"` |
| `createTempFileImpl` | 添加随机 6 字符后缀替代硬编码 `XXXXXX` |
| `createTempDirImpl` | 同上 |

**注意**：`std.process.getEnvVarOwned` 返回 `![]u8`，需要处理错误路径。如果获取环境变量失败，返回硬编码默认值（`"/root"` / `"/tmp"`）。

### 5.3 Env 函数真实化

**文件**：`code/kun-lang/src/runtime/primitive/io.zig`

| 函数 | 修复 |
|------|------|
| `isTerminalImpl` | `std.io.getStdOut().isTty()` 返回 bool |
| `getenvImpl` | 使用 Zig 0.17-dev 环境变量 API 替代硬编码 |
| `containsEnvImpl` | 环境变量 API 查找 key |

**注意**：`getEnvVarOwned` 返回的 `[]u8` 需要在 Arena 上复制一份，因为其所有权属于 OS。

### 5.4 新建 glob_engine.zig

**新建文件**：`code/kun-lang/src/runtime/glob_engine.zig`（~200 行）

支持 `*`（任意字符序列）、`?`（单字符）、`[abc]`（字符类）、`[!abc]`（否定字符类）。不处理 `{}` 展开和 `**` 递归匹配。

**验证**：`zig build test` 新增 `runtime/test_file_full.zig`（~15 测试）。

---

## Step 6：Primitive 存根替换 — Group C（Regex/DateTime/JSON）

### 6.1 Regex 引擎

**新建文件**：`code/kun-lang/src/runtime/regex_engine.zig`（~550 行）

Thompson NFA 正则引擎（编译→匹配两阶段）：
- 编译：正则模式 → NFA 状态机
- 匹配：NFA 模拟（跟踪活跃状态集）
- 支持：`.` `*` `+` `?` `[]` `()` `|` 转义 `\`
- API：`compile(pattern) !*RegexHandle`（`RegexHandle` 为 `value.zig` 中定义的不透明类型，内部包含编译后的 NFA 状态机）、`isMatch`、`firstMatch`、`allMatches`、`replace`、`replaceAll`、`split`

更新 `crypto.zig` 中 7 个 Regex 存根为真实调用。

### 6.2 DateTime 格式化

**新建文件**：`code/kun-lang/src/runtime/datetime_fmt.zig`（~250 行）

`strftime`/`strptime` 子集：`%Y` `%m` `%d` `%H` `%M` `%S`。
- `dateTimeNowImpl`：`std.time.milliTimestamp()` → i64
- `dateTimeFormatImpl`：timestamp → formatted string
- `dateTimeParseImpl`：string → timestamp（Result）

### 6.3 JSON 解析器

**新建文件**：`code/kun-lang/src/runtime/json_parser.zig`（~250 行）

非递归 JSON 解析器：
- `JsonValue` = Object / Array / String / Number / Bool / Null（内部中间表示）
- `fromString` → `Result JsonValue String`
- `toString` → String
- **Kun Value 映射**：`jsonFromStringImpl` 内部将 `JsonValue` 转换为 `Value`：Object→Map String Value、Array→List Value、String→Value.string、Number→Value.float、Bool→Value.bool、Null→Value.nil

### 6.4 其他

- `sha256StreamImpl`：循环 `consumeNext` → 逐块 `Sha256.update` → `final`
- `validatorRegexImpl`：委托 `Regex.fromString` → Result

**验证**：`zig build test` 新增 `runtime/test_regex.zig` `runtime/test_datetime.zig` `runtime/test_json.zig`（~30 测试）。

---

## Step 7：质量加固

### 7.1 error.zig span 补全

将 `unbound_variable: []const u8` → `unbound_variable: struct { name: []const u8, span: Span }`，`unbound_type` 同处理。**注意**：当前 `constraint.zig` 中这两个错误变体未被实际 emit（约束生成器对未绑定变量创建新类型变量而非报错）。本修改仅更新类型定义和 i18n 格式，为后续未绑定变量检测做准备。**同步更新** `i18n.zig` 的消息格式化以使用 span 而非 `"0:0"`。

### 7.2 pattern.zig narrowType 扩展

从仅处理 Nilable 扩展为处理 ADT 变体收窄（匹配 `Ok v` → 返回 payload 类型）、Bool 分支收窄（True/False → 原类型）。Record/Tuple 字段收窄暂推迟（实现复杂，且类型检查器已有替代路径）。

### 7.3 文档同步

更新 `system-baseline.md:320-390` Typed AST 段，将 `Expr` 和 `TypedExpr` 的变体定义与实际代码（`ast.zig` + `typed.zig`）对齐。

### 7.4 内存泄漏修复

当前 2 个测试有内存泄漏：`test_cmd.zig` 中 `execCommand` 创建的 `StreamNode` buf 未在测试清理中 free。修复方式：在测试 defer 块中确保 `allocator.free(node.cmd.buf)` 被调用。

**验证**：`zig build test` 514 + 新增测试 ≥ 650 全通过；零内存泄漏。

---

## 变更范围总表

| Step | 新建文件 | 修改文件 | 新增代码行 | 新增测试 |
|------|---------|---------|-----------|---------|
| 1 | `hash_map.zig` | `data.zig`, `eval.zig`, `io.zig`, `build.zig`, `test_main.zig` | ~270 | ~20 |
| 2 | — | `parser.zig`, `lexer.zig` | ~220 | ~30 |
| 3 | — | `effect.zig`, `constraint.zig`, `error.zig`, `i18n.zig` | ~250 | ~25 |
| 4 | — | `stream.zig`, `primitive.zig`(RuntimeEnv), `eval.zig`, `build.zig`, `test_main.zig` | ~120 | ~15 |
| 5 | `glob_engine.zig` | `fs.zig`, `io.zig`, `build.zig`, `test_main.zig` | ~350 | ~15 |
| 6 | `regex_engine.zig`, `datetime_fmt.zig`, `json_parser.zig` | `crypto.zig`, `build.zig`, `test_main.zig` | ~1050 | ~30 |
| 7 | — | `error.zig`, `pattern.zig`, `i18n.zig`, `system-baseline.md`, `test_cmd.zig` | ~150 | ~15 |
| **合计** | **5** | **~20** | **~2410** | **~150** |

目标：**514 → ~665 测试**，效应检查器 2 空存根全部实现（1 个推迟），Parser 完整语法覆盖，Map/Set 可用，核心 Primitive 全部真实实现。

---

## 依赖关系

```
Step 1 (哈希表) ─────────── 无依赖
     │
     └── Env.list (Step 1.4) ─── 自然在 Step 1 中完成

Step 2 (Parser) ──────────── 无依赖

Step 3 (效应检查) ────────── 无依赖（AST 级分析，不依赖其他 Step 的产物）

Step 4 (Stream Primitive) ── 无依赖

Step 5 (File/Env Primitive)
     ├── glob → 依赖 Step 5.4 (glob_engine.zig)
     └── 无外部依赖（getenv/contains/isTerminal 不依赖哈希表）

Step 6 (Regex/DateTime/JSON)
     ├── JSON Object→Map → 依赖 Step 1 (hash_map.zig)
     └── 其余引擎文件均在 Step 6 自身中创建

Step 7 (质量加固) ────────── 无依赖
```

Step 1-4 可并行推进（各 Step 触碰不同文件，无冲突）。Step 6 依赖 Step 1（JSON Object→Map 转换需 hash_map.zig）。Step 7 在最后执行。

---

## 推迟项记录（不在本计划范围）

| 项 | 原因 | 目标版本 |
|----|------|---------|
| 跨 do_block defer unwind | 需 panic 传播机制重构 | v0.2 |
| 子进程信号/signalfd 清理 | 属沙箱子系统 | v0.2 |
| `checkImplicitDo` 实现 | 需 Parser 区分 bound/unbound case/if | v0.3 |
| 等递归类型支持 | 需 TypeEnv 别名集合 + occurs check 选择性关闭 | v0.3 |
| 完整沙箱（Landlock/seccomp/rlimit） | CLI 安全参数 + 系统隔离 | v0.2 |
| Kun Shell | 设计定型，交互环境 | v2.0 |

---

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.24 | R6 审计修复（10 项）：依赖图文字矛盾、桶大小 comptime、范围/列表区分逻辑、eval_fn callEval helper、stat API 验证、RegexHandle 类型、版本历史补全 |
| 2026.06.24 | R5 审计：无新问题 |
| 2026.06.24 | R4 审计修复（8 项）：extern struct 移除、三元处理位置修正、可选链不在优先级表、eval_fn→`?*anyopaque`、walkDir/glob 实现细节、unbound_type emit 点不存在、依赖图 Env.list 归属、JSON→Value 映射 |
| 2026.06.24 | R3 审计：无新问题 |
| 2026.06.24 | R2 审计修复（6 项）：目标描述修正、三元 prefix→binaryOp、getEnvVarOwned 版本依赖、build.zig 细节 |
| 2026.06.24 | R1 审计修复（22 项）：步骤数修正为 7、hashKey 不支持类型的处理、桶结构改用 struct 非 extern、行号改为函数名、evalMapLiteral 签名补全、三元优先级改为整数、Lexer dot_dot token 添加说明、Stream 消费检查签名修正、eval_fn 循环依赖方案、Zmq 0.17 getEnvVarOwned API、Env.list 归入 Step 1.4、依赖图修正、推迟项明确化 |
| 2026.06.24 | 初始版本 |

