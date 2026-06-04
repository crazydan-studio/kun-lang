# 语法使用示例

本目录存放 Kun 语言的语法使用示例，覆盖全部语法模式。

## 示例文件

| 示例 | 覆盖范围 |
|------|---------|
| [综合语法：日志文件处理器](file-processor) | `//` 注释 / 字面量前缀 / ADT 空格泛型 / 类型标注 / Lambda 解构 / case 新语法 / 管道 / do / Record 操作 / 模块导入 / 权限 / 流 / `?` 操作符 / f-string 格式化 |
| [类型系统聚焦](type-showcase) | ADT 四种字段风格 / Newtype / 泛型空格分隔 / Let-多态 / 显式转换 / 类型收窄 / 种类 / Elm 风格函数类型 |
| [IO 与效应系统](networking) | do 记法 / `?` 错误传播 / 权限三级粒度 / Signal / Port / Pid / SocketAddr / Stream / DateTime / Duration / f-string 插值 |
| [模式匹配专题](pattern-matching) | 穷举 / 通配 / 变体 / List `..rest` 模式 / 守卫 / 元组解构 / Record 解构 `as` 别名 / 嵌套 / 字面量 / 类型收窄 |

> 这些示例为语法设计文档 `docs/ai-agent/design/syntax.md` 的配套代码，旨在通过完整的使用场景展示 Kun 语言的全部语法模式。
