# 代码库地图

## 入口点

| 组件 | 路径 | 说明 |
|---|---|---|
| 项目根目录 | `/` | 仓库根目录，包含 README.md、LICENSE、AGENTS.md |
| 源代码 | `code/` | Kun 语言实现源代码（待开发） |
| 文档 | `docs/` | VitePress 项目文档 |
| 构建脚本 | `tools/` | 构建、预览等辅助脚本 |

## 源代码结构

`code/kun-lang/src/` 组织如下，目录命名与 `architecture/module-boundaries.md` 的模块划分一一对应：

```
src/
├── main.zig              # CLI 入口（kun 可执行文件）
├── lib.zig               # 共享库入口（libkunlang.so）
├── test_main.zig         # 测试运行器根文件
│
├── ast/                  # 抽象语法树（解释器核心）
│   ├── ast.zig           # 未类型化的 AST 节点与 Span
│   └── typed.zig         # 带类型标注的 Typed AST
│
├── lexer/                # 词法分析器（解释器核心）
│   ├── lexer.zig
│   └── test_lexer.zig
│
├── parser/               # 语法分析器（解释器核心）
│   ├── parser.zig
│   └── test_parser.zig
│
├── typecheck/            # 类型检查器（解释器核心）
│   ├── env.zig           # 类型环境
│   ├── unify.zig         # 合一求解器
│   ├── infer.zig         # 顶层推断入口
│   ├── constraint.zig    # 约束生成与效应接线
│   ├── effect.zig        # 效应检查器
│   ├── pattern.zig       # 模式穷举与类型收窄
│   ├── error.zig         # 结构化类型错误
│   └── test_*.zig        # 对应模块的单元测试
│
├── i18n/                 # 国际化子系统（解释器核心）
│   ├── i18n.zig          # locale 检测 + 双语消息格式
│   └── test_i18n.zig
│
├── runtime/              # 运行时
│   ├── value.zig         # 运行时值类型
│   ├── env.zig           # 变量帧
│   ├── eval.zig          # 求值器（标记 switch 分发）
│   ├── defer.zig         # defer 链数据结构
│   ├── hash_map.zig      # Map/Set 开地址哈希表
│   ├── glob_engine.zig   # glob 模式匹配引擎
│   ├── stream_consumer.zig  # Stream 惰性消费状态机
│   ├── primitive.zig     # Primitive 函数表与绑定
│   └── test_*.zig        # 对应模块的单元测试
│
├── command/              # 命令调用系统
│   ├── cmd.zig           # fork-exec / pipe / PATH 解析
│   └── test_cmd.zig
│
├── module/               # 模块解析系统
│   ├── module_resolver.zig  # ModuleResolver（四级搜索/递归加载/循环检测）
│   └── test_module_resolver.zig
│
├── stdlib/               # 标准库 Primitive 实现
│   ├── io.zig            # IO.println / print / readln / envList 等
│   ├── fs.zig            # File.readString / writeBytes / walkDir / glob 等
│   ├── crypto.zig        # sha256 / sha256Stream / jsonFromString / base64 等
│   ├── data.zig          # List.length / head / Map.insert / Set.contains 等
│   ├── stream.zig        # Stream.lines / iter / fold / range / Cmd.pipe 等
│   └── test_*.zig        # 对应模块的单元测试
│
├── cli/                  # CLI 参数解析引擎
├── security/             # 安全子系统
│
├── tests/                # 集成测试（lex→parse→typecheck→eval 全流水线）
│   └── test_integration.zig
│
└── examples/             # Kun 示例脚本
    ├── k8s-deploy/
    └── monorepo-ci/
```

## 关键目录

| 目录 | 用途 |
|---|---|
| `docs/ai-agent/context/` | 项目上下文与 AI 协作规范（最高优先级） |
| `docs/ai-agent/architecture/` | 技术架构与系统设计 |
| `docs/ai-agent/design/` | 应用层行为与功能设计（type-system / standard-library / syntax / kun-shell；roles-and-permissions / supply-chain-security / command-function-system / capability-mapping-guide 已废弃） |
| `docs/ai-agent/requirements/` | 需求文档 |
| `docs/ai-agent/process/` | 任务启动检查清单、应用开发工作流 |
| `docs/ai-agent/backlog/` | 待办事项 |
| `docs/ai-agent/plans/` | 执行计划 |
| `docs/ai-agent/skills/` | AI 技能提示词库 |
| `docs/ai-agent/audits/` | 审计记录与审计执行指南 |
| `docs/ai-agent/examples/` | 语法使用综合示例 |
| `docs/ai-agent/diagrams/` | PlantUML 图表文件 |
| `docs/ai-agent/archive/` | 历史版本文档归档 |
| `docs/ai-agent/input/` | 原始需求输入记录 |
| `docs/ai-agent/discussions/` | 设计讨论记录 |
| `docs/ai-agent/lessons/` | 经验教训与违规记录 |
| `docs/ai-agent/testing/` | 测试记录与基线值 |
| `docs/ai-agent/bugs/` | Bug 修复笔记 |
| `docs/ai-agent/references/` | 实现指南、维护检查清单、文档命名规范 |
| `docs/ai-agent/retrospectives/` | 回顾总结 |
| `docs/ai-agent/articles/` | 技术文章 |
| `docs/ai-agent/analysis/` | 技术分析报告（如语言选型评估） |
| `code/` | 源代码 |
| `tools/` | 构建脚本 |

## 脆弱文件

当前项目处于初始阶段，暂无已识别的脆弱文件。
