# 审计报告：第二轮审计——修复验证与深度分析

**审计日期**: 2026-06-04
**审计范围**: 设计文档全量 9 项修复验证 + 5 个新维度深度分析

---

## 一、验证已修复问题

### 1. `design/syntax.md`

| 检查项 | 结果 | 说明 |
|--------|------|------|
| `?` 幽灵操作符已从优先级表移除 | ✅ 修复正确 | 优先级表（L875-908）无 `?` 后缀操作符；L809-836 明确说明 `?` 不作为独立后缀操作符使用，已由 `=!`/`<-!` 替代 |
| `{ field as alias = literal }` 语法规则 | ✅ 修复正确 | L507-511 精确定义了三形式混用规则：`{field as alias = literal}` 先匹配字面量后绑定别名 |

### 2. `architecture/system-baseline.md`

| 检查项 | 结果 | 说明 |
|--------|------|------|
| sed/awk 矛盾消除 | ✅ 修复正确 | L757 和 L1005 一致声明 sed/awk 由标准库覆盖、不映射为 CDF 命令 |

### 3. `examples/pattern-matching.md`

| 检查项 | 结果 | 说明 |
|--------|------|------|
| `checkFile` 改为 IO 函数 | ✅ 修复正确 | L294-299: `checkFile : Path -> IO String`，内含 `do` 块 |
| `describeFileType` 改为 IO 函数 | ✅ 修复正确 | L302-311: `describeFileType : Path -> IO String`，使用 `<-!` 解包 |

### 4. `examples/networking.md`

| 检查项 | 结果 | 说明 |
|--------|------|------|
| `parse?` 移除 | ✅ 修复正确 | 全文无 `parse?` 痕迹，全部使用 `=!`/`<-!` 语法 |

### 5. `design/standard-library.md`

| 检查项 | 结果 | 说明 |
|--------|------|------|
| List 模块 API 完整性 | ✅ 修复正确 | L363-379: 含 `map`/`filter`/`fold`/`filterMap`/`head`/`last`/`get`/`append`/`reverse`/`length`/`isEmpty`，覆盖核心操作 |
| Map 模块 API 完整性 | ✅ 修复正确 | L389-405: 含 `get`/`insert`/`fromList`/`toList`/`keys`/`values`/`update`/`size`/`isEmpty`/`merge`，覆盖字典核心操作 |

### 6. `design/command-signature-system.md`

| 检查项 | 结果 | 说明 |
|--------|------|------|
| `Fd` 类型定义 | ✅ 修复正确 | L666: `type Fd = Fd Int`，简洁正确 |
| `OrPath` 类型定义 | ✅ 修复正确 | L668-670: `FdSource Fd \| PathSource Path`，语义完整 |
| `OrStdioMode` 类型定义 | ✅ 修复正确 | L672-676: `OrPathMode OrPath \| Pipe \| Inherit`，覆盖三种标准流模式 |

### 7. `design/feature-inventory.md`

| 检查项 | 结果 | 说明 |
|--------|------|------|
| 管道操作符状态 | ✅ 修复正确 | L82: `\|>`、`<\|`、`>>`、`<<` 均为 ✅ 设计定型 |
| 高阶函数状态 | ✅ 修复正确 | L84: map/filter/fold 等均为 ✅ 设计定型 |

### 8. `design/roles-and-permissions.md`

| 检查项 | 结果 | 说明 |
|--------|------|------|
| DNS 绕过已文档化 | ✅ 修复正确 | L188-191 明确 `resolve` 不经能力检查；附安全说明（L190: 理论上可用于 DNS 隧道） |

### 9. `design/type-system.md`

| 检查项 | 结果 | 说明 |
|--------|------|------|
| 整数溢出说明 | ✅ 修复正确 | L105-109: debug 模式 Panic，release 模式可关闭（静默回绕），明确溢出是值域问题 |
| capability_check 时机说明 | ✅ 修复正确 | L235-241: 发生在运行时 IO 原语内部，非类型检查期间 |

### 修复验证结论：9/9 ✅ 全部修复正确

---

## 二、新发现的问题

### P0（必须修复，影响核心语义）

#### P0-1: `Result` 类型缺少组合子 API 定义

- **文件**: `design/type-system.md` L297-300, `design/standard-library.md`
- **问题**: `Result t e` 仅定义了 ADT 结构（`Ok t | Err e`）和绑定操作符（`=!`/`<-!`），但作为核心错误处理类型，缺少标准组合子的 API 定义：
  - `map : (a -> b) -> Result a e -> Result b e`
  - `andThen : (a -> Result b e) -> Result a e -> Result b e`（即 `>>=`）
  - `mapError : (e -> f) -> Result a e -> Result a f`
  - `withDefault : a -> Result a e -> a`
  - `ok : Result a e -> ?a`           // Result 转为 ?T，Err 对应 Nil
  - `toResult : e -> ?a -> Result a e` // ?T 转为 Result，Nil 对应 Err
- **影响**: `Result` 是 Kun 错误处理的核心类型，缺少组合子意味着用户只能通过 `case` 模式匹配手动展开，代码冗长且易出错
- **修复建议**: 在 `design/standard-library.md` 新增 `Result` 模块一节，定义上述组合子

#### P0-2: 非法 UTF-8 输入处理策略未定义

- **文件**: `architecture/system-baseline.md` L542-544, `design/type-system.md` L93
- **问题**: 文档声明 `String` 始终是有效 UTF-8 序列，但未定义**从外部源读取到非法 UTF-8 时的处理策略**。以下场景缺少规范：
  - `readFile` 读取到非 UTF-8 文件
  - 网络响应包含非法 UTF-8 字节序列
  - `Bytes -> String` 转换遇到非法序列
- **影响**: 实现者自行决定策略（Panic/替换/跳过）会导致行为不一致；用户代码无法依赖统一的错误处理路径
- **修复建议**: 在 `design/type-system.md` `String` 节中明确：
  1. 输入源（文件/网络）在转换为 `String` 前是否检查 UTF-8 合法性
  2. 非法序列的处理策略：运行时 Panic / 返回 `Result String IOError` / 静默替换为 U+FFFD
  3. 列举安全的转换函数签名

### P1（建议修复，影响可用性）

#### P1-1: Nilable 类型 `?T` 缺少配套函数

- **文件**: `design/type-system.md` L52-81
- **问题**: `?T` 有 `??`（Nil 合并）和 `?.`（可选链）操作符，但缺少标准库中 Nilable 类型的常用函数：
  - `mapNil : (a -> b) -> ?a -> ?b`
  - `orElse : ?a -> a -> a`（类似 `??` 但可能用于链式风格）
  - `withDefault : a -> ?a -> a`
  - `toResult : e -> ?a -> Result a e`
  - `filter : (a -> Bool) -> ?a -> ?a`
- **影响**: 用户对 `?T` 的操作仅限于语言操作符和 `case` 模式匹配，无法利用组合子链式处理可选值
- **修复建议**: 在 `design/standard-library.md` 新增或扩展相关模块，或在 `design/type-system.md` 提及标准库提供这些函数

#### P1-2: 模块名冲突（同名不同路径）未定义

- **文件**: `architecture/system-baseline.md` L746-761（定义了搜索顺序但未处理冲突）
- **问题**: 当 `import List` 在多个搜索路径中匹配到同名文件时，文档只定义了搜索优先级顺序（标准库 > 项目本地 > `$KUN_PATH`），但未定义：
  - 是否允许同名模块存在于不同路径（如项目 `modules/List.kun` 与标准库 `List.kun` 同名）？
  - 搜索优先级是否能保证无歧义（即高优先级路径命中后不再搜索低优先级）？
  - 用户自定义路径中的同名模块是覆盖还是忽略？
  - 是否提供显式路径导入语法（如 `import "./modules/List"`）作为冲突时的逃生舱？
- **影响**: 用户可能无意中引入与标准库同名的模块，导致不可预期的行为和难以诊断的错误
- **修复建议**: 在 `architecture/system-baseline.md` 模块解析节中：
  1. 明确"优先级路径命中即停止搜索"规则
  2. 考虑提供显式路径导入语法（`import p"./modules/List"`）
  3. 文档化模块名冲突时的编译期告警策略

#### P1-3: 运行时堆栈跟踪格式未定义

- **文件**: `architecture/system-baseline.md` L222-340
- **问题**: 文档定义了结构化错误类型的字段（TypeError、PermissionError 等），但未定义**运行时 Panic 或未处理 Error 传播时的堆栈跟踪格式**。错误结构中仅包含触发点的源码位置，不含调用链信息
- **影响**: 用户遇到运行时错误时无法追踪错误的传播路径，在深层嵌套的函数调用中难以定位问题根源
- **修复建议**: 在 `architecture/system-baseline.md` 错误诊断节中补充：
  1. 堆栈帧的运行时表示（如 `StackFrame = { file, line, column, function }`）
  2. 堆栈跟踪的输出格式（类 Rust `error[E0277]` 风格或类 Elm 简洁风格）
  3. 用户态 vs 运行时内部的帧过滤规则

### P2（建议记录，低优先级）

#### P2-1: 嵌套 `with caps` 的作用域交集规则未完全覆盖

- **文件**: `design/roles-and-permissions.md` L68 和 L390-406
- **问题**: 文档定义了两条规则：
  - 多个脚本级 `with caps` 块 = **并集**（L68）
  - 模块函数 `with caps` 与调用者 = **交集**（L403）

  但未定义**函数内嵌套 `with caps ... do`** 的交集行为。例如：

  ```kun
  with caps
    fs.read = [p"/a/"]
  do
    with caps
      fs.read = [p"/a/b/"]
    do
      ...
  ```

  内层 `with caps` 是取并集（`[p"/a/", p"/a/b/"]`）还是交集（`[p"/a/b/"]`）？文档指向交集语义（scope_stack push/pop），但未显式说明
- **影响**: 实现歧义——不同开发者可能实现不同的嵌套语义
- **修复建议**: 在 `design/roles-and-permissions.md` 中显式说明：嵌套 `with caps ... do` 块的有效能力集 = 当前作用域 ∩ 内层声明（即始终取交集收窄，不可扩权）

#### P2-2: 编译期错误消息模板覆盖不全

- **文件**: `architecture/system-baseline.md` L227-254
- **问题**: 文档为 `TypeError` 提供了完整的错误消息模板（L246-254），但其他编译期错误类型（语法错误、模块解析错误、循环依赖错误、能力声明冲突等）未定义消息格式
- **影响**: 不同错误类型的消息格式可能不一致，影响用户体验
- **修复建议**: 在 `architecture/system-baseline.md` 中统一规范所有编译期错误的消息模板，或建立通用错误消息格式指南

---

## 三、汇总

| 严重度 | 数量 | 编号 |
|--------|------|------|
| P0 | 2 | P0-1, P0-2 |
| P1 | 3 | P1-1, P1-2, P1-3 |
| P2 | 2 | P2-1, P2-2 |
| **总计** | **7** | |

**修复验证**: 9/9 ✅ 全部正确

**新发现问题**: 7 项（2 P0 + 3 P1 + 2 P2）
