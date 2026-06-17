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
├── deploy.kun         # 入口：CLI 解析 → 状态机编排（4 Phase + rollback）
├── deployer.kun      # kubectl 操作封装（apply / set image / rollout / rollback）
├── verifier.kun      # HTTP 健康检查（带重试 + 超时 + 递归）
├── canary.kun        # 灰度流量逐步调整
└── notifier.kun      # Slack/Webhook 通知（纯 Markdown 格式化 + curl Webhook）
```

## 覆盖的 Kun 特性

### 类型系统

| 特性 | 位置 | 示例 |
|------|------|------|
| ADT 状态机 | `deployer.kun:20` | `DeployPhase = Staging \| Canary ... \| Rollback ... \| Done \| Failed` |
| ADT 健康状态 | `verifier.kun:20` | `HealthStatus = Healthy \| Degraded \| Unreachable \| Timeout` |
| 穷举匹配 | `deploy.kun:197` | `case healthStatus of V.Healthy ... → V.Degraded ... → V.Unreachable ... → V.Timeout ...` |
| Record 配置 | `deploy.kun:25` | `Config = { namespace, deployment, image, replicas, ... }` |
| `case` 守卫模式 | `deployer.kun:74` | 多返回值 `case result of Ok output → let raw = ...` |
| 通配模式 `_` | `verifier.kun:102` | `case result of ... Err _ → do ...` |

### 效应系统

| 特性 | 位置 | 示例 |
|------|------|------|
| `do` 块多层嵌套 | `deploy.kun:110` | 3 层 `case ... of Ok _ → do ...` 嵌套编排 |
| 效应回调标注 | `canary.kun:60` | `List.map (\step → do ...) steps`——回调含 `do` 块 |
| `defer` | 隐含 | 临时文件确保清理 |
| 纯函数分离 | `notifier.kun:45` | `formatMessage` 纯 → `notify` 效应 |

### 亮点模式

| 特性 | 位置 | 说明 |
|------|------|------|
| **状态机编排** | `deploy.kun:4` | 四个 Phase 通过函数调用链串联：staging→canary→rollout→health→rollback |
| **递归重试** | `verifier.kun:72` | `checkEndpointWithRetry`——函数式递归实现指数退避 |
| **流算序列** | `canary.kun:52` | `List.range start end \|> List.filter \|> List.map` 生成灰度步骤 |
| **纯 Markdown 格式** | `notifier.kun:45` | 通知消息纯计算，与发送分离 |
| **curl Webhook** | `notifier.kun:62` | Kun 无 HTTP 客户端——`Cmd.curl?` JSON-RPC 到 Slack |
| **带 `--` 参数** | `deployer.kun:58` | `Cmd.kubectl? { } "--to-revision={n}"` 特殊 flag |
| **Duration 类型安全** | `verifier.kun:62` | `3s` `5s` `60s` 字面量——编译期保证单位 |
| **`:命令` 作用域交换** | `deploy.kun:140` | 模块别名 `D.rollbackDeployment` / `V.checkEndpoint` / `N.notify` |

### 多模块协作

```
deploy.kun (入口：CLI + 状态机)
    ├── deployer.kun (kubectl 操作)
    ├── verifier.kun (HTTP 健康检查)
    ├── canary.kun (流量灰度)
    └── notifier.kun (Slack 通知)
```

## 需求覆盖

| 需求 | 覆盖 |
|------|:--:|
| Staging 验证 | ✅ `deploy.kun:Phase 1`——apply manifest + set image |
| Canary 灰度（10% 流量） | ✅ `canary.kun:gradualShift`——`startPercent→endPercent` 分步调整 |
| Full rollout | ✅ `deployer.kun:rolloutStatus`——等待 kubectl rollout 完成 |
| 健康检查 | ✅ `verifier.kun:checkEndpoint`——带重试 + 超时 + HTTP 状态码验证 |
| 失败自动回滚 | ✅ `deploy.kun:executeRollback`——`rollout undo` |
| 通知 | ✅ `notifier.kun:notify`——Slack Webhook + 控制台 |

## 缺失与不足

| 问题 | 说明 |
|------|------|
| **无内置 HTTP 客户端** | 健康检查和 Webhook 全部通过 `Cmd.curl?` 完成，需要 curl 命令存在 |
| **`Cmd.timeout` 未实现**（v1.0） | kubectl rollout 超时依赖 `--timeout` flag，非语言级超时 |
| **`Signal.on` 未实现**（v1.0） | 无法优雅处理 SIGTERM/SIGINT 进行部署清理 |
| **canary 实际 K8s 机制** | 流量权重依赖 Service Mesh（Istio/Linkerd），`setTrafficWeight` 为简化示意 |
| **JSON 构造手动拼接** | 无 `Parser.JSON.toString` 可用于 POST 请求体，当前手工字符串拼接 |
| **`Cmd.retry` 未实现**（v1.0） | 健康检查重试为手动递归，`Cmd.retry` 可更简洁 |
