# 日志：全面审计修复与语法检查大会战

## 日期与会话信息

- **日期**：2026-06-05
- **会话类型**：审计修复 + 语法检查 + 代码修正
- **提交者**：`AI <ai@kun-lang.crazydan.io>`

## 工作内容

### 1. 全面清理 CDF 过时引用

废弃 CDF 方案后，`roles-and-permissions.md`、`system-baseline.md`、`supply-chain-security.md`、`feature-inventory.md` 中仍有大量 CDF 引用。统一更新为 `.cmd.kun` / 命令签名 / Builder API 等新术语。

### 2. 多轮语法检查与修正

对 `design/`、`examples/`、`architecture/` 下所有 ` ```kun ` 代码块进行多轮迭代扫描：

| 批次 | 发现 | 主要问题 |
|------|------|---------|
| 1 | 6 处 | `>>=` 伪代码标记、`<-!` 脱离 `do`、IO 操作缺少 `do`、行变量写法 |
| 2 | 4 处 | 废弃文档 `let without in`、`as` 导出、管道顺序 |
| 3 | 5 处 | `run2`→`run1`、`withEnv`/`withRunAs` 签名缺失、`followSymlinks` 缺省值 |
| 4 | 8 处 | `f` 前缀、`Any`→`a`、`let` 标注、Record 空格、代码块标签、Config 构造器 |
| 5 | 2 处 | walkDir 脱离 `do` 块 |
| 6 | 5 处 | `run1`/`run2` IO 类型修正、`case` 分支顺序、`e.name`→`e.path`、反引号注释 |
| 7 | 3 处 | 注释名不符、废弃文档同步 |

### 3. `.cmd.kun` 设计完善

- 简化声明顺序约束（仅 `command`/`import` 两条硬性限制）
- 补充 `withFlag` 语义注释、`stdout`/`stderr` 缺省说明
- 补充声明顺序规则文档
- 完善编译器封装步骤（扩展积类型注入、隐式字段覆盖）

### 4. 语法扩展

- `Path ++` 拼接操作
- Record `{a, ..rest}` 解构语法
- `?(Result T E)` 语法规则

### 5. 命令模块导出控制

- Record 字段级导出语法（对称 ADT 语法：`Command(field1, field2)` / `Command(..)`）
- `withRunAs`/`withEnv` 不导出给 `.cmd.kun`，仅 `InternalCommand` 使用
- `InternalCommand` 编译器私有访问机制：编译期规则 + 模块导出控制 + 编译器特权
- `command` 声明 `with` → `for`（语义更准确）

### 6. 幻影类型替代 `CommandType`

- `Stream`/`Document` 幻影类型替代 `CommandType` ADT
- `Command a` → `Command mode a`
- 编译器通过函数签名中的幻影类型选择行流/文档处理路径
- 保留 `InternalCommand.run1`/`run2` 封装逻辑复用
- `createStreamCommand`/`createDocumentCommand` → `asStream`/`asDocument`

### 7. 幻影类型系统文档

- `type-system.md`：幻影类型定义、零变体 ADT 机制
- 导入导出规则、模式匹配限制
- 通用场景示例（单位标记、格式标记）
- 幻影类型 vs ADT 选用对比

## 已修改文件清单

```
docs/ai-agent/architecture/system-baseline.md
docs/ai-agent/design/command-function-system.md
docs/ai-agent/design/command-signature-system.md
docs/ai-agent/design/feature-inventory.md
docs/ai-agent/design/roles-and-permissions.md
docs/ai-agent/design/standard-library.md
docs/ai-agent/design/supply-chain-security.md
docs/ai-agent/design/syntax.md
docs/ai-agent/design/type-system.md
docs/ai-agent/examples/file-processor.md
docs/ai-agent/examples/type-showcase.md
docs/ai-agent/input/input-command-function-design.md
docs/ai-agent/context/project-context.md
docs/.vitepress/config.mts
```

## 下一步计划

- 进入实现阶段（类型检查器/解析器/运行时原型）
- PlantUML 图表补全
