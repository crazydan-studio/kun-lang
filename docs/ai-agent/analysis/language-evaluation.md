# 宿主语言评估：Zig vs Rust vs Go

## 评估背景

对 Kun 语言的三个候选底层实现语言（Zig、Rust、Go）进行全面评估。Kun 是一门面向 Linux 的函数式脚本语言，架构重设计后核心需求为：fork-exec 子进程管理、Arena 分配器、HM 类型推断、Landlock/seccomp/signalfd 等 Linux syscall、编译期 Parser.Record 代码生成、无依赖单体二进制。

## 评估维度

| 维度 | 权重 | 说明 |
|------|------|------|
| LLM 模型支持 | ×1.5 | 代码生成质量和工具补全支持度（AI 辅助开发为主要工作流） |
| 构建与运行时性能 | ×1.5 | 编译速度、运行时效率、交叉编译 |
| 维护便捷性 | ×1 | 依赖管理、构建系统、工具链、兼容性 |
| 对 Kun 支持的完整性 | ×3 | syscall、Arena、comptime、C ABI、无 hidden control flow |
| 构建产物大小/独立性 | ×2 | 二进制体积、无依赖运行时、启动时间 |
| 构建环境支持 | ×1 | CI、IDE、安装便捷度 |

## 综合评分

| 维度（权重） | Zig | Rust | Go |
|-------------|-----|------|-----|
| 1. LLM 模型支持（×1.5） | 2.5 | 5 | 4 |
| 2. 构建与运行时性能（×1.5） | 5 | 3 | 4 |
| 3. 维护便捷性（×1） | 2.5 | 5 | 4 |
| 4. 对 Kun 支持的完整性（×3） | 5 | 3.5 | 1 |
| 5. 构建产物大小/独立性（×2） | 5 | 3 | 2 |
| 6. 构建环境支持（×1） | 3 | 5 | 4 |
| **加权总分** | **41.75** | **38.5** | **27.0** |

## 详细分析

### 维度 1：LLM 模型支持程度

| 语言 | 评分 | 评估 |
|------|------|------|
| **Rust** | 5 | 训练数据最丰富，GitHub 上大量高质量代码。GPT-4o/Claude/DeepSeek 对其模式极为熟悉。proc macro、unsafe 边界、借用检查器等复杂领域也能正确生成。 |
| **Go** | 4 | 训练数据充足，尤其 CLI/网络代码。Go 的简单性降低了 LLM 出错概率。但 ADT/sum type 模拟（interface + type switch）会让 LLM 生成冗长代码。 |
| **Zig** | 2.5 | 到 2026 年社区增长，训练数据有所改善。但 comptime、分配器传递、error union 等核心惯用模式仍不稳定。Claude/DeepSeek 支持优于 GPT 系列。 |

### 维度 2：构建与运行时性能

| 语言 | 评分 | 评估 |
|------|------|------|
| **Zig** | 5 | 编译亚秒级，增量编译亚秒级。运行时性能 = C，无 GC pause。Arena 分配是几条指令。交叉编译一等公民。`zig build` 单命令产出静态二进制。 |
| **Go** | 4 | 编译速度快，GC 导致尾部延迟不可预测。但对于短生命周期脚本执行器，STW 暂停通常 < 1ms，影响可控。 |
| **Rust** | 3 | 编译慢（LLVM + 单态化），完整构建分钟级。增量编译已显著改善。运行时性能与 C 同级。交叉编译需预编译 std，设置复杂。 |

### 维度 3：维护便捷性

| 语言 | 评分 | 评估 |
|------|------|------|
| **Rust** | 5 | Cargo 生态最佳，rust-analyzer 业界标杆。cargo-fix/cargo-clippy 自动化维护。Edition 机制保证兼容性。 |
| **Go** | 4 | 工具链极简可靠，Go 1.x 兼容性承诺极强。gopls LSP 成熟。 |
| **Zig** | 2.5 | 包管理 0.11+ 引入后改善。Pre-1.0 仍有 breaking change。zls LSP 趋于稳定但不如 rust-analyzer。错误信息在改善但远不及 Rust。 |

### 维度 4：对 Kun 支持的完整性 ⭐

> **架构重设计后**：fork-exec 替代 dlopen、AST 标记替代 Monadic IO、tagged union 替代函数指针 Stream、`Cmd.<bin>` 替代 Builder API。关键需求变化如下：

| 需求 | Zig | Rust | Go |
|------|-----|------|-----|
| fork-exec + pipe 捕获 | `std.process.Child` | `std::process::Command` | `os/exec` |
| Arena 分配器 | `std.heap.ArenaAllocator`（惯用） | `bumpalo`/`typed-arena` crate（RAII 冲突） | 与 GC 根本冲突 |
| HM 类型推断 | comptime 泛型 + tagged union | 泛型 + enum（借用检查器摩擦） | interface{} + type switch（冗长） |
| Landlock/seccomp/signalfd | `std.os.linux` 直接 syscall | `nix` crate 或 `unsafe` + `libc` | `golang.org/x/sys/unix` |
| Parser.Record 代码生成 | comptime 直接（`@typeInfo`） | proc macro（复杂，编译慢） | 运行时反射（无编译期保证） |
| ADT / sum type | tagged union（一等公民） | enum（一等公民） | 无（interface 模拟） |
| 无 hidden control flow | ✅ | ✅（除 panic=unwind） | ❌（GC/goroutine 抢占） |

| 语言 | 评分 | 评估 |
|------|------|------|
| **Zig** | 5 | 上述所有需求均为惯用模式或标准库直接支持。comptime 让 Parser.Record 代码生成成为几百行模板而非独立子系统。 |
| **Rust** | 3.5 | fork-exec 是标准库。但 Arena × RAII、AST × 借用检查器、proc macro × 编译速度——三处摩擦持续消耗开发效率。架构简化后 Rust 的可行性明显提升。 |
| **Go** | 1 | GC × Arena 根本冲突，无 ADT/sum type 丧失类型安全核心优势。Landlock/seccomp 可通过 x/sys/unix 调用但不如 Zig 直接。 |

### 维度 5：构建产物大小/独立性

| 语言 | 评分 | 评估 |
|------|------|------|
| **Zig** | 5 | 完整解释器 + HM 类型检查器 < 500KB。无运行时库依赖，启动亚毫秒。适合嵌入 Docker 镜像、CI 流水线、边缘设备。 |
| **Rust** | 3 | 完整解释器 ~1.5MB（strip + musl + LTO）。无运行时依赖但 libc 静态链接。 |
| **Go** | 2 | 完整解释器 ~5MB（含 runtime/GC/scheduler/reflect/net）。启动 0.5-2ms。 |

### 维度 6：构建环境支持

| 语言 | 评分 | 评估 |
|------|------|------|
| **Rust** | 5 | GitHub Actions 一等支持。rustup 安装零摩擦。IDE 生态最佳。 |
| **Go** | 4 | GitHub Actions 支持良好。安装简单（官方二进制）。 |
| **Zig** | 3 | GitHub Actions 社区 action 可用。安装简单（单二进制）。zls LSP 趋于稳定。 |

## 架构重设计的语言选择影响

| 旧设计需求 | 新设计 | 对语言选择的影响 |
|-----------|--------|-----------------|
| dlopen/dlsym 直接调用命令二进制 | fork-exec + pipe 捕获 | **弱化 Zig 优势**：三种语言均等支持 |
| `IO T` Monadic 效应系统 | AST 标记 | **弱化 Zig 优势**：不再需要 comptime 实现效应传播 |
| Stream 函数指针链 | tagged union | **无影响**：更简单，三种语言均可 |
| Builder API + 幻影类型 | `Cmd.<bin>` + Record | **弱化 Zig 优势**：不再需要 comptime 代码生成 |
| Parser.Record 编译期代码生成 | 保持不变 | **维持 Zig 优势**：Zig comptime、Rust proc macro、Go 反射 |

## 结论

**维持 Zig 为宿主语言。**

架构重设计后 Rust 与 Zig 的差距从原来的 29:18 缩小到 41.75:38.5。Rust 的逼近主要因为 fork-exec 替代 dlopen 后，维度 4（Kun 完整性）的差距从 5→3 缩小到 5→3.5。Go 仍不可行——GC 与 Arena 的冲突是根本性的。

### 风险提示与缓解措施

| 风险 | 严重度 | 缓解 |
|------|--------|------|
| LLM 对 Zig 代码生成不稳定 | **高** | 保持 `zig-patterns.md` 高频更新；示例代码库覆盖所有惯用模式；AI 生成代码强制审计 |
| Zig pre-1.0 breaking change | 中 | 版本锁定（当前 0.17.0-dev）；CI 显式校验版本；计划性迁移窗口 |
| 单人维护负担 | 中 | 无依赖策略降低外部风险；Arena 分配减少内存 Bug；comptime 减少手写模板代码 |

### 版本锁定

- 锁定 Zig 版本为 **0.17.0-dev**（版本包 `/opt/ai-agent/tools/`）
- CI 配置中显式指定版本
- 仅在计划性迁移窗口升级

## 扩展评估：其他候选语言

### Kun 宿主语言的硬约束

| 约束 | 原因 |
|------|------|
| 无 GC / 可控内存 | 脚本解释器不能有不可预测的 STW 暂停 |
| 原生 ADT / sum type | HM 类型推断器的 AST 和类型表示必须用 tagged union |
| 穷举模式匹配 | 类型检查器大量依赖 |
| 直接 syscall 访问 | Landlock、seccomp、signalfd、fork-exec 等 Linux 特有机制 |
| 编译期代码生成 | Parser.Record 需要为每个类型生成特化序列化代码 |
| 小体量独立二进制 | 脚本语言分发——嵌入 CI 流水线、Docker 镜像、边缘设备 |
| LLM 友好 | AI 辅助开发为主要工作流，代码生成质量直接影响开发效率 |

### 候选语言评估

#### C++17/20

| 维度 | 评价 |
|------|------|
| ADT | `std::variant` + `std::visit` = pattern matching。不如 Rust/Zig 的 tagged union 优雅，但可用 |
| 内存管理 | `std::pmr::monotonic_buffer_resource` = Arena。无 GC |
| syscall | 直接 `syscall()` 或 libc，原生支持 |
| 编译期 | `constexpr` + `consteval` + 模板元编程 = 强大但冗长。Parser.Record 代码生成可行但不优雅 |
| 二进制 | 极小（与 C 同级） |
| LLM 支持 | ⭐ 最强。训练数据量压倒性第一。LLM 对 C++17/20 惯用模式掌握极好 |

**关键风险**：无借用检查器 = 内存 bug 概率高。模板错误信息冗长。`std::variant` + `std::visit` 的 AST 递归遍历代码比 Zig tagged union 冗长 2-3×。虽然 LLM 能写 C++，但在 20,000 行规模的复杂解释器项目中，内存管理的人工审查负担会显著增加。

#### Swift

| 维度 | 评价 |
|------|------|
| ADT | `enum` + associated values = 完美的代数数据类型，穷举 `switch` |
| 内存管理 | ARC 确定性释放，无 STW。比 GC 好，比 Arena 手动控制差一点 |
| syscall | `Glibc` 模块可用，但 Linux 是二等公民（Darwin 优先） |
| 编译期 | Swift 5.9+ Macro 系统，可做类型驱动代码生成 |
| 二进制 | 因 Swift runtime 较 Zig 大 3-5× |
| LLM 支持 | 中等。iOS/macOS 生态训练数据丰富，但服务端/系统编程场景远少于 Rust/C++ |

**关键风险**：`fork()` 在 Darwin 上不可用，Linux 上的 Swift 生态仍不成熟。Kun 所有核心 syscall（Landlock、seccomp、signalfd、mount ns）都是 Linux 独有的，这让 Swift 的 Darwin 基因成为一个真实问题。

#### D（@nogc 子集）

| 维度 | 评价 |
|------|------|
| ADT | `std.sumtype` 或手工 tagged union，中等 |
| 内存管理 | `@nogc` 子集禁用 GC，手动管理。Arena 可实现 |
| syscall | 直接 C 互操作 |
| 编译期 | CTFE（编译期函数执行）+ `mixin` = 极强 |
| 二进制 | 小（with betterC） |
| LLM 支持 | 较弱。D 社区小，LLM 训练数据远不如 C++/Rust/Zig |

**关键风险**：LLM 支持太弱。这是致命问题——整个项目的 AI 辅助开发工作流会严重受阻。

#### C（纯 C）

| 维度 | 评价 |
|------|------|
| LLM 支持 | ⭐ 最强（与 C++ 并列）。任何 LLM 都以最高质量生成 C |
| 二进制/性能/syscall | 全满分 |
| ADT | 手工 tagged union + `switch`，冗长但完全可控 |

**关键风险**：无泛型/无编译期代码生成 → Parser.Record 的代码生成只能用外部代码生成器（Python 脚本等），打破单体二进制原则。在 20,000 行 C 中维护 HM 推断器的手工 tagged union AST 极易出错。

### 扩展对比矩阵

| | Zig | Rust | C++17 | Swift | C | Go |
|---|---|---|---|---|---|---|
| ADT / sum type | 5 | 5 | 3.5 | 5 | 2 | 1 |
| 无 GC / 可控 | 5 | 5 | 5 | 4 | 5 | 1 |
| syscall | 5 | 4 | 5 | 3 | 5 | 3.5 |
| 编译期代码生成 | 5 | 4 | 4 | 3.5 | 1 | 2 |
| 小二进制 | 5 | 3.5 | 5 | 3 | 5 | 2 |
| LLM 友好 | 2.5 | 5 | 5 | 3.5 | 5 | 4 |
| 内存安全 | 3 | 5 | 1 | 4 | 1 | 3 |

### 扩展评估结论

**没有比 Zig 更适合且 LLM 明显更友好的候选语言。** 这是一个「适合度 vs LLM 友好度」的根本性权衡：

- **C++** 是唯一 LLM 评分不输 Zig 适合度评分的替代。但 `std::variant` 的冗长 + 无借用检查器，在 20,000 行规模会显著提升维护负担。可行但不是更优。
- **Swift** 类型系统完美匹配 Kun 需求，但 Linux syscall 生态的薄弱是硬伤。
- 其他候选（D、C）都有致命短板。

**核心洞察**：Zig 的 LLM 弱点可以通过加强 `zig-patterns.md` 和 AI 代码强制审计来缓解。其他语言在「Kun 完整性」维度的短板是结构性/根本性的，无法通过工程手段弥补。

## 参考

- [项目上下文](../context/project-context.md)
- [系统基线](../architecture/system-baseline.md)
- [Zig 模式指南](../context/zig-patterns.md)
