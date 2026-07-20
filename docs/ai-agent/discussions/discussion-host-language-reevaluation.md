# 宿主语言重新评估：从 Zig 切换至 Rust

> **日期**：2026-07-20
> **状态**：已定稿
> **相关文档**：[语言评估](../analysis/language-evaluation.md)、[代码库撤销回顾](../retrospectives/retrospective-codebase-revocation.md)、[系统基线](../architecture/system-baseline.md)、[Zig 模式指南（已归档）](../context/zig-patterns.md)

## 背景

自上次宿主语言评估（2026-07-16，结论：Zig 41.75 vs Rust 38.5，维持 Zig）以来，设计与项目状态发生重大变化，触发本次重新评估：

### 触发因素 1：代码库撤销事件（commit `559180a`，2026-07-17）

5 万行 Zig 实现被全部撤销。回顾事件，部分根因可归咎于 LLM 对 Zig 代码生成不稳定：

- LLM 在 5 万行规模下生成的 Zig 代码混杂多个版本风格（0.11/0.12/0.13/0.16），comptime/分配器传递/error union 等核心模式不一致
- 加剧了"补丁堆叠导致实现难以维护"的反模式
- 设计大改动后，旧 Zig 实现失去维护价值

详见 [代码库撤销回顾](../retrospectives/retrospective-codebase-revocation.md)。

### 触发因素 2：`Cli.parse`/`Parser.Record` 移出 MVP

Zig comptime 的核心优势是服务于这两个功能的编译期代码生成。当这两项移出 MVP 后：

- comptime 的边际收益消失——MVP 阶段无需编译期类型驱动代码生成
- Zig 与 Rust 在"对 Kun 支持的完整性"维度上持平

### 触发因素 3：效应系统从"代数效应"改为"效应委派"

效应委派系统中 `continue` 是效应转发（分发表查找），无需续延捕获：

- tree-walking 解释器即可实现
- 不再需要 comptime 生成的续延传递变换代码
- Zig comptime 在此维度的优势消失

### 触发因素 4：Zig pre-1.0 breaking change 实际发生

项目从 Zig 0.17.0-dev 回退至 0.16.0 时，部分代码需重写以适配 API 变更：

- `@cImport` → `b.addTranslateC`
- `@Type` → `@Int`/`@Struct`/`@Union`
- `std.fs.path.cwd` → `process.Cwd`

证明 pre-1.0 breaking change 风险已实际发生，而非理论担忧。

## 决策

**切换宿主语言从 Zig 至 Rust。**

## 理由

### 1. LLM 支持是已证明的关键风险

撤销事件证明 LLM 对 Zig 代码生成不稳定是**已实际发生的风险**，非理论风险。在 AI 辅助开发为主要工作流的项目中，此项差距是决定性因素：

| 维度 | Rust | Zig | 加权差距 |
|---|---|---|---|
| LLM 模型支持（×2.0） | 5 | 2.5 | **+5.0 加权（最大单项差距）** |

Rust 是 LLM 代码生成支持度最高的系统编程语言，GitHub 训练数据量在系统编程语言中位列前茅，社区代码风格高度一致（`rustfmt` + `clippy`），`rust-analyzer` 提供语义分析二次校验。对 Kun 直接相关领域（`bumpalo` Arena、`enum` + `match` tagged union、`nix` syscall 包装、`std::process::Command` fork-exec），LLM 均可生成正确实现。

### 2. comptime 优势随 Cli.parse 移出 MVP 而减弱

修订权重后"对 Kun 支持的完整性"维度从 ×3 降至 ×2.0，Zig 与 Rust 在此维度上**持平（4:4）**：

| Kun 需求 | Rust 支持 | Zig 支持 |
|---|---|---|
| fork-exec + pipe 捕获 | `std::process::Command` | `std.process.Child` |
| Arena 分配器 | `bumpalo::Bump`（成熟 crate） | `std.heap.ArenaAllocator` |
| HM 类型推断 | 泛型 + `enum` + 模式匹配 | comptime 泛型 + tagged union |
| Landlock/seccomp/signalfd | `nix` crate + `unsafe` | `std.os.linux` 直接 syscall |
| tagged union AST | `enum` 一等公民 | 原生核心特性 |
| 效应委派系统 | tree-walking + handler 分发表 | tree-walking + labeled switch |
| 无 hidden control flow | ✅（`panic = abort`） | ✅ |
| `Cli.parse`/`Parser.Record` 编译期代码生成 | proc macro（已移出 MVP） | comptime（已移出 MVP） |

### 3. Rust 1.0 稳定性 vs Zig pre-1.0 不稳定

Rust 自 2015 年 1.0 发布以来无 breaking change 事件，Edition 机制（2015/2018/2021/2024）保证向后兼容性。Zig pre-1.0 的 breaking change 风险已通过 0.17.0-dev → 0.16.0 回退实际发生，未来 0.17/0.18/1.0 迁移均可能产生适配成本。

维护便捷性维度（×1.5，原 ×1）：

| 子项 | Rust | Zig |
|---|---|---|
| 包管理 | Cargo 业界标杆 | `build.zig.zon` 改善但仍不及 |
| LSP | rust-analyzer 业界标杆 | zls 趋于稳定但仍不及 |
| 错误信息 | 业界最友好之一 | 在改善但远不及 |
| 兼容性承诺 | 1.0 稳定 | Pre-1.0 风险已实际发生 |
| Lint 工具 | clippy 700+ 条 lint | 无对标 |
| **加权总分** | **7.5** | **3.75** |

### 4. 综合评分

| 维度（权重） | Rust | Zig 0.16 | Erlang/Elixir | Go |
|---|---|---|---|---|
| 1. LLM 模型支持（×2.0） | 5 | 2.5 | 3 | 4 |
| 2. 构建与运行时性能（×1.5） | 4 | 5 | 2 | 4 |
| 3. 维护便捷性（×1.5） | 5 | 2.5 | 4 | 4 |
| 4. 对 Kun 支持的完整性（×2.0） | 4 | 4 | 1 | 1.5 |
| 5. 构建产物大小/独立性（×1.5） | 3.5 | 5 | 2 | 2 |
| 6. 构建环境支持（×1） | 5 | 3 | 3 | 4 |
| **加权总分** | **40.0** | **37.0** | **22.5** | **28.5** |

Rust 首次超过 Zig，差距 3.0 分。Erlang/Elixir 与 Go 因 GC × Arena 根本冲突被排除。

## 落盘清单

### 已修改文档

| 文件 | 变更内容 |
|---|---|
| `docs/ai-agent/analysis/language-evaluation.md` | 完整重写：四语言对比、修订权重表、Rust 摩擦缓解措施、撤销事件教训分析 |
| `docs/ai-agent/context/project-context.md` | 宿主语言 → Rust 1.97；技术基线 → Rust；任务路由新增 2026-07-20 切换记录；zig-patterns 标注为已归档 |
| `docs/ai-agent/architecture/project-vision.md` | 实现策略 → Rust（提及 `bumpalo`/`nix`/`regex` crate） |
| `docs/ai-agent/architecture/system-baseline.md` | 技术栈宿主语言 → Rust；所有 Zig 代码块（Stream/Expr/Type/Value/PrimitiveBinding 等）转为 Rust 等价；`ArenaAllocator` → `bumpalo::Bump`；`comptime` → `const`/`static`/proc macro；zig-regex → `regex` crate；标记 switch → `match` 表达式 |
| `docs/ai-agent/architecture/module-boundaries.md` | Primitive 函数表 → Rust 级绑定；源代码映射 `.zig` → `.rs` |
| `docs/ai-agent/architecture/index.md` | 设计原则 → Rust + 成熟 crate 生态 |
| `docs/ai-agent/design/feature-inventory.md` | `effect`/`handler` 实现语言 → Rust；Regex → Rust `regex` crate；编译期代码展开基础设施 → Rust proc macro |
| `docs/ai-agent/context/codebase-map.md` | 源代码说明 → 基于 Rust 重新实现 |
| `docs/ai-agent/context/zig-patterns.md` | 添加归档头注（2026-07-20，宿主语言切换至 Rust） |
| `docs/ai-agent/context/index.md` | zig-patterns.md 标注为已归档，Rust 模式指南待编写 |
| `docs/ai-agent/context/conventions.md` | Zig 文件命名/测试约定 → Rust 等价（详见文件内变更） |
| `AGENTS.md` | context 目录说明中 Zig 模式指南条目更新 |
| `docs/ai-agent/discussions/index.md` | 新增本讨论记录索引行 |

### 新建文档

| 文件 | 内容 |
|---|---|
| `docs/ai-agent/discussions/discussion-host-language-reevaluation.md` | 本讨论记录 |

## Rust 摩擦缓解措施

| 摩擦 | 缓解措施 | 备注 |
|------|---------|------|
| Arena × RAII | `bumpalo::Bump` + `Bump::scope` 闭包形式，或 arena + ID 索引避免循环引用 | bumpalo 成熟 crate |
| 借用检查器 | AST 节点用 `Rc<RefCell<>>` 或 arena + ID；HM 类型用 `Rc<Type>`；闭包环境用 `Rc<Env>` | LLM 对此模式生成质量高 |
| 编译速度 | `sccache` + `cargo-nextest` + 增量编译 | 日常迭代数秒级 |
| syscall | `nix` crate + 少量 `unsafe` 直接 syscall | nix crate 维护良好 |
| 二进制大小 | `strip` + `x86_64-unknown-linux-musl` + LTO | 约 1.5MB，MVP 可接受 |
| panic unwind | `panic = "abort"` 配置消除 hidden control flow | Cargo.toml `[profile.release]` |

## 后续工作

1. 编写 `docs/ai-agent/context/rust-patterns.md`（Rust 模式指南，对标原 `zig-patterns.md`）
2. 重新实现时基于 Rust + 新设计落地（待设计完全稳定后启动）
3. 未来若 `Cli.parse`/`Parser.Record` 进入实施阶段，评估 Rust proc macro 实现（与 Zig comptime 对比）

## 决策记录

- **决策类型**：架构变更（宿主语言切换）
- **自治级别**：`plan-first` → 用户确认后 `implement`
- **触发条件**：审计发现 + 代码库撤销事件 + 设计变化（Cli.parse 移出 MVP）
- **影响范围**：所有架构/上下文文档中的 Zig 引用、未来实现的语言选择
- **不可逆性**：可逆（未来若 LLM 对 Zig 支持显著改善且 Cli.parse 重新进入 MVP，可重新评估）

## 参考

- [语言评估](../analysis/language-evaluation.md)
- [代码库撤销回顾](../retrospectives/retrospective-codebase-revocation.md)
- [系统基线](../architecture/system-baseline.md)
- [Zig 0.16.0 宿主语言与效应/模块同名消歧（历史讨论）](discussion-zig-host-and-effect-module-namespacing.md)
- [Zig 模式指南（已归档）](../context/zig-patterns.md)
