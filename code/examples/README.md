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
- **Record 类型**：`BuildReport` 作为构建报告的强类型载体
- **Result 错误处理**：`Result a e` 贯穿全流程，替代异常/exit code
- **Optional（?T）**：`?String` 用于可选配置项
- **Newtype**：`Duration` 类型安全的时间运算
- **HM 类型推断**：大量纯函数无需标注类型

### 效应系统
- **`do` 块**：所有 IO/命令调用在 `do` 块中顺序执行
- **效应标注 `!`**：`List.iter : (a -> Unit)! -> List a -> Unit` 仅接受效应回调
- **纯/效应分离**：`generateReport` 纯计算 vs `writeReport` 效应操作
- **`defer`**：临时文件/资源的 LIFO 逆序清理

### 模式匹配
- **穷举匹配**：`case ... of` 确保所有 ADT 变体被处理
- **嵌套解构**：Record 字段解构 + ADT 变体同时匹配
- **守卫**：条件过滤模式分支

### 命令系统
- **`Cmd.<bin>`**：`Cmd.go`、`Cmd.npm`、`Cmd.docker`、`Cmd.kubectl`、`Cmd.curl`
- **`Cmd.<bin>?`**：安全执行返回 `Result`
- **`Cmd.pipe`**：OS 管道链（构建 → 日志过滤）
- **修饰器**：`Cmd.withEnv`、`Cmd.withWorkDir`、`Cmd.mergeStderr`、`Cmd.andThen`
- **`Cmd.which`**：PATH 查找命令

### 函数式编程
- **管道 `|>`**：从左到右的数据流
- **函数组合 `>>` / `<<`**：`parseResult >> formatSummary`
- **高阶函数**：`List.map`、`List.filter`、`List.fold`、`List.iter`、`List.zip`、`List.groupBy`
- **`let ... in`**：局部绑定与延迟求值
- **Lambda**：`\x -> ...` 匿名函数
- **柯里化**：多参数自动柯里化
- **`Nil` 组合子**：`withDefault`、`map`、`orElse`

### 标准库
- **`String`**：`split`、`join`、`trim`、`contains`、`startsWith`、`endsWith`、`toUpper`、`repeat`
- **`List`**：`map`、`filter`、`fold`、`iter`、`zip`、`sortBy`、`range`、`groupBy`
- **`Map`**：`insert`、`get`、`keys`、`values`、`merge`
- **`Regex`**：日志解析、kubectl 输出过滤
- **`DateTime`**：`now`、`format`、`-`（时间差）、`compare`、`before`
- **`Duration`**：`5s`、`30s` 字面量，`+` / `-` / `toSeconds` / `fromMillis`
- **`Path`**：`join`、`fileName`、`parent`、`fromString`
- **`File`**：`readString`、`writeString`、`list`、`createTempFile`、`exists`
- **`IO`**：`println`、`eprintln`、`print`
- **`Cli`**：类型驱动命令行参数解析
- **`Function`**：`identity`、`|>`、`>>`

### 模块系统
- **`export (...)`**：显式导出清单
- **`import X`**：显式导入
- **模块化组织**：入口脚本薄（CLI 参数 + 调度）→ 调用功能模块

## Kun 优势体现

| 维度 | Kun 方案 | 传统 Bash |
|------|---------|-----------|
| 错误处理 | `Result` 类型 → `case of` 穷举 | `set -e` + `$?` 检查，易遗漏 |
| 数据结构 | ADT/Record/List/Map 类型安全 | 字符串拼接、`jq`/`yq` 中转 |
| 组合性 | `|>`、`>>` 函数组合 | pipe `|`（仅 stdout 文本） |
| 时间运算 | `DateTime - Duration` 类型安全 | `date +%s` 字符串转整数 |
| 并行构建 | `List.iter` + fork→回调 | `&` + `wait`（无结构化聚合） |
| 回滚逻辑 | ADT 状态机→match 分支 | `if/elif/else` 嵌套 |
| 清理保证 | `defer` LIFO 确定性 | `trap ... EXIT`（信号依赖） |
| 空值安全 | `?T` + `Nil.withDefault` | `-z "$var"` / `${var:-default}` |
| 类型检查 | 编译期 HM 推断 | 无 |

## 缺失与不足

| 问题 | 影响 | 当前对策 |
|------|------|---------|
| 无内置 HTTP 客户端 | k8s API / Slack webhook 需 `Cmd.curl` | 用 `Cmd.curl?` + `Parser.JSON` 组合 |
| 无内置并发原语 | 并行构建依赖 `Task.spawn`（v0.5 才实现） | 当前用 `List.iter` 串行示意 |
| 无进程交互 | `kubectl exec` 的 tty 交互不可实现 | 设计已记录，v1.1 候选 |
| `Task` 模块 MVP 未实现 | 真正的并行 fork-exec 需 v0.5 | 示例中 `Task.spawn` 仅展示 API 签名 |
| `Random` 模块 MVP 未实现 | canary 分流不可用内置随机 | 当前硬编码流量比例 |
| 无重试机制 | 健康检查需手动 while 循环 | `Cmd.retry`（v1.0）将提供结构化重试 |
