# 系统基线

## 技术栈

| 层 | 技术选择 | 说明 |
|---|---|---|
| 宿主语言 | Zig 0.17.0-dev | 高性能、无 hidden control flow、直接操作内存 |
| 目标平台 | Linux | 使用 fork/exec、namespace、Landlock、seccomp 等 Linux 特有机制 |
| 二进制产物 | `kun`（脚本执行器）+ `kun-shell`（交互式环境）+ `libkunlang.so`（共享解释器核心） | 单体可执行文件 + 动态链接库 |
| 文档构建 | VitePress + pnpm | 现代化的静态文档站点 |
| 版本控制 | Git + GitHub | 分布式版本控制 |

## 运行时生命周期

运行时从启动到退出的完整流程分为四个阶段：

### 启动阶段

```
CLI 参数解析 → 源码读取 → 词法分析 → 语法分析 → 类型检查
```

1. **CLI 参数解析**：运行时解析命令行参数，分离安全参数（`--allow-path`、`--allow-net` 等）与脚本参数
2. **源码读取**：以 UTF-8 编码读取 `.kun` 文件内容到内存
3. **词法分析**：将源码扫描为 Token 序列
4. **语法分析**：将 Token 序列解析为 AST
5. **类型检查**：对 AST 进行类型推断和检查，生成带类型标注的 Typed AST；同时执行效应检查（AST 标记含 `do` 块的函数为效应函数）

类型检查通过后才进入初始化阶段。类型检查失败时输出结构化错误报告并终止。

### 初始化阶段

```
运行时环境建立 → 模块解析 → 沙箱安装 → 标准库绑定
```

1. **运行时环境建立**：
   - 创建 Arena 分配器（per 脚本执行）
   - 检测 locale：读取 `KUN_LOCALE` → `LC_ALL`/`LC_MESSAGES`/`LANG` → 默认英文；结果存入 `RuntimeEnv`。若 locale 为非 zh_CN/en 的外部值，尝试加载外挂 `.po` 文件（`<runtime>/share/kun/po/<locale>.po`）
   - 设置全局求值环境（变量帧栈）
   - 注册内置 Primitive 函数表

2. **模块解析与加载**：
   - 解析 `import` 语句
   - 按搜索路径查找模块文件
   - 递归加载依赖模块并缓存
   - 检测循环依赖

3. **沙箱安装**：
   - 解析 CLI 安全参数（`--allow-path`、`--allow-net`、`--no-sandbox`、`--force`、`--env=`、`--cpu-limit`、`--mem-limit`）

> **安全参数组合**：`--no-sandbox` 禁用全部沙箱层，与 `--allow-path /` 组合可使脚本不受限制地访问整个文件系统。`--no-sandbox` + `--force` 跳过全部安全确认且不提示。这些组合仅应在受信任脚本中用于调试目的。

   - 父进程安装主沙箱层：Landlock（首选，内核 5.13+）→ mount namespace（兜底，内核 3.8+）→ 拒绝运行（内核 < 3.8）
    - 子进程策略安装（fork 后 exec 前）：seccomp-BPF 系统调用过滤 + rlimit 资源限制

> **日志记录**：`--no-sandbox` 和 `--force` 的使用始终通过 stderr `info` 级别日志记录（含时间戳和脚本路径），无论脚本是否成功。此日志不可抑制。

4. **标准库绑定**：
   - 将内置类型（List、Map、Set、Stream 等）的操作注册到环境
   - 将 IO 操作注册为 Primitive

### 执行阶段

```
入口解析 → AST 求值 → do 块顺序执行 → 命令调用
```

1. **入口解析**：按入口规则确定执行起点（`main : List String -> Unit`）
2. **AST 求值**：递归求值 Typed AST 节点。求值器采用 Zig 0.17 的**标记 switch**（labeled switch）实现节点分发——每个 AST 节点类型的求值逻辑为独立分支，利用 `continue :eval` 实现尾递归消除和分支预测优化。标记 switch 使 CPU 分支预测器能够将各节点类型的调度关联到独立的分支指令上，在热路径（如 Stream 消费循环中的逐元素求值）中获得显著性能提升
3. **do 块顺序执行**：`do` 块按顺序执行语句，`defer` 在退出时按 LIFO 逆序执行

defer 的作用域为其**最近的外层 `do` 块**——退出该 `do` 块时（正常返回或 panic）该块内注册的所有 defer 按 LIFO 逆序执行。嵌套 `do` 块各自管理独立的 defer 链：

```kun
do          // outer do
  do        // inner do
    defer inner_cleanup  // 在 inner do 退出时执行
  // inner_cleanup 已在此时执行完
  defer outer_cleanup  // 在 outer do 退出时执行
```

4. **命令调用**：`Cmd.<bin>` 构造 Command 值，通过 `|>` 管道隐式触发、`Cmd.exec` 显式执行或 `?` 后缀立即执行时 fork-exec

求值策略详见下方"执行模型"章节。

### 清理阶段

```
defer 执行 → 资源释放 → 退出码传播 → 运行时终止
```

1. **defer 执行**：按 LIFO 逆序执行当前 `do` 块及其所有外层 `do` 块注册的所有 `defer` 块
2. **资源释放**：
   - 关闭所有打开的文件描述符
   - 销毁 Arena 分配器（释放所有 per-script 分配的内存）
   - 释放模块缓存

3. **退出码传播**：根据执行结果确定进程退出码
   - `main` 正常返回 → 退出码 0
   - 未处理的 panic 传播到顶层 → 退出码依据错误类型确定

## 执行模型

### 求值策略

Kun 采用**严格求值**（Strict Evaluation）作为默认策略：

| 构造 | 求值策略 | 说明 |
|---|---|---|
| 纯表达式 | 严格 | 参数在函数应用前求值 |
| 函数体 | 严格 | 进入函数时立即求值 |
| `case` 分支 | 按需 | 仅匹配到的分支被求值 |
| `if`/三元 | 按需 | 仅条件匹配的分支被求值 |
| `&&`/`\|\|` | 短路 | 左侧确定结果时右侧不求值 |
| `Stream` | 惰性 | 元素在消费时按需拉取 |
| `let ... in` 多绑定 / `let rec` | 延迟 | 绑定组中所有表达式同时被包装为 thunks；每个 thunk 的 env 捕获其他绑定的 thunk 引用（通过互引用循环完成）；首次引用任一绑定时，按依赖拓扑顺序求值并 memoize |
| `let ... in` 绑定 | 延迟 | `let` 与 `in` 之间的绑定仅在 `in` 之后被引用时才真正求值，绑定时不求值。`let ... in` 不可出现在 `do` 块内——`do` 块的顺序执行语义与延迟求值不兼容。`let` 绑定的表达式必须是纯的——不得包含效应函数调用（`IO.*`、`File.*` 等）、`do` 块、或 `Cmd.<bin>?` 等立即执行操作。效应代码必须使用 `do` 块内的 `=` 绑定 |
| Record/List/Map/Set 字面量 | 严格 | 所有元素/字段在构造前求值 |
| Record 字段访问/更新 | 严格 | 被访问的 Record 表达式先求值，然后按编译期偏移量读取/更新字段 |
| `defer` 注册 | — | 非求值操作——在 do 块退出时按 LIFO 逆序执行。注册时不求值；执行时的求值策略与正常表达式相同 |
| `do` 块 | 严格 | 按顺序执行每条语句，最后一条语句的值作为 do 块的值；do in 返回 in 之后表达式的值 |

`let ... in` 的延迟求值通过 **thunk** 实现：绑定表达式被包装为闭包（`fn_ptr` 为求值函数，`env` 为绑定时可见的变量帧）。首次引用时求值 thunk，结果**缓存**在 thunk 的 `env` 中（memoization）。后续引用返回缓存值——确保副作用仅执行一次（但纯性约束已禁止副作用）。`let` 绑定的表达式必须在 `in` 表达式被求值前完成绑定（绑定时不求值，仅构建 thunk）。

### 递归深度限制与尾调用优化

#### 调用深度限制

求值器维护一个调用深度计数器，每次函数调用（含递归和互递归）时递增，返回时递减。计数器超过上限时，求值器立即 panic 并报告 `"Recursion depth exceeded"`。

- 默认上限：10,000 层调用深度
- 覆盖方式：环境变量 `KUN_MAX_RECURSION_DEPTH`（`0` 表示不限制）
- 作用范围：运行时求值阶段，独立于类型检查器已有的 256 层类型深度限制
- 类型深度限制可通过环境变量 KUN_MAX_TYPE_DEPTH 覆盖（0 表示不限制），默认值 256 涵盖了所有已知的实际递归类型使用场景（嵌套 JSON schema、相互递归 AST 定义等）
- defer 交互：defer 块内的函数调用同样计入深度计数

#### 尾调用优化

尾调用优化（TCO）不纳入 MVP。理由：

- TCO 将递归重写为循环，求值器深度计数器对尾递归失效——背离深度限制的防御性设计
- Kun 以命令调用和 IO 操作为主，深度递归路径不常见。非尾递归的深递归更可能反映编程错误
- TCO 需要 AST 级尾调用分析和代码变换，增加实现复杂度，MVP 收益不显著

TCO 列为 v1.1 候选特性。若未来引入，将对尾递归路径豁免深度计数器。

### do 块与效应函数

`do` 块按顺序执行效应操作。含 `do` 块的函数通过编译器 AST 标记自动识别为效应函数。签名中声明了 `(a -> b)!` 效应回调参数的函数同样自动标记为效应函数。纯函数（无 `do` 块、无 `!` 参数）不能调用效应函数——编译期拒绝。

效应函数涵盖以下命名空间的所有函数：`IO.*`、`File.*`、`Env.*`、`Process.*`、`Sys.*`、`Task.*`、`Random.*`，以及 `Signal.on`（信号注册）。`Cmd.<bin>` 构造 `Command` 值及 `Cmd` 单值修饰器（`Cmd.withEnv`、`Cmd.withCwd`、`Cmd.withStdin`、`Cmd.withRawOpt`、`Cmd.mergeStderr`、`Cmd.withRunAs`——接收 `Command` 并返回 `Command`）及条件组合器（`Cmd.andThen`、`Cmd.orElse`——接收两个 `Command` 返回 `Command`）为纯操作。`Cmd.pipe` 为管道组合器（接收 `List Command` 返回 `Command`，不立即执行，纯操作）。`Cmd.pipe?` 为立即执行管道（接收 `List Command` 并立即 fork-exec 整个管道链，返回 `Result`——效应函数）。`Cmd.<bin>?`、`Cmd.pipe?`、`Cmd.timeout`、`Cmd.retry`、`Cmd.execSafe`、`Cmd.stdoutToString`、`Cmd.stderrToString`、`Cmd.which`（PATH 查找需文件系统访问）、`Cmd.exec`（显式执行 Command 并丢弃输出）为效应函数。

> **注**：在 MVP（v0.1）中，下列命名空间虽被效应检查器识别，但无运行时实现：`Sys.*`、`Task.*`、`Random.*`、`Signal.on`、`Cmd.timeout`、`Cmd.retry`、`Cmd.withRunAs`。效应检查器对它们的守卫不影响编译——调用这些函数在 MVP 中因 Primitive 表无绑定而报"未定义函数"错误。后续版本中逐一激活。

`do` 块内使用 `=` 绑定值（纯值或效应函数的返回值）。`do in` 形式在副作用执行后返回纯值。语法细节见 [`syntax.md`](../design/syntax.md) do 块章节。

### Command 执行模型

`Cmd.<bin>` 返回 `Command` 值——不立即执行。执行触发条件见 [OS 命令调用机制](../design/command-system.md#command-执行模型)（`|>` 管道隐式触发、`Cmd.exec` 显式执行、`?` 后缀立即执行）。未被消费的 `Command` 值是编译错误。

`Cmd.exec : Command -> Unit` 为阻塞调用——内部执行 fork → exec → waitpid，子进程退出后才返回。（不存在 `Cmd.exec?` 变体。需要 `Result` 返回的命令使用 `Cmd.<bin>?` 或 `Cmd.pipe?`）。此语义确保 `do` 块内的 `Cmd.exec` 调用间有确定的执行顺序。

具体执行流程见下方「命令调用机制」章节。

### Stream 惰性求值

Stream 在运行时表示为 tagged union，替代函数指针链：

```zig
const Stream = union(enum) {
    cmd: struct { fd: i32, pid: i32, buf: []u8 },
    mapped: struct { upstream: *Stream, f: FnPtr },
    filtered: struct { upstream: *Stream, pred: FnPtr },
    taken: struct { upstream: *Stream, remaining: usize },
    dropped: struct { upstream: *Stream, remaining: usize },
    lines: struct { upstream: *Stream, buf: []u8, pos: usize, max_len: usize },
    parse_mapped: struct { upstream: *Stream, f: FnPtr },
    parse_mapped_keep: struct { upstream: *Stream, f: FnPtr },
};
```

- `cmd` 变体持有子进程的 pipe fd 和 pid，`buf` 为堆分配
- 变换操作（`map`、`filter`、`take`、`drop`）通过包裹上游 Stream 构造新节点；`take`/`drop` 的 `remaining` 为 `usize`，API 层 `Int` 参数 ≤ 0 时：`take 0` 返回空 Stream，`take n (n < 0)` 编译期报错（或 panic）；`drop 0` 等同原 Stream，`drop n (n < 0)` 同 `take` 处理
- `lines` 变体：按 `\n` 切分输入流——`buf` 为跨 chunk 的累积缓冲区，分配在构造时所属的 Arena 上。`max_len` 为行长上限（默认 1 MiB），超过上限时当前行被截断并产生 `Err LineTruncated` 错误作为元素值，缓冲区重置后继续下一行。缓冲区增长策略：正常行（len ≤ max_len）遇到 `\n` 时返回该行（不含 `\n`），buf 重置复用已分配空间；超长行（len > max_len）产生 `Err LineTruncated { partial_len: max_len }` 元素，丢弃当前缓冲内容（含后续 `\n` 前的所有字节）后重置下一行；上游终止时若 buf 非空返回最后一行（可能不含结尾 `\n`）。API 层提供 `Stream.lines`（默认 1 MiB）和 `Stream.linesMax n`（自定义上限，n ≤ 0 编译期报错）。n 的上限为 256 MiB（防止仲裁者传入极大值耗尽 Arena 内存）；超出上限编译期报错。
- `parse_mapped`：映射并丢弃 `Err` 结果（对应 `Stream.parseMap`）
- `parse_mapped_keep`：映射并保留 `Result`（对应 `Stream.parseMapKeep`）
- `filterMap` 无独立 tagged union 变体——在代码生成阶段展开为 `mapped` + 过滤 `Nil` 的复合操作
- 终端操作（`toList`、`iter`、`fold`）循环消费直到 stream 终止
#### 纯变换合并优化

编译器在代码生成阶段对相邻的纯 Stream 变换操作（`Stream.map`/`Stream.filter`/`Stream.take`/`Stream.drop`）执行合并优化：若相邻操作均为纯变换且上游非 IO 源（非 `cmd` 变体），将多层 tagged union 节点折叠为单次遍历。合并条件：(1) 操作均为纯变换；(2) 无中间终端操作；(3) 填充到合并后循环的迭代逻辑中。此优化减少 tagged union 分配开销和间接调度次数。

#### Stream 消费强制检查

编译器对 `do` 块内通过 `Cmd.<bin>`、`Cmd.pipe` 或 `Stream.*` 构造操作产生的 Stream 值执行 **AST 级穷举消费分析**（非全程序流敏感分析）：

1. **作用域**：分析的粒度为单个 `do` 块。Stream 值跨 `do` 块边界传递、作为函数参数传递或作为返回值时，视为"已消费"——不追踪跨边界别名。
2. **检测规则**：`do` 块末尾检查每个在此块内构造且绑定到变量的 Stream 值是否存在消费路径（`toList`/`iter`/`fold`/`string`/`bytes`）。条件消费（`if`/`case` 分支）的所有分支均需消费——缺失分支编译期报错。
3. **`let ... in` 交互**：`let ... in` 不可出现在 `do` 块内（`do` 块的顺序执行语义与延迟求值不兼容），因此 Stream 不会被 `let` 延迟绑定——消除了一类分析歧义。
4. **`Cmd.timeout`/`retry` 交互**：这些函数返回 `Result (Stream String) CommandError`——其 `Ok` 分支的 `Stream` 仍须消费；`Err` 分支的消费检查豁免。
5. **`defer` 交互**：`defer` 块内的操作不计入消费分析（`defer` 在退出时执行，届时消费为时已晚）。

此分析与效应检查共享同一 AST 遍历——在效应检查阶段同时完成 Stream 消费检查，无需独立 pass。

#### 管道缓冲区与非阻塞 IO

子进程 stdout 通过 pipe 捕获，Linux 默认 pipe 缓冲区为 64KB。Stream 消费时若子进程输出超过缓冲区容量，子进程 `write()` 阻塞等待父进程 `read()`。Kun 运行时采用以下策略：

- 每个 `cmd` 变体持有独立 pipe fd，消费循环中通过 `poll`/`select` 实现非阻塞读取
- 编译器对纯 Stream 管道（无 IO 源）生成单循环消费代码，无缓冲区风险
- IO 绑定的 Stream 管道在终端操作时驱动逐元素拉取，父进程在消费每一元素后立即释放缓冲区空间

此策略确保长时间运行的管道（如 `Cmd.find |> Stream.lines |> Stream.filter`）不会因缓冲区满而死锁。

#### 双向管道与死锁预防

父进程同时向子进程 stdin 写入并读取子进程 stdout 时，存在管道缓冲区满死锁风险：双方均阻塞在 `write`（管道 64KB 满），双方均不在 `read`。此场景在 `Cmd.withStdin` 与 `Stream` 消费同时发生时触发。

Kun 采用单线程非阻塞双向 poll/select 策略：

- stdout 与 stdin 共享同一 `poll`/`select` 事件循环，优先读取 stdout（必须先清空 stdout 缓冲区给子进程空间，再尝试推送更多 stdin 数据）
- stdin 写入为非阻塞——`write` 返回 `EAGAIN` 时 poll 循环转向读取 stdout
- `Cmd.withStdin` String 重载：fork 前将输入完整读入内存缓冲区，fork 后通过非阻塞 `write` 逐 chunk 写入
- 全量 stdin 写尽后立即 `shutdown(fd, SHUT_WR)` 关闭写端，子进程收到 EOF 后可继续写 stdout 直至退出
- 不引入额外线程——保持解释器单线程语义

### 主事件循环

Kun 运行时采用单线程主事件循环，在以下场景驱动 IO：

| 场景 | 被轮询的 fd | 触发条件 |
|------|-----------|---------|
| Stream 消费（`cmd` 变体） | 子进程 stdout pipe fd | `toList`/`iter`/`fold` 等终端操作逐元素拉取 |
| 双向管道 | stdout + stdin pipe fd | `Cmd.withStdin` + Stream 消费同时进行 |
| 信号处理 | signalfd | 整个脚本执行期间（与 `Signal.on` 共用） |

事件循环由消费 Stream 的终端操作隐式驱动——Stream 元素拉取时执行 `poll`，事件循环结束后控制权返回 Kun 求值器。脚本进程全局共享一个 `poll` 对象，每次 Stream 消费独立调用 `poll`。

非阻塞 IO 策略：所有 pipe fd 设置为 `O_NONBLOCK`；`poll` 返回就绪后读取；`EAGAIN` 时重新进入 `poll`。

## 错误诊断

### 错误类型体系

运行时定义了以下结构化错误类型：

### `TypeError`

类型检查阶段的错误，包含源文件名、行号、列号、期望类型、实际类型、错误原因、修复建议。

### 类型检查算法

类型检查采用 **Hindley-Milner**（HM）推断，分为两个阶段：

#### 阶段一：约束生成

遍历 Typed AST，为每个表达式节点生成类型约束方程。约束类型包括：

- **等价约束**：`T1 ~ T2`，要求两个类型合一为相同结构
- **实例化约束**：多态类型在使用点生成新的类型变量，确保泛型函数每次调用独立
- **函数应用约束**：`f a` 生成 `Tf ~ Ta -> Tr`（函数类型与参数类型、返回类型的关系）

Let 多态：`let` 绑定的泛型函数在约束生成时对其类型签名做泛化（generalization），产生的类型变量进入多态环境，每次引用时实例化为新类型变量。

#### 阶段二：合一

对阶段一生成的约束集，使用 **Algorithm W** 风格的合一求解器逐条解析：

1. 维护一个**代换**（substitution）映射，记录类型变量到具体类型的替换关系
2. 对每条等价约束 `T1 ~ T2`，按结构递归合一：
   - 两者同为类型变量 → 代换中任一为另一（按优先级取）
   - 一方为类型变量，另一方为具体类型 → 代换该变量为该类型（occurs check 防止无限递归）
   - 两者同为具体类型（如 `List a ~ List Int`） → 递归合一部分参数
   - 结构不匹配（如 `Int ~ String`） → 产生 `TypeError`
3. 全部约束合完成后，将最终的代换应用到 AST，生成带完整类型标注的 Typed AST

#### Let 多态与泛化

`let` 绑定引入的多态函数类型通过以下步骤处理：

```
let f = \x -> x
// 1. 推断 f 的类型变量：a -> a
// 2. 泛化：将自由类型变量提升为多态类型变量：forall a. a -> a
// 3. 实例化：f 42 → 实例化为 Int -> Int；f "hi" → 实例化为 String -> String
```

#### 效应检查

在类型合一的同时，效应检查器（Effect Checker）扫描 AST 中的 `do` 块、效应命名空间调用和 `!` 参数声明：

- 识别含 `do` 块的函数，标记为效应函数
- 识别签名中声明了 `(a -> b)!` 参数的函数，标记为效应函数（`!` 在编译器内部退糖为 `EffectFn(a, b)` 类型构造器，与 `Fn(a, b)` 在结构等价下不兼容）
- 验证纯函数体中无效应函数调用
- 验证纯函数签名中无 `!` 参数声明
- 验证 `!` 参数的传入实参为效应函数（实参的类型为 `EffectFn(a, b)`，效应检查器验证该函数含 `do` 块或效应命名空间调用）
- 验证 `do` 块外的代码无效应命名空间（`IO.*`、`File.*`、`Env.*`、`Process.*`、`Sys.*`、`Task.*`、`Random.*`，以及 `Signal.on`）函数调用
- 验证 `Cmd.<bin>?`、`Cmd.pipe?`、`Cmd.timeout`、`Cmd.retry`、`Cmd.execSafe`、`Cmd.stdoutToString`、`Cmd.stderrToString`、`Cmd.which`、`Cmd.exec` 仅在 `do` 块内使用
- Lambda 含有效应函数调用时，要求该 lambda 在 `do` 块内定义
- 验证 `do` 块内未被消费的 `Command` 值：未被 `Cmd.exec`、`|>` 管道或 `?` 后缀消费的 `Command` 值为编译错误

效应检查失败也产生 `TypeError`，纳入统一的错误报告。

### Typed AST

类型检查的输出是 Typed AST——在原始 AST 节点上附加完整类型标注的中间表示（IR）。Typed AST 是 HM 推断器与求值器之间的契约，定义了求值器的输入格式。

#### 结构设计

Typed AST 不复制 AST 树结构。每个原始 AST 节点附加 `TypeId` 字段，指向类型环境中的具体类型：

```zig
const TypeId = u32;  // 类型环境中的索引

const TypedExpr = struct {
    expr: *const Expr,   // 指向原始 AST 节点的指针（Arena 分配）
    ty: TypeId,          // 该表达式的推断类型
};
```

#### AST 节点类型

求值器通过 labeled switch 分发的 AST 节点完整枚举：

```zig
const Expr = union(enum) {
    // 字面量
    int_literal: i64,
    float_literal: f64,
    string_literal: []const u8,
    bytes_literal: []const u8,
    char_literal: u32,
    bool_literal: bool,
    unit_literal,
    nil_literal,

    // 变量与绑定
    variable: struct { name: []const u8, index: u32 },
    let_in: struct { name: []const u8, value: *Expr, body: *Expr },
    let_rec: struct { bindings: []const LetBinding, body: *Expr },

    // Lambda 与函数应用
    lambda: struct { params: []const Param, body: *Expr },
    apply: struct { func: *Expr, arg: *Expr },

    // 控制流
    if_expr: struct { cond: *Expr, then: *Expr, else: *Expr },
    case_expr: struct { scrutinee: *Expr, branches: []const Branch },

    // 复合类型
    record_literal: struct { fields: []const RecordFieldExpr },
    record_access: struct { record: *Expr, field: []const u8 },
    record_update: struct { record: *Expr, updates: []const RecordFieldExpr },
    tuple_literal: struct { elements: []const *Expr },
    list_literal: struct { elements: []const *Expr },
    map_literal: struct { entries: []const MapEntry },
    set_literal: struct { elements: []const *Expr },

    // 运算符
    binary_op: struct { op: BinOp, lhs: *Expr, rhs: *Expr },
    unary_op: struct { op: UnaryOp, expr: *Expr },
    pipe_op: struct { lhs: *Expr, rhs: *Expr },

    // 效应
    do_block: struct { stmts: []const DoStmt },
    defer_stmt: struct { expr: *Expr },

    // 命令
    cmd_call: struct { bin: []const u8, options: ?*Expr, args: []const *Expr },

    // 模式匹配辅助
    pattern_match: struct { expr: *Expr, pattern: Pattern },
};
```

#### 类型标注粒度

**每个子表达式**均标注类型——求值器无需类型信息即可求值基础类型（`Int`/`Float`/`Bool`/`Char`），但以下节点需要运行时类型信息进行分发：

| 节点类型 | 需要的类型信息 | 运行时使用方式 |
|---------|--------------|--------------|
| ADT 模式匹配 | 变体 tag 值（`uint8_t`） | 选择 `case` 分支 |
| `?T` 模式匹配 | Nil/非 Nil 区分 | 选择 `Nil` 分支或值分支 |
| Record 字段访问 | 字段偏移量（编译期计算） | 直接内存偏移访问，tag 为 `uint8_t` |

Record 字段偏移量在编译期计算（已知字段顺序和类型排列），编码在 Typed AST 的 Record 访问节点中。无运行时虚表分发。

#### 类型环境

```zig
const TypeEnv = struct {
    types: std.ArrayListUnmanaged(Type) = .empty,
    // TypeId = types 列表索引
};

const Type = union(enum) {
    int_t,
    float_t,
    bool_t,
    char_t,
    string_t,
    bytes_t,
    path_t,
    duration_t,
    unit_t,
    regex_t,
    // 复合类型
    variable: struct { id: u32, level: u32 },
    list: TypeId,
    map: struct { key: TypeId, value: TypeId },
    set: TypeId,
    stream: TypeId,   // Stream t — 惰性序列（元素类型为 t）
    record: struct { fields: []const RecordField },
    tuple: struct { elements: []const TypeId },
    adt: struct { name: []const u8, variants: []const ADTVariant },
    nilable: TypeId,
    function: struct { param: TypeId, result: TypeId },
    effect_fn: struct { param: TypeId, result: TypeId },
    // 标准库类型（编译器内置支持但非基础类型）
    decimal_t,
    command_t,   // Cmd.<bin> 构造的 Command 值，不透明类型
};

> `command_t` 为不透明单元变体——所有 `Cmd.<bin>` 产生的 Command 值在类型系统中等价（结构等价）。编译器不对 Command 值的特定命令名或选项类型做类型级区分——选项错误在运行时 fork/exec 阶段由命令本身报告。若后续版本引入类型化命令模块（v0.5），`command_t` 可扩展为携带 `<bin>_options` 参数的变体。
```

#### 生命周期

Typed AST 分配在脚本级 Arena 上，与原始 AST 共享同一 Arena。类型检查完成后，原始 AST 不再被引用——求值器仅遍历 Typed AST。Arena 销毁时两种 AST 同时释放。

#### 错误报告

类型错误输出包含：

| 字段 | 说明 |
|------|------|
| 源文件名 + 行号 + 列号 | 错误发生的精确位置 |
| 期望类型 | 上下文要求的类型 |
| 实际类型 | 推断出的实际类型 |
| 错误原因 | 类型不匹配的具体原因 |
| 修复建议 | 基于启发式规则的建议 |

所有错误消息通过 i18n 子系统输出，支持中英文双语。编译期错误在构造时存储 msgid 和运行时参数，输出阶段按 locale 格式化。英文 locale 下直接使用 msgid（零额外开销），中文 locale 下从内嵌翻译表查找。完整设计见 [i18n 子系统](i18n.md)。

#### 错误输出示例

以下展示用户终端可见的实际错误输出格式。

**类型不匹配**：

```
── Error: Type Mismatch ────────────────────────────── src/main.kun:12:20 ──
  Expected: String
  Found:    Int
  ──┤
10 │   name : String
11 │   name =
12 │     42
   │     ^^
  ──┤
  Reason: Int 无法与 String 合一
  Hint:   是否缺少 toString 调用？    name = toString 42
```

**模式匹配非穷举**：

```
── Error: Non-Exhaustive Pattern ───────────────────── src/parse.kun:8:3 ──
  Missing patterns for type `Result Int String`:
    ├─ Err _
    └─ patterns covered: Ok n
  ──┤
7  │   case parse input of
8  │     Ok n -> process n
   │     ^^^^^^^^^^^^^^^^^
  ──┤
  Hint: 添加 Err 分支处理：
          Err e -> handleError e
```

**效应违反**：

```
── Error: Effect Violation ───────────────────── src/compute.kun:5:17 ──
  Pure function `compute` calls effect function `File.readString`
  ──┤
4  │ compute : Int -> String
5  │ compute = \n -> File.readString p"/etc/config"
   │                  ^^^^^^^^^^^^^^^
  ──┤
  Hint: 将 compute 移入 do 块，或改为返回常量的纯函数
```

**未消费的 Stream**：

```
── Error: Unconsumed Stream ────────────────────── src/pipe.kun:6:3 ──
  Stream from `Cmd.grep` is never consumed — the subprocess will
  become a zombie and its output pipe will leak.
  ──┤
5  │   do
6  │     Cmd.grep { pattern = "ERROR" } p"/var/log/app.log"
   │     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
7  │     IO.println "done"
  ──┤
  Hint: 添加终端操作消费 Stream：
          Cmd.grep { pattern = "ERROR" } p"/var/log/app.log"
            |> Stream.lines
            |> Stream.iter IO.println
```

**导入解析失败**：

```
── Error: Import Resolution ──────────────────────── src/app.kun:1:8 ──
  Module `Foo.Bar` not found
  ──┤
1 │ import Foo.Bar
   │        ^^^^^^^
  ──┤
  Searched:
    ├─ lib/Foo/Bar.kun          (not found)
    ├─ $KUN_PATH/Foo/Bar.kun    (not found)
    └─ <runtime>/lib/kun/Foo/Bar.kun  (not found)
  Hint: 检查模块文件是否存在，或确认 KUN_PATH 环境变量
```

### `CommandError`

命令执行阶段的语义化错误类型，完整定义见 [`standard-library.md`](../design/standard-library.md)。包含 `NotFound`、`PermissionDenied`、`CommandFailed`、`KilledBySignal`、`IoError`、`PipeFailed` 六个变体。

### 错误传播模型

| 错误类型 | 检测阶段 | 传播方式 | 处理方式 |
|---|---|---|---|
| `TypeError` | 类型检查 | 编译期报错 | 必须修复后重试 |
| 命令失败（无 `?`） | 运行时 | panic | unwind + defer 链 |
| 命令失败（有 `?`） | 运行时 | `Result` | 调用者通过 `case` 处理 |
| 同步 syscall 失败 | 运行时 | `Result` | 调用者通过 `case` 处理 |

### panic 语义

panic 触发 unwind 时，当前 `do` 块的所有 `defer` 按 LIFO 逆序始终执行。未捕获的顶层 panic 退出码：

#### defer 中的二次 panic

若 defer 块在执行过程中自身触发 panic（二次 panic），运行时采用保留首次 panic、静默丢弃二次 panic 的策略：

- 首次 panic 是异常的根因，保留它可提供最具价值的诊断信息
- defer 块通常用于资源清理，清理逻辑失败是次生错误，掩盖根因会误导调试
- 二次 panic 通过 stderr 输出级别为 `warn` 的日志（含 defer 位置和 panic 原因），但不影响 unwind 流程
- 后续 defer 块继续正常执行，不受二次 panic 影响

| 错误变体 | Kun 进程退出码 |
|---|---|
| `CommandFailed { exitCode = n }` | `n`（传播子进程退出码） |
| `NotFound _` | 127 |
| `PermissionDenied _` | 126 |
| `KilledBySignal { signal = s }` | `128 + s` |
| `PipeFailed { error }` | 传播内层 `error` 的退出码 |
| `IoError _` | 1 |
| 用户调用 `Process.exit n` | `n` |
| 纯运行时错误（除零、数组越界等） | 1 |
| 递归深度超限 | 1 |
| SIGINT（Ctrl+C） | 130（128 + 2） |
| SIGTERM | 143（128 + 15） |
| `execve()` 失败（fork 后） | 127（ENOENT）/126（EACCES）/1（其他） |
| `fork()` 失败（EAGAIN/ENOMEM） | 1 |
| 资源限制超限（RLIMIT_CPU / RLIMIT_AS） | 1 |

panic 发生时若存在活跃子进程（已 fork 但未 waitpid），运行时在 unwind 前按以下顺序处理：

1. 向所有活跃子进程发送 `SIGTERM`，等待最多 5 秒
2. 超时仍未退出的子进程发送 `SIGKILL`
3. `waitpid` 回收所有子进程后执行 defer 链
4. defer 中清理操作（如 `File.remove tmp`）在子进程终止后安全执行，避免删除正在写入的文件

此策略确保资源清理的确定性，防止孤儿进程和文件损坏。

> **已知限制**：若子进程处于 D 状态（不可中断睡眠——通常因等待 NFS/磁盘 I/O），`SIGKILL` 无法终止，`waitpid` 将永久阻塞 Kun 进程。此系 Linux 内核的根本性限制，无法在用户态解决。`--cpu-limit` rlimit 对此场景无效——D 状态进程不消耗 CPU 时间，`RLIMIT_CPU` 不会触发。Kun 通过在 panic 清理阶段设置 wall-clock 超时（`alarm()` / `timerfd`）缓解：若整个清理流程超过 10 秒，Kun 进程自行 `_exit(1)` 退出。此策略确保单个 Kun 进程不会永久占用 PID 和内存，但无法回收处于 D 状态的子进程（将被 init 收养）。

### 信号处理与 defer 链保证

运行时在启动阶段为 `SIGINT` 和 `SIGTERM` 注册信号处理器，通过 **signalfd** 机制（Linux 3.8+，与 `Signal.on` 共用同一 signalfd 描述符；`SIGPIPE` 除外——它被忽略而非通过 signalfd 捕获）将信号转换为可控 panic 流程：

- `SIGINT`（Ctrl+C）→ panic 消息 `"interrupted by SIGINT"`
- `SIGTERM` → panic 消息 `"terminated by SIGTERM"`
- panic 触发标准 unwind 流程：当前 `do` 块及其所有外层 `do` 块的 `defer` 按 LIFO 逆序执行（先当前块，再外层块）→ 子进程回收（SIGTERM → SIGKILL → waitpid）→ Arena 销毁 → 退出码传播
- `SIGPIPE` 在启动阶段设置为 `SIG_IGN`（忽略），确保 `Cmd.withStdin` 向已退出子进程的 stdin pipe 写入时不被信号终止。`write()` 返回 `EPIPE` 错误由调用方通过 `Result` 或 panic 处理
- `SIGKILL` 和 `SIGSTOP` 不注册处理器（Linux 内核不允许），收到此二信号时进程按内核默认行为终止——defer 链不执行

此设计确保 `Ctrl+C` 或 `kill <pid>` 不会遗留临时文件、孤儿子进程或泄漏的文件描述符。

> **局限**：信号检测通过主事件循环轮询 signalfd 完成。若主事件循环因阻塞系统调用（如 D 状态 `waitpid`）停止轮询，信号将排队于 signalfd 中，直到阻塞调用返回后才被处理。10 秒 wall-clock 超时（见上方已知限制）提供最终兜底。

## 命令调用机制

所有命令通过 `Cmd.<bin>` 语法调用，命令执行采用 fork-exec 子进程 + 管道捕获 stdout/stderr。语言层设计见 [OS 命令调用机制](../design/command-system.md)。

### 子进程执行流程

```
Cmd.<bin> { options } [posArgs...]
  │
  ├── 编译期：模块发现与选项类型检查
  │   ├── 搜索 ~/.kun/cmd/<Name>.kun → $KUN_PATH/cmd/<Name>.kun → <runtime>/lib/kun/cmd/<Name>.kun
  │   ├── 找到类型化模块 → 加载并提供选项类型检查
  │   └── 未找到 → 裸调用：运行时 PATH 查找 + camelCase 自动映射
  │
  └── 运行时：fork-exec + Stream pipe 捕获
```

Command 执行的系统契约：

```
动作: fork → chdir 到 Cmd.withCwd 指定目录或 Path.cwd（子进程内） → [Cmd.withRunAs: initgroups → setgid → setuid] → setrlimit → install seccomp → exec → waitpid
返回: Stream String（|> 管道触发 / Cmd.exec 显式执行）或 Result (Stream String) CommandError（? 后缀）
argv: Record 选项 → Cmd.withRawOpt 追加 → -- 分隔符 → 位置参数
stdout: pipe 捕获为 Stream String
stderr: 透传到父进程（mergeStderr 时合并到 stdout）
stdin: 继承父进程（/dev/null 或外部管道）
```

子进程 fork 后、exec 前执行以下清理以消除信号竞争：
- 关闭从父进程继承的 signalfd 描述符（`close(signalfd_fd)`）
- 将 `SIGINT`/`SIGTERM` 信号处理器恢复为默认行为（`SIG_DFL`）
- 解除所有被阻塞的信号（通过 `sigprocmask` 恢复默认信号掩码）
此清理确保 fork 与 exec 之间的信号处理符合子进程预期。

## 运行时 PATH 解析

`Cmd.<bin>` 的命令查找发生在**运行时**。编译时不检查命令是否存在。首次 PATH 解析成功后结果缓存（每次 `do` 块入口刷新）。运行时未找到命令则触发 `NotFound` panic。

## 安全隔离

CLI 安全参数（`--allow-path`、`--allow-net`、`--no-sandbox`、`--force`、`--env=`、`--cpu-limit`、`--mem-limit`）的完整说明见 [`kun` CLI 工具](../design/kun-cli-tool.md#安全控制)。

### 安全层架构

父进程与子进程采用两层安全机制叠加（非替代）：

1. **父进程层**（初始化阶段一次性安装）：
   - `prctl(PR_SET_NO_NEW_PRIVS, 1)` — 最优先执行，禁止当前进程及所有后代获取新特权（setuid exec 将无法提升权限），是 Landlock 生效的前提条件
   - Mount namespace `/proc`/`/sys`/`/dev` 加固（内核 3.8+，始终执行）——在所有沙箱模式下均创建最小 mount namespace 重新挂载 `/proc`、`/sys`、`/dev` 为安全实例。此层独立于 Landlock 文件控制，确保伪文件系统始终受控
   - Landlock 文件控制（内核 5.13+）——限制真实文件系统访问；网络控制（内核 6.7+）——限制网络访问
   - Mount namespace 目录级隔离（兜底，内核 3.8+，Landlock 不可用时）：同时创建 network namespace（`CLONE_NEWNET`，内核 3.0+）——在 Landlock 网络控制不可用时（内核 5.13–6.6）提供网络隔离
   - 拒绝运行（内核 < 3.8）
2. **子进程层**（每次 fork 后始终安装）：seccomp-BPF 系统调用过滤 + rlimit 资源限制

> **层次依赖**：Landlock 文件控制依赖 `PR_SET_NO_NEW_PRIVS` 生效；若 Landlock 不可用（内核 < 5.13），mount namespace 兜底提供文件系统隔离但不具备路径精细度。seccomp-BPF 在文件访问上完全依赖上两层——不阻止 `openat`/`read`/`write` 系统调用（这是 Kom 的基本功能前提）。三层安全均运作时，子进程在文件访问、网络、系统调用类型上形成完整隔离链。

### 网络隔离

Kun 的默认安全策略为"无网络访问"。`--allow-net` 为全局开关——启用后所有 `Cmd.*` 子进程均可发起网络连接。未启用 `--allow-net` 时，网络隔离通过以下机制实现：

| 内核版本 | 网络隔离机制 |
|---------|------------|
| ≥ 6.7 | Landlock 网络控制（文件 + 网络规则集） |
| ≥ 3.0 | Network namespace（`CLONE_NEWNET`，与 mount namespace 同时创建） |
| < 3.0 | 拒绝运行 |

`CLONE_NEWNET` 创建一个拥有独立网络栈的新 namespace——无任何网络接口（含 lo），子进程无法建立任何 TCP/UDP 连接。无 per-command 或 per-destination 过滤——精细化网络出口控制需通过 Landlock 网络控制（内核 6.7+）在后续版本中实现。

Landlock 使用严格模式：内核版本不支持所需规则集时拒绝运行，不做静默降级。Mount namespace 采用 `pivot_root`（需 `CLONE_NEWNS`）而非 `chroot`，消除 chroot 已知逃逸路径（`chdir("..")` 多次 + `chroot(".")` 可回到真实根）。

伪文件系统加固在**所有沙箱模式下均执行**（含 Landlock 模式）。`/proc`、`/sys`、`/dev` 在 mount namespace 中重新挂载为最小安全实例：`/dev` 仅暴露 `null`、`zero`、`random`、`urandom`、`tty`、`stdin`/`stdout`/`stderr`、`fd`、`shm`，隐藏 `/dev/mem`、`/dev/kmem` 等可读写内核内存的危险设备。`/proc` 仅暴露当前进程目录和基础内核信息，阻止 `/proc/kallsyms`、`/proc/sysrq-trigger` 等危险接口的访问。

seccomp-BPF 过滤规则禁止以下系统调用类别：

| 类别 | 禁止的 syscall |
|------|---------------|
| 进程注入 | `ptrace`、`process_vm_readv`、`process_vm_writev` |
| FD 窃取 | `pidfd_getfd`（Linux 5.6+，通过 pidfd 从其他进程获取 FD，可窃取父进程特权 FD 绕过 Landlock） |
| 内核模块 | `init_module`、`finit_module`、`delete_module` |
| 内核执行 | `kexec_load`、`kexec_file_load` |
| BPF 逃逸 | `bpf`（可加载 eBPF 程序绕过 seccomp 或注入内核钩子） |
| 文件系统重挂载 | `mount`、`umount2`、`pivot_root`（子进程禁止）；`fsopen`、`fsmount`、`fsconfig`、`open_tree`、`move_mount`（Linux 5.2+ 新 mount API）；`mount_setattr`（Linux 5.12+，修改挂载属性，可移除 nosuid/nodev 保护） |
| 命名空间逃逸 | `unshare`、`clone`（含 `CLONE_NEWNS`/`CLONE_NEWUSER`/`CLONE_NEWNET` 等标志时）；`setns`（加入已有命名空间，绕过 ns 隔离） |
| 原始套接字 | `socket`（`AF_PACKET` 协议族） |
| Landlock 逃逸 | `open_by_handle_at`、`name_to_handle_at`（按 inode 打开文件可绕过 Landlock 路径级限制） |
| 内核利用原语 | `perf_event_open`（CPU PMU 侧信道 / kprobe 附加）、`userfaultfd`（用户态缺页处理，可绕过 W^X）、`memfd_create`（匿名内存文件 + `execveat` 可绕过文件系统级执行限制） |
| 利用辅助 | `personality`（`ADDR_NO_RANDOMIZE` 禁用 ASLR；`PER_LINUX32` 改变 syscall 行为）、`modify_ldt`（x86 LDT 操作，可构造调用门或段越界访问内核内存）、`kcmp`（比较进程间内核资源共享关系，辅助构造利用） |
| 异步 I/O 逃逸 | `io_uring_setup`、`io_uring_enter`、`io_uring_register`（历史漏洞频发，可绕过 seccomp 检查） |

子进程的 seccomp 规则集是固定编译期常量，不受用户配置影响。

> **prctl 子选项过滤**：`prctl` 系统调用不可整体阻止（legitimate 用途包括 `PR_SET_PDEATHSIG`、`PR_SET_NAME` 等）。seccomp-BPF 的 arg0 过滤能力用于阻止以下危险子选项：`PR_SET_MM`（修改进程内存映射描述，可混淆 `/proc/self/maps`）、`PR_CAP_AMBIENT`（提升 ambient 能力集）。实现由 seccomp-BPF 在 arg0 参数上匹配这两个常量值并返回 `SECCOMP_RET_ERRNO`。

沙箱层级展示见 [`kun` CLI 工具](../design/kun-cli-tool.md#沙箱层级)。

### 资源限制（rlimit）

资源限制在进程启动时一次性设置，覆盖解释器自身和所有 `fork` 的子进程——不区分主进程与子进程预算。任一超出限制均触发 panic。

子进程 fork 后、exec 前可进一步收紧限制（但不可放宽），默认值与 CLI 覆盖参数见 [`kun` CLI 工具](../design/kun-cli-tool.md#资源限制)。

### 环境变量安全

子进程缺省继承干净白名单（`PATH`、`HOME`、`USER`、`TERM`、`LANG`、`PWD`、`SHELL`、`TZ`、`DISPLAY`、`XDG_RUNTIME_DIR`、`LC_ALL`、`LC_CTYPE`、`TMPDIR`）。始终剔除列表（`LD_PRELOAD`、`LD_AUDIT`、`LD_DEBUG`、`LD_LIBRARY_PATH`、`LD_PROFILE`、`LD_ORIGIN_PATH`、`GCONV_PATH`、`GLIBC_TUNABLES`）无论策略如何永不传递。额外始终剔除的模式匹配规则：`BASH_FUNC_*`（bash Shellshock-class 函数注入，CVE-2014-6271）、`PYTHONPATH`、`PERL5LIB`、`PERLLIB`、`RUBYLIB`、`RUBYOPT`、`GIO_EXTRA_MODULES`、`GTK_MODULES`（各语言解释器的模块注入向量）。

## 类型运行时表示

### 基础类型

| Kun 类型 | C ABI 表示 | 大小 | 对齐 |
|---|---|---|---|
| `Int` | `int64_t` | 8 字节 | 8 |
| `Float` | `double` | 8 字节 | 8 |
| `Bool` | `uint8_t` | 1 字节 | 1 |
| `Char` | `uint32_t` | 4 字节 | 4 |
| `Duration` | `int64_t` | 8 字节 | 8 |
| `Unit` | `void` | 0 字节 | 1 |
| `Regex` | `*const RegexHandle` | 8 字节 | 8 |
| `Decimal` | `struct { int64_t mantissa, int32_t exponent }` | 12 字节 | 8 |
| `Command` | `struct { uint8_t tag, uint8_t payload[32] }` | 33 字节 | 8 |

> `Regex` 的运行时表示为指向编译后正则引擎句柄的不透明指针。`Command` 为 `Cmd.<bin>` 构造的不透明值，内部结构为编译器实现细节；`Decimal` 以尾数+指数二元组表示。
>
> `Unit` 在 Record/Tuple 作为字段时占用 0 字节（编译器优化省略），但对齐视为 1（与 Zig 0 大小类型的对齐行为一致）。
>
> `payload[32]` 适用于常规命令（命令名 + 少量选项和参数）。修饰器链过长或参数过多的 Command 在编译期展开为 Arena 堆分配的内部表示——此时 `tag` 标记为间接模式，`payload` 存储堆指针。编译器和运行时对此透明处理——用户无需感知内联/堆分配边界。

### 字符串与字节类型

| Kun 类型 | C ABI 表示 |
|---|---|
| `String` | `Slice { uint8_t* ptr, uint64_t len }` |
| `Bytes` | `Slice { uint8_t* ptr, uint64_t len }` |
| `Path` | `Slice { uint8_t* ptr, uint64_t len }` |

```c
typedef struct {
    uint8_t* ptr;
    uint64_t len;
} Slice;
```

### 复合类型

#### `List t`

```c
typedef struct {
    uint8_t* ptr;
    uint64_t len;
    uint64_t cap;
} Array;
```

#### `Map k v`

Map 运行时采用哈希表实现。开地址法，键值对存储在桶数组中。

#### `Set t`

Set 运行时采用与 Map 相同的哈希表结构，仅使用键部分。

### 和类型（ADT）

ADT 在运行时表示为带标记的联合体（tagged union），tag 使用 `uint8_t`。Zig 0.17 中，packed union/struct 支持原生等值比较，求值器在模式匹配时对 tag 的比较可直接使用 `packed struct` 的 `==` 运算符（等价于底层整数的单指令比较），无需手动提取 tag 字节后比较。

```c
// ADT 运行时布局：tag-first design
// Zig 实现中可使用 packed struct { tag: u8, payload: [max_size]u8 }
// 匹配时直接比较整行：if (adt.tag == expected_tag)
// 或对 packed 整体比较：if (adt == expected_pattern)
typedef struct {
    uint8_t tag;
    union {
        // 各变体 payload 在此展开，编译器按最大变体分配空间
        uint8_t _max_size[0];  // 占位
    } payload;
} ADT;
```

#### `?T` (Nilable 类型)

`?T` 的运行时表示分两个策略：

- **引用类型**（`String`、`Bytes`、`Path`、`List`、`Map`、`Set`、`Closure`）：使用 **null 指针** 表示 `Nil`。底层 `Slice.ptr == NULL` 且 `Slice.len == 0` 时值为 `Nil`，否则值为 `T`。零额外存储开销。
- **值类型**（`Int`、`Float`、`Bool`、`Char`、`Duration`、`ADT`、`Record`、`Tuple`）：使用 **tagged union** 表示。tag=0 → `Nil`，tag=1 → `T`。与 ADT 布局一致（`uint8_t` tag + payload）。Zig 0.17 中，值类型的 nilable 可使用 `packed struct { tag: u8, value: T }` 实现，等值比较退化为单条整数比较指令。

```c
// ?Int 的运行时表示（值类型策略）
typedef struct {
    uint8_t tag;          // 0 = Nil, 1 = Int value present
    union {
        int64_t value;    // tag=1 时有效
    };
} NilableInt;
```

#### Record

Record 字段按**声明顺序**排列，使用 **C 兼容对齐**（`alignof` 取所有字段中最大者）。编译器按字段类型的大小和对齐自动插入 padding：

```c
// type User = { name : String, age : Int, active : Bool }
typedef struct {
    Slice   name;         // offset 0,  size 16 (ptr 8 + len 8)
    int64_t age;          // offset 16, size 8
    uint8_t active;       // offset 24, size 1
    // padding: 7 bytes → total 32 bytes (alignof 8)
} UserRecord;
```

Record 无运行时类型 tag——编译器在编译期确保 Record 类型的结构等价，求值器通过字段偏移直接访问。

#### Tuple

Tuple 在运行时表示为**匿名 Record**，字段名为索引（`_0`、`_1`、...）。布局规则与 Record 相同：

```c
// (Int, String) — 二元组
typedef struct {
    int64_t _0;
    Slice   _1;           // alignof=8, 无需额外 padding
} Tuple_Int_String;       // total 24 bytes
```

#### `Map k v`

Map 运行时采用开地址哈希表。C ABI 表示为：

```c
typedef struct {
    uint8_t* entries;      // 桶数组指针：每个桶为 { hash: u64, key: k, value: v, occupied: bool }
    uint64_t len;          // 当前键值对数量
    uint64_t cap;          // 桶数组容量
} Map;
```

#### `Set t`

Set 运行时与 Map 共用同一结构，仅使用键部分（value 为空或忽略）：

```c
typedef struct {
    uint8_t* entries;      // 桶数组指针：每个桶为 { hash: u64, key: t, occupied: bool }
    uint64_t len;          // 当前元素数量
    uint64_t cap;          // 桶数组容量
} Set;
```

### Stream

Stream 在运行时表示为 Zig tagged union（详见执行模型 Stream 惰性求值段）。其 C ABI 表示为一个不透明句柄——Kun 用户代码不直接操作 Stream 的内存布局，而是通过 `Stream.map`/`Stream.filter`/`Stream.toList` 等 API 消费：

| Kun 类型 | C ABI 表示 | 大小 |
|---|---|---|
| `Stream t` | `*const StreamHandle` | 8 字节 |

> `StreamHandle` 为不透明指针——内部为 tagged union（`cmd`/`mapped`/`filtered`/`taken`/`dropped`/`lines`/`parse_mapped`/`parse_mapped_keep`），由运行时分配在 `Stream` 构造时的所属 Arena 上。

### 函数值

```c
typedef struct {
    void*    (*fn_ptr)(void* env, void* args);
    void*    env;
    uint64_t arity;
    uint64_t env_size;
} Closure;
```

> **注**：Kun 的类型系统采用单参数柯里化模型（每层 `function: struct { param, result }`），因此运行时中所有 Kun 函数的 `arity` 恒为 1。多参数函数（如 `add : Int -> Int -> Int`）在求值器中表示为嵌套 Closure：`fn_ptr` 返回中间 Closure，由调用方再次应用。`arity` 字段保留供未来可能的 C ABI 互操作中使用（将 Kun 函数暴露为 C 风格多参数函数指针）。

#### 闭包捕获

编译器在类型检查后执行**闭包转换**（closure conversion / lambda lifting）：
1. 遍历 AST，识别每个 Lambda 的自由变量（Lambda 内引用但未在参数列表中绑定的变量）
2. 将自由变量打包为 `env` 结构体（字段按捕获顺序排列，对齐为最大字段的 `alignof`）
3. 生成闭包构造代码：在 Arena 上分配 `env` + `Closure`，填充 `fn_ptr`、`env` 指针、`arity=1`、`env_size`
4. 嵌套 Lambda：每层 Lambda 执行独立的闭包转换——内层 Lambda 可能捕获外层的自由变量及其外层闭包的 `env` 引用

#### 运行时 Value 类型

求值器计算 Typed AST 节点产生的运行时值：

```zig
const Value = union(enum) {
    int: i64,
    float: f64,
    bool: bool,
    char: u32,
    unit,
    nil,
    string: Slice,
    bytes: Slice,
    path: Slice,
    duration: i64,
    regex: *const RegexHandle,
    decimal: struct { mantissa: i64, exponent: i32 },
    command: CommandPayload,
    list: Array,
    map: MapRepr,
    set: SetRepr,
    record: *anyopaque,    // 指向 Arena 上的 Record 内存
    adt: ADTRepr,
    closure: Closure,
    stream: *StreamNode,   // 指向 tagged union Stream 节点
};

const Array = struct { ptr: [*]u8, len: u64, cap: u64 };
const MapRepr = struct { entries: [*]u8, len: u64, cap: u64 };
const SetRepr = struct { entries: [*]u8, len: u64, cap: u64 };
const ADTRepr = struct { tag: u8, payload: [*]u8 };
const CommandPayload = struct { tag: u8, data: [32]u8 };
```

## 内存管理

### 分配策略

采用分层分配策略，核心是 Arena 分配器：

| 层次 | 分配器 | 生命周期 | 用途 |
|---|---|---|---|
| 脚本级 | Arena | per 脚本执行 | AST、类型表示、临时字符串 |
| 模块级 | Arena | per 模块加载（加载与类型检查完成后销毁） | 模块 AST、缓存类型 |
| 全局 | 标准堆 | 运行时进程全周期 | 内置类型表、Primitive 注册表 |

Arena 分配器特性：线性分配（bump allocation），无释放操作；Arena 在阶段结束时整体销毁。Zig 0.17 的 `ArenaAllocator` 为线程安全且无锁（lock-free）实现——若未来引入并发特性（如 v0.5 的 `Task.spawn`），Arena 不会成为并行度的瓶颈。

脚本模式（`kun` CLI）使用以上三层 Arena 模型。Kun Shell 扩展为双 Arena + 绑定表三层内存模型以支持跨 REPL 求值的绑定持久化，完整设计见 [`kun-shell.md`](../design/kun-shell.md#内存模型)。

#### Arena 与 Stream 生命周期契约

Stream tagged union 的缓冲区所有权遵循以下规则：

| Stream 变体 | 缓冲区所在 Arena | 原因 |
|------------|-----------------|------|
| `cmd` | 脚本级 Arena | `cmd.buf` 为堆分配缓冲区，在构造该 Stream 的脚本执行期间存活 |
| `mapped`、`filtered`、`taken`、`dropped` | 同一 Arena（上游的 Arena） | 纯变换操作不分配新缓冲区——它们包裹上游 Stream 并共享其 Arena |
| `lines` | 构造时所属 Arena | `lines.buf` 为跨 chunk 累积缓冲区，分配在 `Stream.lines` 调用时的当前 Arena 上 |

**关键约束**：
- Stream 的终端操作（`toList`/`iter`/`fold`/`string`/`bytes`）必须在创建该 Stream 的 Arena 销毁前完成。编译器通过 Stream 消费强制检查隐含此保证——未被消费的 Stream 是编译错误，确保消费发生在 Arena 存活期间
- 上游 Stream 链共享同一 Arena：`Cmd.find |> Stream.lines |> Stream.filter` 中，所有节点的缓冲区分配在同一 Arena，一旦消费开始，Arena 不可提前销毁
- Stream 不再被引用后，其缓冲区在 Arena 统一销毁时释放——无需逐个节点追踪释放

### 资源清理

资源管理原则：**谁打开谁关闭，Arena 销毁时自动清理**。Arena 维护终结器列表，销毁时按注册逆序执行。

## 模块解析与加载

Kun 采用目录即命名空间方案：文件名（去掉 `.kun` 后缀）即模块名，目录层级表达名字空间。模块名由文件路径唯一确定，无需在文件中声明。

### 模块组织

```
my-project/
├── deploy.kun                 ← 可执行脚本（有 main，无 export）
├── lib/                       ← 项目库根目录
│   ├── Cmd/
│   │   └── Git.kun            ← 模块 Cmd.Git
│   ├── File.kun               ← 模块 File
│   └── List.kun               ← 模块 List
└── tests/
    └── test-config.kun        ← 可执行测试脚本
```

### 搜索路径

模块搜索路径优先级定义见 [语法设计](../design/syntax.md#搜索路径)。加载流程如下：

### 加载流程

```
import File
      │
      ▼
搜索 lib/File.kun（同库） → 搜索 $KUN_PATH/File.kun → 搜索 <runtime>/lib/kun/File.kun
      │
      ▼
已在缓存中？──是──→ 返回缓存副本
      │
      ▼否
读取文件 → 词法分析 → 语法分析 → 类型检查 → 递归加载依赖 → 缓存
```

### 循环依赖检测

加载器维护加载中集合和已完成缓存。检测到循环依赖时编译期报错。

### 缓存失效

模块索引缓存在脚本执行期间持久有效。以下场景触发缓存刷新：

- 文件系统变更检测：加载前通过 `stat` 检查模块文件 `mtime`，若变化则重新加载
- `--force` 参数：跳过缓存，强制重新解析与类型检查全部模块
- 新增模块：编译器在每次执行入口遍历库根目录，增量更新索引缓存

此策略确保在不重启 `kun` 的情况下，新增或修改的模块文件在下一次脚本执行时自动生效。

## 标准库集成

标准库模块的实现分为两类：纯 Kun 实现（`.kun` 文件，用语言自身编写）和 Primitive 实现（Zig 原生函数，注册到内置 Primitive 函数表）。编译器语法级结构（`Cmd.<bin>`、`do`/`defer`、`case`、`?T`/`Nil`、`|>` 管道等）不在此列——它们由编译器直接解析和代码生成。

### 分类标准

函数是否内置为 Primitive 取决于**是否能**用纯 Kun 实现，而非是否方便：

| 条件 | 类别 | 说明 |
|------|------|------|
| 需要系统调用（fork/exec/read/write/stat/getenv/signalfd 等） | Primitive | Kun 无 FFI，无法从用户态发起 syscall |
| 需要编译期类型内省（`toString` 泛型分发、`Cli.parse` Record 展开等） | Primitive | 需访问编译器的类型环境，纯 Kun 无法实现 |
| 需要直接操作运行时数据结构（哈希表桶数组、切片指针、列表扩容等） | Primitive | Kun 不可变语义 + 无指针操作能力 |
| 纯数据变换/组合子（仅涉及已有数据结构的遍历/构造，无副作用、无指针操作） | PureKun | 完全可用 Kun 表达 |
| 编译器级语法结构 | 不归类为函数 | 由编译器直接处理，非标准库函数 |

### 决策原则

**"保守内置"原则**：不确定时标记为 Primitive。Primitive 函数可在后续版本降级为 PureKun（用 Kun 重写实现），反向迁移则不可能——从 PureKun 升级为 Primitive 意味着原本可行的用户代码在新版本中编译/行为变化，属于破坏性变更。

### Primitive 函数表

#### 数据结构

Primitive 函数表在编译期以 Zig `comptime` 生成，运行时为静态只读数组：

```zig
const PrimitiveFn = *const fn (env: *RuntimeEnv, args: *const Value) Value;

const PrimitiveBinding = struct {
    module: []const u8,   // 所属模块名，如 "IO"
    name: []const u8,     // 函数名，如 "println"
    fn_ptr: PrimitiveFn,  // Zig 实现函数指针
};

const PrimitiveTable = struct {
    bindings: []const PrimitiveBinding,  // 按 module+name 排序的静态数组
    protected_modules: []const []const u8,  // 受保护模块名集合
};
```

表在编译期生成、全局堆分配、初始化后即不可变。运行时无修改入口（无 setter API，指针为 `const`）。

#### 初始化流程

Primitive 函数表在运行时初始化阶段（创建 Arena 分配器后、模块解析前）载入：

```
运行时环境建立
  ├── 创建 Arena 分配器
  ├── 设置全局求值环境（变量帧栈）
  └── 注册 Primitive 函数表
        ├── 编译期常量表直接载入（无运行时分配）
        ├── 表引用标记为 const（不可再修改）
        └── 构建受保护模块名索引 {IO, File, Env, Process, Sys, Cmd, Random, Stream, Signal, Task}
```

#### 函数查找

运行时通过二分查找（按 `module + "." + name` 字符串比较）定位 Primitive 绑定。查找发生在模块加载时，非每次函数调用时——加载后函数值缓存在模块导出环境中。

### 模块加载时的绑定规则

模块加载器在解析 `import M` 时执行以下流程：

```
import M
  │
  ├── 1. M 在受保护模块名集合中？
  │     ├── 是 → 跳过文件系统搜索（不检查 lib/M.kun、$KUN_PATH/M.kun）
  │     │       ├── 加载 <runtime>/lib/kun/M.kun（仅获取签名声明和文档注释）
  │     │       ├── 对每个 export 函数 f：
  │     │       │     ├── Primitive 表中存在 (M, f) → 绑定 Zig 函数指针为函数体
  │     │       │     └── Primitive 表中不存在 → 使用 .kun 文件中的 Kun 实现
  │     │       └── 若用户在 lib/M.kun 或 $KUN_PATH/M.kun 定义了同名模块：
  │     │             → 编译警告（不是错误）："module `M` is a protected built-in;
  │     │                user definition at <path> is ignored; the built-in
  │     │                implementation takes precedence"
  │     │             → 用户定义不生效，以受保护绑定为准
  │     │
  │     └── 否 → 走常规文件系统搜索路径（lib/ → $KUN_PATH → <runtime>/lib/kun/）
  │
  └── 2. 函数名冲突检测（在加载 .kun 文件时执行）：
        ├── Primitive 绑定的函数名 f 在 .kun 文件中只能出现在类型签名声明中
        ├── 若 .kun 文件尝试为 Primitive 绑定的函数提供实现体：
        │     → 编译错误："function `f` is a protected built-in;
        │        implementation is provided by the runtime;
        │        only type signatures are allowed in module M"
        └── 若 .kun 文件中未声明 Primitive 绑定函数 f 的签名：
              → 编译错误："function `f` is a protected built-in;
                 a type signature declaration is required in module M
                 for documentation purposes"
```

### 混合模块

部分模块混合 Primitive 和 PureKun 函数（如 `File` 模块：`File.readString` 为 Primitive，`File.copy` 为 PureKun）。其 `<runtime>/lib/kun/File.kun` 源文件中：

- Primitive 函数：仅声明类型签名（无函数体），附 `doc` 注释
- PureKun 函数：正常定义完整实现

加载器在处理 `File.kun` 时：
1. 解析 Kun 文件得到所有函数的签名和文档
2. 对每个函数查询 Primitive 表：存在 → 以 Zig 实现替换函数体；不存在 → 保留 .kun 中的实现
3. 签名声明必须存在（文档需要），缺失则编译错误

### HM 约束生成器集成

Primitive 绑定的函数签名在编译期预解析为类型表示，存储为 `PrimitiveBinding` 的类型字段：

```zig
const PrimitiveBinding = struct {
    module: []const u8,
    name: []const u8,
    fn_ptr: PrimitiveFn,
    // 编译期预解析的类型签名（从对应 .kun 文件提取并经过类型检查）
    signature: TypeId,   // 函数类型（function 或 effect_fn 变体）
};
```

HM 约束生成器在处理 Primitive 函数调用时：
1. 从 `PrimitiveTable` 查找 `(module, name)` 对应的 `PrimitiveBinding`
2. 从 `signature: TypeId` 获取预解析的函数类型（无需求值 `.kun` 文件）
3. 将该类型与调用上下文生成等价约束（与普通函数调用相同）

此设计确保 Primitive 函数签名与 HM 合一算法的集成不依赖运行时文件解析——签名在编译期一次性从 `.kun` 源码提取并类型检查后固化在 `PrimitiveBinding` 中。`Cmd.withStdin` 的双重重载（`String -> Command -> Command` 和 `Stream Bytes -> Command -> Command`）在约束生成时由调用点参数类型驱动选择正确的签名——编译器按 HM 上下文中的参数类型自动匹配。

### 安全防护

| 攻击面 | 防护机制 |
|--------|---------|
| 用户用受保护模块名创建 `lib/M.kun` 覆盖内置 | 受保护模块跳过文件系统搜索；用户定义不生效，编译警告提示 |
| 运行时修改 Primitive 表 | 编译期常量静态数组，无运行时修改入口（`const` 引用 + 无 setter API） |
| 用户在同模块 .kun 中定义与 Primitive 同名的函数 | 编译错误："function is a protected built-in; only type signatures allowed" |
| 用户 `import IO` 后重新绑定 `IO = { println = myPrintln }` | Record 字面量创建当前作用域新绑定，不修改模块导出环境；模块绑定不可变 |
| 用户通过 `export (f)` 重新导出受保护函数 | `export` 仅转发已有绑定；受保护函数的绑定来源始终为 Primitive 表 |
| 恶意文件以受保护模块名放置在 `$KUN_PATH` 中 | 受保护模块名跳过所有文件系统搜索路径 |

### 逐函数实现类别总表

详见 `design/standard-library.md` 中每个函数签名后的 `[Primitive]` / `[PureKun]` 标注。以下为汇总：

| 模块 | Primitive 占比 | 说明 |
|------|--------------|------|
| `Int`、`Float`、`String`、`Bytes`、`Char` | 少量 Primitive | 基础运算符由编译器内置；`String.length`/`slice` 需直接操作内存 |
| `Regex` | 几乎全部 Primitive | 正则引擎依赖 C 库（PCRE2/regexec） |
| `Math`、`Function`、`Result`、`Nil` | 全部 PureKun | 纯组合子 |
| `List`、`Map`、`Set` | 结构操作为 Primitive | `map`/`filter`/`fold` 为 PureKun，`get`/`insert`/`append` 等为 Primitive |
| `IO`、`File`(大部分)、`Env`、`Process`、`Sys`、`Random`、`Task` | 全部 Primitive | 需要系统调用 |
| `Cmd` 执行 (`exec`/`pipe`/`which`/`timeout`/`retry`) | Primitive | fork-exec |
| `Cmd` 修饰 (`withEnv`/`withStdin` 等) | PureKun | 纯 `Command` 值变换 |
| `Stream` 构造/终端 (`fromList`/`toList`/`lines` 等) | Primitive | tagged union 操作 |
| `Stream` 变换 (`map`/`filter`/`take`/`drop`) | PureKun | 包裹上游 Stream |
| `Path`、`Duration`、`Decimal`、newtype 模块 | 全部 PureKun | 基于已有基础类型的变换 |
| `Cli` (`parse`/`show`) | Primitive | 需编译期代码展开 |
| `Parser` | Primitive | 需编译期代码展开 |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.15 | 审计修复三轮：defer 作用域统一（嵌套 do 独立链 + LIFO 全展开）；fork/exec 信号竞争防护（子进程清理 signalfd/信号处理器/掩码）；闭包捕获转换流程；Stream 纯变换合并优化细节；let in thunk+memoization 实现 |
| 2026.06.15 | 审计修复二轮：SIGPIPE 忽略策略；Primitive ↔ HM 约束生成器集成接口；Stream 消费 AST 级分析算法；Cmd.exec 阻塞语义；主事件循环架构；Closure arity 与柯里化模型澄清 |
| 2026.06.15 | 审计修复：效应检查规则补全 Stream 消费强制检查；CommandError 新增 Timeout 变体；PipeFailed 嵌套深度限制 16 层；Process.exit 范围检查 |
| 2026.06.15 | Zig 0.17 特性驱动的设计优化：求值器标注 labeled switch 分发（分支预测优化）；TypeEnv 使用 `.empty` 初始化；ADT 比较和 `?T` nilable 比较标注 packed equality 优化；ArenaAllocator 线程安全标注 |
| 2026.06.15 | Zig 宿主语言版本从 0.13.0 升级至 0.17.0-dev；技术栈表更新版本号 |
| 2026.06.15 | i18n 国际化：初始化阶段新增 locale 检测步骤；错误报告章节补充 i18n 策略说明和文档引用 |
| 2026.06.15 | 标准库集成章节重写：新增 Primitive 函数表数据结构、初始化流程、模块加载绑定规则、受保护模块安全防护、逐函数实现类别汇总 |
| 2026.06.14 | 效应函数列表修正：`Signal.*` → `Signal.on`；Stream tagged union 新增 `dropped`/`lines`/`parse_mapped`/`parse_mapped_keep` 变体；seccomp 新增新 mount API syscall（`fsopen`/`fsmount`/`fsconfig`/`open_tree`/`move_mount`）；用户定义效应函数自动获取 `EffectFn` 内部类型 |
| 2026.06.14 | 安全加固：seccomp 新增 `bpf`/`perf_event_open`/`userfaultfd`/`memfd_create`；新增 `prctl(PR_SET_NO_NEW_PRIVS)` 沙箱前置条件；网络隔离新增 CLONE_NEWNET 覆盖内核 5.13–6.6；环境变量过滤新增 `BASH_FUNC_*`/`PYTHONPATH`/`PERL5LIB` 等注入防御；D-state 文档修正（`--cpu-limit` 无效 + wall-clock 超时方案）；`Cmd.withRunAs` 完整权限降级流程 |
| 2026.06.14 | 效应检查算法更新：新增 `(a -> b)!` 效应回调参数检测（含 `!` 的函数标记为效应函数、纯函数禁止声明 `!`、`!` 实参必须为效应函数）；Command 执行模型更新：移除 `do` 块隐式执行，新增 `Cmd.exec` 显式执行，未被消费 Command 是编译错误；效应函数列表新增 `Cmd.exec` |
| 2026.06.13 | 类型检查算法章节；初始化阶段顺序修正（模块解析在沙箱之前）；Stream 消费强制检查 + 管道非阻塞 IO 策略；Landlock 严格模式 + pivot_root + /proc 处理；panic 活跃子进程回收策略；env 白名单扩展；模块缓存失效策略 |
| 2026.06.12 | 文档重构：命令调用机制独立为 `command-system.md`；CLI 工具与安全控制独立为 `kun-cli-tool.md`；`TempFile`/`TempDir` 整合为 `File.createTempFile`/`File.createTempDir`；新增 `Cmd.mergeStderr`、`Cmd.timeout`/`Cmd.retry`、`Cmd.withRunAs`/`Cmd.andThen`/`Cmd.orElse` 文档；版本号统一为 yyyy.MM.dd 日期格式 |
| 2026.06.11 | 模块系统重设计：目录即命名空间；`export (…)` 替代 `module Xxx export (…)`；`import X (…)` 替代 `import X with (…)` |
| 2026.06.10 | 架构重设计：移除 `.cmd.kun`/`IO T`/`with caps`/dlopen/ptrace 等；新增 `Cmd.<bin>` fork-exec + Landlock/mount ns + `defer` + tagged union Stream |
| 2026.05.27 | 项目初始化，设计文档定型 |
