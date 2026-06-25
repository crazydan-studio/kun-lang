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

**注意**：项目 `lib/` 是相对于**脚本文件所在目录**（非工作目录）。入口脚本路径必须先解析为绝对路径，提取其父目录，再拼接 `lib/`。

### 1.3 导入语法处理

解析器已支持三种导入风格（`syntax.md`）：

- `import Foo` / `import Foo as X`
- `import Foo (a, b)` / `import Foo (a as x)`
- `import Foo (..)`

模块解析器的职责仅为**找到 `.kun` 文件并加载其 AST**。符号级的选择（全量导入 vs 精选导入）由类型检查器在符号环境中进行过滤，与模块解析器无关。

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

- **脚本路径解析**：`--run <path>` 中的 `<path>` 先用 `std.fs.realpathAlloc` 解析为绝对路径
- **ModuleResolver 初始化**：从脚本目录提取项目 `lib/`、读取 `KUN_PATH` 环境变量（冒号分隔）、定位运行时 `lib/kun/`（编译期 `@embedFile` 或固定路径）
- **递归 import 加载**：遍历入口脚本的 import 声明，逐条 `ModuleResolver.load()`
- **标准库回退**：import 未找到 `.kun` 文件时，检查 `primitive.zig` 表是否有该模块绑定——有则注入 Primitive，无则检查是否为内置类型（`CommandError`/`Result`/`Duration`/`Path` 等已在 `typecheck/env.zig` 中定义的类型，无需 `.kun` 文件），两者均无则报错 `ModuleNotFound`
- **导入符号注入**：类型检查前，将导入模块的 `export` 列表中符号注入类型环境；无 `export` 的脚本不可被导入；对 Primitive 回退的模块，注入表中该模块的所有函数绑定

### 2.3 标准库 .kun 模块

当前标准库全部以 Zig Primitive 实现，不依赖 `.kun` 文件。`<runtime>/lib/kun/` 目录在 MVP 中可空——Primitive 绑定由 `primitive.zig` 编译期常量表提供。

后续版本中标准库的 `[PureKun]` 函数（如 `List.map`、`Map.filter` 等纯变换函数）可通过 `.kun` 文件实现，由模块解析器加载。

## Step 3：示例验证

### 3.1 验证范围

示例脚本 `k8s-deploy/deploy.kun` 和 `monorepo-ci/build.kun` 导入的模块分为三类：

| 类别 | 模块 | 状态 | 验证 |
|------|------|------|------|
| Primitive 已就绪 | IO, File, Env, Process, Cmd, Stream, List, Map, Set, String, Bytes, Hash, Base64, Parser.JSON | 已实现 | lex→parse→typecheck 全流水线 |
| 存根/推迟 | Cli (v0.3), Validator (v1.1), Task (v0.4), DateTime (v1.1), Regex (v1.1), Random (v0.3) | 无实现或 stub | lex→parse→**跳过 typecheck**（import 回退后报未定义符号） |
| 项目本地模块 | Deployer, Verifier, Canary, Notifier, Builder, Tester, Dockerizer, Reporter | 存在于 `lib/` | lex→parse→ModuleResolver.load→typecheck |
| 类型级 | CommandError, Duration, Result, Path | ADT/内置类型，非模块 | typecheck 通过（类型环境内置） |

### 3.2 实际验证命令

```bash
# 语法解析验证（全流水线 lex→parse）
zig build dump-ast -- code/examples/k8s-deploy/deploy.kun
zig build dump-ast -- code/examples/monorepo-ci/build.kun

# 项目本地模块解析验证（需模块系统完成）
# deploy.kun 的 lib/ 模块应能 resolve + parse 通过
```

## Step 4：收尾修复

### 4.1 已知问题

| 项目 | 说明 |
|------|------|
| `eval.zig` range_literal | 当前为 stub（创建空 StreamNode），需真实实现 `Stream.range` 求值 |
| `eval.zig` pipe_reverse / compose / compose_reverse | `@panic("unimplemented")`，需按 `syntax.md` 语义实现求值 |
| 内存泄漏 | 确认 0 泄漏（当前已 0） |
| 文档同步 | 更新 project-context、feature-inventory、codebase-map |

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
ModuleResolver ──→ --run 端到端 ──→ 示例验证
     ↓                                   ↓
constraint.zig import 处理          eval.zig import 处理
     ↓                                   ↓
 收尾修复（range_literal / compose / pipe_reverse）
```

Step 1-2 严格串行；Step 4 可与 Step 2 并行（修改不同文件）。

## 推迟项（不在本计划范围）

| 项 | 原因 | 目标版本 |
|----|------|---------|
| CLI 安全参数（--allow-path 等） | 沙箱子系统 | v0.2 |
| Landlock/seccomp/rlimit | 安全子系统 | v0.2 |
| `Duration`/`Int`/`Float`/`Char` 模块 Primitive 绑定 | 标准库扩展 | v0.2 |
| `String`/`List`/`Map`/`Set` PureKun 函数 | .kun 标准库文件 | v0.2 |
| Cli 模块 / Parser.Record | 编译期代码展开 | v0.3 |
| 等递归类型 | TypeEnv 别名集合 | v0.3 |
| Regex / Validator / DateTime | 专用引擎 | v1.1 |
| Kun Shell | 交互环境 | v2.0 |

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.25 | R2 审计修复（4 项）：示例验证按模块类别分级（Primitive就绪/存根推迟/本地模块/类型级）、标准库回退增加内置类型检查（CommandError/Result/Duration/Path）、推迟项补充 Duration/Int/Float/Char/PureKun 模块绑定 |
| 2026.06.25 | R1 审计修复（8 项）：模块路径映射修正（`<root>`→四级路径遍历）、导入语法说明引用 syntax.md、标准库交互回退机制、LoadedModule 结构定义 + export 处理、import 处理流程细化（脚本路径解析 + 递归加载 + 符号注入 + 回退）、验证方式补充 --run、已知问题补充 constraint/eval import 处理、依赖图细化 |
