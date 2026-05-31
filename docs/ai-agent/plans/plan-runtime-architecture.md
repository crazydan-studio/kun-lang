# 执行计划：运行时架构设计

## 背景

当前 `docs/ai-agent/architecture/system-baseline.md` 仅包含运行时的骨架描述：技术栈、命令加载机制高层面板、错误诊断类型、安全模型概览、类型系统概述、命令签名系统概述。缺少核心模块的深化设计。

运行时架构设计是后续所有子系统（命令签名系统、安全模型、REPL、标准库实现）的设计基线，必须在展开其他系统前定型。

## 变更范围

### 重写文件

| 文件 | 说明 |
|------|------|
| `docs/ai-agent/architecture/system-baseline.md` | 从骨架文档扩展为完整的运行时架构设计文档 |

### 新增文件

| 文件 | 说明 |
|------|------|
| 无需新增 | 所有运行时代理细节纳入 `system-baseline.md` |

### 修改文件

| 文件 | 说明 |
|------|------|
| `docs/ai-agent/architecture/index.md` | 更新文件说明 |
| `docs/ai-agent/architecture/module-boundaries.md` | 同步运行时新增组件的模块边界 |
| `docs/ai-agent/context/project-context.md` | 更新活跃工作状态 |
| `docs/ai-agent/backlog/index.md` | 更新运行时架构设计状态 |

## 实施步骤

### Step 1: 展开运行时生命周期

新增章节，描述从启动到退出的完整流程：

- 启动阶段：CLI 参数解析 → 源码读取 → 词法/语法/类型分析
- 初始化阶段：运行时环境建立、能力系统初始化、模块解析
- 执行阶段：AST 求值引擎、do 块效应编排、命令加载与调用
- 清理阶段：资源释放、退出码传播

### Step 2: 定义执行模型

新增章节，描述函数式语言执行引擎的核心设计：

- 纯表达式求值策略（严格求值，惰性仅对 Stream 生效）
- IO 效果编排模型：`do`/`do in` 块在运行时的表示（嵌套函数调用链，非特殊操作）
- `<-` 解包的运行时语义：IO 包装的剥离与效果调度
- Stream 惰性求值的运行时实现：拉取驱动的 iterator 模式

### Step 2.5: 展开错误诊断体系

当前 `system-baseline.md` 仅列出错误类型名称，需扩展为完整设计：

- `PermissionError` 的完整结构体定义：资源类型与路径、所需能力名称、源码位置、拒绝原因、修改建议
- `TypeError` 的结构体定义：期望类型、实际类型、表达式位置、错误原因、修复提示
- `ValidationError` 的结构体定义：验证器名称、参数名、实际值、约束条件
- `CommandError` 的结构体定义：命令名、退出码、stderr 输出、源码位置
- 错误传播模型：如何与 Result 类型、`?` 操作符、`<-?` 绑定集成
- 错误报告管道：编译期错误 vs 运行时错误的统一报告接口

### Step 3: 深化命令加载机制

展开当前 `dlopen` 节为完整设计：

- 命令发现策略（PATH 搜索、缓存、内置命令优先）
- C ABI 函数签名约定：参数类型到 C 类型的映射表
- 结构化参数序列化/反序列化：二进制格式定义、大小限制
- dlopen 符号解析流程：函数名匹配 → 签名验证 → 调用
- ptrace 适配层：触发条件、stub 注入、性能模型
- fork/exec 回退：适用场景、进程管理、退出码收集
- 失败处理：命令未找到 → ABI 不匹配 → 运行时崩溃的报告链

### Step 4: 定义类型运行时表示

新增章节，将所有 Kun 类型的运行时 C ABI 表示定型：

- 基础类型：i64（Int/Nat/Duration）、f64（Float）、u1/u8（Bool）、切片（String/Bytes/Path）
- 复合类型：List 表示为 `{ptr, len, cap}`、Map/Set 的 hashtable 结构
- ADT：Tagged union（`{tag, data}` 模式）
- Stream：iterator 结构体（`{next_fn, state}`）
- 函数值：function pointer + closure environment
- IO 包装：thunk 结构体

### Step 5: 定义内存管理策略

新增章节，描述资源的分配与回收：

- 分配策略：arena 分配器为主（per 脚本执行），长期存活值迁移到全局堆
- 字符串/Path 的内部化（interning）策略
- List/Map 等容器的内存布局：连续存储 vs 链式
- 资源清理：文件描述符追踪、do 块的 RAII 风格资源管理
- 循环引用保护：不可变性保证无循环引用

### Step 6: 定义模块解析与加载

新增章节，描述模块在运行时的处理：

- 模块文件搜索路径（标准库路径、项目本地路径、用户自定义路径）
- 模块加载流程：路径解析 → 文件读取 → 词法/语法/类型分析 → 缓存
- 导入图的循环依赖检测
- 标准库模块的特殊处理（编译器内置实现 vs 语言编写的模块）

### Step 7: 定义标准库集成

新增章节，描述标准库如何与运行时集成：

- 内置操作（List/map/filter/fold 等）Primitive 函数表
- IO 操作（readFile/writeFile/readLines 等）的实现模式：调用 POSIX 系统调用
- Args 模块的运行时支持：参数解析的 C 层辅助
- Stream 模块的运行时支持：惰性拉取的状态机生成

### Step 8: 更新导航与元数据

- 更新 `docs/ai-agent/architecture/index.md` 文件说明
- 同步更新 `docs/ai-agent/context/project-context.md` 活跃工作
- 更新 `docs/ai-agent/backlog/index.md` 为 `in-progress`

## 验证方法

1. **构建验证**: `cd /workspace/docs && pnpm lint:md && pnpm build`
2. **一致性审查**: 逐项对照 `docs/ai-agent/design/syntax.md` 确认所有代码示例语法正确（无 `<>`、`--`、`::`、`=>` 等废弃语法）
3. **类型表示审查**: 逐项对照 `docs/ai-agent/design/type-system.md` 确认运行时类型表示与类型系统设计一致
4. **标准库审查**: 逐项对照 `docs/ai-agent/design/standard-library.md` 确认标准库集成部分与 API 签名一致
5. **边界审查**: 确认新引入的运行时概念与 `docs/ai-agent/architecture/module-boundaries.md` 的模块划分一致，必要时更新该文档

## 风险评估

| 风险 | 缓解措施 |
|------|---------|
| 运行时设计过于笼统，无法指导实现 | 每个设计点必须给出 ABI 级别的具体表示或 C 结构体定义 |
| 设计决策与之前语法/类型系统矛盾 | 实施前确认所有代码示例和类型签名与 `docs/ai-agent/design/syntax.md`、`docs/ai-agent/design/type-system.md` 一致 |
| 设计过于详细，变成实现规范 | 保持在"设计"级别：给出结构和接口，而非实现代码；实现细节留到后续编码阶段 |
| 与后续安全模型/命令签名系统设计冲突 | 运行时设计仅定义接口和数据结构，具体能力检查/CDF 验证留到对应子系统文档 |
| 文档范围过大，难以维护 | 每个章节设定位数限制（每节不超过 3 个 C 结构体定义或等价篇幅），超长内容拆分到独立文档 |
| 与 module-boundaries.md 的模块划分矛盾 | 实施前确认运行时组件的职责范围，新增的运行时概念及时同步到 module-boundaries.md |

## 审计要点

1. 所有运行时类型表示是否与 `docs/ai-agent/design/type-system.md` 一致
2. 所有代码示例和伪代码中的语法是否与 `docs/ai-agent/design/syntax.md` 一致（无废弃语法）
3. 命令加载机制的 C ABI 设计是否与 Zig 的 FFI 能力兼容
4. IO 效果编排模型是否与 `do`/`do in`/`<-` 语法语义一致
5. 内存管理策略是否与"不可变默认"的设计原则一致
6. 模块解析策略是否与 `import` 语法语义一致
7. 标准库集成是否与 `docs/ai-agent/design/standard-library.md` 的 API 签名一致
