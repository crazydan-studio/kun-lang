# MVP 定义

## 最小可行产品范围

Kun 0.1.0 的 MVP 目标是验证核心语言设计的可行性。

## MVP 包含

- 基础类型系统（Int、Nat、Float、Bool、String、Bytes、Unit、Path）
- Maybe、Result 和类型
- 基本的命令函数抽象（至少支持 ls、cat、echo 等简单命令）
- 基本的管道操作符
- 简单的 REPL 交互环境
- 基本的类型检查

## MVP 不包含

- 泛型
- 完整的命令签名系统（CDF）
- 安全沙箱
- 高阶函数（map、filter、fold 等）
- 模块系统
- 标准库的完整实现

## 验证标准

- 能够编写简单的 Kun 脚本替代等价的 Shell 脚本
- 类型检查器能捕获基本的类型错误
- REPL 能交互式执行 Kun 表达式
