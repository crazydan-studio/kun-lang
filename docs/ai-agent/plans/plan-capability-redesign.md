# 执行计划：能力安全系统重新设计

## 背景与目标

### 背景

Kun 的能力声明语法存在三个核心问题：
1. **语法不统一**：脚本级用 `capability` 裸语句、作用域块用 `with capability ... { }`、单命令注解用 `with capabilities`——三种形式各不同，单复数混淆
2. **语义模糊**：`capability fs.read("/etc")` 看起来像函数调用，但不产生值、不能传递、不是一等公民
3. **层级过重**：三级粒度（脚本级/作用域块/单命令注解）对脚本语言来说过于复杂

### 目标

- 统一能力声明语法为 `with caps` 形式
- 零默认能力——所有权限必须显式声明
- 二级粒度（脚本级 + 表达式级 `with caps ... do`），移除单命令注解
- 能力对象编译器内置，非标准库 ADT
- CDF 移除能力声明

## 变更范围

**涉及模块**：安全模型、语法设计、运行时架构、CDF 格式、示例文档

**需要修改的文件**（11 个）：

| 文件 | 操作 | 说明 |
|------|------|------|
| `design/roles-and-permissions.md` | 重写 | 能力安全系统权威设计文档 |
| `design/syntax.md` | 修改 | 替换能力声明章节为 `with caps` |
| `design/command-signature-system.md` | 修改 | 移除 CDF behavior 声明 |
| `design/code-formatting.md` | 修改 | 新增 `with caps` 格式化规则 |
| `design/feature-inventory.md` | 修改 | 更新特性状态 |
| `design/app-overview.md` | 修改 | 更新安全模型描述 |
| `architecture/system-baseline.md` | 修改 | 更新能力运行时接口 |
| `architecture/module-boundaries.md` | 修改 | 更新模块边界 |
| `examples/file-processor.md` | 修改 | 更新示例语法 |
| `examples/networking.md` | 修改 | 更新示例语法 |
| `context/project-context.md` | 修改 | 更新最近完成记录 |

**需要新建的文件**（5 个）：

| 文件 | 说明 |
|------|------|
| `input/input-capability-syntax-redesign.md` | 原始输入记录 |
| `discussions/discussion-capability-design.md` | 讨论记录 |
| `requirements/req-capability-design.md` | 需求综合文档 |
| `plans/plan-capability-redesign.md` | 本计划文件 |
| `logs/log-2026-06-01-capability-redesign.md` | 会话日志 |

## 实施步骤

| 步骤 | 内容 | 前置依赖 | 验证方法 |
|------|------|---------|---------|
| 1 | 更新 `roles-and-permissions.md` 完全重写 | 无 | 构建通过 |
| 2 | 更新 `syntax.md` 能力声明章节 | 无 | 构建通过 |
| 3 | 移除 `command-signature-system.md` 的 `behavior` | 无 | 构建通过 |
| 4 | 更新 `system-baseline.md` 能力运行时 | 无 | 构建通过 |
| 5 | 更新 `module-boundaries.md` 模块边界 | 无 | 构建通过 |
| 6 | 更新 `code-formatting.md` 格式化规则 | 无 | 构建通过 |
| 7 | 更新示例文件 `file-processor.md`、`networking.md` | 步骤 1-2 | 构建通过 |
| 8 | 更新 `feature-inventory.md`、`app-overview.md` | 步骤 1 | 构建通过 |
| 9 | 更新 `project-context.md` | 步骤 1-8 | 构建通过 |
| 10 | 创建 input/discussions/logs 等新文件 | 步骤 1-9 | 构建通过 |

## 验证方法

- VitePress 构建（`pnpm --filter ./docs build`）通过
- Kun 代码语法合规性检查（格式化规范校验）
- 内部交叉引用链接有效性检查

## 风险评估

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| 旧语法遗漏 | 文档中存在过期语法 | 中 | 全局搜索 `capability ` 关键字确认全部替换 |
| 路径引用错误 | 文档互链断裂 | 中 | 构建过程会检测无效链接 |
| VitePress 构建失败 | 文档无法部署 | 低 | 构建前本地验证 |
| 与已有讨论记录不一致 | 讨论结论与设计不一致 | 低 | 更新 discussion-syntax-evolution 记录 |

## 状态

- **计划状态**：✅ 已完成（事后补写）
- **实施状态**：✅ 已完成
- **审计状态**：⏳ 待闭合审计
