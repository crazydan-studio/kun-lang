# 语法使用示例

本目录存放 Kun 语言的语法使用示例，覆盖全部语法模式。

## 示例文件

| 示例 | 覆盖范围 |
|------|---------|
| [综合语法：日志文件处理器](file-processor) | 注释 / 字面量 / ADT / 类型标注 / Lambda / case / 管道 / do / Record 操作 / 导入 / 权限 / 流 / `?` 操作符 / 运算符 / **f-string 插值与格式化** |
| [类型系统聚焦](type-showcase) | ADT 四种字段风格 / Newtype / 泛型 / Let-多态 / 显式转换 / 类型收窄 / 种类 |
| [IO 与效应系统](networking) | do 记法 / `?` 错误传播 / 权限三级粒度 / Signal / Port / Pid / SocketAddr / Stream / DateTime / Duration / **f-string 插值** |
| [模式匹配专题](pattern-matching) | 穷举 / 通配 / 变体 / List cons / 守卫 / 元组解构 / Record 解构 / 嵌套 / 字面量 / 类型收窄 / **f-string 插值** |

> 这些示例为语法设计文档 `docs/design/syntax.md` 的配套代码，旨在通过完整的使用场景展示 Kun 语言的全部语法模式。
