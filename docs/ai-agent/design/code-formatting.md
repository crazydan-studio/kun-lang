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

run : Path -> Unit ! {Cmd, IO}
run = \dir -> do
  ...
```

### 可执行脚本

文件**不能有 `export` 声明**，必须定义 `main` 函数。`import` 语句为文件首部：

```kun
// ✅ 可执行脚本
import List
import Path

main : List String -> Unit ! {IO}
main = \_ -> do
  ...
```

其余代码（类型定义、函数定义、绑定等）顺序无强制要求。

## 缩进

使用 2 空格缩进，不使用 Tab。

> **注**：Kun 的解析器**不依赖缩进量，依赖换行与行首 token**来解析结构——所有代码块由显式关键字界定（`do`、`let...in`、`case...of`、`do...with`、`let...in...with`）。分支体内多语句的边界识别通过 `pattern ->` / `else if` / `else` **关键字定界** + `case...of` 配对跟踪实现，不依赖缩进量。缩进规则仅约束代码**格式**（可读性），不约束代码**语义**。`kun fmt` 工具据此规则自动格式化代码；`kun lint` 据此规则检查格式合规性。

各语境的缩进量（相对于父级上下文）：

| 上下文 | 缩进 |
|--------|------|
| 顶层定义 | 0 |
| `export` 导出列表 | +2 |
| `type` 变体 `=` / `\|` | +2 |
| ADT 变体中的 Record 字段 | +4（从 `\|` 算 +2） |
| 函数体 / Lambda 体 | +2 |
| `\args -> do` body 内绑定/语句 | +2（从 `\args -> do` 所在行算） |
| `let in` body 内绑定/语句 | +2（从 `let` 算） |
| `in`（`let in`） | 与 `let` 对齐 |
| `do ... with` / `let ... in ... with` 的 `with` | 与 `do`/`let` 对齐 |
| `do...with` 的 body（语句）/ `let...in...with` 的 body（语句）与 expr | +2（从 `do`/`let` 算） |
| `handler <Eff> of` 的操作分支体 | +2（从 `handler` 算） |
| `if` / `case` 分支模式 | +2（从 `if`/`case` 算） |
| `if` / `case` 分支体（多行） | +4（从 `if`/`case` 算） |
| Branch 内 `-> do` body | +4（从 `if`/`case` 算），同分支多行体 |
| Branch 内显式 `let in` | +4（从 `if`/`case` 算），内层语句再 +2 |
| unbound 分支隐式块 body | +4（从 `if`/`case` 算），同分支多行体 |
| `if` 省略 `else` | 同 `if` / `case` 分支模式与分支体 |
| `\|>` 链续行 | `\|>` 比管线起始端多缩进 2 空格 |
| `pipe` 命令列表项 | +2 |
| `cmd` 字面量多行参数（`{}`/`[]`） | +2 |
| 多行 Record / Map 参数（`#{}`/`{}`） | +2 |
| `defer` | 与所在块内语句同级 |

## 行宽

每行不超过 100 个字符。超出应换行。

### 效应函数

返回 `Unit` 的效应函数体用 `do`（可紧跟 `->`），无论单语句还是多语句：

```kun
deploy : Config -> Unit ! {Cmd, IO}
deploy = \cfg -> do
  IO.println "deploying..."
  cmd rsync { archive = true } [ cfg.source, cfg.target ] |> Cmd.exec

countFiles : Path -> Int ! {Cmd}
countFiles = \dir ->
  let
    entries =
      cmd ls { all = true } [ dir ]
        |> Cmd.streamLines
        |> Stream.toList
  in
    List.length entries
```

返回 `Unit` 的效应函数优先用 `do <body>`（≈ `let <body> in ()`）—— 比 `let <body> in ()` 更简洁，且 `do` 紧跟 `->` 可减少一层缩进：

```kun
notify : String -> Unit ! {IO}
notify = \msg -> do
  IO.println msg
```

### 纯函数

纯函数体为单表达式（单语句直接书写；多语句用 `let in`）。多绑定返回非 `Unit` 须用 `let in` 包裹，`in` 与 `let` 对齐：

```kun
add : Int -> Int -> Int
add = \x y ->
  x + y                             // 单语句，直接书写

sumAndFloor : List Int -> Int
sumAndFloor = \items ->
  let
    total = List.sum items
  in
    toInt (toFloat total / 3.0)     // 多语句，须用 let in
```

多参数 Lambda 换行时，函数体缩进 2。体为 `let in` 时，该关键字与 Lambda 体同级缩进。

Lambda 参数支持解构：

```kun
addPair = \(x, y) -> x + y
sumCoordinates = \{x, y} -> x + y
firstThree = \[a, b, c] -> a + b + c
```

## 类型标注与值绑定：同行或分离

类型标注与值定义可写在一行（`name : Type = expr`）或分两行（`name : Type` 后接 `name = expr`），二者语义等价。`kun fmt` 按以下规则选择形式：

**优先同行**（短类型 + 单表达式 + 行宽未超）：

```kun
x : Int = 5
name : String = "alice"
identity : a -> a = \x -> x
add : Int -> Int -> Int = \x y -> x + y
isEmpty : List a -> Bool = \xs -> List.length xs == 0
```

**优先分两行**（任一条件成立）：

- 类型签名超过 60 字符
- 函数体使用 `do` 或 `let in` 包裹（多语句函数体）
- 函数体多行（如 `case` 表达式）

```kun
// 类型签名长 → 分两行
fetchUser : UserId -> Result User ! {DB, Log}
fetchUser = \uid -> ...

// 返回 Unit 的多语句函数体用 do → 分两行
deploy : Config -> Unit ! {Cmd, IO}
deploy = \cfg -> do
  IO.println "deploying..."
  cmd rsync { archive = true } [ cfg.source, cfg.target ] |> Cmd.exec

// 返回非 Unit 的多语句函数体用 let in → 分两行
currentTime : String ! {DateTime}
currentTime = \ ->
  let
    now = DateTime.now!
  in
    case DateTime.format "HH:mm:ss" now of
      Ok s  -> s
      Err _ -> "??:??:??"
```

**`let in` / `do` 块内的同行标注**：`let in` 或 `do` 块内的绑定同样支持同行标注，便于短绑定的类型说明：

```kun
let
  x : Int = 5
  y : String = "hello"
  z : ?Path = Nil
in
  ...
```

`kun fmt` 默认对 `let in` / `do` 块内短绑定使用同行形式（标注可选，无标注时直接 `name = expr`）。

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

#### Unbound（结果未被消费——`do`/`let in` 上下文中）

当 `case` 结果未被值绑定、也不作为函数返回值，且处于 `do`/`let in` 效应上下文时，各分支为隐式单表达式。分支内可直接书写多语句，不需显式 `do`/`let in` 包裹，结果均为 `Unit`：

```kun
do
  case File.read path of
    Ok text ->
      IO.println "processing..."
      process text
    Err e ->
      IO.println (toString e)
```

`defer` 在 unbound 分支中属于该分支自身的隐式单表达式，退出分支时立即执行：

```kun
do
  case command of
    Deploy config ->
      defer cleanupDeploy ()
      cmd ffmpeg {} [ "input.mp4", tmp ] |> Cmd.exec
    Rollback version ->
      defer cleanupRollback ()
      cmd restore {} [ version ] |> Cmd.exec
```

#### Bound（结果被值绑定或作为函数返回值）

多语句返回 `Unit` 用 `do`；多语句返回非 `Unit` 用 `let in`；单语句直接书写。各分支结果类型必须相同（可为 `Unit`）：

```kun
// 效应上下文 bound — 各分支返回同类型（此处 String）
result =
  case File.read path of
    Ok text ->
      text                            // 单语句，直接书写
    Err e ->
      let
        IO.println (toString e)       // 多语句返回非 Unit，用 let in
      in
        fallbackText

// 效应上下文 unbound — 多语句返回 Unit 用 do
case File.read path of
  Ok text -> do
    IO.println "read ok"
    IO.println text
  Err e -> do
    IO.println "read failed"
    IO.println (toString e)

// 纯上下文 bound — 多语句返回非 Unit 用 let in
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

> `case ... of` 内嵌 `let in` 的 `let` 缩进为 +4（从外层 `case` 算），其内部 body 语句再缩进 +2。`-> do` body 同样 +4（从 `case` 算）。

模式守卫使用 `if`：

```kun
case n of
  0 -> "zero"
  m if m > 0 -> "positive"
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

含有 `if` 守卫时，`if` 放在最后一个子模式之后：

```kun
case color of
  Red | Blue if darkMode -> "dark accent"
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

**Unbound（`do`/`let in` 上下文中，结果未被消费）** — 分支为隐式单表达式，直接书写多语句：

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

**Bound（结果被消费）** — 多语句返回 `Unit` 用 `do`；多语句返回非 `Unit` 用 `let in`；单语句直接书写：

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

省略 `else` 时隐式类型为 `Unit`。在 bound 位置省略 `else`，要求 `then` 分支也返回 `Unit`：

```kun
// unbound 位置：无条件执行效应，省略 else
do
  if needsCleanup then
    defer (File.remove tmp)
    cmd cleanup {} [] |> Cmd.exec
  // 无 else — if 结果被丢弃，隐式 Unit

// bound 位置：then 分支须返回 Unit
result =
  if needsAbort then
    do
      IO.println "aborting"
  // else 省略 → 隐式 Unit，与 then 的单表达式 (Unit) 一致
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

**空 body 约束**：`let in <expr>`（body 无任何绑定）为编译错误。单语句直接书写——无需 `let in` 包裹：

```kun
// ❌ 编译错误
result = let in x + 1

// ✅ 单语句直接书写
result = x + y
```

### `let in` / `do` 单表达式

`let` 在新行开始，body 内语句缩进 +2。返回 `Unit` 时优先用 `do <body>`（≈ `let <body> in ()`）。

`let in` 在副作用执行后返回值——`in` 在独立行，与 `let` 对齐，`in` 后表达式的结果即为整个 `let in` 的值：

```kun
// do — 返回 Unit
cleanup : Path -> Unit ! {File}
cleanup = \p -> do
  removeTemp p
  log "done"

// let in — 返回值
readConfig : Path -> Result Config Error ! {File}
readConfig = \path ->
  let
    content = File.read path
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

**空 body 约束**：`let in <expr>`（body 无任何绑定）、`do`（无 body）、`let`（无 body）均为编译错误。

**嵌套 `let in`**：`let in` 可自由嵌套，效应集为体内所有效应语句的并集：

```kun
let
  result =
    case items of
      Ok item ->
        let
          IO.println "found"
        in
          process item
      Err _ -> default
in
  result
```

### `do ... with` / `let ... in ... with` 表达式

`do`/`let` 块末尾追加 `with` 后缀绑定 handler，`with` 与 `do`/`let` 对齐。`with` 后为 handler（或 handler 组合 `>>`）。`do <body> with <h>` 用于 Unit 返回，`let <body> in <expr> with <h>` 用于值返回。仅 `main`/`TestCase.body` 入口级可用：

```kun
main : List String -> Unit ! {IO}
main = \args -> do
  result = fetchUser (UserId "1")
  case result of
    Ok user -> IO.println user.name
    Err _ -> IO.println "not found"
with
  postgreHandler >> journaldLog
```

值返回形式（`let in ... with`）：

```kun
main : List String -> Unit ! {IO}
main = \args ->
  let
    result = fetchUser (UserId "1")
  in
    case result of
      Ok user -> IO.println user.name
      Err _ -> IO.println "not found"
  with
    postgreHandler >> journaldLog
```

### `effect` / `extern` / `handler` 声明

`effect`/`extern`/`handler` 声明的 body 是 Record 字段列表，格式化规则与 Record 一致——`{` 在 `=` 同行或下方缩进，字段每行一个，逗号前置，`}` 与起始关键字缩进对齐：

```kun
effect DB =
  { query   : Query -> Result Rows DbError
  , execute : Statement -> Result Unit DbError
  }

extern Libc from "libc" =
  { strlen : String -> Int
  , fopen  : String -> String -> ?(Opaque File)
  , fclose : Opaque File -> Int
  }

postgreHandler : Handler {DB} a ! {Cmd, IO}
postgreHandler =
  handler DB of
    query q ->
      let
        sql = Query.toSql q
        result = cmd "psql" {} [ sql ] |> Cmd.execSafe
      in
        case result of
          Ok stream -> parseRows (Stream.toList stream |> String.join "\n")
          Err e -> Err (IoError e)
    execute s ->
      let
        sql = Statement.toSql s
        cmd "psql" {} [ sql ] |> Cmd.exec
      in
        Ok ()
```

### `continue` / `abort`

`continue` 和 `abort` 是控制流原语（非函数），不可作为值传递。每个 handler 分支路径必须有且仅有一次 `continue` 或 `abort`，必须在分支顶层路径：

```kun
loggingDb : Handler {DB} a ! {IO}
loggingDb =
  handler DB of
    query q ->
      let
        IO.println "querying"
        result = continue (DB.query q)    // 委托默认/外层 handler
      in
        result
    execute s ->
      continue (DB.execute s)

// abort 示例：dry-run，不执行真实操作
dryRunDb : Handler {DB} a
dryRunDb =
  handler DB of
    query _ -> abort (Ok [])               // 不调用 continue，返回空结果
    execute _ -> abort (Ok ())
```

> `continue`/`abort` 不可嵌套在 lambda 中（必须在 handler 分支顶层路径）。

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

`|>` 链从 `cmd` 起始时，`|>` 缩进与 `cmd` 名对齐：

```kun
do
  entries =
    cmd ls { all = true } [ dir ]
      |> Cmd.streamLines
      |> Stream.take 100
      |> Stream.toList
```

### `pipe` OS 管道

`pipe` 独占一行，命令列表每项一行，逗号前置：

```kun
pipe
  [ cmd ps { a = true } []
  , cmd grep { pattern = "nginx" } []
  , cmd head { n = 10 } []
  ]
```

`pipe` 的结果可继续接入 `|>` 链：

```kun
pipe
  [ cmd ps {} []
  , cmd grep {} []
  ]
  |> Cmd.streamLines
  |> Stream.toList
```

> `pipe` 是纯函数（`List Command -> Command`），需显式调用 `Cmd.exec`/`Cmd.execSafe`/`Cmd.streamLines`/`Cmd.streamBytes` 触发执行。

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

### `pipe` 命令列表

命令列表中的每个 Command 独占一行，逗号前置：

```kun
pipe
  [ cmd cat {} [ p"/var/log/app.log" ]
  , cmd grep { pattern = "ERROR" } []
  , cmd head { n = 100 } []
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

## `cmd` 字面量调用

### 单行

参数少时全部同行，选项 Record 在前，位置参数在最后：

```kun
cmd ls { long = true } []
cmd git log { maxCount = 50 } [ "main" ]
cmd cat {} [ p"/etc/maybe_missing" ] |> Cmd.execSafe
```

### 多行

参数多时，`cmd` 名独占一行，各参数块换行缩进 2，块之间无空行：

```kun
cmd rsync
  { archive = true, compress = true }
  [ srcPath, dstPath ]
```

选项 Record 可为空 `{}`，位置参数可为空 `[]`。两者均可整体省略。

### `|>` 链接

`cmd` 后可通过 `|>` 链式追加修饰函数（如 `Cmd.withEnv`、`Cmd.withWorkDir`、`Cmd.withStdinStr`）或执行函数（`Cmd.exec`/`Cmd.execSafe`/`Cmd.streamLines`/`Cmd.streamBytes`）：

```kun
cmd "g++" { o = "a.out", "-Wall" = true, "-O2" = true } [ "main.cpp" ]
  |> Cmd.withWorkDir p"/build"
  |> Cmd.exec

cmd mysql { u = "root" } []
  |> Cmd.withStdinStr """
    CREATE DATABASE mydb;
    """
```

### 特殊字符命令名

含 `-`、`.`、`+` 或数字开头的命令使用字符串字面量：

```kun
cmd "ntfs-3g" { force = true } [ "/dev/sda1" ]
cmd "g++" { o = "a.out" } [ "main.cpp" ]
  |> Cmd.exec
cmd "a-b-c" { flag = true } []
```

## `do`/`let in` 块内多行绑定与管道

`do`/`let in` 块内的多行赋值，`=` 独占一行，右侧值体缩进 2：

```kun
do
  entries =
    cmd ls { all = true } [ dir ]
      |> Cmd.streamLines
      |> Stream.take 100
      |> Stream.toList
  IO.println f"found {List.length entries} items"
```

`do`/`let in` 块内语句之间**无空行**。

## Lambda 作为高阶函数参数

### 简单 Lambda（体为纯表达式）

同行：

```kun
stream |> Stream.filter (\l -> String.contains "ERROR" l)
```

### Lambda 体为 `do`/`let in` 块

函数名和 Lambda 各自换行，闭括号与参数紧随或换行：

```kun
do
  List.iter
    (\item -> do
      IO.println f"processing {item.name}"
      cmd process {} [ item.path ] |> Cmd.exec
    )
    items

  Signal.on
    SIGTERM
    (\sig -> do
      Process.exit 0
    )
```

## defer

`defer` 与所在块内语句同级缩进，延迟表达式使用 `()` 包裹。`defer` 的作用域为最近的 `do`/`let in` 块（含 unbound 分支中的隐式块）：

```kun
do
  tmp = p"/tmp/out.mp4"
  defer (File.remove tmp)
  defer (IO.println "cleanup complete")

  cmd ffmpeg {} [ "input.mp4", tmp ] |> Cmd.exec
```

多个 `defer` 按 LIFO 逆序执行。unbound 分支中的 `defer` 属于该分支自身的隐式块，退出分支时立即执行。`defer` 适合"尽力清理"逻辑，不适合"必须成功"的操作。

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

### Unbound 分支（`do`/`let in` 上下文中，结果未被消费）

分支为隐式单表达式，多语句直接书写，无需显式 `do`/`let in` 包裹。分支体缩进 +4（从 `if`/`case` 算），语句间无空行：

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
    cmd tool {} [ target ] |> Cmd.exec
  else
    IO.println "skipping"
    Process.exit 1
```

`defer` 在 unbound 分支中属于该分支自身的隐式块，退出分支时立即执行：

```kun
do
  if needsBackup then
    defer (File.remove tmpBackup)
    cmd tar {} [ sourcePath, tmpBackup ] |> Cmd.exec
  else
    IO.println "skipping backup"
```

若需要分支与外层 `do`/`let in` 共享 `defer` 生命周期，将 `defer` 语句写在外层 `do`/`let in` 中：

```kun
do
  defer globalCleanup ()
  if needsBackup then
    cmd tar {} [ sourcePath, tmpBackup ] |> Cmd.exec
  else
    IO.println "skipping backup"
  // globalCleanup 在此执行
```

### Bound 分支（结果被值绑定或作为函数返回值）

多语句返回 `Unit` 用 `do`；多语句返回非 `Unit` 用 `let in`；单语句直接书写。内嵌 `let`/`do` 缩进 +4（从外层 `if`/`case` 算），内部语句再 +2：

```kun
// 效应上下文 — 多语句返回 Unit 用 do，返回非 Unit 用 let in
result =
  case File.read path of
    Ok text ->
      text
    Err e ->
      let
        IO.println (toString e)
      in
        fallbackText

// 纯上下文 — 多语句返回非 Unit 用 let in
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

分支边界通过关键字定界——`case` 分支结束于下一个 `pattern ->`，`if` 分支结束于 `else if` / `else`。解析器不依赖缩进量识别分支边界，依赖换行与行首 token——`case...of` 嵌套通过配对跟踪，嵌套 `case` 的 `pattern ->` 不触发外层分支终止。

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
- `do`/`let in` 块内连续语句之间不空行
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

currentTime : String ! {DateTime}
currentTime = \ ->
  let
    now = DateTime.now!
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

main : List String -> Unit ! {Cmd, DateTime, IO}
main = \_ -> do
  entries =
    pipe
      [ cmd cat {} [ p"/var/log/app.log" ]
      , cmd grep { pattern = "ERROR" } []
      , cmd head { n = 100 } []
      ]
      |> Cmd.streamLines
      |> Stream.parseMap parseLine
      |> Stream.toList

  IO.println f"found {List.length entries} errors at {currentTime!}"
  List.iter
    (\entry -> do
      IO.println f"[{entry.timestamp}] {entry.message}"
    )
    entries
```

