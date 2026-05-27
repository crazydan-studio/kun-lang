# 系统基线

## 技术栈

| 层 | 技术选择 | 说明 |
|---|---|---|
| 宿主语言 | Zig | 高性能、无 hidden control flow、直接操作内存 |
| 目标平台 | Linux | 使用 dlopen/dlsym、namespace 等 Linux 特有机制 |
| 文档构建 | VitePress + pnpm | 现代化的静态文档站点 |
| 版本控制 | Git + GitHub | 分布式版本控制 |

## 运行时架构

### 命令加载机制

```
Kun 解释器
├── dlopen 加载命令二进制
│   ├── 标准化入口函数接口（C ABI 兼容）
│   ├── 透明适配层（ptrace 拦截 + stub 注入）
│   └── 回退到 fork/exec 模型
├── 结构化参数传递（非 argv 数组）
├── 类型检查与签名验证
└── 结果收集与错误处理
```

### 安全模型

```
安全层
├── 最小权限原则
│   ├── 默认：工作目录及其子目录
│   └── 扩展：显式权限声明
├── 能力安全（Capability-Based Security）
│   ├── 运行时在启动时根据权限声明授予
│   ├── 父脚本显式传递
│   └── 用户确认后动态授予
└── Linux Namespace 沙箱
    ├── Mount Namespace（文件系统隔离）
    ├── PID Namespace（进程隔离）
    └── 容器环境检测（避免嵌套命名空间）
```

## 类型系统概览

| 类别 | 类型 |
|---|---|
| 基础类型 | `Int`、`Nat`、`Float`、`Bool`、`String`、`Bytes`、`Char`、`Regex`、`Duration`、`Unit`、`Path` |
| 复合类型 | `List`、`Map`、`Array`、`Stream`、`Tuple` |
| 和类型 | `Maybe`、`Result`、自定义和类型 |
| 函数类型 | 命令函数、高阶函数、Lambda |
| Effect 类型 | `IO`（结构化 IO 操作管理） |

## 命令签名系统

- **CDF（Command Description File）**：命令描述文件，定义命令的精确签名
- **内置签名**：核心命令（ls、cat、grep、find、sed、awk 等）预置精确签名
- **自动推断**：根据 `--help`/`-h` 输出推断近似签名
- **项目级自定义**：项目目录中提供更精确的签名定义
- **参数验证器**：`range`、`length`、`regex`、`enum`、`custom`，支持链式组合

## 版本历史

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1.0 | 2026-05-27 | 项目初始化，设计文档定型 |
