# 语法合规审计流程

## 背景

在语法全面调整后，需要对所有设计文档和示例中的 Kun 代码进行全面的语法合规审计。人工逐行检查成本高且容易遗漏，子代理审计 + 人工审核的循环模式可有效保证覆盖率。

## 审计流程

```
子代理检查 → 人工审核 → 修复 → 复查 → 直至通过
```

### 步骤说明

1. **子代理检查**：将 `syntax.md` 的全部语法规则 + 附加约束（禁止模式、类型定义要求）作为 prompt，交给子代理对指定文件列表进行逐行检查
2. **人工审核**：审查子代理报告的每一项违规，确认是否有效
3. **修复**：对确认有效的违规进行修复
4. **复查**：再次交给子代理对同一批文件进行全量检查，确保：
   - 原违规已修复
   - 未引入新违规
5. **通过条件**：连续一轮复查零违规

## 审计范围

每次审计应覆盖以下文件中的 Kun 代码示例（含 fenced code block 和 inline code）：

- `docs/design/syntax.md` — 语法设计文档自身的示例
- `docs/design/type-system.md` — 类型系统文档
- `docs/design/standard-library.md` — 标准库文档
- `docs/design/roles-and-permissions.md` — 安全模型文档
- `docs/design/app-overview.md` — 应用概览
- `docs/design/feature-inventory.md` — 功能清单
- `docs/design/supply-chain-security.md` — 供应链安全
- `docs/architecture/system-baseline.md` — 系统基线
- `docs/architecture/module-boundaries.md` — 模块边界
- `docs/examples/*.md` — 语法使用示例

## 审计检查清单

### 语法规则（源自 `syntax.md`）

| # | 规则 | 禁止形式 | 正确形式 |
|---|------|---------|---------|
| 1 | 注释 | `--`、`#`、`/* */` | `//` |
| 2 | Path 字面量 | `` p`...` ``、`path"..."` | `p"..."` |
| 3 | Regex 字面量 | `` r`...` ``、`regex"..."` | `r"..."` |
| 4 | f-string 字面量 | `` f`...` `` | `f"..."` |
| 5 | 多行字符串 | `'''` | `"""`（插值用 `f"""`） |
| 6 | 泛型语法 | `List<Int>`、`Map<K,V>` | `List Int`、`Map k v`（空格分隔） |
| 7 | 嵌套泛型 | `IO<Result<A,B>>` | `IO (Result A B)`（括号分组） |
| 8 | 函数类型 | `(Int, Int) -> Int`（除非元组参数） | `Int -> Int -> Int` |
| 9 | 函数调用 | `map(\x, list)`（括号+逗号） | `map (\x -> x * 2) list`（空格分隔） |
| 10 | Map 字面量 | `#{ "a" => 1 }` | `#{ "a" = 1 }` |
| 11 | Map 索引 | — | `data["key"]` |
| 12 | 名字绑定 | `let x = y`（单条绑定） | `x = y` |
| 13 | 多条绑定 | — | `let ... in` |
| 14 | List 模式 | `x :: xs`、`head::tail` | `[x, *xs]` |
| 15 | Lambda | `\x, y ->` | `\x y ->`、`\(x, y) ->` |
| 16 | 点调用 | `p.parent()`、`code.isSuccess`、`line.slice 5` | `Path.parent p`、`ExitCode.isSuccess code`、`String.slice 5 line` |
| 17 | 导入 | `from List import (map)` | `import List as L`（模块别名）或 `import List with (map, filter)`（精选导入），不可组合 |
| 18 | 导出 | `pub` 关键字 | `module ... export (...)` |
| 19 | `?` 操作符 | `(expr)?` | `funcName? args`（函数名后）；`name <-? expr`（绑定）；Stream 上不支持，用 `filterMap identity` |
| 20 | `<-` 解包 | — | `name <- expr` 仅 IO；`name <-? expr` IO + Result |
| 21 | 无参函数类型 | `() -> T` | 无。改用绑定或 `IO T` |
| 22 | 类型别名 | `type alias` | 仅 `type LongFunc = ...`（函数类型） |
| 23 | Record 类型别名 | `type Point = { x, y }` | `type Point = Point { x, y }`（Newtype）或内联 |
| 24 | 管道 | bare `\|` | `\|>` / `<\|` |
| 25 | 函数组合 | — | `>>`（从左向右）、`<<`（从右向左） |
| 26 | `stream` 关键字 | `stream expr` | 已移除。用 `Stream.fromList`/`Stream.readLines` |
| 27 | IO Stream 消费 | — | IO Stream 必须 `<-` 解包后消费 |

### 附加约束

- 多处使用到同结构的 Record 类型应定义为 Newtype 或 ADT，而非重复内联
- 禁止使用已明确废弃的语法形式

## 常见违规模式

| 模式 | 典型出处 | 修复方式 |
|------|---------|---------|
| `--` 注释 | ADT 定义中的字段注释 | 改为 `//` |
| `#` 注释 | 安全模型文档中的脚本注释 | 改为 `//` |
| `let x = ...`（单条） | 权限作用域示例 | 去掉 `let` |
| `func(arg)`（带括号） | 命令调用示例 | 改为 `func arg`（空格分隔） |
| 字符串路径 | 命令调用参数 | 改为 `p"..."` |
| bare `\|` 管道 | 命令行示例 | 改为 `\|>` |
| 反引号前缀 | 字面量示例 | 改为双引号 `p"..."`/`r"..."`/`f"..."` |

## 参考

- 审计规范见 `docs/context/conventions.md`
- 语法设计权威文档：`docs/design/syntax.md`
