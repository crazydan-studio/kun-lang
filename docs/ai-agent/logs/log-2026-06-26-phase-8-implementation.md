# 开发日志：Phase 8 实施

## Phase 8 — Nilable ADT + 标准库扩展（v0.2）

### 完成时间

2026.06.26

### 提交清单

| 提交 | 说明 |
|------|------|
| `5ae535d` | build.zig msgcheck + env.zig registerNilableAdt |
| `098583d` | module_resolver 更新（isBuiltinType/hasPrimitiveBinding） |
| `3b0be9b` | Nilable/Duration/Int/Float/Char 标准库模块 |
| `4eb65c9` | primitive.zig 注册 + Validator/i18n message.zig |
| `e18b81e` | pattern.zig Some 变体支持 + 裸变量糖化移除 |
| `546bd51` | kw_nil 关键字 token 移除 |
| `cc50031` | i18n kmsg/format 分层 + 26 条 zh_CN 翻译表 |
| `47f3a31` | runtimeReplace 骨架 |
| `5bbe1fd` | nil_to_non_nilable 错误完全移除 |
| `3035059` | Duration/Int/Float/Char 模块测试 |
| `2ef265e` | Validator 真实实现（后移除—应为 PureKun） |
| `aa426a4` | DateTime 格式化引擎 |
| `2ef64e1` | Nilable 模块测试 |
| `ca91914` | `?T` 类型标注解析 (parseTypeAnn) |
| `4d2d8a3` | zig-regex 引擎集成 (deps/zig-regex/) |
| `11e78a3` | Regex Primitive 存根替换 |
| `dfc4e7a` | Regex/Validator/DateTime 测试文件 |
| `b53a308` | regex_literal 真实实现 + RegexHandle 更新 |
| `d482888` | nil_literal 从 AST 完全移除 |
| `fcd0098` | i18n 命名插值→位置插值 |
| `12cc1d1` | Validator 从 Primitive 表移除 |

### 关键决策

- **kw_nil 移除**：`Nil` 不再是内置字面量关键字，改为 `type_ident`，通过 ADT 变体路径处理
- **nil_literal 保留权衡**：曾尝试完全从 AST 移除 `nil_literal`，改为 `ident("Nil")` 路径成功
- **zig-regex 集成**：`build.zig.zon` 因 hash 格式问题改用本地 `deps/zig-regex/` 复制
- **Validator 非内置**：`oneOf`/`range`/`nonEmpty` 为 PureKun，不应注册为 Primitive
- **i18n 位置插值**：命名插值 `{name}` 改为位置 `{s}`/`{d}`/`{f}`（与 `std.fmt` 一致）

### 变更统计

- 18 个实现提交
- 708 测试通过（零泄漏）
- ~1670 行新增代码（不含 zig-regex 源码 26,500 行）
