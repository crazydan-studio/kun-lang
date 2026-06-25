# 执行计划：Phase 7 — 模块系统 + --run 端到端 + 收官

## 背景

Phase 1-6 完成了解释器核心（Lexer/Parser/AST/TypeCheck）、运行时（Eval/Defer/Stream/HashMap）、命令调用系统（Cmd.*/fork-exec/pipe）和标准库 Primitive 实现。当前 `import` 声明能解析但不会实际加载模块——缺少模块搜索路径解析器。`main.zig` 的 `--run` 命令已搭好框架但模块系统未接入。

本计划完成 v0.1.0 的**最后一块拼图**：模块系统搜索路径 + `--run` 端到端可运行 + 示例验证 + 收尾修复。

## 基线数据

| 维度 | 值 |
|------|-----|
| 测试 | **665**（均通过，0 泄漏） |
| 源码文件 | ~50 个 Zig 文件 |
| 实现模块 | Lexer / Parser / AST / TypeCheck / Runtime / Command / Stdlib / i18n |
| 缺失 | 模块加载器、import 解析、--run 端到端 |

## Step 1：模块解析器（Module Resolver）

### 1.1 搜索路径

按 `syntax.md` 定义的四级优先级：

| 优先级 | 路径 | 说明 |
|--------|------|------|
| 1 | 项目 `lib/` | 从脚本所在目录的 `lib/` 出发 |
| 2 | `$KUN_PATH` | 环境变量，冒号分隔的目录列表 |
| 3 | `<runtime>/lib/kun/` | 标准库安装路径 |
| 4 | `~/.kun/cmd/` | 类型化命令模块 |

### 1.2 模块路径映射

`import Foo.Bar.Baz` → 搜索 `<root>/Foo/Bar/Baz.kun`

- 模块名用 PascalCase，文件名也用 PascalCase
- 目录名与模块命名空间一致
- 无循环依赖检测

### 1.3 实现

**新建文件**：`code/kun-lang/src/module/module_resolver.zig`

```zig
pub const ModuleResolver = struct {
    project_lib: ?[]const u8,     // 脚本所在目录的 lib/
    kun_path: [][]const u8,       // $KUN_PATH 冒号分隔
    runtime_lib: []const u8,      // <runtime>/lib/kun/
    cmd_path: []const u8,         // ~/.kun/cmd/
    loaded: std.StringHashMapUnmanaged(*LoadedModule),  // 已加载模块缓存

    pub fn resolve(self: *ModuleResolver, allocator: std.mem.Allocator, module_name: []const u8) ![]const u8 { ... }
    pub fn load(self: *ModuleResolver, allocator: std.mem.Allocator, module_name: []const u8) !*LoadedModule { ... }
};
```

**核心函数**：
- `resolve(allocator, module_name) ![]const u8` — 在四级路径中搜索，返回 `.kun` 文件完整路径
- `load(allocator, module_name) !*LoadedModule` — 调用 resolve 找到文件，递归 lex→parse→typecheck 加载
- `resolvePath(base_dir, module_name) !?[]const u8` — 在单个目录下查找模块

**循环依赖检测**：加载前检查是否已在 `loaded` 中；递归加载时维护调用栈，检测重复模块名。

## Step 2：--run 端到端

### 2.1 import 处理

在 `main.zig` 的 `--run` 路径中集成 `ModuleResolver`：

```
源码读取 → Lexer → Parser → 收集 import 列表
    → ModuleResolver.load() 递归加载依赖
    → 合并所有模块的 decls
    → TypeCheck（全局类型环境）
    → Eval（注入 standard library primitives）
```

### 2.2 main.zig 修改

- 新增 `import` 声明处理：遍历顶层 decls 中的 import，逐条 load
- `ModuleResolver` 初始化：检测脚本目录的 `lib/`、读取 `KUN_PATH` 环境变量、定位运行时 `lib/kun/`
- 标准库 Primitive 自动绑定：导入的 stdlib 模块（IO、File、Cmd 等）在 eval 前注册 Primitive

### 2.3 标准库 .kun 模块

当前标准库全部以 Zig Primitive 实现，不依赖 `.kun` 文件。`<runtime>/lib/kun/` 目录在 MVP 中可空——Primitive 绑定由 `primitive.zig` 编译期常量表提供。

后续版本中标准库的 `[PureKun]` 函数（如 `List.map`、`Map.filter` 等纯变换函数）可通过 `.kun` 文件实现，由模块解析器加载。

## Step 3：示例验证

### 3.1 k8s-deploy/deploy.kun

验证能通过 lex → parse → typecheck 全流水线。

### 3.2 monorepo-ci/build.kun

同上。

### 3.3 验证方式

```bash
zig build dump-ast -- code/examples/k8s-deploy/deploy.kun
zig build dump-ast -- code/examples/monorepo-ci/build.kun
```

## Step 4：收尾修复

### 4.1 已知问题

| 项目 | 说明 |
|------|------|
| eval.zig range_literal | 当前为 stub（创建空 StreamNode），需真实实现 |
| eval.zig pipe_reverse/compose/compose_reverse | `@panic("unimplemented")`，需实现 |
| 内存泄漏 | 确认 0 泄漏（当前已 0） |
| 文档同步 | 更新 project-context、feature-inventory、codebase-map |

### 4.2 测试补充

- `test_module_resolver.zig`：搜索路径优先级、模块缓存、循环依赖检测、模块未找到错误
- `test_main.zig` 新增导入引用

## 变更范围总表

| Step | 新建文件 | 修改文件 | 新增代码行 | 新增测试 |
|------|---------|---------|-----------|---------|
| 1 | `module/module_resolver.zig` | — | ~200 | ~15 |
| 2 | — | `main.zig` | ~80 | ~10 |
| 3 | — | — | 0 | 0 |
| 4 | `module/test_module_resolver.zig` | `eval.zig` | ~80 | ~10 |
| **合计** | **2** | **2** | **~360** | **~35** |

目标：**665 → ~700 测试**，`--run` 端到端可执行示例脚本。

## 依赖关系

```
Step 1 (模块解析器) ──→ Step 2 (--run 端到端) ──→ Step 3 (示例验证)
                                                    ↓
                                              Step 4 (收尾修复)
```

## 推迟项（不在本计划范围）

| 项 | 原因 | 目标版本 |
|----|------|---------|
| CLI 安全参数（--allow-path 等） | 沙箱子系统 | v0.2 |
| Landlock/seccomp/rlimit | 安全子系统 | v0.2 |
| Cli 模块 / Parser.Record | 编译期代码展开 | v0.3 |
| 等递归类型 | TypeEnv 别名集合 | v0.3 |
| Regex / Validator / DateTime | 专用引擎 | v1.1 |
| Kun Shell | 交互环境 | v2.0 |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.25 | 初始版本 |
