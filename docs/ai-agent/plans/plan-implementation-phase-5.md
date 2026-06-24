# 执行计划：Phase 5 — 标准库 Primitives 补全 + Stream 函数体

## 背景与目标

Phase 4 完成了效应检查、命令系统、i18n 和 HM 完备化（552 测试通过）。当前 primordial 表仅有 18 个绑定，其中 17 个为 stub（返回 sentinel 假值），仅 `Process.exit` 有真实实现。

Phase 5 目标：将标准库设计中全部非推迟 [Primitive] 函数实现为真实 Zig 绑定，并将 Stream 基础设施从未接线状态推进到完整管道。

> **模块系统搜索路径** 推迟至 Phase 6。Phase 5 不涉及文件系统模块加载、递归编译或循环依赖检测。`import` 声明在运行时仍为 no-op。

## 基线数据

| 维度 | 值 |
|------|-----|
| Phase 4 测试 | **552**（均通过，含 call 约束修复新增 0 测试） |
| 已注册 Primitive | **18**（1 real + 17 stub） |
| Phase 5 待实现 [Primitive] | **105**（17 stub→real + 88 新注册）。表中共 106 绑定含已实现的 `Process.exit` |
| 待实现 StreamNode 构造器 | **9**（mapped/filtered/taken/dropped/lines/parse_mapped/parse_mapped_keep/list_items/generate） |

### Phase 5 前置架构修复（2026.06.24 已完成）

| 修复 | 说明 |
|------|------|
| A1: call 约束生成 | `constraint.zig` call handler 现在生成 `function(arg_type, result_id)` 统一约束，消除类型盲区 |
| A2: Primitive 签名编码 | `PrimitiveBinding.signature: TypeId` → `{arg_count: u8, return_type: TypeId}`，签名注册时构建函数类型链 |
| A3: 多参 currying | `PrimitiveFn` 签名改为 `fn(env, []const Value) Value`，引入 `Value.partial` 支持 curried 调用 |
| A4: ADT payload 通用化 | `Value.adt.payload: [*]u8` → `*Value`，支持非字符串 payload（record/int/nilable 等） |
| 附加: allocator 修复 | `unify.zig` 中 `subst.put` 改用 `env._allocator` 而非调用方传入的 allocator |
| R2: Command 参数系统 | `CommandPayload` 重构为 `{bin, options, positional}`，支持 Record 选项→kebab-case flag 转换 + 位置参数追加 |
| F9-F11: 多态 primitive | `PrimitiveBinding` 新增 `is_polymorphic: bool` 字段；多态 function 跳过类型注册。复杂返回类型的非多态 primitive（如 `File.list : Result (List Path) IOError`）由 `buildPrimitiveTable` 新增 `comptime` 参数传入对应 TypeId；或标记为 `is_polymorphic = true` 延迟至运行时约束 |

## 按模块分组

### 组 A：基础系统调用（已注册 stub → real）— 17 函数

| 模块 | 函数 | 实现依赖 |
|------|------|---------|
| IO | `println`, `readln` | Zig std.io |
| File | `readString`, `list`, `stat` | Zig std.fs + getenv |
| Env | `getenv`, `contains` | std.os.getenv |
| Process | `pid`, `uid`, `gid` | std.os.linux.getpid/getuid/getgid |
| Cmd | `which` | PATH 搜索 |
| Stream | `lines`, `iter`, `fold`, `toList`, `string`, `bytes` | 需 StreamNode 构造器 + 消费者实现 |

`Process.exit` 已为真实实现，无需变更。

### 组 B：IO/Env/Process 扩展（新注册）— 21 函数

| 模块 | 函数 |
|------|------|
| IO | `print`, `eprint`, `eprintln`, `readBytes`, `readAll`, `readAllBytes`, `isTerminal`, `flush` |
| Env | `list` |
| Process | `kill`, `wait`, `sleep` |
| File | `mkdir`, `mkdirAll`, `writeString`, `touch`, `remove`, `removeDir`, `currentDir`, `homeDir`, `tempDir` |

### 组 C：不可变数据结构（新注册）— 28 函数

| 模块 | 函数 |
|------|------|
| List | `length`, `isEmpty`, `head`, `last`, `get`, `append`, `reverse`, `sort`, `slice`, `take`, `drop` |
| Map | `get`, `keys`, `values`, `size`, `isEmpty`, `insert`, `remove` |
| Set | `size`, `isEmpty`, `contains`, `insert`, `remove` |
| Bytes | `length`, `slice` |
| String | `length`, `slice`, `toString` |

### 组 D：Stream 完整化（4 新注册 + 9 构造器）— 6 stub→real 复用组 A 已有绑定

| 类别 | 内容 |
|------|------|
| 新注册 | `Stream.fromList` `Stream.range` `Stream.iterate` `Stream.linesMax` |
| stub→real | `Stream.lines`, `Stream.iter`, `Stream.fold`, `Stream.toList`, `Stream.string`, `Stream.bytes` |
| StreamNode 构造器 | `mapped`, `filtered`, `taken`, `dropped`, `lines`, `parse_mapped`, `parse_mapped_keep`, `list_items`, `generate` |

### 组 E：加密/编码/解析/日期（新注册）— 18 函数

| 模块 | 函数 |
|------|------|
| Hash | `sha256`, `sha256Hex`, `sha256Stream` |
| Base64 | `encode`, `decode` |
| Parser.JSON | `fromString`, `toString` |
| DateTime | `now`, `format`, `parse` |
| Regex | `isMatch`, `firstMatch`, `allMatches`, `replace`, `replaceAll`, `split`, `fromString` |
| Validator | `regex` |

### 组 F：文件流操作 + Cmd pipe（新注册）— 17 函数

| 模块 | 函数 |
|------|------|
| File | `readBytes`, `writeBytes`, `appendString`, `appendBytes`, `readLines`, `walkDir`, `glob`, `createTempFile`, `createTempDir`, `copy`, `rename`, `removeAll`, `atomicWriteString` |
| Cmd | `pipe?`, `pipe!`, `exec`, `execSafe` |

## 变更范围

### 修改文件

| 文件 | 变更 |
|------|------|
| `code/kun-lang/src/main.zig` | `buildPrimitiveTable()` 调用点更新；`infer()` 前后传递 PrimitiveTable |
| `code/kun-lang/src/runtime/primitive.zig` | 新增 ~90 PrimitiveBinding 条目 + 实现函数体；所有 stub→real。按模块组拆分到 `primitive_io.zig`/`primitive_fs.zig`/`primitive_data.zig`/`primitive_stream.zig`（通过 `@import` 聚合回本文件） |
| `code/kun-lang/src/runtime/value.zig` | StreamNode 构造器函数；Map/Set 哈希表辅助函数；makeOk/makeErr ADT 辅助函数；mapFileError 映射；Regex/DateTime 运行时支持 |
| `code/kun-lang/src/runtime/eval.zig` | StreamNode 消费者调用点（传递 `eval` 函数指针到 `stream_consumer.zig`）；map/set literal eval 从零填充→真实填充 |
| `code/kun-lang/src/runtime/cmd.zig` | Cmd.pipe?/pipe!/exec/execSafe 实现 |
| `code/kun-lang/src/typecheck/constraint.zig` | 注册 Primitive 签名到类型环境（消除类型盲区）；`inferModule` 扩展签名 |
| `code/kun-lang/src/test_main.zig` | 每个里程碑后追加新增测试文件的 `@import` |
| `code/kun-lang/build.zig` | 新增源文件注册到 build graph（`stream_consumer.zig`/`sha256.zig`/`base64.zig`/`json_parser.zig`/`regex_engine.zig`/`datetime_fmt.zig`/`glob_engine.zig`/`errors.zig` + 5 primitive 子文件） |

### 新建文件

| 文件 | 预估行数 | 说明 |
|------|---------|------|
| `code/kun-lang/src/runtime/stream_consumer.zig` | ~200 | StreamNode 消费者（consumeNext + 变体分派循环） |
| `code/kun-lang/src/runtime/regex_engine.zig` | ~600 | NFA 运行时正则引擎（编译+匹配） |
| `code/kun-lang/src/runtime/json_parser.zig` | ~300 | 非递归 JSON 解析器（到 JsonValue AST） |
| `code/kun-lang/src/runtime/base64.zig` | ~80 | Base64 编解码 |
| `code/kun-lang/src/runtime/sha256.zig` | ~120 | SHA-256 实现 |
| `code/kun-lang/src/runtime/primitive_io.zig` | ~400 | IO/Env/Process Primitive 实现 |
| `code/kun-lang/src/runtime/primitive_fs.zig` | ~600 | File Primitive 实现 |
| `code/kun-lang/src/runtime/primitive_data.zig` | ~500 | List/Map/Set/String/Bytes Primitive |
| `code/kun-lang/src/runtime/primitive_stream.zig` | ~400 | Stream/Cmd pipe Primitive |
| `code/kun-lang/src/runtime/datetime_fmt.zig` | ~300 | 自定义 strftime/strptime 实现 |
| `code/kun-lang/src/runtime/glob_engine.zig` | ~300 | 自定义 glob 匹配引擎 |
| `code/kun-lang/src/runtime/errors.zig` | ~50 | `mapFileError` 集中错误映射 + ADT 构造辅助 |

## ADT Tag 编号约定

Primitive 函数返回 `Result T E` 等 ADT 值时，需要统一 tag 编号：

| ADT 类型 | 变体 | Tag |
|----------|------|-----|
| **Result T E** | `Ok` | 0 |
| | `Err` | 1 |
| **IOError** | `NotFound` | 0 |
| | `PermissionDenied` | 1 |
| | `AlreadyExists` | 2 |
| | `Unsupported` | 3 |
| | `Other` | 4 |
| **CommandError** | `NotFound` | 0 |
| | `PermissionDenied` | 1 |
| | `CommandFailed` | 2 |
| | `KilledBySignal` | 3 |
| | `IoError` | 4 |
| | `PipeFailed` | 5 |
| | `Timeout` | 6 |
| **File.Type** | `Regular` | 0 |
| | `Directory` | 1 |
| | `SymbolicLink` | 2 |
| | `Socket` | 3 |
| | `Fifo` | 4 |
| | `CharDevice` | 5 |
| | `BlockDevice` | 6 |
| | `Unknown` | 7 |
| **LineError** | `LineTruncated` | 0 |

> **ADT payload 构造**：前置修复 A4 已将 `Value.adt.payload` 改为 `*Value`。构建 `Ok(val)` 时，在 Arena 上分配 `Value` 并赋值，设置 `tag = 0`。构建 `Err(err)` 时同样分配 `Value` 并设置 `tag = 1`。提取时通过 `value.adt.payload.*` 直接解引用。

## ADT 值构造辅助函数

所有返回 `Result T E` 的 Primitive 必须使用统一的 ADT 构造模式。在 `value.zig` 中新增：

```zig
pub fn makeOk(val: Value, allocator: std.mem.Allocator) !Value {
    const payload = try allocator.create(Value);
    payload.* = val;
    return Value{ .adt = .{ .tag = 0, .payload = payload } };
}

pub fn makeErr(tag: u8, val: Value, allocator: std.mem.Allocator) !Value {
    const payload = try allocator.create(Value);
    payload.* = val;
    return Value{ .adt = .{ .tag = tag, .payload = payload } };
}
```

## Zig 文件系统错误 → IOError Tag 映射

在 `primitive.zig` 中新增集中映射函数，供所有 File/Process primitive 使用：

| Zig 错误 | IOError Tag |
|----------|-------------|
| `error.FileNotFound` / `FileNotFound` | 0 (NotFound) |
| `error.AccessDenied` / `PermissionDenied` | 1 (PermissionDenied) |
| `error.PathAlreadyExists` / `AlreadyExists` | 2 (AlreadyExists) |
| `error.NameTooLong` / `Unsupported` | 3 (Unsupported) |
| 其他 | 4 (Other) |

## Stream 消费者 I/O 错误路径

`consumeNext(node, allocator) EvalError!?Value`：对 `.cmd` 变体的 `read(fd, buf)` 调用：
- 返回 0 → `null` (EOF，关闭 fd + waitpid)
- 返回 <0 → 检查 errno：`EAGAIN` 重试、`EPIPE`/`EIO` → `error.IoError`
- 返回 >0 → 读取的字节 → 转换为 `Value`

## 实施步骤

### Step 1: Primitive 签名注册到类型环境（消除类型盲区）

**前置依赖**：无

**现状**：constraint.zig 对 `Module.name` 标识符创建 fresh type variable（无类型约束），PrimitiveBinding 存储 `{arg_count, return_type}` 但类型环境不查询。导致类型检查器接受任意 primitive 调用签名。

**实施**：
- `constraint.zig:inferModule`：扩展签名接收 `*const PrimitiveTable` 参数，遍历 binding → 对每个 binding 构造完整函数类型链（`registerFunctionType` 逐层包装 `arg_count` 层）→ 注入 `TypeEnv.let_types`（key = `"Module.name"`，value = 函数类型 ID 的 `freshInstance`）。`main.zig` 的调用方在 `typecheck.infer()` 之前调用 `buildPrimitiveTable()` 并传入
- `PrimitiveBinding` 字段已为 `{arg_count: u8, return_type: TypeId}`（前置修复 A2 中已完成），签名注册时使用 `registerFunctionType` 逐层构建函数类型链

> **注意**：`env.registerFunctionType(allocator, is_effect, param_type, result_type)` 已存在于 `env.zig:247`。签名注册时逐层调用此函数构建 curried 函数类型链：`List.get : Int → List a → ?a` 通过 2 次 registerFunctionType 调用构建。此步骤仅注册 Phase 4 已存在的 18 个 Primitive 签名。后续 Step 3-7 每完成一个模块组后，调用 `registerPrimitiveSignatures(env, binding)` 增量注册新签名。Step 8 统一验证全部 105 签名已就位。

### Step 2: Stream 基础设施 — 消费者 + 构造器

**前置依赖**：无（纯运行时）

**现状**：StreamNode 10 变体仅 `cmd` 有构造函数（`cmd.zig:execCommand`）。6 个已注册 Stream Primitive 均返回 sentinel。

**实施**：

**2a. StreamNode 构造器**（`value.zig`）：
- `streamMap(upstream, f)` — 创建 `.mapped` 节点
- `streamFilter(upstream, pred)` — 创建 `.filtered` 节点
- `streamTake(upstream, n)` — 创建 `.taken` 节点
- `streamDrop(upstream, n)` — 创建 `.dropped` 节点
- `streamLines(upstream, max_len)` — 创建 `.lines` 节点
- `streamParseMap(upstream, f)` — 创建 `.parse_mapped` 节点
- `streamParseMapKeep(upstream, f)` — 创建 `.parse_mapped_keep` 节点
- `streamFromList(items)` — 创建 `.list_items` 节点（index=0）
- `streamGenerate(seed, f)` — 创建 `.generate` 节点（count=0）

**2b. Stream 消费者**（独立文件 `stream_consumer.zig`）：
- `consumeNext(node, allocator, eval_fn) EvalError!?Value` — 从 StreamNode 链中拉取下一个 Value。按变体分派：
  - `.cmd` → `read(fd, buf)`，EOF 返回 `null`（关闭 fd + `waitpid`）
- `.mapped` → while 循环拉取 upstream，对每个元素调用 `f`（通过 `applyStreamFn(f, elem, eval_fn)`），返回变换值
- `.filtered` → while 循环拉取 upstream，跳过不满足 `pred` 的元素
- `.taken` → while 循环拉取 upstream，递减 `remaining` 计数器
- `.dropped` → while 循环拉取 upstream，跳过前 `remaining` 个
- `.lines` → while 循环读取 upstream，按 `\n` 分割，返回 `Result String LineError`
- `.parse_mapped` → while 循环拉取 upstream，对每个元素调用 `f`，过滤 Err
- `.parse_mapped_keep` → while 循环拉取 upstream，对每个元素调用 `f`，保留 Err 通过
- `.list_items` → 返回 `items[index]`，`index += 1`；`index >= items.len` → null
- `.generate` → 返回 `seed`，`seed = f(seed)`，`count += 1`

> **StreamFn 调用协议**：`applyStreamFn(stream_fn: StreamFn, arg: Value, eval_fn: EvalFn) EvalError!Value` 在 `stream_consumer.zig` 中定义。对 `.primitive` 变体直接调用 `fn_ptr`；对 `.closure` 变体调用 `eval_fn(closure.body, frame, allocator)`。`EvalFn = *const fn (expr, frame, allocator) EvalError!Value` 由 `eval.zig` 在调用 `consumeNext` 时注入。

**2c. Primitive 实现**（`primitive.zig`）：
- `streamLinesImpl` → 构造 `.lines` 节点（非直接消费）
- `streamToListImpl` → `consumeNext` 循环 → `List Value`
- `streamStringImpl` → `consumeNext` 循环 → 拼接 String
- `streamBytesImpl` → `consumeNext` 循环 → 拼接 Bytes
- `streamIterImpl` → `consumeNext` 循环 → 对每个元素调用回调
- `streamFoldImpl` → `consumeNext` 循环 → 累积 fold

> **构造器与 Primitive 映射**：Step 2a 中 `mapped`/`filtered`/`taken`/`dropped`/`parse_mapped`/`parse_mapped_keep` 这 6 个构造器暂不对应 Kun 层 API——`Stream.map`/`filter` 等为 [PureKun] 函数推迟至 Phase 6。`list_items` 和 `generate` 分别服务于 `Stream.fromList` 和 `Stream.range`/`Stream.iterate` Primitive。其余构造器作为内部基础设施，由 `Stream.lines` Primitive 间接使用（`.lines` 变体），或通过 `value.zig` 的构造器函数由单元测试直接验证。

### Step 3: 基础系统调用（组 A stub→real）

**前置依赖**：无

**实施**：将已注册的 17 个 stub 函数体替换为真实实现：

| 函数 | 实现 |
|------|------|
| `IO.println` | `std.io.getStdOut().writer().print("{s}\n", .{s})` |
| `IO.readln` | `std.io.getStdIn().reader().readUntilDelimiterOrEofAlloc(allocator, '\n', 65536)` |
| `File.readString` | `std.fs.cwd().readFileAlloc(allocator, path, max)` |
| `File.list` | `std.fs.cwd().openIterableDir(path).iterate()` → List Path |
| `File.stat` | `std.fs.cwd().statFile(path)` → File.Stat record |
| `Env.getenv` | `std.os.getenv(key)` → ?String |
| `Env.contains` | `std.os.getenv(key) != null` → Bool |
| `Process.pid` | `std.os.linux.getpid()` → Int |
| `Process.uid` | `std.os.linux.getuid()` → Int |
| `Process.gid` | `std.os.linux.getgid()` → Int |
| `Cmd.which` | PATH 搜索 → `?Path` |

`Stream.*` 6 个 stub 已在 Step 2c 中替换。

### Step 4: IO/Env/Process 扩展（组 B 新注册）

**前置依赖**：Step 3（共享 Arena 分配器和错误处理模式）。注意 `Env.list` 需要 Map 哈希表（Step 5），该项在 Step 4 中跳过，Step 5 后回补

**实施**：注册新 PrimitiveBinding 条目并实现函数体：

| 函数 | 实现关键 |
|------|---------|
| `IO.print` | `writer.print("{s}", .{s})` 不含换行 |
| `IO.eprint`/`IO.eprintln` | `getStdErr()` 写入 |
| `IO.readBytes` | `reader.readAllAlloc(allocator, max)` → Result |
| `IO.readAll`/`IO.readAllBytes` | 全量读取 stdin |
| `IO.isTerminal` | `std.io.getStdOut().isTty()` |
| `IO.flush` | writer flush |
| `Env.list` | 推迟至 Step 5 后实施（需 Map 哈希表基础设施） |
| `Process.kill` | `std.os.linux.kill(pid, sig)` |
| `Process.wait` | `std.os.linux.waitpid(-1, ...)` |
| `Process.sleep` | `std.time.sleep(duration_ns)` |
| `File.mkdir`/`mkdirAll` | `cwd().makeDir`/`makePath` |
| `File.writeString` | `cwd().writeFile(.{ .sub_path = path, .data = s })` |
| `File.touch` | `cwd().createFile(path, .{ .truncate = false })` |
| `File.remove`/`removeDir` | `cwd().deleteFile`/`deleteDir` |
| `File.currentDir`/`homeDir`/`tempDir` | `std.process.getCwdAlloc(allocator)`/`std.os.getenv("HOME")`/`std.fs.path.join(allocator, &.{std.os.getenv("TMPDIR") orelse "/tmp"})` |

### Step 5: 不可变数据结构（组 C）

**前置依赖**：无

**实施**：实现 List/Map/Set/Bytes/String 的纯函数：

**5a. List 操作**（`primitive.zig`）：
所有 List 函数操作 `Value.list.items` slice：
- `length` → `items.len`
- `isEmpty` → `items.len == 0`
- `head` → `items[0]`（Nilable）
- `last` → `items[items.len-1]`（Nilable）
- `get i list` → `items[i]`（Nilable，OOB→Nil）
- `append a b` → alloc new slice，复制 + 拼接
- `reverse` → alloc new slice，逆序复制
- `sort cmp list` → alloc new slice，排序（`std.sort.block`）
- `slice start len list` → alloc new slice
- `take n list` → first n
- `drop n list` → skip n

**5b. Map/Set 操作**（`primitive.zig`）：
当前 `MapRepr` 和 `SetRepr` 是零字段指针占位：
```zig
pub const MapRepr = struct { entries: [*]u8, len: u64, cap: u64 };
pub const SetRepr = struct { entries: [*]u8, len: u64, cap: u64 };
```

需实现最小哈希表（开放寻址 + 线性探测）：
- `Map.insert k v m` → 哈希表插入（不可变语义：alloc new + copy）
- `Map.get k m` → 哈希表查找
- `Map.remove k m` → alloc new，过滤该 key
- `Map.keys`/`values` → 遍历 → List
- `Map.size`/`isEmpty` → `len` 字段
- `Set.insert/remove/contains/size/isEmpty` → 同理（key-only 哈希表）

**5c. Bytes/String**（`primitive.zig`）：
- `Bytes.length` → `.len`
- `Bytes.slice start len b` → `b[start..start+len]`
- `String.length` → `.len`
- `String.slice start len s` → `s[start..start+len]`
- `String.toString a` → 运行时类型分发（int→格式化、string→自身、bool→"true"/"false"等）

**5d. Env.list 回补**（Step 4 延期项）：
- `Env.list` → `std.os.environ` 遍历 → 构造 Map String String（使用 5b 中的哈希表基础设施）

**5e. Map/Set literal eval 真实化**（`eval.zig`）：
- `evalMapLiteral` 和 `evalSetLiteral` 当前返回空占位结构。改为调用 5b 中的哈希表构造逻辑，实填 entries 数据

### Step 6: Stream 新注册 + 流式 File/Cmd（组 D + 组 F）

**前置依赖**：Step 2（Stream 消费者/构造器）、Step 3（基础 syscall）

**实施**：

**6a. Stream 新 Primitive**：
- `Stream.fromList list` → `streamFromList(list.items)` — 惰性列表迭代（`.list_items` 变体）
- `Stream.range start end step` → 构造 `streamGenerate(start, addStep)` + `.taken` 限制。`addStep` 通过 PrimitiveFn 实现（`fn addStep(env, args) Value` 返回 `args[0].int + step`），作为 StreamFn.primitive 包装
- `Stream.iterate f seed` → `streamGenerate(seed, f)` — 无限迭代流
- `Stream.linesMax n stream` → `streamLines(stream, n)`

**6b. 文件流操作**：
- `File.readBytes path` → openFile → StreamNode（`.cmd` 变体 fd，注意 `pid` 字段为 -1 标记文件源；消费者 EOF 时检查 pid<0 跳过 waitpid）→ 包装为 `Ok(stream)`
- `File.writeBytes path stream` → 消费 stream → writeFile
- `File.readLines path` → openFile → `.lines` StreamNode → 包装为 Result
- `File.walkDir path` → 递归目录遍历 → `.generate` StreamNode
- `File.glob pattern path` → glob 匹配 → 收集为 `List Path` → 返回 `Result (List Path) IOError`
- `File.appendString path s` → `writeFile(.{ .flags = .{ .mode = .read_write } })`
- `File.appendBytes path b` → openFile + seek end + writeAll
- `File.atomicWriteString path s` → temp file + rename
- `File.copy src dst` → `std.fs.cwd().copyFile(src, dst, .{})` → Result
- `File.rename old new` → `std.fs.cwd().rename(old, new)` → Result
- `File.removeAll path` → `std.fs.cwd().deleteTree(path)` → Result
- `File.createTempFile` → `std.fs.cwd().createFile(tmpName, .{ .read = true })` → Result Path
- `File.createTempDir` → `std.fs.cwd().makeOpenPath(tmpDir, .{})` → Result Path

**6c. Cmd pipe 函数**：
- `Cmd.exec cmd` → 调用 `execCommand` → 丢弃输出 → Unit
- `Cmd.execSafe cmd` → 调用 `execCommand` → Result
- `Cmd.pipe? cmds` → fork pipe chain → Result (Stream String)
- `Cmd.pipe! cmds` → fork pipe chain → panic on error → Unit

### Step 7: 加密/编码/解析/日期（组 E）

**前置依赖**：Step 5c（String.toString 基础类型转换）

**7a. Hash**（`sha256.zig`）：
- `sha256 bytes` → `std.crypto.hash.sha2.Sha256.hash(b, &out, .{})`
- `sha256Hex bytes` → SHA-256 → hex 编码 String（`std.fmt.bytesToHex`）
- `sha256Stream stream` → 循环调用 `consumeNext(stream_node, allocator, eval_fn)` 逐块更新 → `Sha256.final(&ctx, &out)`；作为 Primitive 函数接收 StreamNode，复用 `stream_consumer.zig` 的消费者 API

**7b. Base64**（`base64.zig`）：
- `encode` → Bytes → base64 String
- `decode` → String → Result Bytes

**7c. Parser.JSON**（`json_parser.zig`）：
- 定义 `JsonValue` union（`Object/Array/String/Number/Bool/Null`）
- `fromString` → 非递归 JSON 解析 → Result JsonValue
- `toString` → JsonValue → JSON String 序列化

**7d. DateTime**（`primitive.zig`）：
- `now` → `std.time.milliTimestamp()` → DateTime (i64)
- `format fmt dt` → strftime → Result String
- `parse fmt s` → strptime → Result DateTime

**7e. Regex**（`regex_engine.zig`）：
- 运行时正则编译（NFA→DFA 或 PCRE2 风格递归下降）
- `fromString` → 编译 → Result Regex
- `isMatch`、`firstMatch`、`allMatches`、`replace`、`replaceAll`、`split` 基于编译后 Regex
- `Validator.regex` → 委托 `Regex.fromString` → Result

### Step 8: 签名回补与类型安全验证

**前置依赖**：Steps 3-7 全部完成

**现状**：Step 1 启动增量注册（每个模块组完成后注入签名）。Steps 3-7 完成后，Step 8 验证全部签名已注册，并填充任何遗漏的绑定。

**实施**：
- 在 `buildPrimitiveTable()` 返回后，调用 `registerAllPrimitiveSignatures(env, table)` 遍历全部 binding，对每个 `module.name` → 注入 `env.let_types`
- 验证类型安全：
  - `String.length 42` → 类型错误 `Int ≠ String`
  - `List.append "x" [1,2,3]` → 类型错误
  - `Map.insert 1 "v" m`（m 为 `Map Int Int`）→ 类型错误 `String ≠ Int`
  - 正确用法 `String.length "hello"` → 类型检查通过
  - `List.head []` → 类型为 `?a` 不报错
- 若签名注册后导致现有 552 测试失败，逐个检查是否为暴露 latent type error（原 stub 时期被掩盖的类型不一致）

> **注意**：注册的签名类型 ID 是原始的编译期常量（`int_t`/`string_t` 等），需通过 `freshInstance()` 实例化以避免跨模块类型 ID 别名冲突——`freshInstance` 将泛化变量替换为新分配的类型变量，与 Phase 3 的 Let 多态机制相同。

## 验证方法

| 验证项 | 方法 |
|--------|------|
| 构建通过 | `zig build` |
| 单元测试 | `zig build test`（每组新增测试文件） |
| 回归 | Phase 4 的 552 测试全通过 |
| IO.println | `kun --run` 执行含 `IO.println "hi"` 的脚本（已能执行但当前输出空，修复后应输出 "hi"） |
| List 操作 | `zig build test` 验证 List.length/head/get/append/reverse/sort |
| Map 操作 | `zig build test` 验证 Map.insert/get/remove |
| Stream 管道 | `zig build test` 验证 `fromList→toList` 终操作；StreamNode 构造器单元测试 |
| DateTime | `zig build test` 验证 now/format epoch |
| Regex | `zig build test` 验证 isMatch/firstMatch/replace |
| 类型安全 | `zig build test` 验证 `String.length 42` 被类型检查器拒绝（Int ≠ String）；正确用法通过 |

### 新增测试文件

| 文件 | 预估测试数 | 覆盖 |
|------|-----------|------|
| `runtime/test_io.zig` | 15 | IO.print/println/readln/eprint/flush/isTerminal |
| `runtime/test_file.zig` | 20 | File.readString/writeString/list/stat/mkdir/touch/currentDir |
| `runtime/test_env_proc.zig` | 15 | Env.getenv/contains/list + Process.pid/uid/gid/exit/kill/sleep |
| `runtime/test_list.zig` | 20 | List 全 11 函数 |
| `runtime/test_map_set.zig` | 20 | Map 全 7 + Set 全 5 |
| `runtime/test_string_bytes.zig` | 10 | String.length/slice/toString + Bytes.length/slice |
| `runtime/test_stream_transform.zig` | 25 | Stream.fromList/map/filter/take/drop/lines/toList/iter/fold |
| `runtime/test_hash_base64.zig` | 10 | sha256/encode/decode |
| `runtime/test_datetime.zig` | 10 | now/format/parse |
| `runtime/test_regex.zig` | 15 | Regex 全 7 + Validator.regex |
| `runtime/test_json.zig` | 10 | Parser.JSON.fromString/toString |
| `runtime/test_cmd_pipe.zig` | 15 | Cmd.exec/execSafe/pipe?/pipe! |
| `typecheck/test_primitive_types.zig` | 10 | 类型安全：错误调用被拒绝 + 正确调用通过 |
| **合计** | **~195** | |

## 分期里程碑

| 阶段 | 产出 | 验证标准 |
|------|------|---------|
| M1: 类型注册 | Primitive 签名 → TypeEnv | `String.length` ident 类型约束生效 |
| M2: Stream | 7 构造器 + 消费者 + 6 stub→real | StreamNode 构造器 + 消费者单元测试；`Stream.lines`/`Stream.toList` Primitive 测试 |
| M3: 基础 syscall | 组 A 全部真实实现 | `IO.println "hello"` 输出；`File.readString` 读文件 |
| M4: IO/Env/Proc 扩展 | 组 B 全部注册+实现（`Env.list` 除外，其绑定位先于 M5 注册，实现在 Step 5d 回补） | `File.mkdir` 创建目录 |
| M5: 数据结构 | 组 C 全部实现 | `List.sort`/`Map.insert`/`Set.contains` |
| M6: Stream+File流+Cmd | 组 D + 组 F | `Cmd.exec "ls" \|> Stream.lines \|> Stream.toList` |
| M7: 加密/编码/日期/Regex | 组 E 全部 | `Hash.sha256`/`Base64.encode`/`Regex.isMatch` |
| M8: 签名回补+类型安全 | 105 Primitive 签名全注册 + 类型错误验证 | `String.length 42` 被拒绝；552 回归通过 |
| M9: 集成 | 全部新增 ~195 测试 + 552 回归 | `zig build test` 全通过；`kun --run` 端到端脚本验证 |

## 风险评估

| 风险 | 缓解措施 |
|------|---------|
| 106 Primitive 实现量大，可能引入内存泄漏 | 全部使用 Arena 分配器，单测试文件隔离；Valgrind/LeakSanitizer 检查 |
| Map/Set 哈希表实现正确性 | Step 5 独立实现 + 独立测试；使用 Zig std.hash 非加密哈希。仅需支持 6 种白名单 key 类型（`Int`/`String`/`Bool`/`Char`/`Path`/`Duration`），对齐 `standard-library.md:1353-1355` |
| StreamNode 消费者递归深度（长管道） | 消费者实现使用 while 循环非递归；Arena 分配避免栈溢出 |
| StreamFn closure 调用形成循环依赖 | Stream 消费者逻辑放置在独立文件（`stream_consumer.zig`），同时 import `value.zig`（类型）和接收 `eval` 函数指针避免直接 import `eval.zig`；`primitive.zig` 通过函数指针传入 `eval` |
| Stream.iterate 无限流耗尽 Arena | 承认此为用户错误（消费无限流），`toList` 等终操作在 Arena OOM 时返回 `OutOfMemory` 错误而非 panic |
| Regex 引擎实现复杂度 | 实现简化版 NFA 正则（支持基本元字符：`.*+?[]()` `\|`），推迟高级特性到后续版本；预估 ~600 行（非初始 400 行） |
| Primitive 数量导致 primitive.zig 单文件过长 | 按模块拆分为 `primitive_io.zig`/`primitive_fs.zig`/`primitive_data.zig`/`primitive_stream.zig` 共 4 个子文件，通过 `@import` 聚合 |
| Env.list 需 Map 哈希表（Step 4 依赖 Step 5） | 将 `Env.list` 声明上移至 Step 5 后实施，Step 4 中注释 Env.list 依赖 |
| **回归保护** | M1/M8 后立即运行全量 552 测试，diff 失败列表；逐一检查是否为 latent type error（之前 stub 掩盖的类型不一致）
| IO.isTerminal 签名 ambiguity | 实现为 `() -> Bool`（运行时 syscall），标注 `is_effect = true`；设计文档中的 `isTerminal : Bool` 视为省略参数列表的简写 |
| **Stream transform 函数归属** | `Stream.map`/`filter`/`take`/`drop` 等为 [PureKun] 函数，不属 Phase 5 [Primitive] 范围。Phase 5 仅实现底层 StreamNode 构造器；Kun 层 API 在 Phase 6 通过模块系统加载 .kun 文件实现 |
| **Stream I/O 错误路径缺失** | `consumeNext` 对 `.cmd` fd 的 `read()` 调用需处理 errno 错误（EPIPE/EIO/EAGAIN）。消费者接口从 `?Value` 扩展为 `EvalError!?Value`；I/O 错误时返回 `error.IoError` |
| **ADT 构造无统一辅助** | 在 `value.zig` 新增 `fn makeOk(val: Value, allocator) !Value`、`fn makeErr(tag: u8, val: Value, allocator) !Value`，统一 ADT 构造模式 |
| **Zig 错误→IOError tag 映射分散** | 在新建文件 `runtime/errors.zig` 中新增 `fn mapFileError(err: anyerror) u8` 集中映射（`FileNotFound→0, AccessDenied→1, NameTooLong→3` 等），供所有 Primitive 子文件通过 `@import` 共享 |
| **v0.1 无沙箱安全警告** | Step 3 实施时记录：`File.*`/`Process.kill`/`Cmd.*` 在 v0.1 中不受 `--allow-path`/`--allow-net` 限制；沙箱推迟至 v0.2 |
| **createTempFile/createTempDir 自动清理** | v0.1 中实现为手动清理：返回 Path 值，由调用方负责在 `do` 块的 `defer` 中调用 `File.remove`。全局自动清理机制推迟至 Phase 6（需模块系统提供退出钩子） |
| **test_main.zig 未入修改清单** | 每个里程碑完成后更新 `test_main.zig` 添加新测试文件 `@import` |
| **运行时错误无 i18n** | v0.1 的 IOError/CommandError/EvalError 使用英文消息；运行时间错误 i18n 推迟至 v0.5 |
| **Primitive 子文件组织** | 按模块组拆分：`primitive_io.zig`（IO/Env/Process）、`primitive_fs.zig`（File）、`primitive_data.zig`（List/Map/Set/String/Bytes）、`primitive_stream.zig`（Stream/Cmd pipe）；每个子文件通过 `@import` 聚合到 `primitive.zig` |
| **Phase 5 ≠ v0.1.0 完整发布** | Phase 5 产出包含全部 105 [Primitive] 实现 + Stream 基础设施。模块系统（import 加载 .kun 文件）和 PureKun 标准库推迟至 Phase 6。沙箱推迟至 v0.2。kun doc 推迟至 v0.5 |
| **DateTime format/parse 无 Zig std** | 实现自定义 strftime/strptime 子集 (~300 行)，支持 `%Y/%m/%d/%H/%M/%S` |
| **File.glob 无 Zig std** | 实现自定义 glob 引擎 (~300 行)：字面量 + `*`/`?` + `[abc]` 字符类 |
| **File.walkDir/glob StreamNode** | 使用 `.generate` 变体 + Dir iterator 状态跟踪，每步 advance 返回 Path |
| **Cmd pipe 链** | Phase 5 限制单管道（2 命令），多命令管道和双向 pipe 推迟至 Phase 6 |
| **Process 原语 Linux-only** | `std.os.linux.*` 为 Linux 专有 API；Phase 5 目标平台为 Linux |
| **File.stat Record 结构** | 参考 `standard-library.md` File.Stat：`size: Int`, `mode: Int`, `type_: Int`(tag), `atime/mtime/ctime: DateTime`, `uid/gid: Int`, `device: ?{major,minor: Int}` |
| **Stream.range step 捕获** | `addStep` PrimitiveFn 通过 `Value.partial` currying 捕获 step 值（构造 `partial{fn=addStepImpl, args=[step], remaining=1}`），在 `.generate` 节点中作为 StreamFn.primitive 传入 |
| **DateTime/glob 引擎未入文件表** | `datetime_fmt.zig` (~300 行 strftime/strptime) 和 `glob_engine.zig` (~300 行 glob) 加入新建文件表；`sha256Stream` 通过 `stream_consumer.zig` 的 consumeNext 函数指针消费流，无额外循环依赖 |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.24 | R5 闭合审计通过（0 新增 FAIL）；R6 新视角发现 6 项计划缺口（错误处理/安全/构建/ADT 辅助/错误映射/临时文件）并全部修复到计划 |
| 2026.06.24 | Phase 5 前置架构修复完成（A1-A4）+ 552/552 测试通过；call 约束生成 + Primitive 多参 currying + ADT payload 通用化 + unify allocator 修复 |
| 2026.06.23 | 审计修复（6 项）：子组标题计数修正（B→21/E→18/F→17）、新增 Step 8 签名回补与类型安全验证、新增 `test_primitive_types.zig` 类型安全测试、风险评估扩展（StreamFn 循环依赖/Map key 白名单/Arena 耗尽/IO.isTerminal/回归保护） |
| 2026.06.23 | 初始版本 |
