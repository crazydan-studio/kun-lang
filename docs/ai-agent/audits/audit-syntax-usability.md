# 审计报告：Kun 语法设计与可用性

> 类型：开放式审计（语法 + 可用性）
> 审计者：独立 AI 审计代理
> 日期：2026-06-13
> 审计范围：`syntax.md`, `type-system.md`, `command-system.md`, `cli.md`, `project-vision.md`, `product-scope.md`

## 执行摘要

**总体评分：B+（设计阶段评价）**

Kun 的语法设计在一致性、类型安全和表达力方面表现突出。ADT + 模式匹配 + HM 推断的组合在 shell 语言领域是开创性的。`Cmd.<bin>` 的命令即函数模型和类型驱动的 CLI 解析是两个突出的设计亮点。

但存在一个根本性张力：**目标用户（Linux 运维/DevOps）的技术背景与语言所需的心智模型之间存在显著落差**。从 bash/Python 到 Elm/Haskell 风格函数式编程的认知跳跃，是 Kun 面临的最大采用风险。此外，若干语法细节存在可用性陷阱或未充分指定的空白区域。

---

## 详细发现

### 发现 #2：HM 类型推断的错误信息缺乏设计

**严重性：CRITICAL**

**涉及文件**：`type-system.md:336`（仅提及 HM），`syntax.md`（未涉及错误信息格式）

**问题**：设计文档详细说明了类型系统的"幸福路径"（推断成功），但对推断失败时的错误信息格式完全未定义。HM 推断器产生的原始合一错误（如 "cannot unify `a -> b` with `Int`"）对目标用户完全不可理解。

**具体场景**：
```kun
// 用户意图：对列表中每个元素执行命令
// 错误：map 期望纯函数，但用户传入了效应函数
results = lines |> map (\line -> Cmd.echo { n = true } line)
```
HM 推断器会报：效应 lambda 在纯上下文中。但原始错误可能显示为某种深奥的类型变量冲突。

**建议**：
1. 在 `type-system.md` 新增"错误信息设计"章节，定义以下错误类型的格式化模板：
   - 类型不匹配（标注两个类型的"人类可读"表示，高亮差异位置）
   - 效应泄露（纯函数使用了 IO 操作，指出具体调用点）
   - 未约束类型变量（缺少类型标注的歧义，给出拟标注示例）
   - 无穷类型（递归 Record 未通过 `type` 别名）
2. 为 20 个最常见推断错误编写"面向运维"的错误消息模板（参考 Elm 编译器的错误信息质量）
3. 在编译器中实现错误溯源：记录类型变量的来源位置，在错误信息中显示"这个 `a` 来自第 12 行的 `x` 参数"


### 发现 #4：Command 自动执行的隐式触发规则存在意外风险

**严重性：HIGH**

**涉及文件**：`command-system.md:96-106`

**问题**：`Command` 值的执行触发规则有三条，其中两条是隐式的：

> `|>` 隐式触发：左侧 `Command`，右侧函数期望 `Stream`
> `do` 块语句边界：未被 `=` 绑定或 `|>` 消费的 `Command` 表达式作为独立语句执行

**意外场景**：

1. **意外执行**：用户在 `do` 块中写了 `Cmd.rm { r = true } p"/tmp/foo"` 作为独立语句，意图是构造用于调试的 `Command` 值（忘了绑定给变量），结果文件被删除
2. **管道消费失败**：用户写 `Cmd.ps {} |> filter ...`，但 `filter` 是多态的，编译器无法确定是否应触发执行。按文档 104 行："若右侧函数为多态…编译器需先合一…若无法确定触发条件则回退为错误信息"。这个回退错误信息对用户来说会很困惑
3. **条件分支中的意外**：
   ```kun
   do
     if debug then
       Cmd.echo {} "debug info"    // 独立语句 → 执行 ✓
     else
       Cmd.date {}                 // 独立语句 → 执行 ✓
   ```
   这里执行是预期的。但如果用户重构代码，将 `Cmd.date {}` 移到 `=` 绑定后，行为会静默改变
4. **与变量绑定的视觉相似性**：
   ```kun
   do
     Cmd.ls { long = true }          // 执行并 panic（若 ls 失败）
     result = Cmd.ls { long = true } // 不执行，result 绑定为 Command 值
   ```
   两行代码看起来几乎相同，但行为完全不同。建议对未消费的 `Command` 在编辑器中显示视觉提示（如下划线波浪线）

**建议**：
1. 为未消费的 `Command` 值引入 lint 警告："bare Command expression in do block will auto-execute; did you mean to bind it with `=`?"
2. 考虑 `|>` 隐式触发的备选：要求用户显式标记，如 `Cmd.cat p"/x" |> exec |> Stream.lines`
3. 在 `command-system.md` 增加"常见误用模式"章节，列举上述陷阱及正确写法
4. 编辑器集成（LSP）应显著标记未绑定 Command 的区别


### 发现 #5：f-string 格式说明的范围局限性

**严重性：MEDIUM**

**涉及文件**：`syntax.md:114-234`

**问题**：f-string 格式说明仅覆盖 Int、Float、String、DateTime 四种类型。以下常见场景缺少格式说明：

**5a. 整数的填充/对齐格式不一致**：
字符串支持 `{name:>10}` 对齐，但整数格式说明表中未提及对齐支持。按 Python f-string 惯例，整数也应支持对齐（如 `{42:>6}` → `"    42"`）。文档需要明确整数是否支持 `fill` + `align` + `width` 语法。

**5b. 填充字符的解析歧义**：
`syntax.md:180-183` 中 `{42:#>6}` 是 `#`（填充）+ `>`（对齐）+ `6`（宽度）。但如何区分 `{42:x>6}` 中的 `x` 是填充符还是十六进制格式符？根据文档，`x` 是格式符，所以 `{42:x>6}` 可能被解析为 `x`（十六进制格式）然后是 `>6`（无效），或报告错误。需明确填充字符只能是单个非格式符字符。

**建议**：
1. 在格式说明文档中明确整数对齐支持（如支持则补示例，不支持则说明原因）
2. 规范填充字符：填充字符必须出现在对齐符之前，且不能是格式说明中已定义的格式符（`d`/`x`/`X`/`o`/`b` 等）


### 发现 #6：模块系统缺少关键特性

**严重性：MEDIUM**

**涉及文件**：`syntax.md:847-937`

**问题**：

**6a. 无 re-export 机制**：无法从一个模块导出另一个模块的符号。常见场景：`lib/Api.kun` 作为 facade 重新导出 `Api.Internal.*` 的部分符号。当前设计缺乏此能力。

**6b. 通配符导入的命名空间污染**：`import List (..)` 将所有公开符号注入当前作用域。若两个模块同时有同名函数（如 `List.map` 和 `Map.map`），此风格无法使用两个模块的全量导入。文档未说明同名冲突时的处理规则。

**6c. 模块默认不暴露任何符号**：文档未明确说明未声明 `export (...)` 的模块是否为"全私有"（所有符号仅模块内可见）。这应该是明确的，以避免理解歧义。

**建议**：
1. 添加 re-export 支持：`export (import List (map, filter))` 或类似语法
2. 明确通配符导入冲突解决规则：同名时编译器报"ambiguous import"并要求限定
3. 在 `syntax.md` 的模块章节明确：无 `export` 声明的模块，所有符号仅模块内部可见


### 发现 #7：kebab-case ↔ camelCase 双向映射的心智负担

**严重性：MEDIUM**

**涉及文件**：`cli.md:29-55`, `command-system.md:67-84`

**问题**：存在两个独立的映射系统：

1. **Cmd 系统**：Kun 代码中的 `camelCase` Record 字段 → 运行时 `--kebab-case` CLI flag
2. **Cli 系统**：`kebab-case` 声明器 `name` → 编译期 `camelCase` Record 字段 → 命令行 `--kebab-case`

两个系统都实现了相同的转换方向（camelCase ↔ kebab-case），但 Cli 系统多了一层：用户先写 kebab-case 声明，编译器映射到 camelCase 字段，然后在帮助输出中又显示为 kebab-case。

**混淆场景**：
```kun
type SyncConfig =
  { dryRun     : Bool       // camelCase
  , maxRetries : Int        // camelCase
  }

// 声明器用 kebab-case
Cli.flag "dry-run" 'n' "..."      // kebab-case
Cli.option "max-retries" 'r' "..." // kebab-case

// 编译期映射：dry-run → dryRun, max-retries → maxRetries
// 生成的 CLI flag：--dry-run, --max-retries
```

用户需要记住：写类型时用 camelCase，写声明器 name 时用 kebab-case，最终 CLI flag 是声明器的 kebab-case。三处命名，两套规则。对于全小写字段（如 `verbose`），两个方向等价，不造成混淆。

**建议**：
1. 在 `cli.md` 中增加一条"命名心法"可视化说明：声明器 kebab → 类型 camelCase 的转换图
2. 考虑未来版本中，声明器 name 是否可以同时接受 camelCase（自动映射），减少用户的命名风格切换
3. 在编译器错误信息中，当字段名不匹配时，同时显示两种形式：`field 'dryRun' not found; did you mean the kebab-case declaration 'dry-run'?`


### 发现 #8：`Cmd.<bin>` 语法中 `.` 的语义过载

**严重性：MEDIUM**

**涉及文件**：`command-system.md:13-50`, `syntax.md:672-688`

**问题**：`.` 在 Kun 中有三种含义：

1. **Record 字段访问**：`record.name`（`syntax.md:652`）
2. **元组索引**：`tuple.0`（`syntax.md:667`）
3. **函数限定访问**：`List.map` → `模块.函数`（`syntax.md:682`）
4. **命令调用**：`Cmd.ls` → 特殊编译器语法（`command-system.md:16`）
5. **子命令链**：`Cmd.docker.container.ls` → 多层子命令（`command-system.md:37`）

其中 4 和 5 的 `.` 语义与 1/2/3 截然不同：它不是访问模块的函数，而是拼接命令名。对于阅读者来说，`Cmd.docker.container.ls` 看起来像是 `Cmd.docker.container` 模块的 `ls` 函数，但实际上 `docker.container` 并非模块名——它是命令名的一部分。

**具体混淆**：`Cmd.pipe` 和 `Cmd.ls` 都使用 `Cmd.` 前缀，但 `pipe` 是模块中的函数，`ls` 是编译器识别的命令名。从用户角度看，这两者形式相同但行为不同。

**建议**：
1. 在设计文档中增加一节"点号 `.` 的语义分类"，明确区分上述五种用法及其解析规则
2. 考虑是否为命令名使用不同的视觉语法（如 `Cmd/ls` 或 `Cmd:ls`），将命令调用与模块函数访问区分开。但需权衡：当前语法简洁且与 shell 用户的心智模型接近
3. 至少在当前语法下，文档应明确说明"`Cmd.` 后的第一个标识符是命令名（运行时 PATH 查找），后续 `.` 链是子命令拼接"


### 发现 #9：`do in` 语法的不对称性

**严重性：LOW**

**涉及文件**：`syntax.md:588-626`

**问题**：`do` 块有两种形式：

1. `do ...`（隐式返回最后一条语句的值，类型由最后一条语句决定）
2. `do ... in`（显式在 `in` 后返回表达式，且可访问 `do` 块内的绑定）

这种不对称性可能导致混淆：
```kun
do
  x = getX ()
  IO.print x
// 返回 Unit（IO.print 的结果）

do
  x = getX ()
in
  x
// 返回 x 的值
```

`in` 关键字的选择与 `let ... in` 呼应（`syntax.md:433-443`），具有一致性。但 `do in` 退出的语义（`do` 块内注册的 `defer` 在 `in` 表达式求值前执行）需要更明确的文档说明。

**建议**：在 `syntax.md` 的 `do` 块章节中明确 `do ... in` 的 `defer` 执行时机：defer 在 `do` 块执行完毕后、`in` 表达式求值前执行。明确约定 `do ...` 始终返回 Unit，而不是最后一条语句的值。


### 发现 #10：`defer` 仅在 `do` 块内有效 — 无纯代码资源管理

**严重性：LOW**

**涉及文件**：`syntax.md:629-647`

**问题**：`defer` 仅在 `do` 块（效应上下文）内有效。对于需要资源清理的纯代码（如大内存分配、文件描述符），没有对应的模式。虽然有 GC/不可变数据默认，纯代码中仍有需要及时释放的资源场景。

**影响**：在纯上下文中，用户必须将代码移入 `do` 块才能使用 `defer`，即使实际操作不涉及 IO 效应。这会污染函数的效应标记，降低代码复用性。

**建议**：
1. 评估是否需要纯上下文的 `defer`（可能不需要，因为 Kun 的不可变数据默认 + 所有权模型可覆盖大部分场景）
2. 若不需要，在文档中明确说明理由："纯代码通过不可变数据 + 引用计数管理资源，无需显式释放；`defer` 仅用于效应资源的时序性清理（如临时文件）"


### 发现 #11：`CliError` ADT 的 human-readable 消息未与类型信息关联

**严重性：LOW**

**涉及文件**：`cli.md:288-298`, `cli.md:372-375`, `cli.md:1306-1356`

**问题**：`Cli.show : CliError -> String` 生成人类可读的错误消息，但这些消息在编译期展开时就有类型信息可用，但 `Cli.show` 不利用类型信息。例如：

```
Error: option '--port' has invalid value: expected 1..65535, got 99999
```

"1..65535" 来自 `Validator.range 1 65535`，但 "integer" 这个类型名是硬编码的。如果目标字段是 `Float` 或自定义类型，`BadValue.expected` 字段能否正确反映类型信息？

`CliError.BadValue` 的 `expected : String` 是自由格式字符串，编译期展开时需填充为人类可读的类型描述（如 "integer", "float", "path"）。但文档未明确这个字符串的生成规则。`got` 字段也未说明是原始输入字符串还是解析失败后的表示。

**建议**：
1. 为 `BadValue` 的 `expected` 字段定义标准化的类型描述生成规则（每个基础类型映射到一个可读名称）
2. 考虑将 `BadValue.expected` 改为结构化类型（如 `TypeDesc` 枚举）而非自由文本，便于程序化处理


### 发现 #12：文档生成（`kun doc`）缺乏设计

**严重性：LOW**

**涉及文件**：`syntax.md:29-31`（文档注释规则仅 3 行），CLI 提及但无独立设计文档

**问题**：`syntax.md` 中关于文档注释的描述仅停留在语法层面（"直接位于 type、函数定义、export 声明上方的注释行自动视为文档注释"），但：
- 输出格式未定义（HTML? man page? 终端纯文本?）
- 文档注释中的 Markdown 渲染子集未定义（哪些 Markdown 特性被支持）
- 模块间交叉引用语法未定义
- 示例代码块在文档中的处理未定义

**建议**：
1. 编写独立的 `docs/ai-agent/design/documentation-generation.md` 设计文档
2. 定义文档注释支持的具体 Markdown 子集（建议：CommonMark 0.30 核心 + 代码块语法高亮）
3. 定义文档交叉引用语法（如 `` `List.map` `` 是否自动链接到 `List` 模块的 `map` 函数）
4. 明确至少两种输出格式：Markdown（`kun doc --md`）和静态 HTML（`kun doc --html`）


### 发现 #13：类型标注与值定义分离的意外后果

**严重性：LOW**

**涉及文件**：`syntax.md:323-344`

**问题**：类型标注行 (`add : Int -> Int -> Int`) 和值定义行 (`add = \x y -> x + y`) 是分离的。这提供了清晰的视觉结构，但：

1. **无类型标注时的歧义**：如果用户省略类型标注，只写 `add = \x y -> x + y`，编译器需要推断类型。这与有标注的函数混合在同一个文件中，可能导致视觉扫描时的不一致感
2. **多行类型签名的可读性**：对于返回类型复杂的函数，类型签名可能很长：
   ```kun
   parse : String -> Result { name : String, items : List { id : Int, label : String } } ParseError
   ```
   这在一行中难以阅读，但文档未说明是否支持多行类型签名

**建议**：在 `syntax.md` 中明确类型签名是否允许跨行（建议允许，以 `->` 或 `Result` 处断行）


### 发现 #14：与 Nushell/Elvish/Xonsh 的竞争定位

**严重性：INFO（非缺陷，但需关注）**

**涉及文件**：`project-vision.md`, `product-scope.md`

**分析**：

| 维度 | Kun | Nushell | Elvish | Xonsh |
|------|-----|---------|--------|-------|
| 类型系统 | HM 推断 + ADT | 结构化类型（运行时） | 动态类型 | Python 类型（可选） |
| 安全沙箱 | Landlock+seccomp（内置） | 无 | 无 | 依赖 OS |
| 学习曲线 | 陡峭（2-4 周） | 平缓（1-3 天） | 平缓（1-2 天） | 平缓（1 天，前提会 Python） |
| 平台 | Linux only | 跨平台 | 跨平台 | 跨平台 |
| 生态 | 无（新语言） | 丰富插件 | 中等 | 依托 Python 生态 |
| 编译期保证 | 完整类型检查 | 有限（类型标注） | 无 | mypy 可选 |
| 管道数据 | 类型化 ADT | 结构化表格 | 结构化值 | Python 对象 |

**Kun 的独特优势**（其他竞争者无法或难以复制的）：
1. **编译期类型安全** — 消除整个类别的运行时错误（未定义变量、类型不匹配、未处理错误）
2. **内置多层安全沙箱** — Landlock + seccomp + namespace 的组合在 shell 领域无出其右
3. **Command 值抽象** — 命令作为一等值，可组合、可修饰、可延迟执行，远超管道的表达能力
4. **结构化管道** — `|>` 传递类型化数据流，`Cmd.pipe` 处理 OS 管道，两者互补

**Kun 的主要竞争劣势**：
1. 生态从零开始（需自建标准库 + 命令类型模块）
2. 无跨平台支持（排除 macOS 开发者和 Windows/WSL 用户）
3. 函数式范式的普及度远低于命令式

**建议**：
1. 在营销/文档中清晰传达 Kun 不是"又一个 shell"，而是"类型安全的脚本语言"
2. 优先投资命令类型模块的自动生成工具（`kun cmd init`），降低生态冷启动成本
3. 为最常见的 100 个 Linux 命令提供预置类型模块，让用户第一天就能体验类型安全的命令调用
