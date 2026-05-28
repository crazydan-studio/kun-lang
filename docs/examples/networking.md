# IO 与效应系统聚焦：网络服务监控

覆盖：`do` 记法（深度）、`?` 操作符、权限声明三级粒度、`Signal`/`Port`/`Pid`/`SocketAddr`、`Stream`、`DateTime`/`Duration`、错误链、`capability` 作用域

```kun
-- ============================================================
-- networking.ku  —  网络服务监控脚本
-- 涵盖：do 记法（深层嵌套）、? 操作符（错误传播）、
--       权限声明三级粒度、Signal/Port/Pid/SocketAddr、
--       Stream 惰性 IO、DateTime/Duration、IOError 处理
-- ============================================================

-- 脚本级权限声明（全局基线）
capability
  net.http("api.example.com")
  , fs.read("/var/log")
  , fs.write("/tmp/reports")
  , process.signal

import DateTime as DT
import Duration as Dur

-- ============================================================
-- ADT：监控结果
-- ============================================================

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

-- ============================================================
-- do 记法：多层嵌套
-- ============================================================

-- 基础 do：单一 IO 操作
printTimestamp : IO<Unit>
printTimestamp =
  do
    now <- DT.now()
    print("check at: " ++ now.format("%H:%M:%S"))

-- 多层 do：按顺序组合
checkService : SocketAddr -> IO<HealthStatus>
checkService = \addr ->
  do
    -- 第一层 IO
    start <- DT.now()
    result <- httpGet(addr, path"/health")

    -- case 分支内嵌套 IO
    case result of
      Ok(body) ->
        do
          end <- DT.now()
          let elapsed = end - start
          if contains("\"status\":\"ok\"", body) then
            pure(Up { responseTime = elapsed })
          else
            pure(Down { error = "unexpected response" })
      Err(err) ->
        do
          print("request failed: " ++ toString(err))
          pure(Down { error = toString(err) })

-- ============================================================
-- ? 操作符：Error 自动传播
-- ============================================================

-- 在返回 Result<T, E> 的函数中，? 解包 Ok 并传播 Err
type ConfigError
  = MissingField String
  | InvalidPort
  | ResolveFailed String

loadConfig : Path -> IO<Result<{ host : String, port : Port }, ConfigError>>
loadConfig = \path ->
  do
    content <- readFile(path)
    -- ? 解包 Result，若为 Err 则提前返回
    let host  = parseField("host", content)?
    let portStr = parseField("port", content)?
    let portInt = toInt(portStr)
    let port  = Port.fromInt(portInt)?

    Ok({ host = host, port = port })

-- ? 的链式使用
fetchAndReport : SocketAddr -> IO<Result<MonitorResult, String>>
fetchAndReport = \addr ->
  do
    start <- DT.now()
    body  <- httpGet(addr, path"/api/data")?
    end   <- DT.now()
    let parsed = parseJson(body)?
    let data   = extractField("value", parsed)?
    logResult(data)
    Ok(Result
      { service   = "api"
      , endpoint  = addr
      , status    = Up { responseTime = end - start }
      , checkedAt = start
      })

-- ============================================================
-- Signal / Pid 使用
-- ============================================================

-- 发送信号
reloadDaemon : Pid -> IO<Result<(), IOError>>
reloadDaemon = \pid ->
  do
    result <- kill(pid, SIGHUP)
    case result of
      Ok(_)       -> print("sent HUP to " ++ toString(pid))
      Err(err)    -> print("failed: " ++ toString(err))
    result

-- 等待子进程
watchProcess : Pid -> Duration -> IO<Result<ExitCode, IOError>>
watchProcess = \pid, timeout ->
  do
    result <- wait(pid, timeout)
    case result of
      Ok(code) ->
        do
          if code.isSuccess() then
            print("process exited ok")
          else
            print("process failed: " ++ toString(code))
          pure(Ok(code))
      Err(err) ->
        do
          print("wait failed: " ++ toString(err))
          pure(Err(err))

-- ============================================================
-- Stream：惰性处理网络数据
-- ============================================================

-- 流式读取 HTTP 响应
streamResponse : SocketAddr -> Stream<String>
streamResponse = \addr ->
  stream httpGetStream(addr, path"/events")
    |> filter(\line -> contains("data:", line))
    |> map(\line -> line.slice(5))

-- 消费流
processEvents : SocketAddr -> IO<Unit>
processEvents = \addr ->
  do
    streamResponse(addr)
      |> take(100)
      |> iter(\event -> processEvent(event))

-- ============================================================
-- 权限作用域（三级粒度）
-- ============================================================

-- 1. 脚本级（顶部声明）：全局可用
-- capability net.http(...), fs.read(...)

-- 2. 作用域级：临时扩缩权限
generateReport : Path -> IO<Unit>
generateReport = \outputPath ->
  do
    data <- collectData()

    -- 临时授予网络权限，块内有效
    with capability net.http("api.example.com") {
      enriched <- enrichWithApi(data)
      writeFile(outputPath, enriched)
    }
    -- 离开块后 net.http 权限自动收回

    print("report generated")

-- 3. 单命令级：精确约束
cleanArtifacts : Path -> IO<Unit>
cleanArtifacts = \dir ->
  do
    -- 仅此一条命令获得 fs.write 权限
    rm(dir) with capabilities fs.write("/tmp")
    print("cleaned")

-- ============================================================
-- DateTime / Duration 操作
-- ============================================================

timeWindow : Duration -> IO<Bool>
timeWindow = \window ->
  do
    now   <- DT.now()
    start <- DT.fromUnixSecs(1700000000)
    let elapsed = now - start
    pure(elapsed < window)

-- Duration 字面量 + 运算
scheduleCheck : IO<Unit>
scheduleCheck =
  do
    let interval = 30s
    let timeout  = 5s
    let delay    = 100ms
    let oneDay   = 1d
    let halfHour = 30m

    print("checking every " ++ toString(interval))
    print("timeout: " ++ toString(timeout))

-- ============================================================
-- 组合：完整监控检查
-- ============================================================

main : IO<Unit>
main =
  do
    -- 构造 SocketAddr
    let addr = Tcp(parse("10.0.1.5")?, port(8080))

    printTimestamp()
    status <- checkService(addr)

    case status of
      Up(info) ->
        print("service is up (" ++ toString(info.responseTime) ++ ")")
      Down(err) ->
        do
          print("service is down: " ++ err.error)
          -- 重启逻辑：发送 SIGTERM
          let pid = pid(1234)
          result <- kill(pid, SIGTERM)
          case result of
            Ok(_) -> print("sent SIGTERM")
            Err(e) -> print("kill failed: " ++ toString(e))
      Timeout ->
        print("request timed out")

    -- 流式处理事件
    processEvents(addr)

    -- 生成报告
    generateReport(path"/tmp/reports/health.json")
```
