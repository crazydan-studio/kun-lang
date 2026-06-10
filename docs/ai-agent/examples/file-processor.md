# 综合语法示例：日志文件处理器

覆盖：注释、字面量、ADT、函数定义、Lambda、模式匹配、管道、`do` 块、Stream、Record 操作、模块导入、`Cmd.pipe`、`Cmd.<bin>?`、f-string

```kun
// ============================================================
// file-processor.kun  —  日志文件处理器
// 涵盖：注释 / 字面量 / ADT / 类型标注 / 函数定义 / Lambda /
//       case 模式匹配 / if / 管道 / do / Record 操作 / 导入 /
//       Cmd.pipe / Stream / Cmd.<bin>?
// ============================================================

// 模块导入
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
type Config
  = Config
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
    parts = String.split "|" line
  in
    if List.length parts < 4 then
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

// identity 辅助函数
identity : a -> a
identity = \x -> x

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

// ============================================================
// Record 创建 / 访问 / 更新
// ============================================================

createDefaultConfig : Path -> Config
createDefaultConfig = \logDir ->
  let
    cfg = Config
      { logDir   = logDir
      , minLevel = Info
      , output   = Path.join logDir "report.txt"
      }
  in
    { cfg | minLevel = Warn }

// ============================================================
// do 块 + Cmd.pipe + Stream
// ============================================================

processLogFile : Path -> Unit
processLogFile = \logPath ->
  do
    entries =
      Cmd.pipe
        [ Cmd.cat logPath
        , Cmd.grep { pattern = "ERROR" }
        , Cmd.head { n = "100" }
        ]
        |> Stream.lines
        |> Stream.parseMap parseLine
        |> Stream.toList
    IO.println f"found {List.length entries} errors"
    List.iter
      (\entry ->
        do
          IO.println f"[{entry.timestamp}] {entry.message}"
      )
      entries

// 使用 Cmd.<bin>? 处理命令可能失败
safeReadConfig : Path -> Unit
safeReadConfig = \configPath ->
  do
    result = Cmd.cat? configPath
    case result of
      Ok stream ->
        lines =
          stream
            |> Stream.lines
            |> Stream.toList
        IO.println f"read {List.length lines} lines"
      Err err ->
        case err of
          CommandFailed { exitCode, stderr } ->
            IO.println f"cat failed ({exitCode}): {stderr}"
          NotFound cmd ->
            IO.println f"command not found: {cmd}"
          _ ->
            IO.println "unknown error"

// ============================================================
// 主入口：组合所有操作
// ============================================================

main : List String -> Unit
main = \_ ->
  do
    // 字面量展示
    appName  = "log-processor"     // String
    version  = 2024                // Int
    debug    = false               // Bool
    rate     = 3.14                // Float
    newline  = '\n'                // Char
    timeout  = 30s                 // Duration

    // Path 字面量（前缀 p + 双引号）
    logPath    = p"/var/log/myapp/access.log"
    configPath = p"./config.toml"
    backupDir  = p"/tmp/backup"

    // 容器字面量
    levels   = [Debug, Info, Warn, Error]     // List
    counts   = #{ "ok" = 42, "err" = 7 }       // Map（= 分隔键值对）
    uniqPids = #[100, 200, 300]               // Set
    pair     = ("result", true)                 // Tuple

    // Bytes 字面量
    magicBytes = 0xCAFEBABE

    // 正则字面量
    ipRegex = r"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"

    // f-string 插值与格式化
    greeting   = f"app {appName} v{version}"                 // 变量插值
    formatted  = f"rate: {rate:.2f} / timeout: {timeout}"    // Float 精度
    hexVal     = f"hex: {255:x} / {255:X}"                   // 整数进制

    // 索引访问
    first     = levels[0]         // List 索引 → ?LogLevel
    firstChar = "hello"[0]        // String 索引 → Char
    firstElem = pair.0            // Tuple 索引

    // 管道操作符
    result =
      [3, 1, 4, 1, 5, 9, 2, 6]
        |> L.map (\n -> n * 2)
        |> L.filter (\n -> n > 5)
        |> L.fold (\acc n -> acc + n) 0

    // 运算符展示
    sum     = 10 + 20
    concat  = "hello" ++ " world"
    eq      = sum == result
    and_    = true && false
    neg     = not eq

    // 处理日志
    processLogFile logPath

    // 安全读取配置
    safeReadConfig configPath

    IO.println f"done"
```
