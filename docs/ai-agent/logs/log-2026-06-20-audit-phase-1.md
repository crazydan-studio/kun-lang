# Phase 1 双代理审计循环

> 日期：2026-06-20 | 类型：审计+修复

## 工作内容

### 第 1 轮：测试完整性审计

Agent A 审计 Phase 1 单元测试，对照 `syntax.md` 语法设计文档，发现 17 项问题：
- **3 个源码 bug**：`/` 和 `%` 列为 `invalid` token、`heapExpr` 返回栈指针导致 segfault、tokenize/parseModule 中 Arena 生命周期错误
- **14 个测试缺口**：TokenKind 类型覆盖不完整（缺 `invalid`/`exclamation` 等）、parser 测试仅计数不验证 AST 结构、运算符优先级测试不完整

Agent B 修复源码后，Agent A 再审计发现 2 个弱测试（export/concat 断言不足），修复后 51 测试全通过。

提交：`7074f45`、`ef0819a`

### 第 2 轮：源码实现正确性审计

Agent A 深度审计源码正确性，发现 15 项问题：
- **P0（3 项）**：整数前缀 `0x`/`0o`/`0b` 未被 `parseInt` 剥离、`??` 运算符在 parser 中缺失、多参数调用语义（tuple 打包 vs 柯里化）
- **P1（6 项）**：字符串转义序列未解释、`[1..10]` 范围字面量错误解析为 spread、字符字面量缺 `\xNN`/`\u{NNNNNN}`、`?` 为 `invalid` token、`.invalid` 静默降级、Duration 无溢出保护
- **P2（6 项）**：parsePattern 静默降级、无递归深度限制、`case` 分支终止逻辑脆弱等

修复：整数前缀剥离、`??` 加入 getPrecedence、`?` 改为独立 TokenKind、字符串转义解释、Duration 改用 parseInt、字符字面量 UTF-8 解码。

提交：`e599fe1`

### 最终状态

| 指标 | 第 1-2 轮后 | 第 8 轮最终 |
|------|-----------|-----------|
| 总测试数 | **68** | **75** |
| 通过率 | **68/68 ✅** | **75/75 ✅** |
| 泄漏 | **0** | **0** |
| P0 修复 | 5 项 | **12 项** |
| P1 修复 | 6 项 | **8 项** |

### 第 3 轮：导出语法与运算符优先级

- export 从 `name=value` 绑定改为纯名称列表 `export (map, filter, fold)` ✅
- `??` 从复用 `.concat` 改为独立 `BinaryOp.nil_coal` 变体 ✅
- 运算符优先级完全对齐 `syntax.md` 优先级表 ✅
- 新增 8 个测试（? token、孤立 #、仅空白、list values、when 守卫、defer、大整数边界）
- 提交：`0fe054c`

### 第 4 轮：构建系统集成

- 修复 `zig build dump-ast` 的 cwd 路径（`run_dump.setCwd`）✅
- 提交：`a15c5a6`

### 第 5 轮：深度代码质量修复

- 大写进制前缀 `0X`/`0O`/`0B` lexer 支持 ✅
- `#{}`/`#[]`/`#()` parsePrefix handler 实现（Map/Set/Group）✅
- 联合类型变体解析添加 `.assign` 终止边界 ✅
- 双行函数定义 `name : Type / name = body` 支持 ✅
- case 分支添加 `let`/`do`/`if`/`assign` 终止边界 ✅
- `set_literal` 类型改为指针一致 ✅
- 提交：`bdc6a0a`

### 第 6 轮：死角清理

- 移除死函数 `exprSpan` ✅
- `typed.zig` 接入 `lib.zig` 编译链 ✅
- 提交：`32cf2e2`

### 第 7 轮：元审计（文档基础设施）

- 补全 backlog Phase 1 工作项 ✅
- 补全 VitePress 计划侧边栏 4 个缺失条目 ✅
- 同步版本历史 ✅
- 提交：`6265b7f`

### 第 8 轮：skipTypeAnn 修复

- `skipTypeAnn` 停止消费 `ident` token（防止吞吃下行函数名）✅
- 修复跨行类型标注 + 函数定义模式 ✅
- 提交：`18aecb7`

## 涉及文件（补充）

- `code/kun-lang/src/ast/ast.zig` — BinaryOp 新增 nil_coal；set_literal 类型修正
- `code/kun-lang/src/lexer/lexer.zig` — 大写前缀、? token、孤立 #、仅空白测试
- `code/kun-lang/src/parser/parser.zig` — export 语法、优先级表、skipTypeAnn、hash_brace handler、联合变体终止、双行函数、case 终止
- `code/kun-lang/src/lib.zig` — typed.zig 接入
- `code/kun-lang/build.zig` — dump-ast cwd
- `docs/.vitepress/config.mts` — 计划侧边栏补全

## 未解问题清单（Phase 2 处理）

| # | 问题 | 严重性 |
|---|------|--------|
| 1 | `record_update`/`range_literal`/`ternary` parser 未实现 | P2 |
| 2 | 多参数调用 tuple 打包 vs 柯里化语义 | P2 |
| 3 | `.invalid` token 静默降级为 `int_literal(0)` | P2 |
| 4 | 无递归深度限制 | P2 |
| 5 | 无输入大小限制（DoS 风险） | P2 |
| 6 | 字节字面量奇数字节数未验证 | P2 |
| 7 | 多行函数应用歧义（换行后标识符被当参数） | P2 |
