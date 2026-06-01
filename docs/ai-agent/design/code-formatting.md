# 代码格式化规范

> 参考：Elm 格式化规范

## 缩进

使用 2 空格缩进，不使用 Tab。

## 行宽

每行不超过 100 个字符。超出应换行。

## 函数定义

`\` 与参数列表和 `=` 在同一行：

```kun
add : Int -> Int -> Int
add = \x y ->
  x + y
```

简短表达式函数可在一行内定义：

```kun
add = \x y -> x + y
increment = \x -> x + 1
```

Lambda 参数支持解构：

```kun
addPair = \(x, y) -> x + y
sumCoordinates = \{x, y} -> x + y
firstThree = \[a, b, c] -> a + b + c
```

多参数 Lambda 换行时，`->` 在参数行末尾，函数体缩进：

```kun
process = \x y ->
  let
    z = x + y
  in
    z * (x + y)
```

## 控制流

### `case`

`case` 必须在换行后开始，不能与 `=`、`->` 在同一行：

```kun
-- 正确
result =
  case value of
    Ok r -> r
    Err _ -> default

-- 错误
result = case value of   -- case 与 = 在同一行
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
    parts = split "|" line
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
-- 正确
result =
  let
    x = 1
    y = 2
  in
    x + y

-- 错误
result = let          -- let 与 = 在同一行
  x = 1
in x + y              -- in 与表达式在同一行
```

单条绑定时省略 `let`：

```kun
result =
  x + y
```

### `do` / `do in`

`do` 在新行开始，`in` 在独立行：

```kun
-- 无返回值
main =
  do
    step1
    step2

-- 有返回值
main =
  do
    step1
    step2
  in
    result
```

`do` 块内每一行操作独立：

```kun
readConfig : Path -> IO (Result Config Error)
readConfig = \path ->
  do
    content <- readFile path
    lines  = split "\n" content
    minLvl =? parseLevel "INFO"
  in
    Ok (createDefaultConfig logDir)
```

### `with caps`

`with caps` 块用于声明能力，独立成行，配置项缩进 2 空格：

```kun
with caps
  fs.read = [Path.cwd, p"/tmp"]
  fs.write = fs.read
```

脚本级 `with caps` 与函数体之间空 1 行：

```kun
with caps
  fs.read = [Path.cwd]

main = do
  ...
```

函数内 `with caps` 与 `do` 同一缩进层级：

```kun
readConfig =
  with caps
    fs.read = [p"/etc/config"]
  do
    readFile p"/etc/config"
```

`with caps` 块不允许为空。

## 管道

每个管道操作独立一行，`|>` 在行首：

```kun
-- 正确
result =
  list
    |> filter predicate
    |> map transform
    |> fold (+) 0

-- 错误
result = list |> filter predicate |> map transform |> fold (+) 0
```

## Record

### 创建/更新

单行：

```kun
point = { x = 1, y = 2 }
```

多行时每个字段独立一行，右括号缩进与左括号对齐：

```kun
config =
  { name = "app"
  , version = "0.1"
  , debug = false
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

单行：

```kun
list = [1, 2, 3]
```

多行时每个元素独立一行，右括号与左括号对齐：

```kun
list =
  [ 1
  , 2
  , 3
  ]
```

## ADT 定义

变体竖排，`=` 与第一个变体在同一行：

```kun
type Maybe t
  = Just t
  | Nothing

type Result t e
  = Ok t
  | Err e
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
  : SocketAddr
  -> Path
  -> IO (Result String IOError)
```

## 注释

`//` 后加一个空格再写注释内容：

```
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

- 顶层声明之间空 1 行
- 函数体内的逻辑段落之间可空 1 行
- 缩进级别不变时连续的空行不超过 1 行
- 文件末尾留 1 个空行

## 完整示例

```kun
type Color
  = Red
  | Green
  | Blue

parseLevel : String -> Result LogLevel String
parseLevel = \s ->
  case s of
    "DEBUG" -> Ok Debug
    "INFO"  -> Ok Info
    "WARN"  -> Ok Warn
    "ERROR" -> Ok Error
    _       -> Err f"unknown level: {s}"

processLargeFile : Path -> IO Unit
processLargeFile = \path ->
  do
    lines <-? Stream.readLines path
    lines
      |> filter (contains "ERROR")
      |> map parseLine
      |> filterMap toMaybe
      |> iter (\entry -> print entry.message)

readConfig : Path -> IO (Result Config Error)
readConfig = \path ->
  do
    content <- readFile path
    lines   = split "\n" content
    logDir  = p"/var/log/myapp"
    minLvl  =? parseLevel "INFO"
  in
    Ok (createDefaultConfig logDir)
```
