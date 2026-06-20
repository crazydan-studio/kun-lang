# 时效性文档审计报告（Round 10）

审计日期：2026-06-20

## 已修复验证（Round 9 问题）

以下问题已不复存在，验证通过：
- 缩进错误（Err 分支、IO.println）、Stream.fromList 类型变量 `t`→`a`
- 命名：LineError.partial_len→partialLen
- 示例语法：Task lambda 添加 do 包裹、Base64 纯上下文 IO.println 改为纯表达式、Path 未绑定 case 绑定变量
- API 标注：Cli.show 添加 [推迟 v0.5]、List.sum 注释修正
- 互斥违规：code-formatting.md do-in 内 let-in→do-in
- do in 约束：syntax.md/type-system.md 补充 `in` 部分不可嵌套 let in

## 新增问题

### 严重（语法错误/API 不匹配）

#### 1. [示例语法] 零参效应函数 `-> T` 示例使用裸 `do` 导致类型错误（跨 3 文档）

**问题**：零参效应函数的类型是 `-> T`（T ≠ Unit），但示例使用裸 `do` 包裹函数体。据语法设计（syntax.md:984），裸 `do` 固定返回 `Unit`，与函数签名的 `-> T` 类型冲突。应使用 `do in` 或将返回值通过 `in` 表达式传递。

**影响位置**：

| 文件 | 行号 | 代码片段 |
|------|------|---------|
| `type-system.md` | 251-261 | `now : -> DateTime` / `now = \ -> do DateTime.now` |
| `type-system.md` | 257-261 | `getPid : -> Pid` / `getPid = \ -> do Process.pid` |
| `syntax.md` | 257-261 | `getPid : -> Pid` / `getPid = \ -> do Process.pid` |
| `code-formatting.md` | 112-115 | `pid : -> Process.Pid` / `pid = \ -> do Process.pid` |

**建议修复**：使用 `do in` 模式：
```kun
now : -> DateTime
now = \ ->
  do
    DateTime.now
  in
    DateTime.now
```
或简化（若函数仅返回且无副作用预处理）为：
```kun
now : -> DateTime
now = \ ->
  do in
    DateTime.now
```

#### 2. [示例语法] `Hash.sha256Hex` 参数类型不匹配（standard-library.md:2531）

**问题**：`File.readBytes : Path -> Result (Stream Bytes) IOError`，绑定 `Ok data` 后 `data : Stream Bytes`。但 `Hash.sha256Hex : Bytes -> String` 期望 `Bytes`，而非 `Stream Bytes`。调用 `Hash.sha256Hex data` 是类型错误。

**位置**：`standard-library.md` 第 2528-2535 行
```kun
case File.readBytes p"/path/to/file" of
  Ok data ->
    hash = Hash.sha256Hex data    // ❌ data: Stream Bytes, sha256Hex: Bytes -> String
```

**建议修复**：使用 `Stream.bytes` 消费后计算，或改为直接使用 `Hash.sha256Stream`：
```kun
case File.readBytes p"/path/to/file" of
  Ok data ->
    hash = Hash.sha256Hex (Stream.bytes data)
```

#### 3. [示例语法] `Float.approxEqual` 参数顺序错误（standard-library.md:196）

**问题**：`approxEqual : Float -> Float -> Float -> Bool` 签名为 `epsilon -> a -> b -> Bool`。示例 `Float.approxEqual (0.1 + 0.2) 0.3 1e-10` 将 `(0.1+0.2)` 作为 epsilon 传入，语义错误（epsilon 应为 `1e-10`，待比较值为 `(0.1+0.2)` 和 `0.3`）。

**位置**：`standard-library.md` 第 196 行
```kun
Float.approxEqual (0.1 + 0.2) 0.3 1e-10    // ❌ 参数错位
```

**建议修复**：
```kun
Float.approxEqual 1e-10 (0.1 + 0.2) 0.3    // ✅ epsilon = 1e-10
```

#### 4. [示例语法] `Stream.lines` 输出 `Result` 后直接 `filter`/`parseMap` 类型错误（跨 3 文档）

**问题**：`Stream.lines : Stream String -> Stream (Result String LineError)` 输出包含 `Result` 包装的元素。后续 `Stream.filter (String.contains "ERROR")` 和 `Stream.parseMap parseLine` 直接处理元素类型为 `String` 的函数，与 `Result String LineError` 不兼容。缺少 `Stream.filterMap Result.ok` 步骤提取 `Ok` 值。

**影响位置**：

| 文件 | 行号 | 错误链 |
|------|------|--------|
| `standard-library.md` | 1913-1916 | `Cmd.cat ... \|> Stream.lines \|> Stream.filter (String.contains "ERROR")` |
| `basic.kun` | 110-115 | `Cmd.cat path \|> Stream.lines \|> Stream.filter (String.contains "ERROR")` |
| `log-analyzer.kun` | 40-43 | `Cmd.cat logPath \|> Stream.lines \|> Stream.parseMap parseLine` |

**建议修复**：在 `Stream.lines` 之后添加 `|> Stream.filterMap Result.ok` 步骤提取成功的行：
```kun
Cmd.cat logPath
  |> Stream.lines
  |> Stream.filterMap Result.ok       // 新增：提取 Ok 行，丢弃 Err
  |> Stream.filter (String.contains "ERROR")
  |> Stream.parseMap parseLine
  |> Stream.toList
```

### 中等（格式/命名/一致性）

#### 5. [语法合规] `defer` 表达式括号不一致（syntax.md vs code-formatting.md）

**问题**：`code-formatting.md:733` 使用 `defer (File.remove tmp)` 带括号包裹，格式约定明确了使用括号。但 `syntax.md:1046` 用 `defer cleanupDeploy ()` 无括号，`syntax.md:1051` 用 `defer cleanupRollback ()` 同样无括号。虽然语法上 `defer expr` 允许无括号，但若格式约定使用括号则应保持一致。

**位置**：`syntax.md:1046,1051` vs `code-formatting.md:733`

**建议修复**：统一使用括号：`defer (cleanupDeploy ())`

#### 6. [语法合规] cli.md:1309 顶层 case 含效应调用（需 do 上下文）

**问题**：示例展示的 `case parseConfig raw of ...` 为顶层表达式（无外层 `do` 包裹），其分支中包含 `IO.println` 效应调用。注释说明「应当在 do 块中」但代码块未包裹。读者可能误以为顶层允许效应调用。

**位置**：`cli.md:1309`

**建议修复**：将示例包裹在 `do` 块内或添加注释明确为片段的缩略展示。

#### 7. [API 一致性] cli.md 使用 `Cli.show` 但标注推迟 v0.5

**问题**：`Cli.show` 在 `standard-library.md:1672` 标注 `[推迟 v0.5]`。cli.md 全部 15 个示例均使用 `Cli.show err` 作为错误格式化。若按 MVP 分期这些示例在 v0.1 不可执行——虽可视为前瞻文档，但与推迟标注的文字说明矛盾。

**位置**：`cli.md` 全部 15 个示例（line 612, 703, 772, 818, 1032, 1078, 1133, 1319 等）

**建议修复**：在 cli.md 开头或推迟标注处明确说明「示例中 `Cli.parse`/`Cli.show` 为 v0.5 特性，当前仅作语法设计展示」。

### 轻微（措辞/可读性）

#### 8. [措辞] `standard-library.md:2219` 注释中的 `File.createTempFile` 结果绑定

示例中 `Ok tmp` 后使用 `defer (File.remove tmp)`。这里 `tmp` 的类型是 `Path`，注释无问题，但约定使用 `Path` 而非 `String` 访问文件系统。临时文件路径返回类型在 API 定义中 `createTempFile : -> Result Path IOError`，`tmp : Path` 正确。

#### 9. [措辞] `command-system.md:50-54` 顶层 Command 未消费

`Cmd["ntfs-3g"] { force = true } "/dev/sda1"` 和 `Cmd["g++"] { o = "a.out" } "main.cpp"` 为顶层语句构造 Command 值但不消费。虽语法规则仅对 `do` 块内要求消费，但顶层未消费 Command 的设计意图不明确。

**位置**：`command-system.md:50-54`

#### 10. [措辞] `feature-inventory.md:68` Test 模块状态描述歧义

标注 `Test | ✅ 设计定型`，但下文提到「`kun test` 子命令」而未标注推迟版本。`standard-library.md:2742` 明确 Test 推迟至 v1.0，`MVP.md:73` 也列在「不包含」中。

**建议修复**：在 feature-inventory.md Test 行末尾添加 `（实现推迟 v1.0）`。

## 交叉引用一致性问题

#### X1. MVP.md 未列出 `Hash.md5`/`Hash.md5Hex` 为推迟特性

`standard-library.md:2517` 将 `Hash.md5`/`Hash.md5Hex` 标注 `[推迟 v0.5]`，但 `MVP.md`「不包含」表格中未列出。虽 `Hash.md5` 作为次要模块不影响 MVP 范围判断，但不一致。

#### X2. `feature-inventory.md` 与 `standard-library.md` 的 `Parser.JSON` 状态一致

两者均标注 `Parser.JSON` 为设计定型且 `fromString`/`toString` 可用（无推迟标注）。`MVP.md:30` 标注 `Parser.JSON` 为「v0.5」——但 `fromString`/`toString` 本身无推迟标记，推迟的是 `Parser.Record` 的 `fromJson`/`toJson`。此处 `MVP.md` 可能混淆 `Parser.JSON` 与 `Parser.Record`。

检查 `standard-library.md`：
- `Parser.JSON.fromString : String -> Result JsonValue String` — **有完整实现无推迟标注**
- `Parser.JSON.toString : JsonValue -> Result String String` — **有完整实现无推迟标注**
- `Parser.Record.fromJson / toJson` — **标注 `[推迟 v0.5]`**

**结论**：`MVP.md:30` 行 `Parser.JSON（v0.5）` 应修正为 `Parser.Record（v0.5）`。`Parser.JSON` 本身在 MVP v0.1 范围内。

#### X3. `system-baseline.md` effect 函数列表与 `standard-library.md` 一致

检查通过：
- `Cmd.andThen` / `Cmd.orElse` 在 `system-baseline.md:156` 列为纯操作 → 匹配
- `Cmd.pipe?` / `Cmd.pipe!` 列为效应函数 → 匹配
- `Cmd.timeout` / `Cmd.retry` 列为效应函数 → 匹配
- `Cmd.which` 列为效应函数 → 匹配

## 示例代码问题汇总（按文档）

| 文档 | 严重 | 中等 | 轻微 | 关键问题摘要 |
|------|------|------|------|------------|
| `standard-library.md` | 3 | 0 | 1 | sha256Hex 类型错误、approxEqual 参数错位、Stream.lines Result 未解包 |
| `syntax.md` | 1 | 1 | 0 | getPid 裸 do 类型错误、defer 括号不一致 |
| `type-system.md` | 1 | 0 | 0 | now/getPid 裸 do 类型错误 |
| `code-formatting.md` | 1 | 0 | 0 | pid 裸 do 类型错误 |
| `cli.md` | 0 | 2 | 0 | 顶层 case 含效应、推迟 api 在示例中未标注 |
| `command-system.md` | 0 | 0 | 1 | 顶层未消费 Command |
| `basic.kun` | 1 | 0 | 0 | Stream.lines Result 未解包后 filter |
| `log-analyzer.kun` | 1 | 0 | 0 | Stream.lines Result 未解包后 parseMap |
| `feature-inventory.md` | 0 | 0 | 1 | Test 模块缺少推迟标注 |
| `MVP.md` | 0 | 0 | 1 | Parser.JSON/Parser.Record 混淆 |
| 其余 5 份文档 | 0 | 0 | 0 | 通过 |

## 建议修复清单

按优先级排序：

### P0 — 必须立即修复
1. `type-system.md:251-261` + `syntax.md:257-261` + `code-formatting.md:112-115`：零参效应函数裸 `do` → `do in` 重构
2. `standard-library.md:2531`：`Hash.sha256Hex data` → `Hash.sha256Hex (Stream.bytes data)` 或改用 `sha256Stream`
3. `standard-library.md:196`：`Float.approxEqual` 参数顺序修正
4. `standard-library.md:1913-1916` + `basic.kun:110-115` + `log-analyzer.kun:40-43`：`Stream.lines` 后添加 `|> Stream.filterMap Result.ok`

### P1 — 中等优先级
5. `cli.md:1309`：包裹 do 块或标注为片段
6. `syntax.md:1046,1051`：defer 括号统一
7. `cli.md`：推迟 API 示例添加说明

### P2 — 次要
8. `feature-inventory.md:68`：Test 添加推迟标注
9. `MVP.md:30`：修正 `Parser.JSON（v0.5）`→`Parser.Record（v0.5）`
10. `command-system.md:50-54`：顶层 Command 添加消费或注释
