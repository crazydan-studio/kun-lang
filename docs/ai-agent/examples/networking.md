# IO 与效应系统聚焦：网络服务监控

覆盖：`do` 块（深度）、`Cmd.pipe`/`Cmd.<bin>?`、`Signal`/`Port`/`Pid`/`SocketAddr`/`Stream`/`DateTime`/`Duration`、defer、错误链

```kun
// ============================================================
// networking.kun  —  网络服务监控脚本
// 涵盖：do 块（深层嵌套）、Cmd.pipe / Cmd.<bin>?、
//       Signal/Port/Pid/SocketAddr、
//       Stream、DateTime/Duration、defer
// ============================================================

import DateTime
import Duration
import ExitCode
import IpAddress with (IpAddress, Ipv4)
import Port
import Signal with (SIGTERM, SIGINT)
import Pid
import Time
import TempFile
import File
import Process

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
// do 块：多层嵌套
// ============================================================

// 基础 do：单一操作
printTimestamp : -> Unit
printTimestamp = \ ->
  do
    nowTime = Time.now
    IO.println f"check at: {nowTime:%HH:mm:ss}"

// 命令行检查：curl + 解析
checkService : SocketAddr -> Unit
checkService = \addr ->
  let
    ip = case addr of
      Tcp ip _ -> ip
      Udp ip _ -> ip
  in
  do
    start = Time.now
    result = Cmd.curl? { silent = true } (IpAddress.toString ip)
    case result of
      Ok _ ->
        end = Time.now
        IO.println f"up ({end - start})"
      Err err ->
        IO.println f"down: {err}"

// ============================================================
// Stream：惰性处理网络数据
// ============================================================

// 流式读取 HTTP 响应
processEvents : SocketAddr -> Unit
processEvents = \addr ->
  do
    result = Cmd.curl? { silent = true } addr
    case result of
      Ok events ->
        events
          |> Stream.lines
          |> Stream.filter (\line -> String.contains "data:" line)
          |> Stream.take 100
          |> Stream.iter (\event -> do IO.println event)
      Err e -> IO.println f"stream failed: {e}"

// ============================================================
// Signal / Pid 使用
// ============================================================

// 发送信号
reloadDaemon : Pid -> Unit
reloadDaemon = \pid ->
  do
    Cmd.kill { s = "HUP" } (Pid.toInt pid)
    IO.println f"sent HUP to {pid}"

// Signal.on — 仅可执行脚本可用
handleTerminate : -> Unit
handleTerminate = \ ->
  do
    Signal.on
      SIGTERM
      (\sig ->
        do
          IO.println "received SIGTERM, shutting down..."
          Process.exit 0
      )
    Signal.on
      SIGINT
      (\sig ->
        do
          IO.println "interrupted"
          Process.exit 0
      )

// ============================================================
// defer 资源清理
// ============================================================

backupAndClean : Path -> Unit
backupAndClean = \workDir ->
  do
    tmp = TempFile.create
    case tmp of
      Ok tmpPath ->
        defer (File.remove tmpPath)
        IO.println f"using temp: {tmpPath}"
        Cmd.tar { c = true, f = "backup.tar.gz" } workDir
      Err _ ->
        IO.println "failed to create temp file"

// ============================================================
// DateTime / Duration 操作
// ============================================================

timeWindow : Duration -> Bool
timeWindow = \window ->
  do
    current = Time.now
    start = DateTime.fromUnixSecs 1700000000
    elapsed = current - start
  in
    elapsed < window

// Duration 字面量 + 运算
scheduleCheck : -> Unit
scheduleCheck = \ ->
  do
    interval = 30s
    timeout  = 5s
    delay    = 100ms
    IO.println f"checking every {interval}"
    IO.println f"timeout: {timeout}"

// ============================================================
// 组合：完整监控检查
// ============================================================

main : List String -> Unit
main = \_ ->
  do
    // 注册信号处理
    handleTerminate
    // 构造 SocketAddr
    addr = Tcp (IpAddress.parse "10.0.1.5" |> Result.withDefault (Ipv4 (127, 0, 0, 1))) (Port.fromInt 8080)
    printTimestamp
    // 命令行检查
    checkService addr
    // 流式处理事件
    processEvents addr
    // 生成报告
    backupAndClean p"/tmp/reports"
```
