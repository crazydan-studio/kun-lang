# 日志：CDF→Kun 代码生成设计与命令函数系统定稿

## 日期与会话信息

- **日期**：2026-06-03
- **会话类型**：设计（CDF 代码生成 + 命令函数系统）
- **提交者**：`AI <ai@kun-lang.crazydan.io>`

## 工作内容

### CDF→Kun 代码生成设计

对 CDF 格式进行了全面重写，从运行时解析改为编译期代码生成：

| 设计决策 | 结论 |
|---------|------|
| CDF 定位 | 编译期代码生成源，转译为 Kun 模块 |
| `option` 映射 | `option <name> "<flag>" : T[!] [with (v)]`，只映射短名或长名 |
| `param <N>` | 确定位置，始终必填，不使用 `!` |
| `param *` | `param * : List T`，显式 `List` |
| `validator` | `Validator t` 纯函数，不可涉及 IO |
| `parser` | 纯函数 `Stream String -> Stream (Result T String)` |
| `output <name>` | 引用 `parser`；内置 `default`/`json` |
| `type` 字段名 | 直接命名，不受关键字限制 |
| `command <name>` | 同名时省略二进制名 |
| 子命令命名 | `<main>_<sub1>_<sub2>` |
| 子命令选项 | 不继承父命令，独立声明 |
| Bool 缺省 | `false`，不在类型定义中体现 |
| `module` 声明 | 在文件开头 |

### 命令函数实现方式分类

| 实现方式 | 新增覆盖 | 原理 |
|---------|---------|------|
| 内建 Primitive | `ps`、`lscpu`、`uptime`、`locate`、`walkDir`（替代 `find`） | 直接调用内核 API |
| CDF 映射 | `curl`、`dig`、`rsync`、`tar`、`gzip`、`ss` 等 | 外部命令 + parser 解析 |

### 验证器系统

- `Validator t` 类型 + `all`/`any`/`not` 组合器 + 内置验证器
- `include`/`exclude` 替代 `enum`，支持泛型 `List t -> Validator t`
- `regex` 验证器使用 `Regex` 类型（`r"..."` 字面量）

### Record 缺省值语法移除

- `{ name : String = "default" }` 语法已移除
- 改为通过类型模块导出构造默认对象的函数
- 验证器和解析器中涉及 `()` 的内容统一使用 `Unit`

## 已修改文件清单

| 文件 | 变更 |
|------|------|
| `design/command-signature-system.md` | CDF 格式重写、代码生成规则、覆盖范围更新 |
| `design/standard-library.md` | Validator 纯函数约束、CDF 示例更新 |
| `design/feature-inventory.md` | CDF→Kun 代码生成、内建 Primitive 范围更新 |
| `discussions/discussion-cdf-code-generation.md` | 13 个议题的讨论记录 |
| `discussions/index.md` | 新增入口 |
| `.vitepress/config.mts` | 侧边栏新增 CDF 代码生成入口 |
| `context/project-context.md` | 最近完成记录更新 |
| `logs/log-2026-06-02-design-audit-fixes.md` | 追加 CDF 代码生成内容 |
