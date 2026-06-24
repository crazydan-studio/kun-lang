# 审计记录：Phase 5 计划 — 第 2 轮验证审计

| 维度 | 值 |
|------|-----|
| 审计日期 | 2026-06-24 |
| 审计轮次 | Round 2 |
| 结果 | **4 FAIL 发现 → 全部修复** |

## 发现项

| # | 级别 | 发现 | 修复 |
|---|------|------|------|
| F1 | FAIL | `Env.contains` return_type 误为 `int_t` | 修正为 `bool_t`，新增 `bool_t` 参数到 `buildPrimitiveTable` |
| F2 | FAIL | `Stream.bytes` return_type 误为 `int_t` | 修正为 `bytes_t`，新增 `bytes_t` 参数 |
| F3 | FAIL | Step 1 引用已不存在的 `binding.signature` | 更新为 `{arg_count, return_type}` 描述 |
| F4 | FAIL | ADT tag 编号未定义 | 添加 IOError/CommandError/File.Type/LineError tag 表 + ADT payload 构造指南 |

## WARN 项（未修复，待后续审计）

| W1 | `Env.contains` return_type 仍然为 `int_t` 在影响范围外——audit-phase5-plan-round1.md 未列出此发现 |

## 验证结果

- 主构建成功（`zig build`）
- 全部 552 测试通过（`zig build test`）
- `buildPrimitiveTable` 参数从 4 扩展到 6（int/string/unit/stream_string/bool/bytes）
- 28 个调用点全部更新

## 结论

Round 2 全部 4 项 FAIL 已修复。计划可进入下一轮审计。
