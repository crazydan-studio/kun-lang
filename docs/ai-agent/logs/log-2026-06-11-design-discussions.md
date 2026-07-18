# 开发日志 — 2026-06-11

## 会话类型

设计讨论 + 文档重组

## 工作内容

### 讨论事项

1. **宿语选择讨论**：评估 Zig/Rust/Go/C++17/Swift/D/C 七个候选语言。结论：维持 Zig，无 LLM 明显更友好的替代。补充扩展分析至 `analysis/language-evaluation.md`。

2. **List.iter 效应函数约束**：明确 `List.iter` 回调可为 IO 效应函数，回调 lambda 需在 `do` 块中定义；补充性能指引（fork COW 开销 ~0.5ms/次，大规模走批处理）。

3. **结构等价 vs 名称等价**：分析两种方案的实现复杂度与运行时性能，建议改为名称等价以保护 newtype 类型安全。

4. **FileType 变体命名**：建议为纯枚举不载负载信息，`RegularFile`→`Regular`，`Symlink`→`SymbolicLink`，`CharacterDevice`→`CharDevice`。设备号放入 `FileStat.device` 字段。

5. **JsonNumber 拆分**：`JsonNumber Float`→`JsonInt Int | JsonFloat Float`，保留 JSON 整数和浮点数语义。

6. **Path.cwd vs Std.cwd**：分析两者功能重复，建议保留 `Path.cwd`（常量），移除 `Std.cd`/`Std.cwd`。新增 `Cmd.withCwd : Path -> Command -> Command` 实现 per-command chdir。

7. **命令组合**：新增 `Cmd.andThen`/`Cmd.orElse` 实现 Bash `&&`/`||` 的短路条件执行，不作为运算符引入以避免与 Bool 逻辑冲突。

8. **String → Path 转换**：分析需 `Path.fromString` 安全转换，编译期常量检查 + 沙箱路径隔离。

9. **标准库重组讨论**：新增 `Math`（后并入 `Float`）、`Function`（缺省导入）、`Nil`（变体缺省导入，函数需显式）；`Pid`/`Port`/`ExitCode`/`DateTime` 改为 Int newtype + `of` 构造器；统一 `fromXxx`/`toXxx` 转换规范。

### 代码变更

#### 架构重设计（早前会话延续）

1. **架构/设计文档全面重写**（6 次提交）：按新方案重写 project-vision、system-baseline、module-boundaries、app-overview、syntax、type-system、standard-library、code-formatting、feature-inventory

2. **标记废弃文档**：roles-and-permissions、supply-chain-security、command-function-system、capability-mapping-guide

3. **示例文件重写**：file-processor、networking、pattern-matching、type-showcase 按最新语法更新

4. **输入文档简化**：input-architecture-redesign.md 精简为概要 + 交付物对照表

5. **清理过时引用**：移除 dlopen/dlsym/ptrace；更新 context/ 路由文档、ai-autonomy-policy、codebase-map、conventions

#### 审计修复（3 轮子代理审计）

6. **do 块缺失**：syntax.md、standard-library.md 函数体补 do；system-baseline.md 代码块补 do

7. **旧 API 残留**：`readFile`→`File.readString`、`print`→`IO.print`、`File.read`→`File.readString`、`fromUnixSecs`→`DateTime.fromUnixSecs`

8. **示例错误**：panic→Ipv4、identity 未定义、FileType 变体无 import、networking type 错误

9. **注释符修复**：stdlib 中 200+ 处 `--` 注释→`//`

#### 设计修订

10. **移除扩展积类型**：syntax.md、type-system.md、feature-inventory.md 删除 `{ Base | field : T }` 语法

11. **main 签名可选**：可执行脚本 `main` 缺省按 `List String -> Unit` 检查

12. **移除 -Wall 自动映射**：改为 `Cmd.withRawOpt "-Wall"`

13. **Std 模块移除**：`Std.cd`/`Std.cwd`→`Cmd.withCwd`；效应函数列表去 Std

14. **标准库全面重组**：新增 Function/Nil 模块；Int/Float/String 改为显式导入；文档注释统一格式（注释符 //，签名前一行）

15. **LSP 全栈同步**：syntax.ts/types.ts/ast.ts/diagnostics.ts/completion.ts/hover.ts/TM grammar/language-config/lint CLI 全部更新

16. **VitePress 语法高亮**：kun-grammar.json 同步

## Git 提交

```
c13e547 重构: 标准库修复注释符 + Int/Float/String 显式导入 + 文档格式统一
9aee586 重构: 标准库全面重组 — Math/Function/Nil 模块 + newtype 重构
b7acaa4 重构: 移除 Std 模块 + 新增 Cmd.withCwd per-command chdir
d805ce1 文档: 新增 Cmd.andThen/Cmd.orElse 短路组合 + List.iter 性能指引
ff93f30 文档: 宿主语言扩展评估 — C++17/Swift/D/C 分析
386bea8 修复: networking 示例中的类型名冲突和 let-in-do 语法错误
5b3874a 文档: 映射规则段落精简 — 去除非选项映射相关语句
8e07eeb 重构: 移除 -Wall 自动映射，改用 Cmd.withRawOpt
b1f7175 文档: 补充 List.iter / Cmd.withRunAs / camelCase→kebab-case 映射规则
42f092d 修复: type-system.md 版本历史表中管道字符转义
aee17da 重构: LSP server/plugin/CLI 代码同步最新设计
6950e14 重构: VitePress 语法高亮配置同步最新设计
54e14bc 重构: 移除扩展积类型 + 允许省略 main 类型标注
620f9e6 文档: 更新宿主语言评估 + zig-patterns 移除 dlopen + 工作流受保护区域同步
cc2068a 文档: 更新 AGENTS.md 和上下文文档路由
6897bc5 修复: 语法文档中残留的旧 print API → IO.print
70cb7c4 修复: 第二轮审计 — 移除残留的旧 API 名称
51b0166 修复: 示例文件编译/类型错误 + 格式化
ccbb615 修复: 架构文档代码块中缺失的 do 块
3a05c34 修复: 设计文档代码示例中的 do 块缺失和 API 名称错误
6476bed 文档: 输入文档简化 + 约定规范更新
608c4d6 文档: 示例文件按最新设计/语法/代码规范重写
b4c07b8 文档: 标记角色安全/供应链安全/命令函数系统/能力映射指南为已废弃
6e8becc 文档: 配套设计文档按新方案重写
46d34f4 文档: 核心设计文档按新方案重写
3b50354 文档: 架构文档按新方案重写
```

## 当前状态

- 版本：0.4.x（架构重设计 + 标准库重组完成）
- 效应跟踪：AST 标记方案
- 命令调用：`Cmd.<bin>` + fork-exec
- 安全隔离：CLI 参数 + Landlock/mount ns/seccomp
- 缺省导入：`Function.*`、`Nil` 变体
- 标准库：全部模块独立签名文档
- 废弃文档：4 个已标记
