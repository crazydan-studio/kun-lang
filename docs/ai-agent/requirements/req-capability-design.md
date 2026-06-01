# 需求综合：能力安全系统重新设计

## 背景与动机

Kun 作为面向 Linux 的函数式脚本语言，其安全模型的设计直接决定了语言的实用性和可信度。原有的能力系统存在语法不统一、语义模糊、层级过重三个核心问题，需要通过本次重新设计解决。

## 功能描述

### 1. 能力声明语法

**需求**：统一能力声明语法，消除单复数混淆和多种语法形式。

**方案**：采用 `with caps` 关键字 + `命名空间.动作 = [目标列表]` 格式。

```kun
-- 脚本级声明
with caps
  fs.read = [Path.cwd, p"/tmp"]
  process.exec = ["ls", "cat"]

-- 函数级（do 表达式块）
readConfig =
  with caps
    fs.read = [p"/etc/config"]
  do
    readFile p"/etc/config"
```

### 2. 零默认能力原则

**需求**：可执行脚本启动时无任何默认权限，所有 IO 操作（包括当前目录读写）都必须通过显式的 `with caps` 声明授予。

### 3. 二级声明粒度

**需求**：移除单命令权限注解，只保留脚本级和表达式级两级。

**理由**：单命令注解语义上被 `with caps ... do` 包裹单条命令完全覆盖，且有管道归属歧义。

### 4. 编译器内置能力对象

**需求**：`(Namespace, Action, Targets)` 三元组为编译器内置结构，非标准库 ADT。

**理由**：支持 `fs.read = [...]` 点号语法（非合法 identifier），禁止动态构造，编译期字段校验。

### 5. 模块禁止声明能力

**需求**：模块（库文件）中出现 `with caps` 属于编译期错误。模块内函数可通过 `with caps ... do` 交集收窄能力范围。

**约束规则**：模块函数的能力 = 调用方脚本能力 ∩ 函数自身 `with caps`。

### 6. 目标字面量规则

**需求**：能力目标只能是编译期字面量，禁止运行时动态拼接。

**匹配规则**：
| 动作 | 匹配方式 | 示例 |
|------|---------|------|
| `fs.read` / `fs.write` | 路径前缀匹配 | `p"/etc/"` 匹配 `/etc` 及所有子路径 |
| `net.http` / `net.https` | 精确/glob 匹配 | `"*.example.com"` 匹配子域名 |
| `process.exec` | 精确命令名匹配 | `["ls"]` 不匹配 `lsblk` |

### 7. CDF 移除能力声明

**需求**：CDF 不再声明能力行为，`behavior` 段从 CDF 格式中移除。seccomp 规则由参数类型和模式推导。

### 8. 审查机制

**需求**：提供三种审查入口：
- `kun --audit`——静态审计，展示脚本声明的所有能力
- `kun --confirm`——交互式确认，逐项确认能力后执行
- `kun --cap-log`——运行时审计日志

### 9. 独立资源预算限流层

**需求**：CPU 时间、内存分配等资源限制独立于能力系统，由执行器参数配置。

### 10. 与 OS 权限的关系

**需求**：能力系统完全独立于操作系统的 sudo，两者正交。不阻止脚本内部调用 sudo。最低 Linux 内核版本 3.8。

## 验收标准

1. ✅ 所有设计文档中的能力声明示例使用 `with caps` 新语法
2. ✅ 无 `capability fs.read(...)` 旧语法残留
3. ✅ 无 `with capability ... { }` 旧语法残留
4. ✅ 无单命令权限注解内容
5. ✅ CDF 文档中无 `behavior` 能力声明
6. ✅ 明确说明零默认能力原则
7. ✅ 明确说明模块禁止声明能力规则
8. ✅ 明确说明目标字面量匹配规则
9. ✅ 明确说明审查机制
10. ✅ VitePress 构建通过

## 涉及模块

- 安全模型：`design/roles-and-permissions.md`
- 语法设计：`design/syntax.md`
- 格式化规范：`design/code-formatting.md`
- 运行时架构：`architecture/system-baseline.md`
- CDF 格式：`design/command-signature-system.md`
- 模块边界：`architecture/module-boundaries.md`
- 应用概览：`design/app-overview.md`
- 示例文件：`examples/file-processor.md`、`examples/networking.md`

## 约束与假设

- 能力系统运行时实现（CapabilityManager 的 C/Zig 实现）不在本次设计范围内
- 本次仅涉及语法设计、文档和规范层面
- 假设 Linux kernel 3.8+ 可用的用户命名空间支持

## 开放问题

- 能力系统在 REPL 模式中的具体交互设计
- `--cap-log` 的日志格式和存储策略
- 父-子脚本能力传递的运行时实现细节

## 来源

- [能力语法重新设计输入](../input/input-capability-syntax-redesign.md)
- [能力安全系统设计讨论](../discussions/discussion-capability-design.md)
