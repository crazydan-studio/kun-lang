# IO 与效应系统聚焦：网络服务监控

覆盖：`do` 记法（深度）、`?` 操作符、权限声明三级粒度、`Signal`/`Port`/`Pid`/`SocketAddr`/`Stream`/`DateTime`/`Duration`、错误链、`capability` 作用域

```
// ============================================================
// networking.kun  —  网络服务监控脚本
// 涵盖：do 记法（深层嵌套）、? 操作符（错误传播）、
//       权限声明三级粒度、Signal/Port/Pid/SocketAddr、
//       Stream 惰性 IO、DateTime/Duration、IOError 处理
// ============================================================

// 脚本级权限声明（全局基线）
capability
  net.http("api.example.com")
  , fs.read("/var/log")
  , fs.write("/tmp/reports")
  , process.signal

import DateTime with (now, fromUnixSecs)
import Duration
import ExitCode

// ============================================================
// ADT：监控结果
// ============================================================

type HealthStatus
  = Up { responseTime : Duration }
  | Down { error : String }
  | Timeout

type MonitorResult
  = Result
    { service  : String
    , endpoint : SocketAddr
    , status   : HealthStatus
    , checkedAt : DateTime
    }

// ============================================================
// do 记法：多层嵌套
// ============================================================

// 基础 do：单一 IO 操作
printTimestamp : IO Unit
printTimestamp =
  do
    nowTime <- now
    print f"check at: {nowTime:%H:%M:%S}"

// 多层 do：按顺序组合
checkService : SocketAddr -> IO HealthStatus
checkService = \addr ->
  do
    // 第一层 IO
    start <- now
    result <- httpGet addr p"/health"

    // case 分支内嵌套 IO
    case result of
      Ok body ->
        do
          end <- now
          elapsed = end - start
          if contains "\"status\":\"ok\"" body then
            pure (Up { responseTime = elapsed })
          else
            pure (Down { error = "unexpected response" })
      Err err ->
        do
          print f"request failed: {err}"
          pure (Down { error = toString err })

// ============================================================
// ? 操作符：Error 自动传播
// ============================================================

// 在返回 Result t e 的函数中，? 解包 Ok 并传播 Err
type ConfigError
  = MissingField String
  | InvalidPort
  | ResolveFailed String

loadConfig : Path -> IO (Result { host : String, port : Port } ConfigError)
loadConfig = \path ->
  do
    content <- readFile path
    // ? 解包 Result，若为 Err 则提前返回
    host  = parseField? "host" content
    portStr = parseField? "port" content
    portInt = toInt portStr
    port  = Port.fromInt? portInt

    Ok { host = host, port = port }

// ? 的链式使用
fetchAndReport : SocketAddr -> IO (Result MonitorResult String)
fetchAndReport = \addr ->
  do
    start <- now
    body  <- httpGet? addr p"/api/data"
    end   <- now
    parsed = parseJson? body
    data   = extractField? "value" parsed
    logResult data
    Ok (Result
      { service   = "api"
      , endpoint  = addr
      , status    = Up { responseTime = end - start }
      , checkedAt = start
      })

// ============================================================
// Signal / Pid 使用
// ============================================================

// 发送信号
reloadDaemon : Pid -> IO (Result Unit IOError)
reloadDaemon = \pid ->
  do
    result <- kill pid SIGHUP
    case result of
      Ok _        -> print f"sent HUP to {pid}"
      Err err     -> print f"failed: {err}"
    result

// 等待子进程
watchProcess : Pid -> Duration -> IO (Result ExitCode IOError)
watchProcess = \pid timeout ->
  do
    result <- wait pid timeout
    case result of
      Ok code ->
        do
          if ExitCode.isSuccess code then
            print "process exited ok"
          else
            print f"process failed: {code}"
          pure (Ok code)
      Err err ->
        do
          print f"wait failed: {err}"
          pure (Err err)

// ============================================================
// Stream：惰性处理网络数据
// ============================================================

// 流式读取 HTTP 响应
streamResponse : SocketAddr -> IO (Result (Stream String) IOError)
streamResponse = \addr ->
  do
    response <- httpGetStream addr p"/events"
    Ok (response
      |> filter (\line -> contains "data:" line)
      |> map (\line -> String.slice 5 line))

// 消费流
processEvents : SocketAddr -> IO Unit
processEvents = \addr ->
  do
    result <- streamResponse addr
    case result of
      Ok events ->
        events
          |> take 100
          |> iter (\event -> processEvent event)
      Err e -> print f"stream failed: {e}"

// ============================================================
// 权限作用域（三级粒度）
// ============================================================

// 1. 脚本级（顶部声明）：全局可用

// 2. 作用域级：临时扩缩权限
generateReport : Path -> IO Unit
generateReport = \outputPath ->
  do
    data <- collectData

    // 临时授予网络权限，块内有效
    with capability net.http("api.example.com") {
      enriched <- enrichWithApi data
      writeFile outputPath enriched
    }
    // 离开块后 net.http 权限自动收回

    print "report generated"

// 3. 单命令级：精确约束
cleanArtifacts : Path -> IO Unit
cleanArtifacts = \dir ->
  do
    // 仅此一条命令获得 fs.write 权限
    rm dir with capabilities fs.write("/tmp")
    print "cleaned"

// ============================================================
// DateTime / Duration 操作
// ============================================================

timeWindow : Duration -> IO Bool
timeWindow = \window ->
  do
    current <- now
    start <- fromUnixSecs 1700000000
    elapsed = current - start
    pure (elapsed < window)

// Duration 字面量 + 运算
scheduleCheck : IO Unit
scheduleCheck =
  do
    interval = 30s
    timeout  = 5s
    delay    = 100ms
    oneDay   = 1d
    halfHour = 30m

    print f"checking every {interval}"
    print f"timeout: {timeout}"

// ============================================================
// 组合：完整监控检查
// ============================================================

main : IO Unit
main =
  do
    // 构造 SocketAddr
    addr = Tcp (parse? "10.0.1.5") (Port.fromInt 8080)

    printTimestamp
    status <- checkService addr

    case status of
      Up info ->
        print f"service is up ({info.responseTime})"
      Down err ->
        do
          print f"service is down: {err.error}"
          // 重启逻辑：发送 SIGTERM
          pid = Pid.pid 1234
          result <- kill pid SIGTERM
          case result of
            Ok _  -> print "sent SIGTERM"
            Err e -> print f"kill failed: {e}"
      Timeout ->
        print "request timed out"

    // 流式处理事件
    processEvents addr

    // 生成报告
    generateReport p"/tmp/reports/health.json"
```
