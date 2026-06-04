# 审计记录：第 8 轮元问题审计

## 审计范围

- **焦点**：行号偏移、版本历史一致性、README 一致性、讨论索引完整性、代码块语言标签
- **方法**：子代理分析 → 评审迭代 → 共识

## 发现的问题

| # | 问题 | 等级 | 修复文件 |
|---|------|------|---------|
| 1 | README "惰性求值"与设计文档矛盾 | P1 | `README.md` |
| 2 | 版本方案不一致（0.x.0 vs 0.1.x） | P1 | `feature-inventory.md`, `roles-and-permissions.md` |
| 3 | feature-inventory 版本陈旧 | P1 | `feature-inventory.md` |
| 4 | roles-and-permissions.md 同版本重复 | P1 | `roles-and-permissions.md` |
| 5 | 审计行号偏移 | P2 | 已记录（建议改用章节引用） |
| 6 | row-polymorphism.md 版本不匹配 | P2 | `discussion-row-polymorphism.md` |
| 7 | `discussions/index.md` 遗漏文件 | P2 | `discussions/index.md` |
| 8 | `system-baseline.md` zig→c 标签误用（20 处） | P2 | `system-baseline.md` |

**总计**：4 P1 + 4 P2，已全部修复
