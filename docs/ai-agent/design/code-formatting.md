# 代码格式化规范

## 语句分隔

Kun **不支持**分号（`;`）作为语句分隔符。每条语句必须独占一行。`case` 分支也各自独立为行。

```kun
// ✅ 正确
case x of
  Ok v -> process v
  Err _ -> handleError

// ❌ 错误
case x of Ok v -> process v; Err _ -> handleError
```

## 文件级声明顺序

文件分为两类：库模块（有 `export` 声明）和可执行脚本（有 `main` 无 `export`）。

### 库模块

文件第一个非注释行必须是 `export` 声明，紧接 `import` 语句，之后是其余代码：

```kun
// ✅ 库模块
export (run, helper)

import List
import Path

run : Path -> Unit
run = \dir ->
  do
    ...
```

### 可执行脚本

文件**不能有 `export` 声明**，必须定义 `main` 函数。`import` 语句为文件首部：

```kun
// ✅ 可执行脚本
import List
import Path

main : List String -> Unit
main = \_ ->
  do
    ...
```

其余代码（类型定义、函数定义、绑定等）顺序无强制要求。

## 缩进

使用 2 空格缩进，不使用 Tab。

> **注**：Kun 的解析器**不依赖缩进**来解析结构——所有代码块由显式关键字界定（`do`、`let...in`、`case...of`）。分支体内多语句的边界识别通过 `pattern ->` / `else if` / `else` **关键字定界** + `case...of` 配对跟踪实现，不依赖缩进。缩进规则仅约束代码**格式**（可读性），不约束代码**语义**。`kun fmt` 工具据此规则自动格式化代码；`kun lint` 据此规则检查格式合规性。

各语境的缩进量（相对于父级上下文）：

| 上下文 | 缩进 |
|--------|------|
| 顶层定义 | 0 |
| `export` 导出列表 | +2 |
| `type` 变体 `=` / `\|` | +2 |
| ADT 变体中的 Record 字段 | +4（从 `\|` 算 +2） |
| 函数体 / Lambda 体 | +2 |
| `do` 块内语句 | +2（从 `do` 算） |
| `do in` 的 body 内语句 | +2（从 `do` 算） |
| `in`（`do in` / `let in`） | 与 `do` / `let` 对齐 |
| `let in` 的 body 内绑定 | +2（从 `let` 算） |
| `if` / `case` 分支模式 | +2（从 `if`/`case` 算） |
| `if` / `case` 分支体（多行） | +4（从 `if`/`case` 算） |
| Branch 内显式 `do`/`do in`/`let in` | +4（从 `if`/`case` 算），内层语句再 +2 |
| unbound 分支隐式 do body | +4（从 `if`/`case` 算），同分支多行体 |
| `if` 省略 `else` | 同 `if` / `case` 分支模式与分支体 |
| `\|>` 链续行 | 与管线起始端对齐 |
| `Cmd.pipe` 命令列表项 | +2 |
| 多行 Cmd 参数（`#{}`/`{}`/位置参数） | +2 |
| `defer` | 与所在块内语句同级 |

## 行宽

每行不超过 100 个字符。超出应换行。

### 效应函数

效应函数体必须显式以 `do` 或 `do in` 包裹，无论单语句还是多语句。`do`/`do in` 与 Lambda 体同级缩进：

```kun
deploy : Config -> Unit
deploy = \cfg ->
  do
    IO.println "deploying..."
    Cmd.rsync { archive = true } cfg.source cfg.target |> Cmd.exec

countFiles : Path -> Int
countFiles = \dir ->
  do
    entries =
      Cmd.ls { all = true } dir
        |> Stream.lines
        |> Stream.toList
  in
    List.length entries
```

简短单语句可同行：

```kun
pid : -> Process.Pid
pid = \ -> do Process.pid
```

### 纯函数

纯函数体为 `let in`（单一表达式时可省略）。多绑定须用 `let in` 包裹，`in` 与 `let` 对齐：

```kun
add : Int -> Int -> Int
add = \x y ->
  x + y                             // 单表达式，let in 省略

sumAndFloor : List Int -> Int
sumAndFloor = \items ->
  let
    total = List.sum items
  in
    toInt (toFloat total / 3.0)     // 多语句，须用 let in
```

多参数 Lambda 换行时，函数体缩进 2。体为 `do`/`do in`/`let in` 时，该关键字与 Lambda 体同级缩进。

Lambda 参数支持解构：

```kun
addPair = \(x, y) -> x + y
sumCoordinates = \{x, y} -> x + y
firstThree = \[a, b, c] -> a + b + c
```

## 控制流

### `case`

`case` 必须在换行后开始，不能与 `=`、`->` 在同一行。`case` 整体缩进 2，分支模式缩进 0（从 `case` 算 +2），分支体缩进 +4（从 `case` 算）：

```kun
result =
  case value of
    Ok r -> r
    Err _ -> default
```

分支按结果是否被消费分为 unbound 和 bound 两种格式。

#### Unbound（结果未被消费——do 上下文中）

当 `case` 结果未被值绑定、也不作为函数返回值，且处于 `do` 效应上下文时，各分支为隐式 `do`。分支内可直接书写多语句，不需显式 `do` 包裹，结果均为 `Unit`：

```kun
do
  case File.readString path of
    Ok text ->
      IO.println "processing..."
      process text
    Err e ->
      IO.println (toString e)
```

`defer` 在 unbound 分支中属于该分支自身的隐式 `do`，退出分支时立即执行：

```kun
do
  case command of
    Deploy config ->
      defer cleanupDeploy ()
      Cmd.ffmpeg {} "input.mp4" tmp |> Cmd.exec
    Rollback version ->
      defer cleanupRollback ()
      Cmd.restore {} version |> Cmd.exec
```

#### Bound（结果被值绑定或作为函数返回值）

多语句分支必须用 `do in`（效应上下文）或 `let in`（纯上下文）包裹为单一表达式，单表达式分支直接书写即可。各分支结果类型必须相同：

```kun
// 效应上下文 bound — 多语句分支须用 do in
result =
  case File.readString path of
    Ok text ->
      text                            // 单表达式，不需包裹
    Err e ->
      do
        IO.println (toString e)
      in
        defaultText                   // 多语句，须 do in 包裹

// 纯上下文 bound — 多语句分支须用 let in
processed =
  case items of
    [] ->
      []
    list ->
      let
        filtered = List.filter isPositive list
        squared = List.map square filtered
      in
        List.sum squared |> List.singleton
```

> `case ... of` 内嵌 `do in`/`let in` 的 `do`/`let` 缩进为 +4（从外层 `case` 算），其内部 body 语句再缩进 +2。

模式守卫使用 `when`：

```kun
case n of
  0 -> "zero"
  m when m > 0 -> "positive"
  _ -> "negative"
```

#### Or 模式（多模式匹配）

多个模式以 `|` 连接共享同一分支体时，所有子模式在同一行。分支体支持多语句序列（规则同单模式分支）：

```kun
case level of
  Info | Success    -> "good"
  Warning           -> "warn"
  Failure | Rollback -> "danger"
```

多语句 or 模式分支体示例：

```kun
case level of
  Info | Success ->
    IO.println "proceeding..."      // 效应上下文传播到分支体
    "good"
  Failure | Rollback ->
    IO.println "aborting..."
    "danger"
```

含有 `when` 守卫时，`when` 放在最后一个子模式之后：

```kun
case color of
  Red | Blue when darkMode -> "dark accent"
  Red | Blue               -> "accent"
  Green                    -> "secondary"
```

子模式过多导致超出行宽（100 字符）时，换行缩进，每行一个子模式，`|` 对齐：

```kun
case value of
  AVariantWithLongName
    | BAlsoLongName
    | CLongNameToo -> handleGroup
  Other -> default
```

### `if then else`

`if`、`else if`、`else` 各自独立一行。分支规则与 `case` 一致，按 unbound / bound 区分：

**Unbound（do 上下文中，结果未被消费）** — 分支为隐式 `do`，直接书写多语句：

```kun
do
  if cfg.dryRun then
    IO.println "\n  DRY RUN — exiting.\n"
    Process.exit 0
  else if cfg.verbose then
    IO.println "proceeding..."
    doWork ()
  else
    doWork ()
```

**Bound（结果被消费）** — 多语句分支须用 `do in`/`let in` 包裹，单表达式直接书写：

```kun
result =
  if length parts < 4 then
    Err UnknownFormat
  else if length parts > 100 then
    let
      msg = "too long"
    in
      Err (TooLong msg)
  else
    Ok parsed
```

#### 省略 else

省略 `else` 时隐式类型为 `Unit`。在 bound 位置省略 `else`，要求 `then` 分支也返回 `Unit`（用 `do`）：

```kun
// unbound 位置：无条件执行效应，省略 else
do
  if needsCleanup then
    defer (File.remove tmp)
    Cmd.cleanup {} |> Cmd.exec
  // 无 else — if 结果被丢弃，隐式 Unit

// bound 位置：then 分支须返回 Unit
result =
  if needsAbort then
    do
      IO.println "aborting"
  // else 省略 → 隐式 Unit，与 then 的 do (Unit) 一致
```

> 省略 `else` 的 `if` 不可出现在需返回非 `Unit` 值的位置。

### `let in`

`let` 和 `in` 各自在新行，不能与 `=` 在同一行。body 内绑定缩进 +2（从 `let` 算），`in` 与 `let` 对齐：

```kun
result =
  let
    x = 1
    y = 2
  in
    x + y
```

**空 body 约束**：`let in <expr>`（body 无任何绑定）为编译错误。直接在需要的位置书写 `<expr>` 即可：

```kun
// ❌ 编译错误
result = let in x + 1

// ✅ 直接写表达式
result = x + 1
```

单条绑定时，`let` 可省略（此时无 `in` 关键字）：

```kun
// ✅ 单一表达式，let in 省略
result = x + y
```

### `do` / `do in`

`do` 在新行开始，body 内语句缩进 +2。`do`（无 `in`）结果固定为 `Unit`。

`do in` 在副作用执行后返回值——`in` 在独立行，与 `do` 对齐，`in` 后表达式的结果即为整个 `do in` 的值（必须为非 `Unit`）：

```kun
// do — 返回 Unit
main = \_ ->
  do
    step1
    step2

// do in — 返回值
readConfig : Path -> Result Config Error
readConfig = \path ->
  do
    content = File.readString path
  in
    case content of
      Ok text ->
        let
          lines = String.split "\n" text
          logDir = p"/var/log/myapp"
        in
          Ok (createDefaultConfig logDir)
      Err e -> Err (ConfigReadError e)
```

**空 body 约束**：`do`（无 body）和 `do in <expr>`（body 无语句）为编译错误。

同一函数 scope 内 `do`/`do in` 与 `let in` 不可互嵌套——效应上下文和纯上下文互斥。

```kun
// ✅ do 内嵌套 do
do
  result =
    case items of
      Ok item ->
        do
          IO.println "found"
        in
          process item
      Err _ -> default

// ❌ do 内出现 let in — 编译错误
// ❌ let in 内出现 do — 编译错误
```

## 管道

### `|>` 进程内管道

每个管道步骤独立一行，`|>` 与管线起始端对齐：

```kun
// ✅ 正确
result =
  stream
    |> filter predicate
    |> map transform
    |> fold (+) 0

// ❌ 错误：全部挤在一行
result = stream |> filter predicate |> map transform |> fold (+) 0
```

`|>` 链从 Cmd 起始时，`|>` 缩进与 Cmd 名对齐：

```kun
do
  entries =
    Cmd.ls { all = true } dir
      |> Stream.lines
      |> Stream.take 100
      |> Stream.toList
```

### `Cmd.pipe` OS 管道

`Cmd.pipe` 独占一行，命令列表每项一行，逗号前置：

```kun
Cmd.pipe
  [ Cmd.ps { a = true }
  , Cmd.grep { pattern = "nginx" }
  , Cmd.head { n = 10 }
  ]

Cmd.pipe?
  [ Cmd.find { name = "*.log" }
  , Cmd.xargs { r = "grep ERROR" }
  ]
```

`Cmd.pipe` 的结果可继续接入 `|>` 链：

```kun
Cmd.pipe
  [ Cmd.ps {}
  , Cmd.grep {}
  ]
  |> Stream.lines
  |> Stream.toList
```

## Record / Map

### 创建

单行：

```kun
point = { x = 1, y = 2 }
```

多行时每个字段独立一行，逗号前置，右括号与左括号对齐：

```kun
config =
  { name = "app"
  , version = "0.1"
  , debug = false
  }
```

### Map 字面量

Map 使用 `#{ }` 语法，格式化规则与 Record 相同：

```kun
// 单行
env = #{ "HOME" = "/root" }

// 多行
opts =
  #{ "NODE_ENV" = "production"
   , "DEBUG"    = "true"
   }
```

### 解构

```kun
{ x as x1, y as y1 } = point
```

### 模式匹配

```kun
describePoint = \p ->
  case p of
    { x = 0, y = 0 } -> "origin"
    { x = _, y = 0 } -> "on x axis"
    { name as n, age = 10 } -> f"young {n}"
    _ -> "somewhere"
```

## List / 容器

### 字面量

单行：

```kun
list = [1, 2, 3]
```

多行时每个元素独立一行，逗号前置：

```kun
list =
  [ 1
  , 2
  , 3
  ]
```

范围字面量 `[start..end]` 写在一行内：

```kun
list = [1..1000]
```

### Cmd.pipe 命令列表

命令列表中的每个 Command 独占一行，逗号前置：

```kun
Cmd.pipe
  [ Cmd.cat p"/var/log/app.log"
  , Cmd.grep { pattern = "ERROR" }
  , Cmd.head { n = 100 }
  ]
```

## ADT 定义

变体竖排，`=` 与第一个变体同行，`|` 与 `=` 对齐：

```kun
type Validation e a
  = Pass a
  | Fail e
```

变体带无名字段时同行：

```kun
type Color
  = Red
  | Green
  | Blue
```

变体带 Record 字段时，`{` 在 `|` 下方缩进，字段换行：

```kun
type ParseResult
  = Success String
  | Skipped String
  | Failure
      { line    : Int
      , col     : Int
      , message : String
      }
  | Fatal
      { reason : String
      , cause  : ?ParseResult
      }
```

## 类型标注

类型标注在定义的上方独立一行：

```kun
add : Int -> Int -> Int
add = \x y -> x + y
```

多行类型标注时后继行缩进 2 空格：

```kun
fetchData
  : Host
  -> Path
  -> Result String FetchError
```

## 导出声明

### 库模块

`export` 独占一行，导出列表换行缩进，逗号前置：

```kun
export
  ( JsonValue
  , JsonValue(..)
  , fromString
  , toString
  )
```

导出列表仅 1-2 项时可同行：

```kun
export (Config, defaultConfig)
```

### 可执行脚本

可执行脚本**不能有 `export` 声明**，直接以 `import` 或 `main` 开头。

## Cmd 调用

### 单行

参数少时全部同行，选项 Record 在前，位置参数在最后：

```kun
Cmd.ls { long = true }
Cmd.git.log { maxCount = 50 } "main"
Cmd.cat? p"/etc/maybe_missing"
```

### 多行

参数多时，Cmd 名独占一行，各参数块换行缩进 2，块之间无空行：

```kun
Cmd.rsync
  { archive = true, compress = true }
  srcPath dstPath
```

选项 Record 可为空 `{}`。

### `|>` 链接

Cmd 后可通过 `|>` 链式追加 `Cmd.withEnv`、`Cmd.withRawOpt` 或 `Cmd.withStdin`：

```kun
Cmd["g++"] { o = "a.out" } "main.cpp"
  |> Cmd.withRawOpt "-Wall" Nil
  |> Cmd.withRawOpt "-I" "/usr/local/include"

Cmd.mysql { u = "root" }
  |> Cmd.withStdin """
    CREATE DATABASE mydb;
    """
```

### 特殊字符命令名

含 `-`、`.`、`+` 或数字开头的命令使用 `Cmd["..."]` 转义：

```kun
Cmd["ntfs-3g"] { force = true } "/dev/sda1"
Cmd["g++"] { o = "a.out" } "main.cpp"
  |> Cmd.withRawOpt "-Wall" Nil
Cmd["a-b-c"] { flag = true }
```

## do 块内多行绑定与管道

`do` 块内的多行赋值，`=` 独占一行，右侧值体缩进 2：

```kun
do
  entries =
    Cmd.ls { all = true } dir
      |> Stream.lines
      |> Stream.take 100
      |> Stream.toList
  IO.println f"found {List.length entries} items"
```

`do` 块内语句之间**无空行**。

## Lambda 作为高阶函数参数

### 简单 Lambda（体为纯表达式）

同行：

```kun
stream |> Stream.filter (\l -> String.contains "ERROR" l)
```

### Lambda 体为 `do` 块

函数名和 Lambda 各自换行，闭括号与参数紧随或换行：

```kun
do
  List.iter
    (\item ->
      do
        IO.println f"processing {item.name}"
        Cmd.process {} item.path |> Cmd.exec
    )
    items

  Signal.on
    SIGTERM
    (\sig ->
      do
        Process.exit 0
    )
```

## defer

`defer` 与所在块内语句同级缩进，延迟表达式使用 `()` 包裹。`defer` 的作用域为最近的 `do` 块（含 unbound 分支中的隐式 `do`）：

```kun
do
  tmp = p"/tmp/out.mp4"
  defer (File.remove tmp)
  defer (IO.println "cleanup complete")

  Cmd.ffmpeg {} "input.mp4" tmp |> Cmd.exec
```

多个 `defer` 按 LIFO 逆序执行。unbound 分支中的 `defer` 属于该分支自身的隐式 `do`，退出分支时立即执行。`defer` 适合"尽力清理"逻辑，不适合"必须成功"的操作。

## if/case 分支体格式

分支体格式取决于 `case`/`if` 表达式结果是否被消费。

### 单行分支体

分支体与 `->` / `then` / `else` 同行：

```kun
case x of
  Ok v  -> process v
  Err _ -> handleErr

if done then result else fallback
```

### Unbound 分支（do 上下文中，结果未被消费）

分支为隐式 `do`，多语句直接书写，无需显式 `do` 包裹。分支体缩进 +4（从 `if`/`case` 算），语句间无空行：

```kun
do
  case content of
    Ok text ->
      IO.println f"got {text}"
      process text
    Err e ->
      IO.println "error"
      fallback e

  if condition then
    IO.println "doing work..."
    Cmd.tool {} target |> Cmd.exec
  else
    IO.println "skipping"
    Process.exit 1
```

`defer` 在 unbound 分支中属于该分支自身的隐式 `do`，退出分支时立即执行：

```kun
do
  if needsBackup then
    defer (File.remove tmpBackup)
    Cmd.tar {} sourcePath tmpBackup |> Cmd.exec
  else
    IO.println "skipping backup"
```

若需要分支与外层 `do` 共享 `defer` 生命周期，将 `defer` 语句写在外层 `do` 中：

```kun
do
  defer globalCleanup ()
  if needsBackup then
    Cmd.tar {} sourcePath tmpBackup |> Cmd.exec
  else
    IO.println "skipping backup"
  // globalCleanup 在此执行
```

### Bound 分支（结果被值绑定或作为函数返回值）

多语句分支必须用 `do in`（效应上下文）或 `let in`（纯上下文）包裹为单一表达式。内嵌 `do`/`let` 缩进 +4（从外层 `if`/`case` 算），内部语句再 +2：

```kun
// 效应上下文 — 多语句须用 do in 包裹
result =
  case File.readString path of
    Ok text ->
      text
    Err e ->
      do
        IO.println (toString e)
      in
        defaultText

// 纯上下文 — 多语句须用 let in 包裹
processed =
  if list |> List.isEmpty then
    []
  else
    let
      filtered = List.filter isPositive list
      squared = List.map square filtered
    in
      List.sum squared |> List.singleton
```

分支边界通过关键字定界——`case` 分支结束于下一个 `pattern ->`，`if` 分支结束于 `else if` / `else`。解析器不依赖缩进识别分支边界——`case...of` 嵌套通过配对跟踪，嵌套 `case` 的 `pattern ->` 不触发外层分支终止。

## 注释

`//` 后加一个空格再写注释内容：

```kun
// 这是一条注释
```

文档注释直接以 `//` 开头，支持 Markdown：

```kun
// 计算两数之和
// 参数 `x`、`y` 为待加整数
add = \x y -> x + y
```

行尾注释允许在代码较短时使用，代码与 `//` 之间至少间隔 2 个空格。同组变量尽量对齐：

```kun
// 推荐：对齐注释列
name     = "app"       // String
version  = 2024        // Int
rate     = 3.14        // Float

// 推荐：短代码行尾注释
result =
  case value of
    Ok r -> r           // 解包成功
    Err _ -> default    // 使用默认值

// 不推荐：代码过长挤占注释空间
aLongVariableName = someFunction withMany args  // 不推荐

// 推荐：代码过长时注释独立一行
// 这是一个较长的说明文字
aLongVariableName = someFunction withMany args
```

## 空白行

- 顶层声明（`type` / 函数 / `main`）之间空 1 行
- 同一定义的内部各行之间不空行
- `do` 块内连续语句之间不空行
- `if` / `case` 分支之间不空行
- 函数体内的逻辑段落之间可空 1 行
- 文件末尾留 1 个空行

## 完整示例

```kun
type LogEntry =
  { timestamp : String
  , level     : String
  , message   : String
  }

currentTime : -> String
currentTime = \ ->
  do
    now = DateTime.now
  in
    case DateTime.format "HH:mm:ss" now of
      Ok s  -> s
      Err _ -> "??:??:??"

parseLine : String -> Result LogEntry String
parseLine = \line ->
  case String.split " " line of
    [ts, lvl, ..rest] ->
      Ok { timestamp = ts, level = lvl, message = String.join " " rest }
    _ ->
      Err f"invalid line: {line}"

main : List String -> Unit
main = \_ ->
  do
    entries =
      Cmd.pipe
        [ Cmd.cat p"/var/log/app.log"
        , Cmd.grep { pattern = "ERROR" }
        , Cmd.head { n = 100 }
        ]
        |> Stream.lines
        |> Stream.parseMap parseLine
        |> Stream.toList

    IO.println f"found {List.length entries} errors at {currentTime}"
    List.iter
      (\entry ->
        do
          IO.println f"[{entry.timestamp}] {entry.message}"
      )
      entries
```

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.19 | 单一表达式范式配套更新：缩进表新增 `let in` body、`do in` body、branch 内嵌 `do`/`let` 条目；函数定义按效应/纯函数分离格式说明（效应函数必须 `do`/`do in`、纯函数体单一表达式可省略 `let in`）；`case`/`if` 分支按 unbound/bound 区分格式（unbound 隐式 `do` 不需包裹、bound 多语句须 `do in`/`let in` 包裹）；`let in` 新增空 body 编译错误说明；`do`/`do in` 新增空 body 约束和互斥说明；分支体格式章节重写（移除"继承效应上下文"、新增 unbound/bound 分支格式、defer 在 unbound 分支中的格式） |
| 2026.06.18 | 新增 Or 模式格式化规则——短模式同行、长模式换行缩进、`when` 守卫位置 |
| 2026.06.13 | 代码块标签修正；零参效应 Lambda 示例补充 `do` 块 |
| 2026.06.10 | 代码格式化规范初始定义 |
