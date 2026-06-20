# 首阶段 Zig 代码实现 — build.zig + Lexer + Parser + AST

> 日期：2026-06-20 | 类型：实现

## 工作内容

### 实现文件

| 文件 | 行数 | 说明 |
|------|------|------|
| `code/kun-lang/build.zig` | ~50 | Zig 0.17 构建系统，产出 `kun` + `libkunlang.so` |
| `code/kun-lang/src/main.zig` | ~35 | CLI 入口：`--dump-ast` 子命令 |
| `code/kun-lang/src/lib.zig` | ~4 | `libkunlang.so` 导出 |
| `code/kun-lang/src/ast/ast.zig` | ~120 | AST 节点定义（Expr 联合体 30+ 变体 + 辅助类型） |
| `code/kun-lang/src/ast/typed.zig` | ~60 | 类型化 AST 定义（Phase 2 准备） |
| `code/kun-lang/src/lexer/lexer.zig` | ~710 | 词法分析器：19 个关键字、基础字面量、运算符、前缀字面量、Duration、16 个测试用例 |
| `code/kun-lang/src/parser/parser.zig` | ~780 | 递归下降语法分析器：import/export/type/function 声明 + 30+ 表达式解析函数 |

### 验证

- `zig build` ✅ — 构建通过
- `zig build test` ✅ — 16 个词法测试 + 3 个语法测试通过
- `zig build dump-ast -- <file>` ✅ — 基本 import/let/type/function 声明可解析

### 已知限制（Phase 2+ 解决）

- 复杂嵌套 Record 字面量解析不稳定
- Cmd.\<bin> 语法（`Cmd.git` 等）尚未处理
- f-string 插值表达式未展开
- 表达式末尾未处理的右括号/花括号 fallback 为缺省值
- 无错误恢复（首错误即终止）
- 类型检查器和求值器尚未实现

## 涉及文件

### 新建
- `code/kun-lang/build.zig`
- `code/kun-lang/src/main.zig`
- `code/kun-lang/src/lib.zig`
- `code/kun-lang/src/ast/ast.zig`
- `code/kun-lang/src/ast/typed.zig`
- `code/kun-lang/src/lexer/lexer.zig`
- `code/kun-lang/src/parser/parser.zig`
- `docs/ai-agent/logs/log-2026-06-20-implementation-phase-1.md`

### 修改
- `docs/ai-agent/plans/plan-implementation-phase-1.md`（审计修订）
- `docs/ai-agent/plans/index.md`
- `docs/ai-agent/context/project-context.md`

## 下一步

- Phase 2：类型检查器（HM 类型推断）+ 运行时求值器
- 完善 Parser 以支持全部示例文件解析
- 错误报告系统（i18n 整合）
