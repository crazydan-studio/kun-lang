# 输入记录：能力语法与安全模型重新设计

## 来源

项目维护者

## 日期

2026-06-01

## 原始问题

### 1. 能力声明语法不统一

现有三种能力声明形式：

```kun
capability fs.read("/etc")                          // 脚本级——裸语句，像函数调用但无执行语义
cat p"/etc" with capabilities fs.read("/etc")        // 单命令注解——with + 复数
with capability net.http("api.example.com") { ... }   // 作用域块——with + 单数 + 大括号
```

**问题**：
- `capability` 裸语句看起来像表达式但不产生值，不是一等公民
- `with capability`（单数）和 `with capabilities`（复数）容易混淆
- 作用域块使用 `{ }` 而非语言的惯用 `... in` 模式
- 单命令注解语义有歧义——管道中 `with` 作用于哪个命令？

### 2. `with` 的作用域不清晰

```kun
-- 疑问：单命令注解能否被作用域块完全替代？
cmd with caps        vs        with caps in cmd
```

单命令注解在语义上被 `with caps ... do` 包裹单条命令覆盖，且后者更一致。

### 3. `capability` 语句的语义不明

`capability fs.read("/etc")` 中的 `fs.read("/etc")` 是什么？

- 像是函数调用但实际不是——`capability_check` 检查的是 `(namespace, action, target)` 三元组
- 不能绑定到变量、不能放入列表、不能传递——不是一等值
- 表示的是安全断言而非可计算表达式

### 4. 命名空间分组是否需要？

`fs.read`、`fs.write`、`net.http`、`process.exec`——"命名空间"是否为正确的抽象？还是应该扁平化为动作级？

### 5. 能力目标能否通配？

```kun
fs.read(Any)       -- 安全隐患？还是必要的灵活性？
```

是否有场景确实需要 `Any`？用户传入路径参数时如何处理？

### 6. 三级粒度是否过重？

脚本级声明 → 作用域级声明 → 单命令注解。三层继承/交集规则复杂，对脚本语言来说是否过重？

## 需求

- `with` 关键字统一定义，去掉单复数区分和 `{ }`
- 能力集 = 扁平 `(Namespace, Action, Targets)` 三元组，无继承或通配符
- 目标只能是字面量，不支持运行时拼接
- 能力声明无执行语义——编译期常量
- 作用域块仅针对 `do`/`do in` 表达式（IO 块的天然边界）

## 约束

- 语法需与现有 `let in`、`do in` 模式一致
- 关键字使用 `allow` 或 `with`（最终选择 `with caps`）
- 默认行为：无默认能力——所有权限必须显式声明
- 模块库文件不允许声明能力，只有可执行脚本可以
- 作用域块的能力约束需要改变沙箱配置
- 能力系统与 OS sudo 独立
- 模块内的函数可通过 `with caps ... do` 交集收窄
- CDF 不参与能力声明
- 审查机制：`--audit` / `--confirm` / `--cap-log`
- 最低内核：Linux 3.8

## 处理状态

- [x] 需求分析
- [x] 讨论（见 `discussion-capability-design.md`）
- [ ] 需求文档综合
- [ ] 设计定型
