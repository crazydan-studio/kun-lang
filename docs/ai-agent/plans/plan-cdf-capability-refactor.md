# 执行计划：CDF 能力导向重构

## 背景

当前 CDF（Command Description File）以 CLI 调用形式为中心——`option x "-x" : T` 直接映射命令的 flag，`subcommand` 1:1 嵌套子命令。这种设计虽然精确，但存在以下问题：

1. **参数膨胀**：`ls` 有 50+ flags，但用户核心能力仅是"列出目录内容"
2. **高维护成本**：每个命令的每个 flag 都需要在 CDF 中声明
3. **用户心智负担**：用户仍需理解 CLI 参数才能使用命令函数
4. **auto-inference 过度**：试图捕获所有 flags，90% 不必要

本次重构将 CDF 从 **CLI 选项建模**转变为**能力参数建模**——只表达"用户想获取什么能力"，CLI 映射下移为编译期/运行时实现细节。

## 设计哲学

```
CLI 形式：ls -la --sort=time /tmp
能力语义：列出 /tmp 目录的文件（含隐藏、按时间排序）
能力参数：{ path = p"/tmp", all = true, sortBy = SortBy.Time }
```

## 变更范围

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `design/command-signature-system.md` | 重构 | CDF 格式、参数声明、auto-inference、覆盖范围、run 机制 |
| `design/capability-mapping-guide.md` | **新增** | 能力映射方法论和最佳实践 |
| `architecture/system-baseline.md` | 修改 | 命令加载机制、run 沙箱策略 |
| `architecture/module-boundaries.md` | 修改 | 命令签名系统描述更新 |
| `discussions/discussion-command-function-design.md` | 修改 | 新增议题 9：能力映射决策 |
| `requirements/mvp.md` | 修改 | run 能力控制同步 |
| `design/feature-inventory.md` | 修改 | 命令系统状态更新 |

### CDF 格式变更（核心）

| 旧格式 | 新格式 | 说明 |
|--------|--------|------|
| `option x "-x" : T` | `param x : T with (cli: ["-x"])` | CLI flag 下移为实现细节 |
| `option x "-x" : T!` | `param x : T with (required, cli: ["-x"])` | required 语义清晰 |
| `option x "-x" : List T` | `param x : List T with (cli: ["-x"])` | 无变化 |
| `option x "-x" : Bool` | `param x : Bool with (cli: ["-x"])` | Bool 直接映射 |
| `option x "--xx" : T` | `param x : T with (cli: ["--xx"])` | 长名同理 |
| `param N : T` | `param x : T with (positional: N)` | 位置参数命名化 |
| `param * : List T` | `param args : List T with (positional: *)` | 剩余参数命名化 |
| 无分类 | `param x : T with (essential, ...)` | 新增参数分类 |
| 无分类 | `param x : ?T with (filter, ...)` | 新增参数分类 |
| CDF 顶层直接声明 flags | `param` 声明能力参数，编译期决定 argv | 能力导向 |

### `run` 机制变更

| 旧 | 新 |
|----|----|
| `process.run` 白名单控制 | 同左，但新增命令可达性控制 |
| T4 `run""` 默认允许所有命令 | T4 `run""` 仅在 `process.run` 白名单中可用 |
| 零前置工作——写出来就能跑 | 前置工作：至少 `process.run` 白名单声明 |
| `process.run = []` 通配 | `process.run = []` 通配保留但默认警告 |

### Primitive 边界

保持现有设计：仅替代基础/常用命令能力。不扩展至复杂算法类命令。

## 实施步骤

### Step 1：新增 `capability-mapping-guide.md`

**产出**：能力映射指南文档

内容：
- 核心原则：能力 > 形式
- 五大启发规则（结果影响、格式无关、语义提升、标准库替代、输出驱动）
- 参数分类系统（essential / filter / behavior / ~~display~~ / ~~internal~~）
- 常见命令能力分析表（每个命令的核心能力、映射参数、不映射参数）
- 示例：从 CLI 形式到能力参数的转换过程

### Step 2：重构 `command-signature-system.md`

**产出**：格式语义更新的 CDF 文档

项目：
- 2.1 CDF 格式更新：`option` → `param` + `cli` 映射下沉
- 2.2 新增参数分类系统
- 2.3 重写 auto-inference：从"捕获所有 flags"改为"识别核心能力参数"
- 2.4 重写覆盖范围表：每个命令标注能力映射分析
- 2.5 `run` 控制机制更新：T4 受限于 process.run 白名单
- 2.6 更新所有示例为能力导向风格
- 2.7 移除"零前置工作"文本

### Step 3：更新 `system-baseline.md`

**产出**：同步的命令加载机制文档

项目：
- 3.1 命令加载流程图更新（反映 run 受控）
- 3.2 安全沙箱说明更新
- 3.3 移除"所有命令都能跑"相关表述

### Step 4：更新 `module-boundaries.md`

**产出**：命令签名系统描述更新
- 反映能力映射的设计方向
- auto-inference 重新描述

### Step 5：更新 `discussion-command-function-design.md`

**产出**：新增议题 9（能力映射决策）

### Step 6：更新 `requirements/mvp.md` 和 `feature-inventory.md`

### Step 7：交叉验证

- 全局搜索 `option x "-x"` 模式确认全部更新
- 全局搜索 "零前置" 等旧表述确认清理
- VitePress 构建通过

## 实施顺序

```
Step 1 (新指南) ────── 无依赖，先行
Step 2 (核心重构) ──── Step 1 完成后
Step 3 (system) ───── Step 2 完成后
Step 4 (modules) ───── Step 2 完成后（可并行于 Step 3）
Step 5 (discussion) ── Step 2 完成后（记录决策）
Step 6 (sync) ──────── Steps 1-5 部分/全部完成后
Step 7 (verify) ────── 全部完成后
```

## 验证方法

- VitePress 构建通过（`cd docs && pnpm build`）
- Markdown lint 通过（`cd docs && pnpm lint`）
- 全局搜索旧格式模式（`option.*"-`、`零前置`、`写出来就能跑`）确认清理

## 风险评估

| 风险 | 影响 | 概率 | 缓解 |
|------|------|------|------|
| 现有设计重度依赖旧 CDF 语义 | 需同步 update 所有引用 | 高 | 一次性全面更新，不遗留 |
| 能力参数到 CLI argv 的映射可能复杂 | CDF 编译器实现难度增加 | 中 | 映射规则限定为"直接 flag + 值"，不涉及条件逻辑 |
| 用户习惯了"命令名字即函数名"范式 | 学习曲线 | 中 | capability-mapping-guide 提供过渡指导 |
| `run` 控制收紧影响使用便利性 | 用户需显式声明 | 低 | 符合安全模型"最小权限"初衷 |
