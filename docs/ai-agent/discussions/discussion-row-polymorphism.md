# 讨论记录：行多态与扩展积类型

## 讨论背景

Kun 当前积类型（Record）系统为精确结构类型：`{ name : String, age : Int }`。函数参数必须完全匹配 Record 结构，不支持宽度子类型化和深度子类型化。这在以下场景中产生不便：

1. **函数复用**：一个只读取 `name` 字段的函数，无法接受包含额外字段的 Record
2. **配置扩展**：无法基于基础配置类型添加字段表达扩展配置
3. **模块化**：不同模块定义的部分重叠的 Record 类型无法互操作

## 参与方

- AI Agent（方案设计与分析）

## 设计目标

1. 允许函数接受"至少包含某些字段"的 Record，通过类型变量表达剩余字段
2. 支持基于已有 Record 类型声明扩展类型（编译期字段展开）
3. 保持**无子类型**设计原则
4. 与现有 HM 类型推断兼容
5. 运行时零开销——Record 的运行时表示不变

## 讨论内容

### 核心概念：行多态（Row Polymorphism）

行多态是参数化多态在 Record 字段上的应用。`{ a | name : String }` 读作"一个 Record 类型，包含 `name : String` 字段，剩余字段的类型变量为 `a`"。

这不是子类型——而是通过类型变量实现了函数对 Record 结构的泛化。类型检查时，行变量 `a` 被合一的 Record 的具体剩余字段替换。

### 语法方案

#### 方案 A：统一 `{ | }` 语法（推荐）

```kun
// 行多态——类型变量表示剩余字段
getName : { a | name : String } -> String
getName = \{ name } ->
  name

// 扩展积类型——有名类型展开为字段
type CmdOptions = { runAs : ?RunAs }

type GitCommitOptions =
  { CmdOptions
  | message : String
  }
// 编译期等价于：{ runAs : ?RunAs, message : String }
```

语法统一：`{ <左侧> | <字段定义> }`，左侧为：
- **类型变量**（小写）→ 行多态
- **有名 Record 类型**（大写开头）→ 字段展开

#### 方案 B：分离语法

```kun
// 行多态
getName : { a | name : String } -> String

// 扩展积类型——使用 extends 关键词
type GitCommitOptions = CmdOptions extends { message : String }
```

**选定**：**方案 A**。统一 `{ | }` 语法更简洁，与 Record 更新语法 `{ r | field = value }` 形式一致。

### 类型系统扩展

#### 行变量与行约束

引入行变量（row variables）作为类型变量的一种：

```kun
// 类型签名 { a | name : String } -> String 的内部表示
getName : ∀a. { name : String | a } -> String
```

类型检查时：
1. 调用 `getName { name = "Kun", version = "0.1" }`，生成约束：
   - `{ name : String | a } ~ { name : String, version : String }`
   - 合一后：`a = { version : String }`
2. 行变量的合一过程称为**行合一**（row unification），是标准 HM 合一的扩展

#### 与"无子类型"原则的关系

行多态不是子类型。子类型（`{ name : String, age : Int } <: { name : String }`）是隐式向上转型，而行多态是参数化多态——类型变量在调用点被具体类型替换，是编译期的精确匹配。

具体区别：

| 维度 | 子类型 | 行多态 |
|------|--------|--------|
| 机制 | 隐式向上转型 | 类型变量替换 |
| 安全性 | 协变/逆变问题 | 类型安全，无变体问题 |
| 推断 | 需单独的子类型约束求解 | 标准合一扩展 |
| 运行时 | 可能需要类型擦除/装箱 | 零开销 |

#### 与 Record 模式解构的交互

现有 Record 解构与行多态天然互补：

```kun
// 行多态函数 +  Record 解构
getName : { a | name : String } -> String
getName = \{ name } ->    // 解构时只提取需要的字段
  name

// 多层访问
getNested : { a | outer : { b | inner : String } } -> String
getNested = \{ outer = \{ inner } } ->
  inner
```

#### 与 Record 更新的交互

```kun
// 更新操作与行多态兼容
updateName : { a | name : String } -> { a | name : String }
updateName = \r ->
  { r | name = "new name" }   // 保留其他字段
```

行多态保证：输入 Record 的剩余字段类型 `a` 不变地传递到输出。

#### 与字段访问速记的交互

```kun
// .name 速记在行多态下自动适配
records : List { name : String, size : Int }
records |> map .name   // 类型安全：自动识别 name 字段
```

### 扩展积类型的设计约束

`type GitCommitOptions = { CmdOptions | message : String }` 在编译期展开为：

```kun
{ runAs : ?RunAs, message : String }
```

约束：
1. `CmdOptions` 必须是有名 Record 类型（`type CmdOptions = { ... }`），不可为行变量
2. 展开后字段名冲突的处理规则：**扩展字段覆盖基类型字段**（类似 Record 更新语义）
3. 不支持多继承——`{ A, B | field : T }` 的优先级规则过于复杂

### 运行时表示

不变。行多态是纯编译期概念，所有行变量在类型检查后被具体类型替换。运行时 Record 仍为结构化内存布局。

## 开放式问题

1. **二元操作符限制**：能否在二元操作符（如 `==`）两侧使用不同结构但都有相同字段的 Record？
   - 行多态函数参数：可
   - `==` 操作符：否——双方类型必须精确一致
2. **多行变量**：是否支持 `{ a | name : String, b | age : Int }`（多于一个行变量）？
   - 当前**不支持**。单行变量可覆盖绝大多数场景，多个行变量显著增加类型系统复杂度
3. **与 do/IO 的交互**：行多态函数中调用 IO 操作是否影响推断？
   - 不影响。`IO` 和 `do` 在效应层面独立于 Record 类型
4. **语法冲突**：`{ a | name : String }` 中的 `|` 是否与管道 `|>` 冲突？
   - 否。管道在表达式上下文中（值运算），`{ | }` 在类型上下文中，位置可区分。且 `|` 后紧接标识符时解析为类型构造的一部分而非管道

## 设计影响范围

| 组件 | 影响 | 工作量 |
|------|------|--------|
| 类型系统（行变量 + 行合一） | 核心扩展 | 大 |
| 语法（类型标注 + 类型定义） | 新增语法构造 | 中 |
| 类型检查器 | 扩展推断算法 | 大 |
| 解析器 | 新增语法规则 | 中 |
| 运行时 | 无影响 | 无 |
| 标准库 | 函数签名可更灵活 | 小 |
| 现有代码 | 兼容——旧 Record 类型继续工作 | 无 |

## 结论

**推荐推进方向**：
1. 采纳方案 A 统一 `{ | }` 语法
2. 行多态 + 扩展积类型一并设计，使用同一语法构造
3. 类型系统扩展在 HM 基础上引入行变量和行合一
4. 扩展积类型定义为编译期字段展开

**暂不纳入本次设计**：
- 多行变量
- `==` 等操作符的行多态支持
- 深度行多态（嵌套 Record 的行变量传播）

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 0.3.0 | 2026-06-04 | 初始设计文档。统一 `{ | }` 语法，单行变量，编译期字段展开 |
