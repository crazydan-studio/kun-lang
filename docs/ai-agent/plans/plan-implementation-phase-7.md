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

对四级搜索路径的每个根目录 `<base>`，`import Foo.Bar.Baz` 按以下规则解析：

- 文件查找：`<base>/Foo/Bar/Baz.kun`
- 模块名用 PascalCase，文件名也用 PascalCase，目录层级表达命名空间
- 标准库示例：导入 `List` → 在 `<runtime>/lib/kun/List.kun` 查找
- **MVP 简化**：采用按需文件查找（per-import），不实现 `syntax.md` 的编译期全库预索引。预索引优化推迟 v0.2。

**注意**：项目 `lib/` 是相对于**脚本文件所在目录**（非工作目录）。入口脚本路径必须先解析为绝对路径，提取其父目录，再拼接 `lib/`。

### 1.3 导入语法处理

解析器当前支持以下导入形式：

- `import Foo` / `import Foo as X` ✅
- `import Foo (a, b)` / `import Foo (..)` ❌（未实现，推迟 v0.2）

模块解析器的职责仅为**找到 `.kun` 文件并加载其 AST**。符号级的选择（全量导入 vs 精选导入）由类型检查器在符号环境中进行过滤，与模块解析器无关。

**export 解析**同样有限：当前支持 `export (name1, name2)` 但未支持 `export (Result(Ok))` 的 ADT 变体细粒度导出和 `export (Command(field1))` 的 Record 字段选择。两步均推迟到精选导入实现时（v0.2）一并处理。

### 1.4 标准库交互

当 `import IO` 在四级路径中未找到 `IO.kun` 文件时，回退到 `primitive.zig` 编译期常量表中的内置绑定。这意味着 MVP 中 `<runtime>/lib/kun/` 可以不存在 `.kun` 文件——标准库通过 Primitive 表提供。

### 1.5 实现

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
- `load(allocator, module_name) !*LoadedModule` — 调用 resolve 找到文件，lex→parse→typecheck 递归加载
- `resolvePath(base_dir, module_name) !?[]const u8` — 在单个目录下查找模块

**LoadedModule 结构**：
```zig
pub const LoadedModule = struct {
    name: []const u8,           // "Foo.Bar"
    path: []const u8,           // 文件系统完整路径
    decls: []const Decl,        // 解析后的顶层声明
    exports: ?[]const []const u8, // export(...) 列表，null 表示脚本（不可导入）
};
```

**export 处理**：解析模块后提取 `export (...)` 声明中的符号列表。有 `export` 无 `main` 为库模块，可被其他模块导入；有 `main` 无 `export` 为可执行脚本，不可被导入；两者同时出现为编译错误。

**循环依赖检测**：加载前检查是否已在 `loaded` 缓存中（已加载则直接返回）；递归加载时维护调用栈，检测重复模块名 → 报 `error.CircularImport`。

## Step 2：--run 端到端

### 2.1 import 处理流程

```
入口脚本路径解析（绝对路径）→ 提取脚本所在目录
    → 初始化 ModuleResolver（project_lib = 脚本目录/lib/）
    → 对入口脚本执行 Lexer → Parser → 提取 import 列表
    → 对每条 import 调用 ModuleResolver.load()
        → resolve() 在四级路径中搜索 .kun 文件
        → 找到后 lex→parse，递归处理该模块的 import
        → 缓存到 loaded map，检测循环依赖
    → 合并所有模块的 decls（入口脚本 + 所有依赖）
    → TypeCheck（全局类型环境，注入导入符号）
    → Eval（注入 primitive.zig 标准库绑定）
```

### 2.2 main.zig 修改

- **脚本路径解析**：`--run <path>` 中的 `<path>` 先解析为绝对路径（通过 `std.c.realpath` 或等价的 Zig 文件系统 API）
- **ModuleResolver 初始化**：从脚本目录提取项目 `lib/`、读取 `KUN_PATH` 环境变量（冒号分隔）、定位运行时 `lib/kun/`（编译期 `@embedFile` 或固定路径）
- **递归 import 加载**：遍历入口脚本的 import 声明，逐条 `ModuleResolver.load()`
- **标准库回退**：import 未找到 `.kun` 文件时，检查 `primitive.zig` 表是否有该模块绑定——有则注入 Primitive，无则检查是否为内置类型（`CommandError`/`Result`/`Duration`/`Path` 等已在 `typecheck/env.zig` 中定义的类型，无需 `.kun` 文件），两者均无则报错 `ModuleNotFound`
- **导入符号注入**：类型检查前，将导入模块的 `export` 列表中符号注入类型环境；无 `export` 的脚本不可被导入；对 Primitive 回退的模块，注入表中该模块的所有函数绑定
- **运行时符号绑定**：类型检查后、Eval 前，对每个导入的 Kun 模块，将 `function_def` 求值得到的 Closure 绑定到全局 Frame 中——键名为 `模块别名.函数名`（如 `D.applyManifest`）。Primitive 模块的运行时绑定已在 `primitive.zig` 表中，无需额外处理。

### 2.3 标准库 .kun 模块

当前标准库全部以 Zig Primitive 实现，不依赖 `.kun` 文件。`<runtime>/lib/kun/` 目录在 MVP 中可空——Primitive 绑定由 `primitive.zig` 编译期常量表提供。

后续版本中标准库的 `[PureKun]` 函数（如 `List.map`、`Map.filter` 等纯变换函数）可通过 `.kun` 文件实现，由模块解析器加载。

## Step 3：示例验证

### 3.1 验证范围

示例脚本 `k8s-deploy/deploy.kun` 和 `monorepo-ci/build.kun` 导入的模块分为三类：

| 类别 | 模块 | 状态 | 验证 |
|------|------|------|------|
| Primitive 已就绪 | IO, File, Env, Process, Cmd, Stream, List, Map, Set, String, Bytes, Hash, Base64, Parser.JSON, DateTime, Regex, Validator | 已实现（DateTime/Regex/Validator 有 Primitive 绑定，regex 使用 zig-regex 引擎） | lex→parse→typecheck 全流水线 |
| 未实现 | Cli (v0.3), Task (v0.4), Random (v0.3) | 无 Primitive 绑定 | lex→parse→回退失败→报 ModuleNotFound |
| 项目本地模块 | Deployer, Verifier, Canary, Notifier, Builder, Tester, Dockerizer, Reporter | 存在于 `lib/` | lex→parse→ModuleResolver.load→typecheck |
| 类型级 | CommandError, Duration, Result, Path | ADT/内置类型，非模块 | typecheck 通过（类型环境内置） |

### 3.2 实际验证命令

```bash
# 语法解析验证（dump-ast 保持单文件行为，不解析 import 依赖）
zig build dump-ast -- code/examples/k8s-deploy/deploy.kun
zig build dump-ast -- code/examples/monorepo-ci/build.kun

# 全流水线验证（--run 接入 ModuleResolver 后可用）
zig build
./zig-out/bin/kun --run code/examples/k8s-deploy/deploy.kun --help
```

## Step 4：收尾修复

### 4.1 已知问题

| 项目 | 说明 | 处理 |
|------|------|------|
| `eval.zig` range_literal | 创建空 StreamNode，忽略 from/to 值 | **Phase 7 修复** |
| `eval.zig` pipe_reverse / compose / compose_reverse | `@panic("unimplemented")` | **Phase 7 修复** |
| `eval.zig` regex_literal | `@panic("regex engine not yet implemented")` | 推迟 v1.1（改用 zig-regex） |
| `eval.zig` range 模式匹配 | `@panic("unimplemented: range")` | 推迟 v0.2 |
| 内存泄漏 | 确认 0 泄漏（当前已 0） | — |
| 文档同步 | 更新 project-context、feature-inventory、codebase-map | — |

### 4.2 测试补充

- `module/test_module_resolver.zig`：搜索路径优先级、模块缓存命中、循环依赖检测报错、模块未找到错误、export 列表提取、脚本不可导入错误
- `test_main.zig` 新增 `module_resolver` 引用
- 集成测试：`--dump-ast` 对示例脚本全流水线验证

## 变更范围总表

| Step | 新建文件 | 修改文件 | 新增代码行 | 新增测试 |
|------|---------|---------|-----------|---------|
| 1 | `module/module_resolver.zig` | — | ~220 | 0 |
| 2 | — | `main.zig` | ~100 | ~15（`module/test_module_resolver.zig`） |
| 3 | — | — | 0 | 0 |
| 4 | — | `eval.zig` | ~100 | ~10 |
| **合计** | **1** | **3** | **~420** | **~25** |

目标：**665 → ~690 测试**，`--run` 端到端可执行示例脚本。

## 依赖关系

```
Step 1 (ModuleResolver) → Step 2 (--run + main.zig) → Step 3 (示例验证)
                              ↓
                        Step 4 (eval.zig 收尾)
```

Step 1→2 严格串行。Step 4 与 Step 2-3 无代码冲突（修改 eval.zig 的不同区域），可并行。

## 推迟项（不在本计划范围）

| 项 | 原因 | 目标版本 |
|----|------|---------|
| CLI 安全参数（--allow-path 等） | 沙箱子系统 | v0.5 |
| Landlock/seccomp/rlimit | 安全子系统 | v0.5 |
| `Duration`/`Int`/`Float`/`Char` 模块 Primitive 绑定 | 标准库扩展 | v0.2 |
| `String`/`List`/`Map`/`Set` PureKun 函数 | .kun 标准库文件 | v0.2 |
| Regex 引擎 + Validator 完整实现 | zig-regex | v0.2 |
| DateTime 格式化引擎 | 专用引擎 | v0.2 |
| Cli 模块 / Parser.Record | 编译期代码展开 | v0.3 |
| 等递归类型 | TypeEnv 别名集合 | v0.3 |
| Kun Shell | 交互环境 | v2.0 |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.25 | R5 审计修复（4 项）：DateTime/Regex/Validator 从"存根"移至"Primitive 已就绪"、补充运行时符号绑定说明（Kun 模块函数如何进入 eval Frame）、标注 MVP 预索引简化、移除依赖图中不存在的 constraint.zig 节点、--dump-ast 行为明确化 |
| 2026.06.25 | R4 审计：已知问题补全（5 个 panic stub 分级处理） |
| 2026.06.25 | R3 审计修复：导入/导出语法实际覆盖范围修正 |
| 2026.06.25 | R2 审计修复（4 项）：示例验证按模块类别分级、标准库回退增加内置类型检查、推迟项补充、constraint.zig 从 Step 4 移除 |
| 2026.06.25 | R1 审计修复（8 项）：模块路径映射修正、导入语法说明、标准库交互回退、LoadedModule 结构、处理流程细化、验证方式、已知问题、依赖图 |
