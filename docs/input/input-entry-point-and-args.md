# 输入记录：脚本入口与参数传递

## 来源

项目维护者，2026-05-30

## 核心问题

1. 可执行脚本是否都需要以 `main` 函数为入口？
2. 如何接受和解析脚本的传参？
3. 如何接受命名参数（`--flag`、`-o value`）？

## 讨论要点

### 入口方案

| 方案 | 规则 |
|------|------|
| A. 强制 `main` | 每个可执行文件必须定义 `main : IO Unit` |
| B. 顶层即入口 | 顶层 IO 表达式按顺序执行，`main` 可选 |
| C. 混合 | 有 `main` 则从 `main` 启动；无 `main` 则执行顶层 IO |

最终采用方案 C。同时：
- `main` 签名非 `IO Unit` 或 `List String -> IO Unit` 时告警
- 有 `module export` 的库文件不自动执行顶层表达式
- 无 `main` 且无顶层 IO 表达式时告警

### 脚本参数

- `main : List String -> IO Unit` 接收命令行参数
- 脚本名（argv[0]）不传入
- 无参数时传入空列表

### 命名参数

通过标准库 `Args` 模块解析：
- `Args.flag name short` — 布尔开关（`--verbose`/`-v`）
- `Args.option name short` — 带值选项（`--output file`/`-o file`）
- `Args.positional index` — 位置参数

## 设计结果

- `syntax.md`：新增"脚本入口"章节，含入口规则、命令行参数、命名参数
- `standard-library.md`：新增 `Args` 模块文档
