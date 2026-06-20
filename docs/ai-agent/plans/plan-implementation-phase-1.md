# 执行计划：首阶段实现 — 项目骨架 + 词法分析器 + 语法分析器 + AST

## 背景与目标

Kun 语言的设计阶段已全部完成定型。`code/kun-lang/` 的目录结构与模块划分已在 README 中定义，但所有 `.zig` 源文件尚未创建。

**目标**：建立 Zig 构建系统 + 可运行的最小 `kun` CLI 入口，实现词法分析器（源码→Token）、AST 节点定义、语法分析器（Token→AST），并可通过 `zig build dump-ast` 解析示例 `.kun` 文件输出 AST dump 验证。

**产出**：`kun` 可执行文件接受 `--dump-ast <file.kun>` 参数，输出源码的 AST 结构化表示。

## 变更范围

### 新建文件

| 文件 | 行数（估） | 说明 |
|------|-----------|------|
| `code/kun-lang/build.zig` | ~80 | 构建系统：`kun` 可执行文件 + `libkunlang.so` 共享库 |
| `code/kun-lang/src/main.zig` | ~60 | CLI 入口：子命令路由（`dump-ast` / `--help`） |
| `code/kun-lang/src/lib.zig` | ~30 | `libkunlang.so` 导出公共 API（`tokenize` / `parse`） |
| `code/kun-lang/src/lexer/lexer.zig` | ~550 | 词法分析器：源码字符扫描 → Token 序列 |
| `code/kun-lang/src/ast/ast.zig` | ~450 | AST 节点定义（Expr 联合体 + 辅助类型 + Span + 位置信息） |
| `code/kun-lang/src/ast/typed.zig` | ~120 | 类型化 AST（TypedExpr + Type 联合体，先留空定义） |
| `code/kun-lang/src/parser/parser.zig` | ~1000 | 语法分析器：Token 序列 → AST（递归下降） |

### 暂不实现（Phase 2+）

- 类型检查器（`src/typecheck/`）— Phase 2
- 求值器 / 运行时（`src/runtime/`）— Phase 2
- 命令系统（`src/command/`）— Phase 3
- CLI 参数解析引擎（`src/cli/`）— Phase 3
- 安全子系统（`src/security/`）— Phase 3
- i18n（`src/i18n/`）— Phase 4
- 标准库 Primitive 绑定（`src/stdlib/`）— Phase 4

### 不修改的文件

- `code/README.md` — 目录结构说明已准确
- `code/kun-lang/README.md` — 模块组织已准确
- 所有 `docs/ai-agent/` 设计文档 — 当前阶段不涉及设计变更

## 实施步骤

### Step 1: 创建 `build.zig`

**前置依赖**：无

要点：
- 目标平台 `linux-x86_64`
- 可执行文件 `kun`：入口 `src/main.zig`
- 共享库 `libkunlang.so`：入口 `src/lib.zig`
- 在 `build.zig` 中通过 `comptime` 断言限制最低 Zig 版本为 0.17.0-dev
- `zig build` 构建全部；`zig build dump-ast -- <file>` 构建并 dump AST
- `zig build test` 运行全部单元测试
- 引用 `code/examples/` 作为默认测试输入目录

**验证**：`zig build` 成功，生成 `zig-out/bin/kun` 可执行文件

### Step 2: 定义 AST 节点

**前置依赖**：Step 1（仅为编译通过）

`ast.zig` 定义辅助类型和 `Expr` 联合体，完整覆盖语法设计文档中的全部表达式形式。

#### 2.1 位置信息

```zig
pub const SourceLoc = struct {
    line: u32,  // 1-based
    col: u32,   // 1-based
    offset: usize,  // 源文件字节偏移（0-based）
};

pub const Span = struct {
    start: SourceLoc,
    end: SourceLoc,
};
```

#### 2.2 辅助类型

```zig
pub const DurationUnit = enum { sec, ms, min, hour, day, us, ns };

pub const Stmt = struct {
    kind: union(enum) {
        binding: struct {},
        defer_: struct { expr: *const Expr },
        expr: *const Expr,
    },
    span: Span,
};

pub const Param = struct {
    name: []const u8,
    span: Span,
};

pub const Binding = struct {
    name: []const u8,
    value: *const Expr,
    span: Span,
};

pub const Branch = struct {
    pattern: *const Pattern,
    guard: ?*const Expr,
    body: *const Expr,         // bound 分支的单表达式 / unbound 分支的隐式 do
    is_unbound: bool,
    span: Span,
};

pub const Pattern = union(enum) {
    wildcard: Span,
    literal: *const Expr,
    ident: struct { name: []const u8, span: Span },
    variant: struct { name: []const u8, arg: ?*const Pattern, span: Span },
    list: struct { items: []const Pattern, rest: ?*const Pattern, span: Span },
    tuple: struct { items: []const Pattern, span: Span },
    record: struct { fields: []const struct { name: []const u8, pattern: *const Pattern }, span: Span },
    guard: struct { inner: *const Pattern, cond: *const Expr, span: Span },
};
```

#### 2.3 Expr 联合体

```zig
pub const Expr = union(enum) {
    int_literal: struct { value: i64, span: Span },
    float_literal: struct { value: f64, span: Span },
    string_literal: struct { value: []const u8, span: Span },
    bool_literal: struct { value: bool, span: Span },
    char_literal: struct { value: u21, span: Span },
    nil_literal: Span,
    duration_literal: struct { value: i64, unit: DurationUnit, span: Span },
    path_literal: struct { value: []const u8, span: Span },
    regex_literal: struct { value: []const u8, span: Span },
    bytes_literal: struct { value: []const u8, span: Span },
    ident: struct { name: []const u8, span: Span },
    lambda: struct { params: []const Param, body: *const Expr, span: Span },
    call: struct { func: *const Expr, arg: *const Expr, span: Span },
    let_in: struct { bindings: []const Binding, body: *const Expr, span: Span },
    do_block: struct { body: []const Stmt, result: ?*const Expr, span: Span },
    if_expr: struct { cond: *const Expr, then: *const Expr, else_: *const Expr, span: Span },
    case_expr: struct { subject: *const Expr, branches: []const Branch, span: Span },
    pipe: struct { left: *const Expr, right: *const Expr, span: Span },
    pipe_reverse: struct { left: *const Expr, right: *const Expr, span: Span },  // <|
    compose: struct { left: *const Expr, right: *const Expr, span: Span },        // >>
    compose_reverse: struct { left: *const Expr, right: *const Expr, span: Span },// <<
    binary_op: struct { op: BinaryOp, left: *const Expr, right: *const Expr, span: Span },
    unary_op: struct { op: UnaryOp, operand: *const Expr, span: Span },
    list_literal: struct { items: []const ExprItem, span: Span },
    tuple_literal: struct { items: []const Expr, span: Span },
    record_literal: struct { fields: []const RecordField, span: Span },
    record_access: struct { record: *const Expr, field: []const u8, span: Span },
    record_update: struct { record: *const Expr, fields: []const RecordField, span: Span },
    map_literal: struct { entries: []const MapEntry, span: Span },
    set_literal: struct { items: []const Expr, span: Span },
    range_literal: struct { from: *const Expr, to: *const Expr, step: ?*const Expr, span: Span },
    ternary: struct { cond: *const Expr, then: *const Expr, else_: *const Expr, span: Span },
};
```

- 所有节点带 `Span`
- 节点通过 Arena 分配器管理生命周期
- 嵌套子表达式使用 `*const Expr` 指针（非值复制）

### Step 3: 实现词法分析器

**前置依赖**：Step 1, Step 2

对照 `docs/ai-agent/design/syntax.md` "词法分析" 节和 "字面量" 节，实现：

| Token 类别 | 优先级 | 说明 |
|-----------|--------|------|
| 关键字 | P0 | `type`, `case`, `of`, `if`, `then`, `else`, `do`, `in`, `let`, `defer`, `import`, `export`, `as`, `when`, `not`, `true`, `false`, `Nil` |
| 标识符 | P0 | 小写开头为变量/函数，大写开头为类型/变体/模块 |
| 整数/浮点/字符串/字符/Bool/Nil 字面量 | P0 | 涵盖全部基础字面量 |
| 运算符 | P0 | `\|>`, `<\|`, `>>`, `<<`, `++`, `?.`, `??`, `&&`, `\|\|`, `==`, `/=`, `<=`, `>=`, `+`, `-`, `*`, `/`, `%`, `=`, `:`, `.`, `,`, `\|`, `\`, `->` 等 |
| 括号定界符 | P0 | `(`, `)`, `[`, `]`, `{`, `}`, `#(`, `#[`, `#{` |
| 多字符运算符最长匹配 | P0 | `->` 不匹配 `-` + `>`；`\|\|` 不匹配 `\|` 两次 |
| 多行字符串 `"""` | P0 | 含公共缩进移除逻辑 |
| 前缀字面量 | P0 | `p"..."`, `f"..."`, `f"""..."""`（示例文件必须） |
| Duration 字面量 | P0 | `5s`, `100ms`, `2h`, `30m`, `1d`, `500us`, `200ns`（示例文件必须） |
| 注释 | P0 | `//` 跳过至行尾 |
| `r"..."` 正则字面量 | P1 | P0 示例未使用 |
| Bytes 字面量 `0x...` | P1 | P0 示例未使用 |
| `#{}` Map / `#[]` Set 定界符 | P1 | P0 示例未使用 |
| 错误恢复 | P1 | 非法字符报告但不 panic |

核心函数签名：
```zig
pub const Token = struct {
    kind: TokenKind,
    slice: []const u8,  // 直接引用 source，不额外分配
    span: Span,
};

pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) ![]const Token
```

**验证**：
```zig
test "lexer" {
    const tokens = try tokenize(allocator, "42 + 1");
    // assert tokens == [Int(42), Op(+), Int(1)]
}
```
`zig build test` 通过。

### Step 4: 实现语法分析器

**前置依赖**：Step 1, Step 2, Step 3（依赖 Token 类型和 AST 定义）

#### 4.1 顶层入口

新增模块级入口函数，处理顶层声明后再进入表达式解析：

```zig
pub const Decl = union(enum) {
    import: struct { module: []const u8, alias: ?[]const u8, span: Span },
    export: struct { bindings: []const Binding, span: Span },
    type_def: struct { name: []const u8, def: *const TypeDef, span: Span },
    function_def: struct { name: []const u8, params: []const Param, return_type: ?*const TypeAnn, body: *const Expr, span: Span },
};

pub fn parseModule(allocator: std.mem.Allocator, tokens: []const Token) ![]const Decl
```

#### 4.2 表达式解析函数

递归下降语法分析器，对照 `docs/ai-agent/design/syntax.md` 全部语法节实现：

| 解析函数 | 优先级 | 说明 |
|---------|--------|------|
| `parseExpr` | P0 | 顶层表达式入口，调度各具体解析函数 |
| `parseIntLiteral` | P0 | 整数字面量（10/16/8/2 进制 + `_` 分隔） |
| `parseFloatLiteral` | P0 | 浮点数字面量 |
| `parseStringLiteral` | P0 | 字符串 + 转义序列 |
| `parsePrefixLiteral` | P0 | `p"..."`, `f"..."`（示例文件必须） |
| `parseDurationLiteral` | P0 | `5s`, `100ms`（示例文件必须） |
| `parseMultilineString` | P0 | `"""..."""` 含 `f"""..."""` |
| `parseIdent` | P0 | 标识符 |
| `parseLambda` | P0 | `\args -> body` |
| `parseCall` | P0 | `func arg`（空格分隔应用） |
| `parseLetIn` | P0 | `let <bindings> in <expr>` |
| `parseDoBlock` | P0 | `do <body>` / `do <body> in <expr>` |
| `parseIf` | P0 | `if cond then then_expr else else_expr` |
| `parseCase` | P0 | `case subject of <branches>` |
| `parseBinaryOp` | P0 | Pratt parser 按 `syntax.md` 优先级表 |
| `parseUnaryOp` | P0 | `-` / `not` |
| `parseListLiteral` | P0 | `[a, b, c]` 含 `..rest` 解构 |
| `parseTupleLiteral` | P0 | `(a, b, c)` |
| `parseRecordLiteral` | P0 | `{ field = value }` |
| `parseRecordAccess` | P0 | `expr.field` |
| `parsePipe` | P0 | `\|>`, `<\|`, `>>`, `<<` |
| `parseMapLiteral` | P1 | `#{ "key" = value }` |
| `parseSetLiteral` | P1 | `#[a, b, c]` |
| `parseRegexLiteral` | P1 | `r"..."` |
| `parseBytesLiteral` | P1 | `0x...` |
| `parseRangeLiteral` | P1 | `[1..10]` |
| `parseTernary` | P1 | `? :` |
| `parseRecordUpdate` | P1 | `{ record \| field = val }` |
| 错误恢复 | P2 | 基本错误恢复（同步点） |

核心函数签名：
```zig
pub fn parseModule(allocator: std.mem.Allocator, tokens: []const Token) ![]const Decl
```

**验证**：
1. `zig build test` — 内置测试覆盖所有 P0 表达式
2. `zig build dump-ast -- code/examples/k8s-deploy/deploy.kun` — 输出合法 AST
3. `zig build dump-ast -- code/examples/monorepo-ci/build.kun` — 输出合法 AST

### Step 5: CLI 驱动与 AST dump

**前置依赖**：Step 1–4

`main.zig` 实现：
- `--dump-ast <file.kun>`：词法分析 + 语法分析 → 打印 AST 结构化表示（JSON 或调试格式）
- `--help`：显示使用说明
- 默认（无子命令）：提示使用方式

`lib.zig` 导出：
```zig
pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) ![]const Token
pub fn parseModule(allocator: std.mem.Allocator, tokens: []const Token) ![]const Decl
```

**验证**：
```bash
cd code/kun-lang
zig build dump-ast -- code/examples/k8s-deploy/deploy.kun
# 应输出结构化 AST 表示
```

### Step 6: 更新元数据

- `plans/index.md`：新增本计划条目（已完成）
- `context/project-context.md`：更新活跃工作与任务路由记录

## 验证方法

| 验证项 | 方法 |
|--------|------|
| 构建通过 | `cd code/kun-lang && zig build` |
| 单元测试 | `cd code/kun-lang && zig build test` |
| AST dump | `zig build dump-ast -- <file.kun>` 输出合法结构化 AST |
| 示例覆盖 | 验证 `code/examples/k8s-deploy/deploy.kun` 和 `code/examples/monorepo-ci/build.kun` 可完整解析 |
| 错误报告 | 传入非法 `.kun` 文件，验证词法/语法错误位置与描述 |
| 边界 | 空文件、仅注释、超大数字、深嵌套、全局 Unicode |

## 分期里程碑

| 阶段 | 文件 | 验证标准 |
|------|------|---------|
| M1: 骨架 | `build.zig` + `main.zig` + `lib.zig` | `zig build` 通过，输出 `zig-out/bin/kun` |
| M2: AST | `ast/ast.zig` + `ast/typed.zig` | 编译通过，AST 定义完整覆盖语法文档的全部表达式形式 |
| M3: 词法 | `lexer/lexer.zig` | `zig build test` 通过，P0 token 全覆盖 + 至少 10 个测试用例 |
| M4: 语法 | `parser/parser.zig` | `zig build test` 通过，可完整解析两个示例目录的全部 `.kun` 文件 |
| M5: 集成 | 全部文件 | `zig build dump-ast` 对示例文件输出合法 AST |

## 风险评估

| 风险 | 缓解措施 |
|------|---------|
| Zig 0.17.0-dev API 不稳定（尤其 I/O 和文件系统 API 重命名） | 对照 `zig-patterns.md` 的 0.13→0.17 变更摘要，使用标记 switch 和新式 `Io` API |
| AST 定义与语法文档不一致 | 逐节对照 `syntax.md` 实现，实施后子代理审计交叉一致性 |
| 运算符优先级歧义 | Pratt parser 按 `syntax.md` 优先级表实现，测试验证结合性 |
| Arena 分配器生命周期管理 | 按 `zig-patterns.md` 规范，公开函数显式接收 allocator 参数 |
| 递归下降导致栈溢出（深嵌套） | 标记 switch 结合 `continue` 尾递归消除；设置递归深度限制告警 |
| P0 范围评估偏差导致示例文件无法完整解析 | 审计后已将 `p"..."`/`f"..."`/Duration/多行字符串提至 P0，确保示例覆盖率 |

## 审计要点

1. AST 节点定义是否完整覆盖 `syntax.md` 中所有表达式形式
2. Token 类型是否完整覆盖词法分析章节列出的所有类别
3. 运算符优先级和结合性是否与 `syntax.md` 一致
4. 递归下降解析器的错误恢复策略
5. `build.zig` 的 Zig 版本约束是否正确
6. P0/P1 优先级划分是否合理——P0 是否足以解析示例目录的全部文件
7. `parseModule` 的声明解析是否覆盖 `import`/`export`/`type`/函数定义

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.20 | 审计修订：补齐 AST 节点（list/tuple/record/access/binary/unary 等 + 辅助类型）、调整 P0/P1 划分、新增顶层声明入口、修正文件路径、明确定义 Span/辅助类型 |
| 2026.06.20 | 初始版本 |
