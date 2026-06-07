# 讨论：String 操作与 Path 模块的函数归属

## 背景

在文档评审中发现，示例代码和设计文档中多处使用了裸顶层函数调用（如 `split "\n" content`、`endsWith ".log"`），但这些函数在标准库和类型系统中未被定义为顶层函数。需要明确 String 类型操作和 Path 类型操作的函数归属约定。

## 参与方

- 项目维护者（设计决策）
- AI Agent（实施）

## 讨论内容

### 问题 1：String 操作是顶层函数还是类型函数？

示例代码中存在两种用法：
- `split "\n" content`（裸函数）
- `String.split "\n" content`（模块限定）

**决策**：所有 String 操作（`split`、`contains`、`endsWith`、`startsWith`、`join`、`trim`、`toUpper`、`toLower`、`replace`、`length`、`slice`）均为 `String` 类型的函数，必须通过 `String.xxx` 模块限定调用。不存在裸顶层函数。

### 问题 2：Path 模块的函数有哪些？

`Path` 是内置类型，但 `import Path` 导入的 `Path` 模块包含工具函数。

**决策**：`Path` 模块常量和函数：
- `Path.cwd`：当前工作目录（脚本启动时冻结）
- `Path.join : Path -> String -> Path`：拼接路径段
- `Path.parent : Path -> Path`：父目录路径
- `Path.fileName : Path -> String`：文件名（含扩展名）
- `Path.extension : Path -> String`：文件扩展名

## 结论

1. `String.xxx` 为 String 类型函数的标准调用形式
2. `Path` 模块包含路径操作工具函数
3. 已修复全仓库 6 处裸 `split` 调用和 2 处裸 `endsWith` 调用
4. 已更新 `type-system.md:294` 标注 String 操作模块归属
5. 已在 `standard-library.md` 新增 `Path` 模块文档

## 行动项

- [x] file-processor.md：`split` → `String.split`（3 处）
- [x] code-formatting.md：`split` → `String.split`（3 处）
- [x] standard-library.md：`endsWith` → `String.endsWith`
- [x] type-system.md：标注 String 操作模块归属
- [x] standard-library.md：新增 Path 模块文档
