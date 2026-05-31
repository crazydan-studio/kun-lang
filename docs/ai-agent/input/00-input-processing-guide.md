# 输入处理指南

## 目的

规范原始输入的收集和初步处理流程。

## 输入来源

- 用户反馈
- 问题报告
- 功能请求
- 技术调研
- 代码审查发现

## 处理流程

1. 将原始输入记录到本目录
2. 对输入进行初步分类和标注
3. 识别需要澄清的歧义点
4. 在 `docs/ai-agent/discussions/` 中发起必要的讨论
5. 在 `docs/ai-agent/requirements/` 中综合为结构化需求

## 文件命名

使用 `input-<来源>-<简短描述>.md` 格式，例如：
- `input-user-command-compose-request.md`
- `input-bug-type-inference-error.md`
