# Kun 语言示例

两个真实运维场景脚本，系统性地展示 Kun 语言特性。

## 场景

| 场景 | 目录 | 说明 |
|------|------|------|
| Monorepo CI/CD | `monorepo-ci/` | Go+JS monorepo 并行构建、测试、Docker 镜像打包、构建报告 |
| K8s 部署 | `k8s-deploy/` | staging→canary→full rollout→健康检查→回滚→通知 |

## 覆盖的 Kun 语言特性

### 类型系统
- **ADT（代数数据类型）**：`BuildResult`、`DeployPhase`、`HealthStatus`——结构化描述构建/部署状态
- **Record 类型**：`BuildConfig`、`DeployConfig`、`HealthCheck` 作为强类型配置载体
- **Result 错误处理**：`Result a e` 贯穿全流程，替代异常/exit code
- **Optional（?T）**：`?String`、`?Int`、`?Duration` 用于可选配置项
- **Newtype**：`Duration` 类型安全的时间运算（`5s`、`10s`、`60s` 字面量）
- **纯/效应分离**：`formatMessage`（纯）vs `writeReport`/`buildService`（效应）

### 效应系统
- **`do` 块**：所有 IO/命令调用在 `do` 块中顺序执行
- **`List.iter` 效应回调**：`List.iter (\x -> do ...) items`——仅迭代器接受 do 块回调
- **自动效应推断**：含 `Cmd.*` / `File.*` 调用的函数由编译器自动标记 `EffectFn`

### 模式匹配
- **穷举匹配**：`case ... of` 确保所有 ADT 变体被处理
- **嵌套解构**：Record 字段解构 + ADT 变体同时匹配

### 命令系统
- **`Cmd.<bin>` / `Cmd.<bin>?`**：`Cmd.go`、`Cmd.docker`、`Cmd.kubectl`、`Cmd.curl`
- **修饰器**：`Cmd.mergeStderr`、`Cmd.withWorkDir`、`Cmd.andThen`
- **`Cmd.stdoutToString`**：收集子进程 stdout 为 String

### 并发
- **`Task.spawn` / `Task.all`**：并行构建、并行测试、批量 Docker（v0.5 API）

### 函数式编程
- **管道 `|>`**：从左到右的数据流
- **Lambda**：`\x -> ...` 匿名函数
- **柯里化**：多参数自动柯里化
- **高阶函数**：`List.map`、`List.filter`、`List.fold`、`List.iter`、`List.zip`、`List.filterMap`

### 标准库
- **`String`**：`split`、`join`、`trim`、`repeat`、`startsWith`
- **`List`**：`map`、`filter`、`fold`、`iter`、`zip`、`range`、`length`
- **`DateTime` + `Duration`**：`now`、`format`、算术运算、`toSeconds`/`toMillis`
- **`Stream`**：`string`（消费流为 String）
- **`Hash` / `Bytes`**：`sha256Stream`、`sha256Hex`、`toHex`
- **`Path`**：`join`、`++`、`fromString`、`toString`
- **`File`**：`readBytes`、`writeString`、`stat`、`atomicWriteString`、`exists`
- **`IO`**：`println`、`eprintln`
- **`Cli`**：类型驱动命令行参数解析
- **`Validator`**：`nonEmpty`、`range`、`oneOf`

### 模块系统
- **`export (...)`**：显式导出类型及变体
- **`import X as Y`**：模块别名
- **薄入口 + `lib/` 库模块**：入口脚本仅 CLI 解析 + 调度，功能在 `lib/` 中

## Kun 优势体现

| 维度 | Kun 方案 | 传统 Bash |
|------|---------|-----------|
| 错误处理 | `Result` 类型 → `case of` 穷举 | `set -e` + `$?` 检查，易遗漏 |
| 数据结构 | ADT/Record/List 类型安全 | 字符串拼接、`jq`/`yq` 中转 |
| 组合性 | `\|>` 管道 | `\|`（仅 stdout 文本） |
| 时间运算 | `DateTime - Duration` 类型安全 | `date +%s` 字符串转整数 |
| 并行构建 | `Task.spawn` / `Task.all` 结构化并发 | `&` + `wait`（无结构化聚合） |
| 回滚逻辑 | ADT 状态机→match 分支 | `if/elif/else` 嵌套 |
| 空值安全 | `?T` 类型 | `-z "$var"` / `${var:-default}` |

## 缺失与不足

| 问题 | 影响 | 对策 |
|------|------|------|
| 无内置 HTTP 客户端 | k8s API / webhook 需 `Cmd.curl` | 用 `Cmd.curl` + `Cmd.stdoutToString` 组合 |
| `Task.spawn` 未实现（v0.5） | 并行构建需 v0.5 运行时 | 代码已使用目标 API 签名 |
| `Cmd.timeout` 未实现（v1.0） | kubectl 超时依赖 `--timeout` flag | `Cmd.timeout` 提供结构化超时 |
| `Signal.on` 未实现（v1.0） | 无法优雅处理信号 | 设计已记录，v1.0 计划 |
| `Parser.JSON.toString` 未实现（v1.0） | JSON payload 手动拼接 | v1.0 将提供 `Parser.JSON.toString` |
| `Random` 模块未实现（v0.5） | canary 分流无内置随机 | 当前硬编码流量比例 |
