# Bug 修复

本目录存放 Bug 修复笔记，记录问题现象、根因分析、修复方案和预防措施。

## 编写指南

在编写 Bug 修复笔记前，请阅读 [Bug 修复笔记编写指南](00-bug-fix-note-writing-guide.md)。

## 笔记结构

每条 Bug 修复笔记应包含以下部分：

1. **问题描述**：Bug 的表现、复现步骤和影响范围
2. **根因分析**：Bug 的根本原因
3. **修复方案**：具体的修复方法和变更
4. **验证方法**：如何验证 Bug 已修复
5. **预防措施**：防止同类 Bug 再次发生的措施

## 文件命名

使用 `bug-<简短描述>.md` 格式，例如：

- `bug-type-inference-null-pointer.md`
- `bug-pipe-lazy-eval-deadlock.md`
- `bug-namespace-escape-path.md`
