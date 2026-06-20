# 深度审计报告 — Round 11

审计日期：2026-06-20
审计范围：cli.md（1375 行）、code-formatting.md（934 行）、command-system.md（462 行）、跨文档约定一致性、conventions.md 约束检查

## 发现汇总

| 严重度 | 数量 |
|--------|------|
| 严重 | 0 |
| 中等 | 1 |
| 轻微 | 5 |
| **总计** | **6** |

---

## 中等

### M1. mvp.md:69 推迟特性表中的函数名与标准库 API 不一致

**文件**: `docs/ai-agent/requirements/mvp.md:69`
**行内容**:
```
- `Parser.JSON.fromJson` / `Parser.Record.fromRecord`（编译期代码展开 v0.5）
```

**问题**: 标准库当前 API 中：
- `Parser.JSON` 模块的 API 为 `fromString : String -> Result JsonValue String`（`standard-library.md:2664`），**不存在** `fromJson` 函数。`fromJson` 是 `Parser.Record` 的函数。
- `Parser.Record` 模块的 API 为 `fromJson : String -> Result a String`（`standard-library.md:2707`），**不存在** `fromRecord` 函数。

**建议**: 将 mvp.md:69 改为 `Parser.Record.fromJson / Parser.Record.toJson（编译期代码展开 v0.5）`。`Parser.JSON.fromString`/`Parser.JSON.toString` 不在 V0.5 推迟范围内（当前即为可用状态）。

---

## 轻微

### W1. cli.md:396-423 声明器与字段类型对应表中函数缺少 `Cli.` 前缀

**文件**: `docs/ai-agent/design/cli.md:396-423`
**问题**: 表中使用裸函数名（如 `\|> withNegation`、`\|> withDefault true`、`\|> withEnvVar "DEBUG"`、`\|> withRequires "output"`、`\|> withValidator (Validator.range 1 65535)` 等），但文档中所有实际代码示例均使用 `Cli.` 前缀（如 `Cli.flag "verbose" 'v' "h" \|> Cli.withNegation`）。Kun 不支持 `open`/`use`，所有函数必须通过模块前缀调用。表中省略 `Cli.` 前缀可能误导读者认为可以裸调用。

**建议**: 为表中所有修饰器函数补全 `Cli.` 前缀。

### W2. code-formatting.md `|>` 对齐规则与示例不完全一致

**文件**: `docs/ai-agent/design/code-formatting.md`
**行 79**: `|> 链续行 | 与管线起始端对齐`
**问题**: 规则声明的"与管线起始端对齐"在文档示例中未得到一致遵循：

- 简单管道示例（行 409-414）：`stream` 缩进 +2，`|> filter` 缩进 +4（非对齐）
- Cmd 管道示例（行 424-429）：`Cmd.ls` 缩进 +4，`|> Stream.lines` 缩进 +6（非对齐）
- `Cmd.pipe` 管道示例（行 450-457）：`Cmd.pipe` 缩进 0，`[` 缩进 +2，`|> Stream.lines` 缩进 +2（与 `[` 对齐而非与 `Cmd.pipe` 对齐）

三个示例呈现出不同的对齐参考点。实际规律为 `|>` 比管线起始端**额外多缩进 2 空格**，但 `Cmd.pipe` 后 `|>` 参考点是 `[` 而非 `Cmd.pipe`。规则声明与示例存在偏差。

**建议**: 明确"管线起始端"的定义（表达式首行 vs 首 token），或在规则中统一描述为"`|>` 链续行缩进 +2（从管线起始端算）"。

### W3. command-system.md:175 OS 管道章节标题未列 `Cmd.pipe!`

**文件**: `docs/ai-agent/design/command-system.md:175`
**行内容**: `## OS 管道：`Cmd.pipe` / `Cmd.pipe?``
**问题**: 章节标题中仅列出 `Cmd.pipe` 和 `Cmd.pipe?`，但正文详细讨论了 `Cmd.pipe!`（行 185）。`Cmd.pipe!` 是该章节的重要 API 之一，标题遗漏导致读者可能认为该变体不存在或不重要。

**建议**: 将标题更新为 `## OS 管道：`Cmd.pipe` / `Cmd.pipe?` / `Cmd.pipe!``。

### W4. system-baseline.md:628 系统契约未包含 fork 后信号清理步骤

**文件**: `docs/ai-agent/architecture/system-baseline.md:628-634`
**问题**: 系统契约的行为序列列出：
```
fork → chdir → [withRunAs: initgroups → setgid → setuid] → setrlimit → install seccomp → exec → waitpid
```
但正文行 637-639 描述子进程需在 fork 后、exec 前执行三项信号清理：
1. 关闭从父进程继承的 signalfd 描述符
2. 将 SIGINT/SIGTERM 信号处理器恢复为默认行为
3. 解除所有被阻塞的信号掩码

这三项未出现在契约序列中。契约应准确反映子进程的完整执行流程。

**建议**: 在 `setrlimit → install seccomp` 之间（或 `install seccomp → exec` 之间）插入信号清理步骤：
```
fork → chdir → [withRunAs] → close signalfd → restore signal handlers → restore signal mask → setrlimit → install seccomp → exec → waitpid
```

### W5. app-overview.md 文件路径引用错误（误报）

**文件**: `docs/ai-agent/audits/audit-round11-deep.md:87`

经核实，`app-overview.md` 存在于 `docs/ai-agent/design/app-overview.md`，而非 `context/` 目录。该问题为审计脚本的路径预期错误，非文档缺陷。无需修复。

---

## cli.md 示例总体评价

cli.md 包含约 35 个 ` ```kun ` 代码块，总行数 1375 行。审计结论：

- **系统性错误：无**。所有 CliError 变体名称在使用时与定义一致（行 288-298 定义 vs 行 1314-1320 引用）；kebab-case → camelCase 映射在所有示例中正确；`CliSpec` 类型结构在所有示例中正确；宏引用路径（`Cli.` 前缀）在所有代码示例中正确；所有 `Cli.option`/`Cli.flag`/`Cli.count`/`Cli.arg` 的 `name` 参数均使用 kebab-case。
- **仅有 1 处轻微问题**（W1 — 表中修饰器函数省略 `Cli.` 前缀），且仅影响表格区域，不影响代码示例。
- 错误处理和帮助输出示例（行 1306-1356）完整且自洽，每种错误类型的示例文本与对应的 `CliError` 变体匹配。
- 文档质量高，示例可读性强。

---

## 跨文档一致性确认（一致项，免报告确认）

以下引用对经检查一致，仅记录供追溯：

| 引用对 | 结果 |
|--------|------|
| type-system.md 效应函数列表 ↔ system-baseline.md 效应函数列表 | 一致 ✓ |
| command-system.md `Cmd.<bin>?`/`Cmd.<bin>!` 语法定义 ↔ syntax.md `Cmd` 调用语法 | 一致 ✓ |
| feature-inventory.md 功能状态 ↔ standard-library.md 对应模块状态 | 一致 ✓ |
| mvp.md 推迟特性表 ↔ standard-library.md 推迟特性一览表（除 M1 外） | 基本一致（M1 除外） |
| conventions.md 代码块标签约束 ↔ 所有文档中的代码块 | 仅 ` ```kun ` 和 ` ```kun-cdf `（无违规），` ```kun-cmd ` 不存在 | 一致 ✓ |
| conventions.md 审计禁止模式 ↔ 所有设计文档 | 无违规 | 一致 ✓ |
| cli.md ↔ clis.md（定义 vs 引用） | clis.md 不存在（非必备依赖，cli.md 未引用） | N/A |

---

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.06.20 | 第一版 |

