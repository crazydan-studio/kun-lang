# Kubernetes 金丝雀部署

## 场景说明

将构建产物部署到 Kubernetes 集群，依次经过：

1. **Staging 验证**：apply 部署清单 + 设置容器镜像
2. **Canary 灰度**：10% → 100% 流量逐步切换到新版本
3. **Full Rollout**：等待所有 Pod 滚动更新完成
4. **健康检查**：HTTP 端点持续探测，失败自动回滚
5. **通知**：Slack Webhook + 控制台双重通知

## 文件结构

```
k8s-deploy/
├── README.md         # 本文件
├── deploy.kun        # 入口：CLI 解析 → 状态机编排（4 Phase + rollback）
└── lib/              # 项目库根
    ├── Deployer.kun  # kubectl 操作封装
    ├── Verifier.kun  # HTTP 健康检查（带递归重试）
    ├── Canary.kun    # 灰度流量逐步调整
    └── Notifier.kun  # Slack/Webhook 通知
```

## 覆盖的 Kun 特性

### 类型系统

| 特性 | 位置 | 示例 |
|------|------|------|
| ADT 状态机 | `Deployer.kun` | `DeployPhase = Staging \| Canary ... \| Rollback ... \| Done \| Failed` |
| ADT 健康状态 | `Verifier.kun` | `HealthStatus = Healthy \| Degraded \| Unreachable \| Timeout` |
| 穷举匹配 | `deploy.kun` | `case healthStatus of V.Healthy ... → V.Degraded ... → V.Unreachable ... → V.Timeout` |
| Record 配置 | `deploy.kun` | `Config = { namespace, deployment, image, replicas, ... }` |
| 通配模式 `_` | `Verifier.kun` | `case result of Ok _ -> ... \| Err _ -> ...` |

### 效应系统

| 特性 | 位置 | 示例 |
|------|------|------|
| `do` 块多层嵌套 | `deploy.kun` | 3 层 `case ... of Ok _ → do ...` 嵌套编排 |
| 效应回调标注 | `Canary.kun` | `List.iter` 接受效应回调 `(\step -> do ...)` |
| 纯函数分离 | `Notifier.kun` | `formatMessage` 纯 → `notifySlack`/`notifyConsole` 效应 |

### 并发与状态机

| 特性 | 位置 | 说明 |
|------|------|------|
| ADT 状态机编排 | `deploy.kun` | 四个 Phase 通过函数调用链串联 |
| 递归重试 | `Verifier.kun` | `retryLoop`——函数式递归 + 指数退避 |
| 流序列生成 | `Canary.kun` | `List.range \|> List.filter \|> List.map` 灰度步骤 |

### 命令系统

| 特性 | 位置 | 示例 |
|------|------|------|
| `Cmd.kubectl?` | `Deployer.kun` | apply / set image / rollout status |
| `Cmd.curl` + `Cmd.stdoutToString` | `Verifier.kun` / `Notifier.kun` | HTTP 健康检查 + Webhook 通知 |
| 带 `--` 参数 | `Deployer.kun` | `--to-revision=` 特殊 flag |

### 标准库标识

| 特性 | 位置 |
|------|------|
| `Duration` 类型安全字面量 | `5s`、`10s`、`60s` |
| `String.repeat` 分隔线 | `deploy.kun` |
| `List.iter` 效应回调 | `Canary.kun` |
| `List.zip` / `List.map` | `build.kun`（跨场景） |
| `Stream.string` 消费输出 | `Deployer.kun` |
| f-string | 全模块 |

### 模块系统

| 特性 | 位置 | 示例 |
|------|------|------|
| `export (...)` | 各 `lib/*.kun` | 显式导出类型 + 函数 |
| `import X as Y` | `deploy.kun` | `import Deployer as D` |
| 跨模块协作 | `deploy.kun` | `D.applyManifest → C.gradualShift → V.checkEndpoint → N.notify` |

## 需求覆盖

| 需求 | 状态 |
|------|:--:|
| Staging 验证 | ✅ |
| Canary 灰度（逐步调整流量） | ✅ |
| Full rollout（等待 kubectl 完成） | ✅ |
| 健康检查（递归重试 + 超时） | ✅ |
| 失败自动回滚 | ✅ |
| Slack 通知 | ✅ |

## 缺失与不足

| 问题 | 说明 |
|------|------|
| 无内置 HTTP 客户端 | 健康检查和 Webhook 通过 `Cmd.curl` 完成 |
| `Cmd.timeout` 未实现（v1.0） | kubectl rollout 超时依赖 `--timeout` flag |
| `Signal.on` 未实现（v1.0） | 无法处理 SIGTERM/SIGINT |
| canary 流量实际机制 | 依赖 Service Mesh，`setTrafficWeight` 为简化示意 |
| JSON 构造手动拼接 | `Parser.JSON.toString`（v1.0）可用后将消除手动字符串拼接 |
