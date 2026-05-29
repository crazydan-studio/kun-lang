# 综合语法示例：日志文件处理器

覆盖：注释、字面量、ADT、函数定义、Lambda、模式匹配、管道、IO、流、Record 操作、权限声明、模块导入、`?` 操作符

```kun
-- ============================================================
-- file-processor.ku  —  日志文件处理器
-- 涵盖：注释 / 字面量 / ADT / 类型标注 / 函数定义 / Lambda /
--       case 模式匹配 / if / 管道 / do / Record 操作 / 导入 /
--       权限声明 / 流 / 操作符 / ? 操作符
-- ============================================================

-- 脚本级权限声明
capability fs.read("/var/log"), fs.read("/etc")

-- 模块导入
import List as L
import Map (get, insert)
import Path

-- ============================================================
-- ADT 定义
-- ============================================================

-- 基础枚举 ADT
type LogLevel
  = Debug
  | Info
  | Warn
  | Error

-- Record 风格变体字段
type LogEntry
  = Entry
    { timestamp : DateTime
    , level     : LogLevel
    , message   : String
    , pid       : Pid
    }

-- 无名字段 ADT
type ProcessError
  = ParseFailed String
  | FileNotFound Path
  | PermissionDenied Path
  | UnknownFormat

-- Newtype
type Config = Config
  { logDir    : Path
  , minLevel  : LogLevel
  , output    : Path
  }

-- 泛型 ADT
type Tree<T>
  = Leaf T
  | Node (Tree<T>, Tree<T>)

-- ============================================================
-- 类型标注 + 函数定义
-- ============================================================

-- 类型标注与定义分离
parseLevel : String -> Result<LogLevel, String>
parseLevel = \s ->
  case s of
    "DEBUG" -> Ok(Debug)
    "INFO"  -> Ok(Info)
    "WARN"  -> Ok(Warn)
    "ERROR" -> Ok(Error)
    _       -> Err("unknown level: " ++ s)

-- 纯函数：解析单行日志
parseLine : String -> Result<LogEntry, ProcessError>
parseLine = \line ->
  let parts = split("|", line)
  if length(parts) < 4 then
    Err(UnknownFormat)
  else
    let timestamp = parseTime(parts[0])
    let level     = parts[1]
    let message   = parts[2]
    let pidStr    = parts[3]
    case parseLevel(level) of
      Ok(lvl) ->
        Ok(Entry
          { timestamp = timestamp
          , level     = lvl
          , message   = message
          , pid       = pid(pidStr)
          })
      Err(e) -> Err(ParseFailed(e))

-- 高阶函数：按级别过滤
filterByLevel : LogLevel -> List<LogEntry> -> List<LogEntry>
filterByLevel = \minLevel, entries ->
  let shouldInclude = \entry ->
    case (minLevel, entry.level) of
      (Debug, _)     -> true
      (Info, Info)   -> true
      (Info, Warn)   -> true
      (Info, Error)  -> true
      (Warn, Warn)   -> true
      (Warn, Error)  -> true
      (Error, Error) -> true
      _              -> false
  entries |> L.filter(shouldInclude)

-- ============================================================
-- 管道 + Lambda 多参数
-- ============================================================

-- 统计各级别数量
countByLevel : List<LogEntry> -> Map<LogLevel, Int>
countByLevel = \entries ->
  entries
    |> L.fold(\acc, entry ->
      let level = entry.level
      let n = get(level, acc) |> maybe(0, identity)
      insert(level, n + 1, acc)
    , #{})
    |> identity

-- ============================================================
-- Record 创建 / 访问 / 更新
-- ============================================================

createDefaultConfig : Path -> Config
createDefaultConfig = \logDir ->
  let cfg =
    { logDir   = logDir
    , minLevel = Info
    , output   = logDir.join("report.txt")
    }
  -- Record 更新语法（不可变复制 + 修改）
  { cfg | minLevel = Warn }

-- ============================================================
-- IO 函数 + do 记法 + ? 操作符
-- ============================================================

-- 读取并解析配置文件
readConfig : Path -> IO<Result<Config, ProcessError>>
readConfig = \path ->
  do
    -- <- 从 IO 中解包
    content <- readFile(path)
    -- 纯函数解析
    let lines  = split("\n", content)
    let logDir = path"/var/log/myapp"
    -- ? 解包 Result，Err 自动传播
    let minLvl = parseLevel(L.head(lines) |> maybe("INFO", identity))?
    Ok(createDefaultConfig(logDir))

-- ============================================================
-- 流处理
-- ============================================================

-- 惰性读取大文件并逐行过滤
processLargeFile : Path -> IO<Unit>
processLargeFile = \path ->
  do
    stream readFile(path)
      |> L.filter(\line -> contains("ERROR", line))
      |> L.map(parseLine)
      |> L.filterMap(identity)
      |> L.iter(\entry -> print(entry.message))

-- ============================================================
-- 主入口：组合所有操作
-- ============================================================

main : IO<Unit>
main =
  do
    -- 字面量展示
    let appName  = "log-processor"     -- String
    let version  = 2024                -- Int
    let debug    = false               -- Bool
    let rate     = 3.14                -- Float
    let newline  = '\n'                -- Char
    let timeout  = 30s                 -- Duration
    let empty    = ()                  -- Unit

    -- Path 字面量
    let logPath    = path"/var/log/myapp/access.log"
    let configPath = path"./config.toml"
    let backupDir  = path"/tmp/backup"

    -- 容器字面量
    let levels   = [Debug, Info, Warn, Error]   -- List
    let counts   = #{ "ok" => 42, "err" => 7 }  -- Map
    let uniqPids = #[ 100u, 200u, 300u ]        -- Set
    let pair     = ("result", true)              -- Tuple

    -- Bytes 字面量
    let magicBytes = 0xCAFEBABE

    -- 正则字面量
    let ipRegex = regex`[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+`

    -- f-string 插值与格式化
    let greeting   = f"app {appName} v{version}"               -- 变量插值
    let formatted  = f"rate: {rate:.2f} / timeout: {timeout}"  -- Float 精度
    let hexVal     = f"hex: {255:x} / {255:X}"                 -- 整数进制
    let showCount  = f"count: {result}"                         -- Int 默认十进制

    -- 索引访问
    let first     = levels[0]     -- List 索引 → Maybe<LogLevel>
    let firstChar = "hello"[0]    -- String 索引 → Char
    let firstElem = pair.0        -- Tuple 索引

    -- 点调用语法
    let logDir    = logPath.parent()
    let fileName  = logPath.filename()

    -- 管道操作符
    let result =
      [3, 1, 4, 1, 5, 9, 2, 6]
        |> L.map(\n -> n * 2)
        |> L.filter(\n -> n > 5)
        |> L.fold(\acc, n -> acc + n, 0)

    -- 运算符展示
    let sum     = 10 + 20
    let diff    = 100 - 30
    let prod    = 6 * 7
    let quot    = 42 / 2
    let rem     = 10 % 3
    let concat  = "hello" ++ " world"
    let eq      = sum == prod
    let neq     = sum != diff
    let lt      = 1 < 2
    let gt      = 3 > 1
    let and_    = true && false
    let or_     = true || false
    let neg     = not eq
    let negNum  = -42

    -- 读取文件
    content <- readFile(logPath)
    let lines = split("\n", content)

    -- 解析并过滤
    let parsed = lines |> L.filterMap(parseLine)
    let errors = parsed |> L.filter(\e -> e.level == Error)

    -- 生成报告
    let report =
      L.map(\e ->
        f"{e.timestamp:%Y-%m-%d %H:%M:%S} [{e.level}] {e.message}"
      , errors)
        |> join("\n")

    -- 写入结果
    writeFile(backupDir.join("errors.log"), report)

    -- 权限作用域
    with capability fs.read("/etc") {
      let sysconfig = readFile(path"/etc/myapp/config.toml")
      print(sysconfig)
    }

    -- 单命令权限注解
    cleanTemp() with capabilities fs.write("/tmp")

    print(f"done: processed {L.length(lines)} lines")
```
