# 文档命名与时效性

## 文件命名规范

| 类型 | 格式 | 示例 |
|---|---|---|
| 稳定文档 | `kebab-case.md` | `project-vision.md` |
| 日期记录 | `YYYY-MM-DD-描述.md` | `2026-05-27-initial-setup.md` |
| 编号指南 | `NN-描述.md` | `00-requirement-synthesis-guide.md` |
| 图表文件 | `描述.puml` | `type-system-overview.puml` |

## 文档时效性

### 活跃文档

- `docs/ai-agent/context/` — 始终保持最新
- `docs/ai-agent/architecture/` — 当前版本的架构
- `docs/ai-agent/design/` — 当前版本的设计
- `docs/ai-agent/requirements/` — 当前活跃的需求

### 归档文档

- `docs/ai-agent/archive/<version>/` — 历史版本文档
- 归档后不应再被修改

### 过程文档

- `docs/ai-agent/plans/`、`docs/ai-agent/audits/` — 按时间组织
- 过程文档不需要保持最新，但应完整保留历史记录
