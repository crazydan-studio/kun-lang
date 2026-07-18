# 讨论记录：CDF→Kun 代码生成与命令函数签名设计

## 讨论背景

CDF（Command Description File）最初被设计为运行时解析的描述文件，使用独立的 DSL 语法声明命令的参数和输出类型。随着设计演进，CDF 的定位需要重新审视——是否继续作为运行时格式，还是转为编译期代码生成源。

## 参与方

- AI Agent（方案分析与实施）
- 项目维护者（决策裁定）

## 讨论内容

### 议题 1：CDF 的运行时 vs 编译期定位

| 方案 | 说明 |
|------|------|
| 运行时解析 CDF | 运行时加载 CDF 文件，动态构造命令调用。需携带 CDF 解析器 |
| **编译期代码生成**（选定） | CDF 在编译期转译为 Kun 模块代码，生成 Options Record 类型、函数签名、argv 构造和输出解析器调用 |

**结论**：编译期代码生成。CDF → Kun 模块 → 类型检查 → 机器码生成，消除了运行时解析开销。

### 议题 2：`option` 的短名/长名选择

| 方案 | 说明 |
|------|------|
| 同时支持长短名 | `"-a,--all"` 或拆分声明 |
| **二选其一**（选定） | `option <name> "-a"` 或 `option <name> "--all"`，不同的选项字段必然对应不同的命令选项 |

**结论**：只映射短名或长名，二选其一。

### 议题 3：`param` 的语义和类型

| 方案 | 说明 |
|------|------|
| `param * : Path`（隐式 List） | `param *` 自动推断为集合类型 |
| **`param * : List Path`**（选定） | 显式写出 `List`，语义与类型系统一致 |
| `param <N>` 可以可选 | 支持 `param 0 : Path?` |
| **`param <N>` 始终必填**（选定） | 确定位置参数按顺序依次存在，不能跳跃缺失 |

**结论**：`param <N>` 始终必填，`param * : List T` 显式 `List`。不同类型的位置参数必须分别映射。

### 议题 4：`Bool` 选项的缺省值

| 方案 | 说明 |
|------|------|
| 在 Record 类型中声明 `= default` | 但 Kun 已移除 Record 默认值语法 |
| **Bool 缺省由实现保证**（选定） | 代码生成器约定：所有 `Bool` 选项逻辑缺省为 `false`，不在类型定义中体现 |

### 议题 5：`!` 标记的适用范围

| 方案 | 说明 |
|------|------|
| 所有非 Bool 类型可用 `!` | `name "-n" : String!` → 必填，类型为 `String` |
| Bool 不受 `!` 影响 | Bool flag 天然可缺省（false），`!` 对其无意义 |

**结论**：`option <name> "-x" : T` = 可选（`?T`），`option <name> "-x" : T!` = 必填（`T`）。`Bool` 不受 `!` 影响。

### 议题 6：校验器 `validator` 的定义和约束

| 方案 | 说明 |
|------|------|
| `Validator t` 为纯函数类型 | `t -> Result t String`，仅对值本身做校验 |
| 校验器不可涉及 IO | 文件存在性检查等涉及 IO 的操作不能作为 `validator` |
| 定义在根命令层级 | `validator <name> = <expr>`，子命令通过名字引用 |

**结论**：校验器是纯函数，不能涉及 IO。仅在最上层定义，子命令引用。

### 议题 7：解析器 `parser` 的设计

| 方案 | 说明 |
|------|------|
| `parser` 为纯函数 | `Stream String -> Stream (Result T String)`，不涉及 IO |
| 返回值包装 `Result` | 每行独立成功/失败，用户可选择 `filterMap Result.ok` |
| 自定义解析器引用模块函数 | `parser myParser : Stream (Result T String) = MyModule.parserFunc` |
| 内置解析器 | `output default`（逐行 String）、`output json`（逐行 JsonValue） |

**结论**：解析器为纯函数，返回值 `Stream (Result T String)`。命令函数返回类型为 `Result (Stream T) IOError`。

### 议题 8：`output` 与 `parser` 的关系

```kun-cdf
parser statusFormat : Stream (Result StatusEntry String) = MyParser.parseStatus

command git
  output statusFormat    // 引用 parser 名字
```

`output <name>` 引用已定义的 `parser`，决定命令函数的返回值类型。

### 议题 9：`command` 同名简化

```kun-cdf
// 函数名与二进制名一致
command git              // 等价于 command git "git"
subcommand status        // 等价于 subcommand status "status"

// 不一致时
command myTool "my-tool"
subcommand list "dpkg-list"
```

**结论**：同名时省略 `"<bin>"` 字符串。

### 议题 10：`option type` 字段名的合法性

```kun-cdf
option type "--type" : String with (include ["int", "bool", "path"])
```

**结论**：Kun Record 字段名不受关键字限制，`type` 可直接作为字段名，无需重命名为 `type_`。

### 议题 11：`bin` 命令路径

```kun-cdf
command myTool "my-tool"
  bin p"/usr/local/bin/my-tool"    // 绝对路径
  bin p"./tools/my-tool"           // 相对路径（不可超出 CDF 目录）
```

**结论**：`bin` 可选；相对路径不可超出 CDF 所在目录（`../` 不允许）；缺省按函数名搜索 PATH。

### 议题 12：子命令的函数命名和选项继承

| 方案 | 说明 |
|------|------|
| 多层嵌套命名 | `<main>_<sub1>_<sub2>`，如 `git_remote_add` |
| **`.` 分隔调用语法（选定）** | 内部函数名使用 `_`，对外调用语法使用 `<main>.<sub1>.<sub2>`，如 `git.remote.add` |
| 父子命令选项不继承 | 子命令的选项各管各的，需要时在子命令上显式声明 |

**结论**：内部实现使用 `<main>_<sub1>_<sub2>`（遵循 Kun 标识符规则），对外调用语法使用 `<main>.<sub1>.<sub2>`。选项不继承，子命令独立声明。

### 议题 13：`module` 声明位置

**结论**：`module` 必须在文件开头声明。代码生成器自动在生成的 Kun 模块文件开头生成 `module` 导出声明。

## 结论

1. CDF 采用编译期代码生成方式，转译为 Kun 模块
2. `option <name> "<flag>" : <type>[!] [with (<validator>)]`
3. `param <N> : <type>`（始终必填），`param * : List <type>`（显式 List）
4. `validator` 为纯函数，不涉及 IO
5. `parser` 为纯函数，返回值 `Stream (Result T String)`
6. `output <name>` 引用解析器
7. `command <name>` 同名时省略二进制名
8. `option type "--type"` 直接使用 `type` 作为字段名
9. Bool 选项缺省 `false`，不在类型定义中体现
10. 嵌套子命令内部命名 `<main>_<sub1>_<sub2>`，对外调用语法 `<main>.<sub1>.<sub2>`
11. `module` 在文件开头
12. `with` 子句支持内联验证器表达式，无需事先声明 `validator`
13. 四层分级可用性模型（T1 内建 → T2 CDF → T3 自动推断 → T4 CDF-less 受限模式）

