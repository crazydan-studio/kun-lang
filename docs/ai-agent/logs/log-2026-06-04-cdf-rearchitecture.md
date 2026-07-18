# 日志：CDF 重构——类型层、架构层、语法层全面修复

## 日期与会话信息

- **日期**：2026-06-04
- **会话类型**：设计（CDF 重构 + 命令函数系统全面调整）
- **提交者**：`AI <ai@kun-lang.crazydan.io>`

## 工作内容

### 1. CDF 类型层与架构问题修复

| 问题 | 修复 |
|------|------|
| `CmdResult` 无正式定义 | 新增 `CmdResult` 类型定义，后改为 `exitcode` 声明机制 |
| 错误类型不一致（`List IOError` vs `IOError`） | 统一为 `IOError` |
| `runAs` 字段冲突 | 编译期报错策略 |
| `process.exec` 语义矛盾 | 完全移除 `process.exec`，无逃生口 |

**修改文件**：`command-signature-system.md`、`roles-and-permissions.md`、`app-overview.md`、`system-baseline.md` 等 11 个文件。

### 2. CDF 形式化语法（EBNF）

新增 CDF 完整 EBNF 语法定义（v1），包含 6 条语义约束：
- `param` 编号递增、`param *` 位置、`!` 标记范围、`output` 引用检查、保留关键字、`bin` 路径范围

**修改文件**：`command-signature-system.md`

### 3. CDF 定义统一

在所有核心文档首次出现处标注 CDF（Command Description File）全称。

**修改文件**：`command-signature-system.md`、`roles-and-permissions.md`、`feature-inventory.md`、`module-boundaries.md`

### 4. CDF 可用性增强

| 改进 | 说明 |
|------|------|
| 内联验证器 | `with (range 1 65535)` 直接写表达式，无需事先声明 `validator` |
| `.` 分隔子命令调用 | `git.remote.add` 替代 `git_remote_add` |
| 分级可用性模型 | T1 内建 → T2 CDF → T3 auto-infer → T4 CDF-less |
| 自动 CDF 生成 | `kun cdf init <command>` |
| CDF 注册中心 | 社区分发 CDF 包的包管理器 |
| CDF-less 受限模式 | 显式 opt-in，`Stream String` 返回，审计日志强制 |

**修改文件**：`command-signature-system.md`、`feature-inventory.md`、`app-overview.md`、`discussion-cdf-code-generation.md`、`roles-and-permissions.md`

### 5. 重复选项与新隐式字段

| 改进 | 说明 |
|------|------|
| `option x "-x" : List T` | 重复选项，argv 展开 `-x v1 -x v2` |
| `env` 隐式字段 | `Map String String` 注入子进程环境变量 |
| `stdin`/`stdout`/`stderr` 隐式字段 | fd 重定向支持 Path/Pipe/Inherit |
| xargs 模式 | `Stream.toList` + `\|>` 管道自然覆盖 |
| `FdSpec` fd 重定向 | `fd : Map Int FdSpec` 支持 ReadFromPath/WriteToPath/ReadFromStr/InheritFrom/RedirectTo |
| 超长参数自动分片 | 超出 2MB 自动分裂执行 + 隐式合并 stdout |

**修改文件**：`command-signature-system.md`、`feature-inventory.md`

### 6. 从 CDF-first 转向 run-first

核心架构转变：

| 维度 | 之前 | 之后 |
|------|------|------|
| 入口 | 先写 CDF 再调用 | `run""` 一等语法，+ `process.run` 白名单控制 |
| 授权 | CDF 存在即授权 | `process.run` 白名单控制 |
| T4 CDF-less | 逃生口，显式 opt-in | `run` 为默认级别 |
| auto-infer | 备选 | 每次 `run` 调用自动触发 |

**修改文件**：`command-signature-system.md`、`roles-and-permissions.md`、`app-overview.md`、`feature-inventory.md`

### 7. 简化返回类型 + 退出码声明

| 维度 | 之前 | 之后 |
|------|------|------|
| 返回类型 | `IO (Result (CmdResult (Stream T)) IOError)` 4 层 | `IO (Result (Stream T) IOError)` 2 层 |
| 退出码 | 在 `CmdResult.exitCode` 中 | `exitcode N = Ok / Ok empty / Err` 声明，命令函数内消化 |
| grep 无匹配 | `Ok { stdout = empty, exitCode = 1 }` | `Ok Stream.empty` |

**修改文件**：`command-signature-system.md`、`feature-inventory.md`、`discussion-cdf-code-generation.md`

### 8. Maybe → `?T` Nilable 类型全面替换

| 维度 | 之前 | 之后 |
|------|------|------|
| 可选值 | `Maybe T`（ADT） | `?T`（语言内置） |
| 有值 | `Just x` | `x` |
| 无值 | `Nothing` | `Nil` |
| 变换 | 无标准函数 | `?.` 可选链 + `??` Nil 合并 |
| Record 缺省 | 不支持 | 未提供字段自动 `Nil` |
| Stream 过滤 | `filterMap toMaybe` | `filterMap Result.ok` |

**修改文件**：`type-system.md`、`syntax.md`、`standard-library.md`、`command-signature-system.md`、`app-overview.md`、`feature-inventory.md`、`system-baseline.md`、`examples/type-showcase.md`、`examples/pattern-matching.md`、`examples/file-processor.md`、`discussion-cdf-code-generation.md`、`discussion-command-function-design.md` 共 12 个文件。

## 已修改文件总览

| 文件 | 变更说明 |
|------|---------|
| `design/command-signature-system.md` | EBNF、CmdResult→exitcode、List T 选项、run-first、nilable 类型、.? 调用语法、分级模型、注册中心、隐式字段、超长参数分片、xargs 模式 |
| `design/type-system.md` | Nilable 类型 `?T` 规则、移除 Maybe |
| `design/syntax.md` | Nil 字面量、?. / ?? 操作符、移除 Maybe 模块 |
| `design/standard-library.md` | Maybe → ?、filterMap Result.ok |
| `design/roles-and-permissions.md` | process.exec 移除、process.run 新增、默认权限表更新 |
| `design/app-overview.md` | run-first 模型、?T 类型表 |
| `design/feature-inventory.md` | 全部新特性条目 |
| `architecture/system-baseline.md` | process.exec→CDF 子进程、Maybe→?T C ABI |
| `architecture/module-boundaries.md` | CDF 定义补充 |
| `examples/type-showcase.md` | Maybe→? 示例 |
| `examples/pattern-matching.md` | Nil 模式匹配示例 |
| `examples/file-processor.md` | filterMap Result.ok |
| `discussions/discussion-cdf-code-generation.md` | 子命令 `.` 命名、?T、exitcode |
| `discussions/discussion-command-function-design.md` | process.exec 移除、?T |

## 未解决的问题

- 无。所有设计决策已完成定稿。

## 下一步计划

- 开始实现阶段（类型检查器 / 解析器 / 运行时原型）
