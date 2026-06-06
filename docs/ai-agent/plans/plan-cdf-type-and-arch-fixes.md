# 执行计划：CDF 类型层与架构层问题修复

## 背景与目标

### 背景

在 CDF 系统的全面审查中，发现 19 项问题，分三块。本计划覆盖**块 2（类型层）**和**块 3（架构层）**，共 11 项问题。

**关键决策**：
- 不新增 `Exec` 模块（无逃生口）
- 命令函数不受 `process.exec` 能力控制，且无逃生口 ⇒ `process.exec` 能力无存在意义 ⇒ **完全移除 `process.exec`**
- 环境变量过滤作为通用子进程安全机制保留，不绑定 `process.exec`

### 目标

- `CmdResult` 正式定义 + 错误类型一致化（`List IOError` → `IOError`）
- `runAs` 字段名冲突处理策略明确
- `process.exec` 完全移除，相关文档彻底清理
- 全项目文档同步（`enum` vs `include/exclude`、`find` 覆盖状态等）

## 变更范围

**涉及模块**：命令签名系统、权限模型、应用概览、需求文档、输入记录

**需要修改的文件**（11 个）：

| 文件 | 操作 | 说明 |
|------|------|------|
| `design/command-signature-system.md` | 修改 | `CmdResult` 定义、错误类型一致、`runAs` 冲突策略、`find` 状态、版本头、CDF-Kun 边界、`output` 关键字语义 |
| `design/roles-and-permissions.md` | 修改 | 完全移除 `process.exec` 能力及所有相关规则、匹配方式、示例；环境变量过滤节解除与 `process.exec` 绑定 |
| `design/app-overview.md` | 修改 | `enum` → `include/exclude` 同步 |
| `discussions/discussion-command-function-design.md` | 修改 | 议题 5 结论改为"完全移除 `process.exec`" |
| `discussions/discussion-capability-design.md` | 修改 | 移除 `process.exec` 条目 |
| `discussions/discussion-design-review-round2.md` | 修改 | 移除 R4/R6 条目（R4 环境变量过滤转为通用机制；R6 Exec 模块不新增） |
| `discussions/index.md` | 修改 | 更新命令函数设计的描述 |
| `architecture/system-baseline.md` | 修改 | line 917 解除 FD_CLOEXEC 与 `process.exec` 的绑定 |
| `requirements/req-capability-design.md` | 修改 | 移除 `process.exec` 示例 |
| `input/input-capability-syntax-redesign.md` | 修改 | 移除 `process.exec` 引用 |
| `logs/log-2026-06-02-design-audit-fixes.md` | 修改 | 移除 `process.exec` 自动推断的记录 |

## 实施步骤

### Step 1：定义 `CmdResult` + 统一错误类型

**文件**：`command-signature-system.md`

在"代码生成规则"表之前新增：

```
### `CmdResult` — 命令执行结果

```kun
type CmdResult t = { stdout : t, exitCode : ExitCode }
```

- 非零退出码不映射为 `Err`——放入 `exitCode` 字段
- 进程启动失败映射为 `Err IOError`
- 输出解析失败在流中逐行标记，不导致整个命令失败

```

统一所有命令签名：`IO (Result (CmdResult (Stream T)) IOError)`，移除 `List IOError`。

在"参数映射关系"节后新增 `List <type>` 语义说明——直接映射 Kun 的 `List` 类型。

### Step 2：`runAs` 字段名冲突策略

**文件**：`command-signature-system.md`

在代码生成规则表后新增：

> `runAs` 为代码生成保留字段名。若 CDF 显式声明名为 `runAs` 的 `option`，编译期报错。用户应改用其他字段名。

### Step 3：完全移除 `process.exec`

**文件**：`roles-and-permissions.md`

3.1 从"进程（process）"能力表删除 `exec` 行，表格变为（仅保留 `run-as`、`signal`、`kill`、`trace`）。

3.2 删除完整节：`process.exec` 的声明规则（L212-L272），包括：
- 声明规则表
- `exec` 匹配方式表（basename / 绝对路径）
- `chmod`/`chown` 的 `process.exec` + `fs.write` 组合控制
- 命令函数能力匹配规则说明

3.3 环境变量过滤节（L274+）解除与 `process.exec` 的绑定，改写为通用子进程安全机制：

```diff
- 通过 `process.exec` 启动子进程前，运行时自动过滤环境变量
+ CDF 命令函数执行子进程前，运行时自动过滤环境变量
```

3.4 删除或更新所有含 `process.exec` 的示例代码（L58、L222-231 等）。

3.5 L38 的 `chdir` 操作说明改为："需通过 CDF 命令函数调用外部 `cd` 命令"。

3.6 L157 的 `[]` 空列表警告移除 `process.exec` 引用。

3.7 L384、L400 的沙箱说明移除 `process.exec` 引用。

### Step 4：`enum` → `include/exclude` 同步

**文件**：`app-overview.md`

L84：`enum` 改为 `include` / `exclude`。

### Step 5：明确 `find` 覆盖状态 + 版本头 + `output` 关键字 + CDF-Kun 边界

**文件**：`command-signature-system.md`

5.1 覆盖范围表新增 `find` 条目：不映射，由 `walkDir` + `filter` 替代。

5.2 版本头：在完整示例前新增说明，并在示例中添加 `// kun-cdf-v1`。

5.3 `output` 关键字：注明 `default`、`json` 为保留标识符，自定义 parser 不可命名为此。

5.4 CDF-Kun 边界表（在 CDF 语法介绍后新增）。

### Step 6：同步讨论/需求/索引文档

**文件**：多个

6.1 `discussion-command-function-design.md`：议题 5 结论改为"完全移除 `process.exec`"，更新 L57、L88。

6.2 `discussion-capability-design.md`：移除 `process.exec` 条目。

6.3 `discussion-design-review-round2.md`：移除 R4（环境变量过滤已改为通用机制）、移除 R6（Exec 模块不新增）。

6.4 `discussions/index.md`：更新描述"移除 process.exec 能力"。

6.5 `system-baseline.md`：L917 "通过 `process.exec` 启动" → "CDF 命令函数执行子进程时"。

6.6 `req-capability-design.md`：移除 `process.exec` 示例。

6.7 `input-capability-syntax-redesign.md`：移除 `process.exec` 引用。

6.8 `log-2026-06-02-design-audit-fixes.md`：移除 `process.exec` 自动推断的记录行。

### Step 7：交叉验证

全局搜索 `process\.exec` 确保全部清理完毕。搜索 `List IOError` 确保全部替换完毕。

## 实施顺序

```
Step 1 (CmdResult) ────────── 无依赖
Step 2 (runAs conflict) ───── 无依赖
Step 4 (enum sync) ────────── 无依赖
Step 5 (find/header/boundary) ── 无依赖
Step 3 (process.exec remove) ── Step 1 完成后（确认无 process.exec 在新定义中引入）
Step 6 (sync docs) ──────────── Steps 3-5 完成后
Step 7 (cross-verify) ──────── 全部步骤完成后
```

## 验证方法

- VitePress 构建通过
- 全局搜索 `process\.exec` 返回 0 结果（排除 input/ 中保留的历史输入）
- 全局搜索 `List IOError` 返回 0 结果
- `CmdResult` 所有引用出现在正式定义之后

## 风险评估

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| 沙箱文档中 `process.exec` 被移除后，chmod/chown 能力控制路径不完整 | CDF 命令无权限门控 | 低 | CDF 存在即授权，`fs.write` 控制路径——已足够 |
| 环境变量过滤节与 `process.exec` 解绑后有歧义 | 不清楚何时触发过滤 | 中 | 明确写为"CDF 命令函数执行子进程前" |
| 用户后续可能想加回逃生口 | 需要恢复文档 | 低 | 此时按需恢复即可，当前无此需求 |
