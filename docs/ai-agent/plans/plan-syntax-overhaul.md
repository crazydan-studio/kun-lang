# 执行计划：语法全面调整

## 背景

根据维护者新规，Kun 的语法需要从当前风格全面迁移到新约定。涉及：注释、字面量引用符号、泛型语法、函数类型标注、函数应用、模式匹配、解构语法、模块系统等 21 项变更。

## 变更总览

| # | 变更 | 旧语法 | 新语法 | 影响文件数 |
|---|------|--------|--------|-----------|
| 1 | 注释标记 | `--` | `//` | 7 |
| 2 | Path 字面量 | `path"..."` | `` p`...` `` | 4 |
| 3 | Regex 字面量 | `` regex`...` `` | `` r`...` `` | 3 |
| 4 | 插值字面量 | `f"..."` | `` f`...` `` | 5 |
| 5 | 泛型语法 | `List<Int>` | `List Int` | 10 |
| 6 | 泛型语法（嵌套） | `IO<Result<A, B>>` | `IO (Result A B)` | 10 |
| 7 | List 解构 | `x :: xs` | `[x, ..xs]` | 4 |
| 8 | Map 字面量 | `#{ "a" => 1 }` | `#{ "a" = 1 }` | 3 |
| 9 | 导入语法 | `import List as L` | `from List import (map)` 等 | 3 |
| 10 | 函数类型 | `(Int, Int) -> Int` | `Int -> Int -> Int` | 4 |
| 11 | 函数应用 | `map(\x, list)` | `map (\x) list` | 6 |
| 12 | 点调用 | `p.parent()` | `Path.parent p` | 6 |
| 13 | 多行字符串 | —（新增） | `'''...'''` | 1 |
| 14 | 数字分隔 | —（新增） | `1_000_000` | 1 |
| 15 | let 绑定 | `let x = y`（单行用 let） | `x = y`（单行无 let） | 1 |
| 16 | 多 let 绑定 | —（新增） | `let ... in` | 1 |
| 17 | Record 别名解构 | —（新增） | `{x as x1}` | 2 |
| 18 | 模块声明 | —（新增） | `module M export (...)` | 1 |
| 19 | `?` 操作符 | `expr?` | `函数名? 参数` | 2 |
| 20 | 参数直接解构 | —（新增） | `\(x, y) ->`, `\{x, y} ->` | 2 |

## 变更范围

| 操作 | 文件 | 说明 |
|------|------|------|
| 重写 | `docs/ai-agent/design/syntax.md` | 全部 21 项变更，语法设计的权威文档 |
| 重写 | `docs/ai-agent/examples/file-processor.md` | 全部语法更新 |
| 重写 | `docs/ai-agent/examples/type-showcase.md` | 泛型/函数类型/ADT 语法更新 |
| 重写 | `docs/ai-agent/examples/networking.md` | 函数调用/插值/泛型更新 |
| 重写 | `docs/ai-agent/examples/pattern-matching.md` | 模式匹配/解构语法更新 |
| 修改 | `docs/ai-agent/design/type-system.md` | 泛型语法、函数类型、`?` 语法、所有代码块 |
| 修改 | `docs/ai-agent/design/standard-library.md` | 类型签名中的泛型语法 |
| 修改 | `docs/ai-agent/design/app-overview.md` | 示例代码片段 |
| 修改 | `docs/ai-agent/examples/index.md` | 覆盖范围描述 |
| 修改 | `docs/ai-agent/architecture/system-baseline.md` | 同步类型概览语法 |
| 修改 | `docs/ai-agent/architecture/module-boundaries.md` | 同步语法引用 |
| 修改 | `docs/ai-agent/context/project-context.md` | 同步语法引用 |
| 修改 | `docs/ai-agent/design/supply-chain-security.md` | 同步示例 |
| 修改 | `docs/ai-agent/design/roles-and-permissions.md` | 同步权限语法 |
| 修改 | `docs/ai-agent/design/feature-inventory.md` | 更新语法状态 |

## 实施步骤

### Step 1: 更新语法设计文档 `docs/ai-agent/design/syntax.md`

按顺序重写各章节：

1. **注释** — `//` 行注释 + doc comment 约定（类型/函数/let/模块上的 `//` 均为文档注释，内容支持 markdown）
2. **字面量** — 所有前缀改为反引号：Path `` p`...` ``、Regex `` r`...` ``、f-string `` f`...` ``；新增 `'''` 多行字符串、`_` 数字分隔
3. **容器字面量** — Map `=` 替代 `=>`：`#{ "a" = 1 }`
4. **泛型** — `Container Type` 替代 `Container<Type>`，嵌套用括号 `IO (Result A B)`
5. **类型声明/ADT** — 泛型空格分隔：`type Result t e = Ok t | Err e`
6. **类型标注** — 删除 `(T1, T2) -> T3` 风格，统一 Elm 柯里化 `Int -> Int -> Int`（除非参数本身为元组）
7. **函数定义与应用** — 空格分隔参数，无逗号：`add x y`
8. **Lambda** — 参数直接解构：`\(x, y) ->`、`\{x, y} ->`、`\[x, y] ->`
9. **Let 绑定** — 单行无 `let`，多行 `let ... in`
10. **模式匹配** — List `[a, ..rest]`、Record `{x as x1, y}`、元组 `(1, y)`
11. **List 解构/展开** — `[a, b, ..rest] = list`、`[..la, 0, ..lb]`
12. **Record 解构别名** — `{x as x1, y as y1} = point`
13. **点调用** — 仅字段投影/元组索引，删除方法调用
14. **管道** — `|>` 保持不变
15. **`?` 操作符** — 标记在函数名后
16. **模块导入** — `import List` / `from List import (map)` 双语法，变体导入 `Result(Ok)`，别名 `map as listMap`
17. **模块导出** — `module List export (map, filter)` 声明
18. **权限声明** — 不变
19. **Stream** — 不变
20. **一致性决议表** — 更新所有条目

### Step 2: 更新类型系统文档 `docs/ai-agent/design/type-system.md`

- 全局泛型语法：`List<T>` → `List t`，`?String` 替代 `Maybe String`；`IO<Result<FileType, IOError>>` → `IO (Result FileType IOError)`
- 函数类型：`(Int, Int) -> Int` → `Int -> Int -> Int`
- Path 字面量：`path"..."` → `` p`...` ``
- 注释：`--` → `//`
- `?` 语法：`expr?` → 函数名后

### Step 3: 更新标准库文档 `docs/ai-agent/design/standard-library.md`

- 泛型语法：`Result<T, E>` → `Result t e`
- 类型签名更新

### Step 4: 更新其他设计文档

- `app-overview.md`：同步示例代码
- `roles-and-permissions.md`：同步权限示例
- `supply-chain-security.md`：同步示例
- `feature-inventory.md`：更新语法状态行

### Step 5: 重写全部四个示例文件

- `file-processor.md`：全量更新（注释、字面量、泛型、函数调用、导入、模式匹配、点调用）
- `type-showcase.md`：全量更新（ADT 语法、泛型、函数类型、let、`?`）
- `networking.md`：全量更新（函数调用、插值、do 记法、权限语法）
- `pattern-matching.md`：全量更新（List/Record/元组模式、守卫、嵌套）

### Step 6: 更新其余引用

- `architecture/system-baseline.md`、`module-boundaries.md`
- `context/project-context.md`
- `examples/index.md`

### Step 7: 验证

```bash
pnpm lint && pnpm build && git commit
```

## 关键设计决策

### 泛型括号规则

```kun
// 旧: List<Int>, IO<Result<FileType, IOError>>
// 新: List Int, IO (Result FileType IOError)
```

### 函数类型与应用规则

```kun
// 旧: add : (Int, Int) -> Int    add(x, y)
// 新: add : Int -> Int -> Int    add x y
```

### 点调用限制

```kun
// 旧: path"/tmp".parent()    record.name    tuple.0
// 新: Path.parent p`/tmp/foo`               record.x      tuple.0
```

`.` 仅保留字段投影（Record 字段、元组索引）。

### 包管理

```kun
from List import (map, filter)       // 限定导入
from List import (map as listMap)    // 别名导入
from Result import (Result(..))       // 导入全部变体
from Result import (Result(Ok))      // 仅导入 Ok 变体
```

## 审计要点

1. 所有类型标注中的泛型语法是否全部迁移（无遗留 `<>`）
2. 所有函数调用是否移除逗号（除元组参数外）
3. 所有 Path/Regex/f-string 字面量是否改为反引号
4. 所有 `--` 注释是否改为 `//`
5. 所有 List 模式是否改为 `[x, ..xs]` 形式（无遗留 `::`）
6. 所有 Map 字面量是否改为 `=`（无遗留 `=>`）
7. 所有导入语句是否更新为 `from ... import` 或新语法
8. 所有点调用方法是否为纯字段投影/元组索引（无方法调用）
