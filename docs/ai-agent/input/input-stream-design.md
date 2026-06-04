# 输入记录：Stream 设计与错误处理

## 来源

项目维护者，2026-05-30

## 核心问题

1. `stream` 关键字是否必要？Stream 应如何构造和消费？
2. 返回 IO Stream 的函数应如何处理错误？
3. 如何区分构造阶段（打开文件）和运行时阶段（读取中）的错误？

## 讨论要点

### `stream` 关键字是否必要

- `stream expr` 只有一种真正需要的场景：将非 Stream 值转为 Stream
- 文件读取等天然返回 Stream 的操作不需要 `stream`
- 结论：移除 `stream` 关键字，用 `Stream.fromList`/`Stream.range` 等模块函数替代

### IO Stream 必须解包后才能消费

- `Stream.readLines : Path -> IO (Result (Stream String) IOError)`
- 构造阶段错误通过 `Result` 暴露，可用 `<-!` 自动解包或显式 match
- 运行时错误静默终止流（与 shell 管道行为一致）
- 安全版本 `readLinesSafe` 每行包裹 `Result`

### 错误处理模型

- `name <-! expr` 同时解包 IO 和 Result，Err 早返回
- `name <- expr` 仅解 IO，留 `Result` 给显式处理
- Stream 上不支持 `result?` 逐元素解包，用 `filterMap Result.ok` 代替

## 设计结果

- `syntax.md`：新增 Stream 章节，删除 `stream` 关键字
- `standard-library.md`：新增 Stream 模块文档
- `type-system.md`：更新 Stream 类型描述
- 示例文件更新为新 Stream API
