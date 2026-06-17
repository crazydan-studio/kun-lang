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

> **注**：Kun 的解析器**不依赖缩进**来解析结构——所有代码块由显式关键字界定（`do`...、`let`...`in`、`case`...`of`）。缩进规则仅约束代码**格式**（可读性），不约束代码**语义**。`kun fmt` 工具据此规则自动格式化代码；`kun lint` 据此规则检查格式合规性。

各语境的缩进量（相对于父级上下文）：

| 上下文 | 缩进 |
|--------|------|
| 顶层定义 | 0 |
| `export` 导出列表 | +2 |
| `type` 变体 `=` / `\|` | +2 |
| ADT 变体中的 Record 字段 | +4（从 `\|` 算 +2） |
| 函数体 / Lambda 体 | +2 |
| `do` 块内语句 | +2（从 `do` 算） |
| `if` / `case` 分支模式 | +2（从 `if`/`case` 算） |
| `if` / `case` 分支体（多行） | +4（从 `if`/`case` 算） |
| `\|>` 链续行 | 与管线起始端对齐 |
| `Cmd.pipe` 命令列表项 | +2 |
| 多行 Cmd 参数（`#{}`/`{}`/位置参数） | +2 |
| `defer` | 与所在块内语句同级 |
| `in`（`do in` / `let in`） | 与 `do` / `let` 对齐 |

## 行宽

每行不超过 100 个字符。超出应换行。

## 函数定义

类型标注与值定义分离，各占一行。Lambda 参数同行，`->` 后换行：

```kun
// 有参函数
add : Int -> Int -> Int
add = \x y ->
  x + y

// 零参函数（仅效应函数）
pid : -> Pid
pid = \ ->
  do
    Process.pid
```

简短表达式可在一行内定义：

```kun
add = \x y -> x + y
increment = \x -> x + 1
pid = \ -> do Process.pid    // 零参效应函数，单表达式可同行
```

Lambda 参数支持解构：

```kun
addPair = \(x, y) -> x + y
sumCoordinates = \{x, y} -> x + y
firstThree = \[a, b, c] -> a + b + c
```

多参数 Lambda 换行时，函数体缩进。体为 `do` 块时 `do` 与 Lambda 体同级缩进：

```kun
process = \x y ->
  let
    z = x + y
  in
    z * (x + y)

deploy : Config -> Unit
deploy = \cfg ->
  do
    IO.println "deploying..."
    Cmd.rsync { archive = true } cfg.source cfg.target |> Cmd.exec
```

`do in` 形式用于执行副作用后返回纯值，`in` 与 `do` 对齐：

```kun
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

## 控制流

### `case`

`case` 必须在换行后开始，不能与 `=`、`->` 在同一行：

```kun
// 正确
result =
  case value of
    Ok r -> r
    Err _ -> default

// 错误
result = case value of   // case 与 = 在同一行
  ...
```

分支必须各自在独立行。简短分支可与 `->` 在同一行：

```kun
case result of
  Ok r -> r
  Err _ -> default
```

多行分支体换行缩进：

```kun
case result of
  Ok r ->
    let
      n = r * 2
    in
      n + 1
  Err _ ->
    default
```

模式守卫使用 `when`：

```kun
case n of
  0 -> "zero"
  m when m > 0 -> "positive"
  _ -> "negative"
```

### `if then else`

`if`、`else` 各自独立一行，分支体缩进 +2：

```kun
result =
  if length parts < 4 then
    Err UnknownFormat
  else
    Ok parsed
```

```kun
parseLine = \line ->
  let
    parts = String.split "|" line
  in
    if length parts < 4 then
      Err UnknownFormat
    else
      let
        timestamp = parseTime parts[0]
      in
        Ok timestamp
```

### `let in`

`let` 和 `in` 各自在新行，不能与 `=` 在同一行：

```kun
// 正确
result =
  let
    x = 1
    y = 2
  in
    x + y

// 错误
result = let          // let 与 = 在同一行
  x = 1
in x + y              // in 与表达式在同一行
```

单条绑定时省略 `let`：

```kun
result =
  x + y
```

### `do` / `do in`

`do` 在新行开始，`in` 在独立行，与 `do` 对齐：

```kun
// 无返回值
main = \_ ->
  do
    step1
    step2

// 有返回值
main = \_ ->
  do
    step1
    step2
  in
    result
```

`do` 块内使用 `=` 绑定值，语句间无空行：

```kun
readConfig : Path -> Result Config Error
readConfig = \path ->
  do
    case File.readString path of
      Ok content ->
        do
          lines  = String.split "\n" content
          logDir = p"/var/log/myapp"
        in
          Ok (createDefaultConfig logDir)
      Err e -> Err (ConfigReadError e)
```

`do` 块内的 `if` / `case` 分支自动继承效应上下文，可直接调用 `Cmd.*`，无需显式嵌套 `do`。嵌套 `do` 仅用于分支需要独立 `defer` 作用域时。

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

`defer` 与所在块内语句同级缩进，延迟表达式使用 `()` 包裹：

```kun
do
  tmp = p"/tmp/out.mp4"
  defer (File.remove tmp)
  defer (IO.println "cleanup complete")

  Cmd.ffmpeg {} "input.mp4" tmp |> Cmd.exec
```

多个 `defer` 按 LIFO 逆序执行。`defer` 适合"尽力清理"逻辑，不适合"必须成功"的操作。

## `do` 块内 if/case 分支效应上下文

外层 `do` 块的效应上下文自动传播到 `if`/`case` 的每个分支，可直接调用 `Cmd.*`：

```kun
do
  if condition then
    IO.println "doing work..."
    Cmd.tool {} target |> Cmd.exec
  else
    IO.println "skipping"
    Process.exit 1

  Cmd.cleanup {} |> Cmd.exec
```

嵌套 `do` 仅在分支需要独立 `defer` 作用域时使用：

```kun
do
  if needsBackup then
    do
      defer (File.remove tmpBackup)
      Cmd.tar {} sourcePath tmpBackup |> Cmd.exec
  else
    IO.println "skipping backup"
```

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
| 2026.06.13 | 代码块标签修正；零参效应 Lambda 示例补充 `do` 块 |
| 2026.06.10 | 代码格式化规范初始定义 |
