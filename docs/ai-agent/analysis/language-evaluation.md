# 宿主语言评估：Rust vs Zig vs Erlang/Elixir vs Go

## 评估背景

对 Kun 语言的四个候选宿主语言（Rust、Zig、Erlang/Elixir、Go）进行全面评估。Kun 是一门面向 Linux 的函数式脚本语言，核心需求为：fork-exec 子进程管理、Arena 分配器、HM 类型推断、Landlock/seccomp/signalfd 等 Linux syscall、tagged union AST 表示、效应委派系统（`effect`/`handler`/`continue`/`abort`）。

### 重新评估的触发因素

自上次评估（Zig 41.75 vs Rust 38.5）以来，设计发生了重大变化：

1. **`Cli.parse`/`Parser.Record` 移出 MVP** — Zig comptime 的核心优势消失（comptime 主要服务于这两个功能的编译期代码生成）
2. **5 万行 Zig 实现被撤销**（commit `559180a`，2026-07-17）— 证明 LLM 对 Zig 代码生成不稳定是**已实际发生的风险**，非理论风险
3. **效应系统从"代数效应"改为"效应委派"** — `continue` 是效应转发（分发表查找），无需续延捕获，tree-walking 解释器即可实现
4. **Zig 版本从 0.17.0-dev 回退至 0.16.0** — pre-1.0 breaking change 风险已实际发生

详细背景见：
- [代码库撤销回顾](../retrospectives/retrospective-codebase-revocation.md)
- [系统基线](../architecture/system-baseline.md)
- [宿主语言重新评估讨论](../discussions/discussion-host-language-reevaluation.md)

## 评估维度与权重（修订）

| 维度 | 权重 | 修订理由 |
|------|------|----------|
| LLM 模型支持 | **×2.0**（原 ×1.5） | 提升 — 撤销事件证明 LLM 对 Zig 不稳定是实际风险 |
| 构建与运行时性能 | ×1.5 | 不变 |
| 维护便捷性 | **×1.5**（原 ×1） | 提升 — pre-1.0 语言的 breaking change 风险已实际发生 |
| 对 Kun 支持的完整性 | **×2.0**（原 ×3） | 降低 — comptime 优势随 Cli.parse 移出 MVP 而减弱 |
| 构建产物大小/独立性 | **×1.5**（原 ×2） | 降低 — MVP 阶段可接受稍大二进制 |
| 构建环境支持 | ×1 | 不变 |

> **修订要点**：原评估中"对 Kun 支持的完整性"权重高达 ×3，主要因为 comptime 服务于 `Cli.parse`/`Parser.Record` 的编译期代码生成。当这两项移出 MVP 后，Zig comptime 的边际收益显著下降；与此同时，撤销事件暴露的 LLM 风险和 pre-1.0 风险被低估，因此相应提升 LLM 支持（×2.0）和维护便捷性（×1.5）的权重。

## 综合评分

| 维度（权重） | Rust | Zig 0.16 | Erlang/Elixir | Go |
|---|---|---|---|---|
| 1. LLM 模型支持（×2.0） | 5 | 2.5 | 3 | 4 |
| 2. 构建与运行时性能（×1.5） | 4 | 5 | 2 | 4 |
| 3. 维护便捷性（×1.5） | 5 | 2.5 | 4 | 4 |
| 4. 对 Kun 支持的完整性（×2.0） | 4 | 4 | 1 | 1.5 |
| 5. 构建产物大小/独立性（×1.5） | 3.5 | 5 | 2 | 2 |
| 6. 构建环境支持（×1） | 5 | 3 | 3 | 4 |
| **加权总分** | **40.0** | **37.0** | **22.5** | **28.5** |

> **关键变化**：Rust（40.0）首次超过 Zig（37.0），差距 3.0 分。原评估中 Zig 41.75 vs Rust 38.5，差距 3.25 分。修订权重后差距反转，且 Rust 在 LLM 支持、维护便捷性、构建环境支持三个维度上对 Zig 形成压倒性优势（10.0 vs 8.0、7.5 vs 3.75、5.0 vs 3.0）。

## 详细分析

### Rust

#### 维度 1：LLM 模型支持（评分 5）

Rust 是 LLM 代码生成支持度最高的系统编程语言。GitHub 上训练数据量在系统编程语言中位列前茅（仅次于 C/C++），且社区代码风格高度一致——`rustfmt` + `clippy` 拉齐了不同项目间的差异。

- GPT-4o/Claude 3.5/DeepSeek V3 对 Rust 模式极为熟悉，包括：
  - 借用检查器错误恢复（推荐 `&`/`&mut`/`Rc`/`RefCell` 的时机）
  - 生命周期标注（罕见场景如 `where for<'a>` 也能正确生成）
  - proc macro 编写（虽然复杂，但比 Zig comptime 模式库更稳定）
  - `unsafe` 边界（FFI 包装层、`MaybeUninit`、`ptr::read/write`）
- `rust-analyzer` 的语义分析可作为 LLM 输出的二次校验，错误恢复链路成熟
- 与 Kun 直接相关的领域：`bumpalo` Arena 模式、`enum` + `match` tagged union、`nix` crate syscall 包装、`std::process::Command` fork-exec，LLM 均可生成正确实现

#### 维度 2：构建与运行时性能（评分 4）

- **编译速度**：完整构建分钟级（与 Zig 的亚秒级相差一个数量级），但增量编译 + `sccache` + `cargo-nextest` 可将日常迭代控制在数秒级
- **运行时性能**：与 C 同级，LLVM 后端优化深度高于 Zig 自研后端
- **交叉编译**：需预编译 std（`rustup target add`），不如 Zig 一等公民，但 `cross` crate 可缓解
- **评估理由**：相比 Zig 的 5 分，Rust 在编译速度上的劣势明确，但运行时性能持平且工具链成熟度更高，故评 4 分而非 3 分（原评估）

#### 维度 3：维护便捷性（评分 5）

- **Cargo 生态最佳**：依赖管理、版本解析、feature gate、workspace 一站式
- **rust-analyzer** 业界 LSP 标杆，IDE 集成成熟
- **Edition 机制**（2015/2018/2021/2024）保证向后兼容性，无 pre-1.0 breaking change 风险
- **clippy** 提供超过 700 条 lint，覆盖惯用法、性能、正确性
- **错误信息**：编译器错误信息是业界最友好之一（带建议、引用相关 RFC）
- **1.0 稳定承诺**：自 2015 年 1.0 发布以来，无 breaking change 事件

#### 维度 4：对 Kun 支持的完整性（评分 4）

| Kun 需求 | Rust 支持情况 |
|---|---|
| fork-exec + pipe 捕获 | `std::process::Command` 标准库直接支持 |
| Arena 分配器 | `bumpalo::Bump`（成熟 crate），RAII 自动 `Drop` |
| HM 类型推断 | 泛型 + `enum` + 模式匹配，借用检查器摩擦通过 `Rc`/`Box` 缓解 |
| Landlock/seccomp/signalfd | `nix` crate + `libc` + 少量 `unsafe` syscall |
| tagged union AST | `enum` 一等公民，`match` 穷举检查 |
| 效应委派系统 | tree-walking 解释器 + handler 分发表，无需续延捕获 |
| 无 hidden control flow | `panic = abort` 配置下符合（`panic = unwind` 有 unwind，但可控） |
| `Cli.parse`/`Parser.Record` 编译期代码生成 | proc macro 可实现，但已移出 MVP，MVP 阶段用运行时反射 |

**摩擦点**：
1. **Arena × RAII**：`bumpalo::Bump` 不与 `Drop` 自动协作，需手动管理生命周期或用 `bumpalo::Bump::scope` 闭包形式
2. **借用检查器**：AST 节点间的循环引用（如 lambda 闭包捕获环境）需用 `Rc<RefCell<>>` 或 arena 分配 + ID 索引
3. **proc macro 编译速度**：Cli/Parser.Record 移出 MVP 后此摩擦消失

**评分理由**：相比 Zig 的 4 分（comptime 优势已随 Cli.parse 移出 MVP 减弱），Rust 的完整性差距缩小到 0；摩擦点均可通过工程手段缓解（详见下文「Rust 摩擦缓解措施」），故评 4 分。

#### 维度 5：构建产物大小/独立性（评分 3.5）

- 完整解释器 + HM 类型检查器：约 1.5MB（`strip` + `musl` + LTO）
- 无运行时依赖，libc 静态链接（`x86_64-unknown-linux-musl` target）
- 启动时间亚毫秒级
- 对比 Zig 的 < 500KB：MVP 阶段可接受稍大二进制；嵌入式场景未来可通过 `no_std` + 自定义 allocator 进一步压缩

#### 维度 6：构建环境支持（评分 5）

- GitHub Actions 一等支持（`dtolnay/rust-toolchain` action）
- `rustup` 安装零摩擦
- IDE 生态最佳（VS Code + rust-analyzer、IntelliJ Rust）
- `cargo-deny`/`cargo-audit` 供应链安全工具链成熟

### Zig 0.16

#### 维度 1：LLM 模型支持（评分 2.5）

Zig 的 LLM 支持是**已证明的关键风险**——5 万行 Zig 实现被撤销（commit `559180a`）部分归因于 LLM 生成的 Zig 代码不稳定：

- **comptime 模式不稳定**：LLM 对 `@typeInfo`/`@Type`/`@Int`/`@Struct` 等内置函数的生成经常出错，且错误难以察觉（编译期失败信息冗长）
- **分配器传递模式不稳定**：LLM 经常忽略 allocator 参数或混用 `page_allocator` 与 Arena，导致内存安全 bug
- **error union 模式不一致**：LLM 对 `try`/`catch`/`err` 的生成风格在不同代码段间不一致，加剧维护负担
- **0.16 → 0.13 风格漂移**：训练数据中混杂多个 Zig 版本的代码（0.11/0.12/0.13/0.14/0.16），LLM 经常生成跨版本不兼容的代码（如 `@cImport` vs `b.addTranslateC`）
- **Claude/DeepSeek 略优于 GPT**，但整体仍不及 Rust 的稳定性

#### 维度 2：构建与运行时性能（评分 5）

- **编译速度**：亚秒级（`zig build` 增量编译），是 Zig 最显著的工程优势
- **运行时性能**：与 C 同级，无 GC pause
- **交叉编译**：一等公民（`zig build -Dtarget=x86_64-linux-musl`），自带 cross-toolchain
- **Arena 分配**：几条指令（`ArenaAllocator` 标准库直接提供）
- **评 5 分不变**

#### 维度 3：维护便捷性（评分 2.5）

- **Pre-1.0 breaking change 风险已实际发生**：项目从 0.17.0-dev 回退到 0.16.0 即是一例
- **包管理**：`build.zig.zon` 引入后改善，但生态远不及 crates.io
- **zls LSP**：趋于稳定但功能不及 rust-analyzer（无完整的 type inference 反馈）
- **错误信息**：在改善但远不及 Rust 的友好度
- **0.16 → 0.17+ 迁移成本**：每次 minor 版本升级均需重新验证全部代码模式

#### 维度 4：对 Kun 支持的完整性（评分 4）

| Kun 需求 | Zig 0.16 支持情况 |
|---|---|
| fork-exec + pipe 捕获 | `std.process.Child` |
| Arena 分配器 | `std.heap.ArenaAllocator`（惯用） |
| HM 类型推断 | comptime 泛型 + tagged union |
| Landlock/seccomp/signalfd | `std.os.linux` 直接 syscall |
| tagged union AST | 原生核心特性 |
| 效应委派系统 | tree-walking 解释器 + labeled switch 高效分发 |
| 无 hidden control flow | ✅ |
| `Cli.parse`/`Parser.Record` 编译期代码生成 | comptime 直接（`@typeInfo`），但已移出 MVP |

**评分理由（从 5 下调至 4）**：原评估中 Zig 在此维度获 5 分，主要因为 comptime 让 Parser.Record 代码生成成为几百行模板而非独立子系统。**当 Cli.parse/Parser.Record 移出 MVP 后**，comptime 的边际收益消失——MVP 阶段 Zig 与 Rust 的完整性差距缩小至 0。考虑到 comptime 仍是潜在优势（未来 Cli/Parser.Record 落地时），保留 4 分而非下调至 3.5。

#### 维度 5：构建产物大小/独立性（评分 5）

- 完整解释器 + HM 类型检查器：< 500KB
- 无运行时库依赖，启动亚毫秒
- 适合嵌入 Docker 镜像、CI 流水线、边缘设备
- **评 5 分不变**

#### 维度 6：构建环境支持（评分 3）

- GitHub Actions 社区 action 可用，但不及 Rust 官方支持
- 安装简单（单二进制下载）
- zls LSP 趋于稳定但仍不及 rust-analyzer
- **评 3 分不变**

### Erlang/Elixir (BEAM)

#### 维度 1：LLM 模型支持（评分 3）

- Elixir 训练数据充足（Phoenix/LiveView 生态推动），LLM 对 Elixir 语法掌握良好
- Erlang 训练数据较少，LLM 对 OTP/supervision tree 等高级模式不稳定
- 函数式编程风格与 Kun 高度契合，LLM 生成的模式（pattern matching、不可变数据）质量较好

#### 维度 2：构建与运行时性能（评分 2）

- **编译速度**：Elixir 编译慢（依赖 mix），Erlang 快但生态小
- **运行时性能**：BEAM VM 性能约为 C 的 1/5–1/10，GC pause 显著但短暂（分代 GC）
- **交叉编译**：不友好，BEAM VM 通常是预编译分发
- **评 2 分**：BEAM 的 GC 与 Kun 的"无 STW"硬约束根本冲突

#### 维度 3：维护便捷性（评分 4）

- mix/rebar3 工具链成熟
- OTP 设计模式文档完善
- 1.0 稳定性极佳（Erlang 自 1986 年以来向后兼容性极强）

#### 维度 4：对 Kun 支持的完整性（评分 1）

**根本性不兼容**：

| Kun 需求 | BEAM 支持情况 |
|---|---|
| 无 GC / 可控内存 | ❌ BEAM GC 是核心特性，无法禁用 |
| 原生 ADT / sum type | ⚠️ Erlang/Elixir 用 tuple + atom 模拟，无编译期穷举检查 |
| 穷举模式匹配 | ❌ 无编译期穷举性检查 |
| 直接 syscall（Landlock/seccomp/signalfd） | ❌ 需 NIF，且 NIF 阻塞 scheduler 是反模式 |
| Arena 分配器 | ❌ BEAM 内存模型根本冲突 |
| fork-exec | ⚠️ `Port` 模块可用，但与 BEAM 进程模型耦合 |
| 小体量独立二进制 | ❌ 必须随 BEAM VM 分发（数十 MB） |

**评 1 分**：BEAM 与 Kun 的核心需求根本冲突——GC × Arena、无原生 ADT、syscall 通过 NIF 反模式、运行时体积过大。即使 LLM 支持良好也无法弥补这些结构性短板。

#### 维度 5：构建产物大小/独立性（评分 2）

- BEAM VM + 应用代码通常 30–80MB
- 无法静态链接到单体二进制（虽有 Bakeware/Livebook Native 等尝试，但成熟度低）
- 启动时间 0.5–2s（冷启动），不及 Zig/Rust 的亚毫秒

#### 维度 6：构建环境支持（评分 3）

- GitHub Actions 支持良好
- 安装简单（asdf/官方包管理器）
- IDE 支持：ElixirLS 良好，Erlang 较弱

### Go

#### 维度 1：LLM 模型支持（评分 4）

- 训练数据充足，尤其 CLI/网络代码
- Go 的简单性降低了 LLM 出错概率
- 但 ADT/sum type 模拟（interface + type switch）会让 LLM 生成冗长代码
- generics（1.18+）引入后训练数据仍在累积

#### 维度 2：构建与运行时性能（评分 4）

- 编译速度快（亚秒级增量）
- GC 导致尾部延迟不可预测
- 短生命周期脚本执行器中 STW 暂停通常 < 1ms，影响可控
- 交叉编译支持良好（`GOOS/GOARCH`）

#### 维度 3：维护便捷性（评分 4）

- 工具链极简可靠
- Go 1.x 兼容性承诺极强（自 2012 年 1.0 以来无 breaking change）
- gopls LSP 成熟

#### 维度 4：对 Kun 支持的完整性（评分 1.5）

| Kun 需求 | Go 支持情况 |
|---|---|
| 无 GC / 可控内存 | ❌ Go GC 是核心特性，无法禁用（`runtime.GC()` 只能触发，不能禁用） |
| 原生 ADT / sum type | ⚠️ interface + type switch 模拟，无编译期穷举检查 |
| 穷举模式匹配 | ❌ 编译器不强制 |
| 直接 syscall | `golang.org/x/sys/unix` 可调用 Landlock/seccomp，但不直接 |
| Arena 分配器 | ❌ GC × Arena 根本冲突（Go 1.20+ 实验性 arena API 但不推荐生产） |
| fork-exec | `os/exec` 标准库 |
| tagged union AST | interface + type switch（冗长 2-3×） |

**评 1.5 分**：GC × Arena 是根本性冲突；interface + type switch 模拟 ADT 在 HM 类型推断器中会产生大量样板代码，影响维护性。比 BEAM 稍好（Go 的 syscall 支持更直接），但仍不可行。

#### 维度 5：构建产物大小/独立性（评分 2）

- 完整解释器约 5–8MB（含 runtime/GC/scheduler/reflect/net）
- 启动 0.5–2ms

#### 维度 6：构建环境支持（评分 4）

- GitHub Actions 支持良好
- 安装简单（官方二进制 + `go install`）
- gopls LSP 成熟

## 核心权衡：Rust vs Zig

| 维度 | Rust | Zig | 优势方 | 差距 |
|---|---|---|---|---|
| LLM 模型支持（×2.0） | 5 | 2.5 | **Rust** | +5.0 加权（最大单项差距） |
| 构建与运行时性能（×1.5） | 4 | 5 | Zig | -1.5 加权 |
| 维护便捷性（×1.5） | 5 | 2.5 | **Rust** | +3.75 加权 |
| 对 Kun 支持的完整性（×2.0） | 4 | 4 | 持平 | 0 |
| 构建产物大小/独立性（×1.5） | 3.5 | 5 | Zig | -2.25 加权 |
| 构建环境支持（×1） | 5 | 3 | **Rust** | +2.0 加权 |
| **加权总分** | **40.0** | **37.0** | **Rust** | **+3.0** |

### 关键洞察

1. **LLM 支持是决定性差距**（+5.0 加权）：撤销事件证明 LLM 对 Zig 不稳定是实际风险，而非理论担忧。在 AI 辅助开发为主要工作流的项目中，此项差距压倒其他维度。
2. **维护便捷性（+3.75 加权）**：Rust 1.0 稳定 vs Zig pre-1.0 不稳定，breaking change 风险已实际发生。
3. **Zig 在性能（+1.5）和二进制大小（+2.25）上的优势不足以抵消上述差距**。
4. **对 Kun 完整性持平**：Cli.parse/Parser.Record 移出 MVP 后，Zig comptime 的边际收益消失。

## 撤销事件的教训

5 万行 Zig 实现的撤销（commit `559180a`，2026-07-17）是本次重新评估的直接触发因素。回顾事件：

### 撤销的根本原因

1. **设计大改动导致旧实现不可维护**：代数效应系统、命令系统重设计、`alias`/`type` 分离、TestCase 测试系统、沙箱加固等设计变更，使基于旧设计的 Zig 实现失去维护价值
2. **LLM 对 Zig 代码生成不稳定**：在 5 万行规模下，LLM 生成的 Zig 代码混杂多个版本风格（0.11/0.12/0.13/0.16），comptime/分配器传递/error union 等核心模式不一致，加剧了"补丁堆叠导致实现难以维护"的反模式
3. **Pre-1.0 breaking change 实际发生**：项目从 0.17.0-dev 回退到 0.16.0 时，部分代码需重写以适配 API 变更（`@cImport` → `b.addTranslateC`、`@Type` → `@Int`/`@Struct`/`@Union` 等）

### 撤销的教训对语言选择的影响

| 教训 | 对 Rust vs Zig 评估的影响 |
|---|---|
| LLM 不稳定是实际风险 | LLM 支持权重 ×1.5 → ×2.0，Rust +5.0 加权优势 |
| Pre-1.0 breaking change 实际发生 | 维护便捷性权重 ×1 → ×1.5，Rust +3.75 加权优势 |
| comptime 优势未在 MVP 中兑现 | Kun 完整性权重 ×3 → ×2.0，Zig 失去最大单项优势 |
| 设计先行原则：实现等待设计稳定 | 切换 Rust 后 LLM 生成质量更高，降低"重新实现"的成本 |

详细回顾见 [代码库撤销回顾](../retrospectives/retrospective-codebase-revocation.md)。

## 结论

**切换至 Rust 为宿主语言。**

修订权重后 Rust（40.0）首次超过 Zig（37.0），差距 3.0 分。核心驱动因素：

1. **LLM 支持是已证明的关键风险**（5 万行撤销事件）— 修订权重后 Rust 在此维度对 Zig 形成 +5.0 加权优势
2. **comptime 优势随 Cli.parse 移出 MVP 而减弱** — Kun 完整性维度 Zig 与 Rust 持平
3. **Rust 1.0 稳定性 vs Zig pre-1.0 不稳定** — 维护便捷性维度 Rust +3.75 加权优势

### Rust 摩擦缓解措施

| 摩擦 | 缓解措施 | 备注 |
|------|---------|------|
| Arena × RAII | 使用 `bumpalo::Bump` + `bumpalo::Bump::scope` 闭包形式，或 arena 分配 + ID 索引避免循环引用 | bumpalo 是成熟 crate，文档完善 |
| 借用检查器 | AST 节点用 `Rc<RefCell<>>` 或 arena + ID；HM 类型用 `Rc<Type>` 共享；闭包环境用 `Rc<Env>` | LLM 对 `Rc`/`RefCell` 模式生成质量高 |
| 编译速度 | `sccache` 缓存 + `cargo-nextest` 并行测试 + 增量编译；CI 用 `cargo build --release` 缓存 | 日常迭代可控制在数秒级 |
| syscall（Landlock/seccomp/signalfd） | `nix` crate 包装 + 少量 `unsafe` 直接 syscall | `nix` crate 维护良好，覆盖 Linux syscall 大部分 |
| 二进制大小 | `strip` + `x86_64-unknown-linux-musl` target + LTO（`-C lto=fat -C codegen-units=1`） | 约 1.5MB，MVP 阶段可接受 |
| panic unwind | `panic = "abort"` 配置消除 hidden control flow | Cargo.toml `[profile.release]` 配置 |

### 版本锁定

- 锁定 Rust 1.97（通过 `rustup` 管理，详见 https://forge.rust-lang.org/index.html）
- 工具链：`rustup toolchain install 1.97`
- 目标平台：`x86_64-unknown-linux-gnu`（开发）/ `x86_64-unknown-linux-musl`（发布静态二进制）
- CI 配置中显式指定 Rust 1.97 + 目标平台
- `rust-toolchain.toml` 固定版本：`channel = "1.97"`

### 后续工作

1. 编写 `docs/ai-agent/context/rust-patterns.md`（Rust 模式指南，对标原 `zig-patterns.md`）
2. 更新所有架构文档中的 Zig 引用为 Rust 对应（`ArenaAllocator` → `bumpalo::Bump`、标记 switch → `match` 等）
3. 重新实现时基于 Rust + 新设计落地

## 扩展评估：其他候选语言

### Kun 宿主语言的硬约束

| 约束 | 原因 |
|------|------|
| 无 GC / 可控内存 | 脚本解释器不能有不可预测的 STW 暂停 |
| 原生 ADT / sum type | HM 类型推断器的 AST 和类型表示必须用 tagged union |
| 穷举模式匹配 | 类型检查器大量依赖 |
| 直接 syscall 访问 | Landlock、seccomp、signalfd、fork-exec 等 Linux 特有机制 |
| 编译期代码生成 | Parser.Record 需要为每个类型生成特化序列化代码（已移出 MVP） |
| 小体量独立二进制 | 脚本语言分发——嵌入 CI 流水线、Docker 镜像、边缘设备 |
| LLM 友好 | AI 辅助开发为主要工作流，代码生成质量直接影响开发效率 |

### 候选语言排除理由

| 语言 | 排除理由 |
|---|---|
| **C++17/20** | `std::variant` + `std::visit` 冗长 2-3×；无借用检查器，内存 bug 概率高；模板错误信息冗长。LLM 支持虽好但维护负担显著高于 Rust |
| **Swift** | 类型系统完美匹配 Kun 需求，但 Linux syscall 生态薄弱（Darwin 优先），`fork()` 在 Darwin 不可用是硬伤 |
| **D（@nogc 子集）** | LLM 支持太弱，社区小，训练数据远不如 Rust/Zig |
| **C（纯 C）** | 无泛型/无编译期代码生成 → Parser.Record 需外部代码生成器，打破单体二进制原则；HM 推断器的手工 tagged union AST 极易出错 |
| **Erlang/Elixir (BEAM)** | GC × Arena 根本冲突；无原生 ADT；syscall 通过 NIF 反模式；运行时体积过大（详见上文） |
| **Go** | GC × Arena 根本冲突；interface + type switch 模拟 ADT 冗长；无编译期穷举检查（详见上文） |

### 核心权衡总结

**Rust 是当前 LLM 友好度与 Kun 完整性双高的最优选择**。Zig 在性能和二进制大小上仍有优势，但 LLM 不稳定和 pre-1.0 风险已通过撤销事件证明是实际成本，不可通过工程手段完全弥补。其他候选语言在「Kun 完整性」维度上存在结构性短板（GC、无原生 ADT、syscall 困难），无法通过工程手段弥补。

## 参考

- [项目上下文](../context/project-context.md)
- [系统基线](../architecture/system-baseline.md)
- [代码库撤销回顾](../retrospectives/retrospective-codebase-revocation.md)
- [宿主语言重新评估讨论](../discussions/discussion-host-language-reevaluation.md)
- [Zig 模式指南（已归档）](../context/zig-patterns.md)
