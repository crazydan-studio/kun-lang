# 输入记录：语法规范附件

## 来源

项目维护者，2026-05-30

## 原始指令

按照附件说明调整语法设计，并同步更新相关文档内的语法样例。

## 输入内容

维护者提供的语法规范要求（共 21 项变更）：

| # | 规范要求 | 原始说明 |
|---|---------|---------|
| 1 | 脚本后缀名 | `.kun` |
| 2 | 注释 | `//` 行注释，类型/函数/let/模块上的注释为文档注释，支持 Markdown |
| 3 | 多行字符串 | `'''` 包裹，自动去公共缩进 |
| 4 | 数字分隔 | 下划线分隔，如 `1_000_000`、`20_000u` |
| 5 | 正则字面量 | `` r`...` `` 前缀 + 反引号 |
| 6 | 插值字面量 | `` f`...` `` 前缀 + 反引号 |
| 7 | Path 字面量 | `` p`...` `` 前缀 + 反引号 |
| 8 | `_` 占位符 | 用于解构和模式匹配中的位置占位 |
| 9 | List 解构/展开 | `[a, b, *rest] = list`、`[*la, 0, *lb]` |
| 10 | Map 字面量 | `#{ "a" = 1 }`（`=` 替代 `=>`），不支持解构 |
| 11 | Record 别名解构 | `{x as x1, y as y1} = point` |
| 12 | 泛型参数 | Elm 风格空格分隔，如 `type Result t e`、`Maybe String`、`IO (Result FileType IOError)` |
| 13 | 点调用 | 仅积类型字段投影和元组索引，无函数调用；函数通过模块导入并调用 |
| 14 | 函数类型 | Elm 风格 `Int -> Int -> Int`，无逗号，无 `()` -> 语法 |
| 15 | 参数解构 | `\(x, y) ->`、`\{x, y} ->`、`\[x, y] ->` |
| 16 | Let 绑定 | 单条无 `let`，多条 `let ... in` |
| 17 | 模式匹配 | 形式与解构一致：`[_, y]`、`[1, _, z, *rest]`、`{x = 1, y}` |
| 18 | `?` 操作符 | 标记在函数名之后 |
| 19 | 模块导入 | `import List` / `from List import (map)` 双语法，变体导入 `Maybe(*)`/`Maybe(Just)`，别名 `map as listMap` |
| 20 | 模块导出 | `module List export (map, filter)`、`Maybe(*)` 变体导出 |
| 21 | 权限声明 | 保持不变 |

## 处理结果

- 计划：`docs/plans/plan-syntax-overhaul.md`
- 设计文档：`docs/design/syntax.md` 全量重写
- 关联文档更新：`docs/design/type-system.md`、`docs/design/standard-library.md`、`docs/design/supply-chain-security.md`
- 示例同步：4 个示例文件全量重写
- 跟踪文档：`docs/backlog/index.md`、`docs/context/project-context.md`、`docs/design/feature-inventory.md`
