# 输入记录：Kun 语言架构重设计方案

## 来源

项目维护者 — 架构评审与深度讨论

## 日期

2026-06-08

## 状态

✅ 已完成。本文档的设计内容已全部落实至以下架构和设计文档中，本文档不再作为设计参考。

## 设计概要速览

经过对原方案从实现可行性、安全纵深防御、性能与资源、用户模型四个维度的深度评审，决定对 Kun 进行一次根本性简化：保留类型安全和表达式导向的核心优势，砍掉 Monadic IO 效应系统、`.cmd.kun` 编译器代码生成、能力声明等过度设计层。

### 核心变更

| 移除 | 替代方案 |
|------|---------|
| `IO T` 效应类型 | AST 标记：含 `do` 块的函数自动标记为效应函数 |
| `do`/`<-`/`<-!` Monadic 语法 | `do`/`do in` 退化为纯执行顺序保证，使用 `=` 绑定值 |
| `.cmd.kun` 模块体系 | `Cmd.<bin>` / `Cmd["..."]` 直接调用 + 自动模块发现 |
| `with caps` 能力声明 | CLI 参数：`--allow-path` / `--allow-net` |
| `Nat` 类型 | `Int` + 运行时范围检查 |
| `=!` / `<-!` 早返回 | `Cmd.<bin>?` / `Cmd.pipe?` 返回 Result |
| dlopen/ptrace 命令加载 | fork-exec 统一替代 |

### 新增

- `Cmd.pipe` / `Cmd.pipe?` — OS 管道链
- `Cmd.withEnv` / `Cmd.withStdin` / `Cmd.withRawOpt` / `Cmd.mergeStderr` — Command 修饰
- `defer` — 结构化资源清理
- `Signal.on` — signalfd 信号处理（仅可执行脚本）
- Landlock + mount namespace 兜底 + seccomp 降级矩阵
- `Parser.JSON` / `Parser.Record` — 编译期类型安全序列化

## 交付物对照

设计内容已全部落实到以下文档中：

| 文档 | 变更类型 |
|------|---------|
| `architecture/project-vision.md` | 重写 |
| `architecture/system-baseline.md` | 重写 |
| `architecture/module-boundaries.md` | 重写 |
| `architecture/index.md` | 更新原则 |
| `design/app-overview.md` | 重写 |
| `design/syntax.md` | 移除 `Nat`/`with caps`/`command`/`=!`/`<-!`/`IO`；简化 do 块 |
| `design/type-system.md` | 移除 `Nat`、`IO T`、幻影类型 |
| `design/standard-library.md` | 移除 `IO` 标记、`Validator`、`RunAs`；新增 `CommandError`、`Cmd.*` |
| `design/code-formatting.md` | 更新 Cmd 调用格式 |
| `design/feature-inventory.md` | 全面更新 |
| `design/roles-and-permissions.md` | 标记已废弃 |
| `design/supply-chain-security.md` | 标记已废弃 |
| `design/command-function-system.md` | 标记已废弃 |
| `design/capability-mapping-guide.md` | 标记已废弃 |
| `design/index.md` | 更新文件清单 |
| `examples/file-processor.md` | 重写 |
| `examples/networking.md` | 重写 |
| `examples/pattern-matching.md` | 更新示例 |
| `examples/type-showcase.md` | 更新示例（移除 `Nat`/`IO`） |
| `examples/index.md` | 更新描述 |
| `context/conventions.md` | 移除 `.cmd.kun` 引用 |

## 设计取舍记录

### 安全模型：声明式 → 命令式权限

原方案的 `with caps` 允许脚本作者在代码中声明最小权限。新方案将权限控制完全移至 CLI 参数（`--allow-path`、`--allow-net`），让操作者在运行时决定安全边界。

**取舍理由**：CLI 参数模式允许同一脚本在不同环境中以不同权限运行——开发时 `--no-sandbox`、CI 中 `--allow-path /build`、生产中仅 `--allow-path /data`。代价：安全控制从"作者不可绕过"变为"操作者可绕过"。

### 效应跟踪：IO 类型 → AST 标记

原方案的 `IO T` 类型包装器提供编译期可证明的纯/效应分离。新方案用 AST 标记替代。

**取舍理由**：消除了 HM 推断中的 IO 效应传播逻辑（~2000 行），用户无需理解 Monad。代价：纯函数的效应性不在类型签名中可见——需要查看源码或依赖 IDE 确定函数是否含副作用。
