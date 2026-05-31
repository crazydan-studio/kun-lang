# 综合语法示例：日志文件处理器

覆盖：注释、字面量、ADT、函数定义、Lambda、模式匹配、管道、IO、流、Record 操作、权限声明、模块导入、`=?` / `<-?` 操作符、f-string

```
// ============================================================
// file-processor.kun  —  日志文件处理器
// 涵盖：注释 / 字面量 / ADT / 类型标注 / 函数定义 / Lambda /
//       case 模式匹配 / if / 管道 / do / Record 操作 / 导入 /
//       权限声明 / 流 / 操作符 / =? / <-? 操作符
// ============================================================

// 脚本级权限声明
capability fs.read("/var/log"), fs.read("/etc")

// 模块导入（新语法）
import List as L
import Map with (get, insert)
import Path

// ============================================================
// ADT 定义
// ============================================================

// 基础枚举 ADT
type LogLevel
  = Debug
  | Info
  | Warn
  | Error

// Record 风格变体字段
type LogEntry
  = Entry
    { timestamp : DateTime
    , level     : LogLevel
    , message   : String
    , pid       : Pid
    }

// 无名字段 ADT
type ProcessError
  = ParseFailed String
  | FileNotFound Path
  | PermissionDenied Path
  | UnknownFormat

// Newtype
type Config = Config
  { logDir    : Path
  , minLevel  : LogLevel
  , output    : Path
  }

// 泛型 ADT（空格分隔泛型参数）
type Tree t
  = Leaf t
  | Node (Tree t, Tree t)

// ============================================================
// 类型标注 + 函数定义
// ============================================================

// 类型标注与定义分离
parseLevel : String -> Result LogLevel String
parseLevel = \s ->
  case s of
    "DEBUG" -> Ok Debug
    "INFO"  -> Ok Info
    "WARN"  -> Ok Warn
    "ERROR" -> Ok Error
    _       -> Err f"unknown level: {s}"

// 纯函数：解析单行日志
parseLine : String -> Result LogEntry ProcessError
parseLine = \line ->
  let
    parts = split "|" line
  in
  if length parts < 4 then
    Err UnknownFormat
  else
    let
      timestamp = parseTime parts[0]
      level     = parts[1]
      message   = parts[2]
      pidStr    = parts[3]
    in
    case parseLevel level of
      Ok lvl ->
        Ok (Entry
          { timestamp = timestamp
          , level     = lvl
          , message   = message
          , pid       = Pid.pid pidStr
          })
      Err e -> Err (ParseFailed e)

// 高阶函数：按级别过滤
filterByLevel : LogLevel -> List LogEntry -> List LogEntry
filterByLevel = \minLevel entries ->
  let
    shouldInclude = \entry ->
      case (minLevel, entry.level) of
        (Debug, _)     -> true
        (Info, Info)   -> true
        (Info, Warn)   -> true
        (Info, Error)  -> true
        (Warn, Warn)   -> true
        (Warn, Error)  -> true
        (Error, Error) -> true
        _              -> false
  in
  L.filter shouldInclude entries

// ============================================================
// 管道 + Lambda 多参数
// ============================================================

// 统计各级别数量
countByLevel : List LogEntry -> Map LogLevel Int
countByLevel = \entries ->
  entries
    |> L.fold (\acc entry ->
      let
        level = entry.level
        n = get level acc |> maybe 0 identity
      in
      insert level (n + 1) acc
    ) #{}
    |> identity

// ============================================================
// Record 创建 / 访问 / 更新
// ============================================================

createDefaultConfig : Path -> Config
createDefaultConfig = \logDir ->
  let
    cfg =
      { logDir   = logDir
      , minLevel = Info
      , output   = Path.join logDir "report.txt"
      }
  in
  { cfg | minLevel = Warn }

// ============================================================
// IO 函数 + do 记法 + ? 操作符
// ============================================================

// 读取并解析配置文件
readConfig : Path -> IO (Result Config ProcessError)
readConfig = \path ->
  do
    // <- 从 IO 中解包
    content <- readFile path
    // 纯函数解析
    lines  = split "\n" content
    logDir = p"/var/log/myapp"
    // =? 解包 Result，Err 自动传播
    minLvl =? parseLevel (L.head lines |> maybe "INFO" identity)
  in
    Ok (createDefaultConfig logDir)

// ============================================================
// 流处理
// ============================================================

// 惰性读取大文件并逐行过滤
processLargeFile : Path -> IO Unit
processLargeFile = \path ->
  do
    lines <-? Stream.readLines path
    lines
      |> filter (contains "ERROR")
      |> map parseLine
      |> filterMap toMaybe
      |> iter (\entry -> print entry.message)

// ============================================================
// 主入口：组合所有操作
// ============================================================

main : IO Unit
main =
  do
    // 字面量展示
    appName  = "log-processor"     // String
    version  = 2024                // Int
    debug    = false               // Bool
    rate     = 3.14                // Float
    newline  = '\n'                // Char
    timeout  = 30s                 // Duration
    empty    = ()                  // Unit

    // Path 字面量（前缀 p + 双引号）
    logPath    = p"/var/log/myapp/access.log"
    configPath = p"./config.toml"
    backupDir  = p"/tmp/backup"

    // 容器字面量
    levels   = [Debug, Info, Warn, Error]   // List
    counts   = #{ "ok" = 42, "err" = 7 }   // Map（= 替代 =>）
    uniqPids = #[ 100u, 200u, 300u ]        // Set
    pair     = ("result", true)              // Tuple

    // Bytes 字面量
    magicBytes = 0xCAFEBABE

    // 正则字面量（新语法：r"..."）
    ipRegex = r"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"

    // f-string 插值与格式化（新语法：f"..."）
    greeting   = f"app {appName} v{version}"               // 变量插值
    formatted  = f"rate: {rate:.2f} / timeout: {timeout}"  // Float 精度
    hexVal     = f"hex: {255:x} / {255:X}"                 // 整数进制
    showCount  = f"count: {result}"                         // Int 默认十进制

    // 索引访问
    first     = levels[0]     // List 索引 → Maybe LogLevel
    firstChar = "hello"[0]    // String 索引 → Char
    firstElem = pair.0        // Tuple 索引

    // 管道操作符
    result =
      [3, 1, 4, 1, 5, 9, 2, 6]
        |> L.map (\n -> n * 2)
        |> L.filter (\n -> n > 5)
        |> L.fold (\acc n -> acc + n) 0

    // 运算符展示
    sum     = 10 + 20
    diff    = 100 - 30
    prod    = 6 * 7
    quot    = 42 / 2
    rem     = 10 % 3
    concat  = "hello" ++ " world"
    eq      = sum == prod
    neq     = sum != diff
    lt      = 1 < 2
    gt      = 3 > 1
    and_    = true && false
    or_     = true || false
    neg     = not eq
    negNum  = -42

    // 读取文件
    content <- readFile logPath
    lines = split "\n" content

    // 解析并过滤
    parsed = lines |> L.filterMap parseLine
    errors = parsed |> L.filter (\e -> e.level == Error)

    // 生成报告（使用 f-string）
    report =
      L.map (\e ->
        f"{e.timestamp:%yyyy-MM-dd HH:mm:ss} [{e.level}] {e.message}"
      ) errors
        |> join "\n"

    // 写入结果
    writeFile (Path.join backupDir "errors.log") report

    // 权限作用域
    with capability fs.read("/etc") {
      sysconfig <- readFile p"/etc/myapp/config.toml"
      print sysconfig
    }

    // 单命令权限注解
    cleanTemp with capabilities fs.write("/tmp")

    print f"done: processed {L.length lines} lines"
```
