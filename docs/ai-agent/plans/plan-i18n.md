# 执行计划：错误消息国际化（i18n）子系统设计

## 背景与目标

当前 Kun 编译器和运行时输出的所有错误消息均为硬编码中文（`type-system.md` 中 20 个错误模板、`system-baseline.md` 中错误输出示例均为中文）。Linux 运维/DevOps 目标用户群体中有大量非中文母语者，错误消息的语言障碍会显著影响 Kun 的可用性。

目标：建立完整的 i18n 子系统，使编译器、运行时和 CLI 输出的结构化消息支持中英文双语，并为未来扩展其他语言留出接口。

约束：
- 仅考虑中文（zh_CN）和英文（en）两种语言
- 非中文环境默认使用英文
- `.po` 文件作为翻译源文件
- 编译时将中文翻译嵌入二进制，英文使用 msgid 本身（零额外存储）
- 其他语言通过外挂 `.po` 文件按需加载

## 变更范围

### 新建文件

| 文件 | 说明 | 预估行数 |
|------|------|---------|
| `architecture/i18n.md` | i18n 子系统完整架构设计 | ~200 行 |
| `plans/plan-i18n.md` | 本执行计划 | ~120 行 |

### 修改文件

| 文件 | 变更内容 | 预估行数 |
|------|---------|---------|
| `architecture/system-baseline.md` | 初始化阶段新增 locale 检测步骤；错误诊断章节补充 i18n 策略说明 | ~30 行 |
| `architecture/module-boundaries.md` | 新增 i18n 子系统（解释器核心工具层） | ~15 行 |
| `architecture/index.md` | 新增 i18n 文档条目 | ~3 行 |
| `design/type-system.md` | 20 个错误消息模板追加英文 msgid 标注 | ~40 行 |
| `plans/index.md` | 新增本计划条目 | ~2 行 |
| `context/project-context.md` | 更新活跃工作与路由记录 | ~5 行 |

### 不修改的文件

- `design/syntax.md` — 语法不变
- `design/standard-library.md` — 标准库 API 不变
- `requirements/mvp.md` — i18n 属基础设施，不改变 MVP 功能范围

## 实施步骤

### Step 1: 创建 `architecture/i18n.md` — i18n 子系统架构设计

**前置依赖**：无

完整架构文档，章节结构：

1. **msgid 体系** — 以英文为键、中文翻译嵌入、英文 fallback
2. **`.po` 文件格式约定** — 标准 gettext 格式，文件位置 `po/zh_CN.po`
3. **构建时代码生成** — `build.zig` 添加 `po2zig` 步骤，生成 `src/i18n/catalog.zig`
4. **运行时 locale 检测** — `KUN_LOCALE` → `LANG`/`LC_MESSAGES` → 默认 `en`
5. **消息格式化 API** — `kmsg(comptime msgid, locale) → comptime format string`
6. **外挂 .po 加载** — 非 zh_CN/en 的 locale 从 `<runtime>/share/kun/po/` 按需加载
7. **msgid 维护工作流** — `zig build msgmerge` → 扫描源码 → 更新 .po
8. **错误消息结构体** — 每个错误携带 msgid 和运行时参数，格式化时查 locale 翻译

### Step 2: 更新 `architecture/system-baseline.md`

**前置依赖**：Step 1

- 初始化阶段（第 31-55 行）新增 locale 检测步骤
- 错误诊断章节补充国际化策略：每个 `TypeError`/`CommandError` 记录 msgid + 参数，输出时按 locale 格式化
- 错误输出示例改为同时展示中英文格式

### Step 3: 更新 `design/type-system.md` — 错误模板标注 msgid

**前置依赖**：Step 1

为 20 个错误消息模板中的每个模板标注英文 msgid。格式：

```
**`Mismatch`**（msgid: "Type Mismatch"）
   ```
   Error: Type Mismatch ─── src/main.kun:{line}:{col}
```

模板中的中文占位符文本（如 `"期望"`、`"发现"`、`"提示"`）在英文版本中对应：
- 期望 → Expected
- 发现 → Found
- 提示 → Hint
- 原因 → Reason

### Step 4: 更新 `architecture/module-boundaries.md`

**前置依赖**：Step 1

- 解释器核心新增 `i18n` 子模块（locale 检测 + 消息翻译）
- 依赖图不变化（i18n 是解释器核心的内部工具层，不引入新模块间依赖）

### Step 5: 更新元数据文件

**前置依赖**：Step 1-4

- `architecture/index.md`：新增 i18n 文档条目
- `plans/index.md`：新增本计划条目
- `context/project-context.md`：更新活跃工作与任务路由记录

## 验证方法

1. **构建验证**：`cd docs && pnpm lint && pnpm build`
2. **一致性审查**：逐文件检查变更未引入与其他文档的矛盾
3. **消息覆盖完整性**：type-system.md 中 20 个模板均有 msgid 标注
4. **架构一致性**：i18n 设计不改变错误类型定义和传播模型

## 风险评估

| 风险 | 缓解措施 |
|------|---------|
| `.po` 文件与源码不同步（新增错误消息未翻译） | build 步骤生成 `msgmerge` 校验报告，缺失翻译显示警告但不阻断构建 |
| 中文翻译被英文 msgid 覆盖（未翻译条目回到英文） | 生成代码中缺失 msgid 的条目直接返回英文原文，不 panic |
| 外挂 `.po` 文件格式错误导致运行时崩溃 | 外挂加载为 best-effort：解析失败 → stderr 警告 + fallback 英文 |
| Zig 的 format 字符串必须 comptime-known 限制 | `kmsg()` 返回 comptime 字符串，locale 参数在调用点通过 comptime 分支展开为不同格式串 |

## 审计要点

1. `.po` 文件格式与标准 gettext 的兼容性
2. 构建时代码生成步骤的性能（不应显著增加构建时间）
3. locale 检测逻辑的边界情况（LANG 为空、LANG 包含编码后缀如 `zh_CN.UTF-8`）
4. 外挂 `.po` 加载的安全边界（拒绝加载过大文件、路径遍历攻击）
5. 消息格式化 API 的类型安全性（`{placeholder}` 名称与 struct 字段的匹配）

