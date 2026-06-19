# 单一表达式范式全面定稿

> 日期：2026-06-19 | 类型：设计定稿 + 文档重写 + 示例迁移

## 工作内容

### 1. 单一表达式范式设计讨论

通过三轮问答澄清并最终确定单一表达式设计规则，核心决策：

- **`do` 固定返回 `Unit`**，`do in` 返回值（必须非 `Unit`，`in` 处于效应上下文）
- **空 body 编译错误**：`do`、`do in`、`let in` 空 body 均为编译错误
- **case/if 分支按 unbound/bound 区分**：
  - unbound（结果未消费，do 上下文中）：分支为隐式 `do`，直接多语句，结果 `Unit`
  - bound/returned（结果被绑定或返回）：多语句须 `do in`/`let in` 包裹；单表达式可省略
- **链式继承**：do 上下文跨嵌套 unbound 分支传播
- **`let in` 纯性约束**：禁止效应函数调用、定义，及效应命名空间函数引用（含值绑定）
- **`do`/`let` 互斥**：同一函数 scope 内不可互相嵌套
- **`defer` 作用域**：最接近的外层 `do`（含 unbound 分支中的隐式 `do`）
- **函数体约束**：效应函数必须 `do`/`do in` 包裹；纯函数体单一表达式可省略 `let in`
- **7 类告警**：无效应 do、未消费绑定、纯表达式最后语句等
- **7 类错误**：空 body、do in 返回 Unit、let in 含效应、互嵌套、变量重复绑定等

### 2. 设计/架构文档重写

| 文件 | 变更 |
|------|------|
| `design/syntax.md` | 新增「单一表达式范式」章节；`do` 固定 `Unit`、`do in` 返回值；let in、case/if 分支体、defer、Lambda、函数定义六章重写 |
| `design/type-system.md` | 效应检查规则扩展 — 错误/告警两级表；隐式 do 上下文；`in` 上下文更新 |
| `design/code-formatting.md` | 缩进表扩展；函数定义按效应/纯分离；case/if 按 unbound/bound 重写；defer unbound 分支格式 |
| `architecture/system-baseline.md` | 求值策略表更新；do 块章节更新；效应检查章节补全新规则 |
| `design/app-overview.md` | 语法设计概述更新 |
| `design/standard-library.md` | Test 模块 equal/ok/notEqual/approxEqual/isNil/panics 从 [PureKun] 改为效应函数 |
| `audits/audit-syntax-usability.md` | 审计发现 #9 状态更新 |

### 3. 跨文档一致性修复

第二轮搜索覆盖全部 `design/`、`architecture/`、`plans/`、`discussions/` 目录，修复：

- `syntax.md:658` — 对比表「继承外层」→「do 上下文链式继承」
- `syntax.md:671` — `do in` 返回「纯值」→「返回值」（`in` 处于效应上下文）
- `system-baseline.md:204` — `let...in` 交互措辞更新（旧「顺序/延迟不兼容」→ 新「do/let 互斥」）
- `system-baseline.md:293-307` — 效应检查章节补全 8 条新规则

### 4. 示例代码迁移

10 个示例文件的效应函数迁移至 `do in` 模式：

| 文件 | 修复项 |
|------|--------|
| `Deployer.kun` | applyManifest/setImage/rolloutStatus/rollbackDeployment 改为 do in |
| `Verifier.kun` | checkOnce/checkEndpoint/retryLoop 改为 do in + 分支多语句包裹 |
| `Notifier.kun` | notifySlack 改为 do in |
| `Canary.kun` | setTrafficWeight 改为 do in |
| `Dockerizer.kun` | inspectImage 的 `case result =` 语法错误修正 |
| `build.kun` | testResults 分支改为 do in |
| `Builder.kun` | buildService/computeChecksum 改为 do in |
| `Reporter.kun` | writeReport 改为 do in + 分支包裹 |
| `Tester.kun` | runTests/collectResults 改为 do in |

### 5. Git 提交

- `b2bb4f0` — 设计: 单一表达式范式全面定稿 — 语法/类型/格式化/架构文档（7 files）
- `96f081c` — 修复: 示例代码适配单一表达式范式（9 files）

## 涉及文件

### 新增
- `docs/ai-agent/logs/log-2026-06-19-single-expression-paradigm.md`

### 修改
- `docs/ai-agent/design/syntax.md`
- `docs/ai-agent/design/type-system.md`
- `docs/ai-agent/design/code-formatting.md`
- `docs/ai-agent/design/standard-library.md`
- `docs/ai-agent/design/app-overview.md`
- `docs/ai-agent/architecture/system-baseline.md`
- `docs/ai-agent/audits/audit-syntax-usability.md`
- `code/examples/k8s-deploy/lib/Canary.kun`
- `code/examples/k8s-deploy/lib/Deployer.kun`
- `code/examples/k8s-deploy/lib/Notifier.kun`
- `code/examples/k8s-deploy/lib/Verifier.kun`
- `code/examples/monorepo-ci/build.kun`
- `code/examples/monorepo-ci/lib/Builder.kun`
- `code/examples/monorepo-ci/lib/Dockerizer.kun`
- `code/examples/monorepo-ci/lib/Reporter.kun`
- `code/examples/monorepo-ci/lib/Tester.kun`
- `docs/ai-agent/logs/index.md`
- `docs/ai-agent/context/project-context.md`

## 下一步

- 类型检查器错误消息模板补充新错误类型
- 解析器适配 `do in` 语法（确保 `do` 关键字后解析 body，`in` 为独立 token）
- 编写单表达式范式使用示例文档
