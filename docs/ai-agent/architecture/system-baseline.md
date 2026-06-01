# 系统基线

## 技术栈

| 层 | 技术选择 | 说明 |
|---|---|---|
| 宿主语言 | Zig | 高性能、无 hidden control flow、直接操作内存 |
| 目标平台 | Linux | 使用 dlopen/dlsym、namespace 等 Linux 特有机制 |
| 文档构建 | VitePress + pnpm | 现代化的静态文档站点 |
| 版本控制 | Git + GitHub | 分布式版本控制 |

## 运行时生命周期

运行时从启动到退出的完整流程分为四个阶段：

### 启动阶段

```
CLI 参数解析 → 源码读取 → 词法分析 → 语法分析 → 类型检查
```

1. **CLI 参数解析**：运行时解析命令行参数，分离脚本路径与脚本参数
2. **源码读取**：以 UTF-8 编码读取 `.kun` 文件内容到内存
3. **词法分析**：将源码扫描为 Token 序列
4. **语法分析**：将 Token 序列解析为 AST
5. **类型检查**：对 AST 进行类型推断和检查，生成带类型标注的 Typed AST

类型检查通过后才进入初始化阶段。类型检查失败时输出结构化错误报告并终止。

### 初始化阶段

```
运行时环境建立 → 能力系统初始化 → 模块解析 → 标准库绑定
```

1. **运行时环境建立**：
   - 创建 Arena 分配器（per 脚本执行）
   - 设置全局求值环境（变量帧栈）
   - 注册内置 Primitive 函数表

2. **能力系统初始化**：
   - 解析脚本级权限声明（`with caps` 声明）
   - 初始化能力管理器（Capability Manager）
   - 设置默认权限（工作目录及其子目录）

3. **模块解析与加载**：
   - 解析 `import` 语句
   - 按搜索路径查找模块文件
   - 递归加载依赖模块并缓存
   - 检测循环依赖

4. **标准库绑定**：
   - 将内置类型（List、Map、Set、Stream 等）的操作注册到环境
   - 将 IO 操作（readFile、writeFile 等）注册为 Primitive

### 执行阶段

```
入口解析 → AST 求值 → 效应编排 → 命令调用
```

1. **入口解析**：按入口规则确定执行起点（`main` 函数或顶层表达式）
2. **AST 求值**：递归求值 Typed AST 节点
3. **效应编排**：`do` 块按顺序执行 IO 操作，`<-` 解包 IO 包装
4. **命令调用**：通过 dlopen/ptrace/fork-exec 执行外部命令

求值策略详见下方"执行模型"章节。

### 清理阶段

```
资源释放 → 退出码传播 → 运行时终止
```

1. **资源释放**：
   - 关闭所有打开的文件描述符
   - 销毁 Arena 分配器（释放所有 per-script 分配的内存）
   - 释放模块缓存

2. **退出码传播**：根据执行结果确定进程退出码
   - `main` 返回 `IO Unit` → 退出码 0
   - 顶层 IO 表达式执行成功 → 退出码 0
   - 未处理的 `Err` 传播到顶层 → 退出码 1
   - 运行时 Panic → 退出码 127

## 执行模型

### 求值策略

Kun 采用**严格求值**（Strict Evaluation，又称 Applicative Order）作为默认策略：

| 构造 | 求值策略 | 说明 |
|------|---------|------|
| 纯表达式 | 严格 | 参数在函数应用前求值 |
| 函数体 | 严格 | 进入函数时立即求值 |
| `case` 分支 | 按需 | 仅匹配到的分支被求值 |
| `if`/三元 | 按需 | 仅条件匹配的分支被求值 |
| `&&`/`\|\|` | 短路 | 左侧确定结果时右侧不求值 |
| `Stream` | 惰性 | 元素在消费时按需拉取 |
| `let ... in` 绑定 | 延迟 | 绑定在被引用前不强制求值 |

`let ... in` 绑定的延迟求值规则：

```kun
a =
  let
    x = expensive ()     // 不会立即求值
    y = x + 1            // 不会立即求值
  in
    // 在此处触发 x 和 y 的求值
    y
```

### IO 效应编排

`do` 块在运行时的表示是**嵌套的函数调用链**，而非特殊控制流结构。每个 `do` 块被去糖（desugar）为一系列函数应用：

```kun
main : IO Unit
main =
  do
    x <- readFile p"/tmp/a"
    y <- readFile p"/tmp/b"
    print (x ++ y)
```

去糖后的运行时表示：

```kun
main = (readFile p"/tmp/a") >>= \x ->
        (readFile p"/tmp/b") >>= \y ->
        print (x ++ y)
```

其中 `>>=` 的类型为 `IO a -> (a -> IO b) -> IO b`，在运行时表现为：

- 对左侧 `IO a` 求值，得到 `a`
- 将 `a` 传入右侧函数，得到 `IO b`
- 返回 `IO b` 作为继续执行的延迟值

`do in` 块的去糖方式类似，但最后一行表达式的结果作为 `do` 块的返回值：

```kun
loadConfig : Path -> IO Config
loadConfig = \path ->
  do
    content <- readFile path
  in
    Config { content = content, size = length content }
```

去糖后：

```kun
loadConfig = \path ->
  readFile path >>= \content ->
  let
    result = Config { content = content, size = length content }
  in
    result
```

`IO` 效果的运行时表示为**thunk 结构体**：

```zig
struct IO_Thunk {
    void* (*eval)(void* env);    // 求值函数指针
    void* env;                   // 闭包环境（捕获的变量）
};
```

- `eval` 执行实际的副作用操作
- `env` 存储闭包中捕获的变量
- `>>=` 组合两个 thunk 时，外层 thunk 的 `eval` 先执行，其返回值传入内层函数

### `<-` 解包的运行时语义

`<-` 在运行时执行以下步骤：

1. 对右侧 `IO T` 表达式求值：调用 thunk 的 `eval` 函数
2. 从 thunk 的返回值中提取类型 `T` 的值（非 `IO` 包装）
3. 将提取的值绑定到左侧名字
4. 继续执行后续表达式

`<-?` 额外执行 Result 解包：

1. 对右侧 `IO (Result T E)` 表达式求值
2. 从 IO thunk 中提取 `Result T E` 值
3. 对 Result 执行模式匹配：
   - `Ok t` → 将 `t` 绑定到左侧名字，继续执行
   - `Err e` → 将 `e` 作为错误传播到当前函数的调用者（提前返回）

### Stream 惰性求值

Stream 在运行时的核心表示是一个**拉取驱动的迭代器**：

```zig
struct Stream {
    void* state;                 // 迭代器内部状态
    Maybe (*next)(void* state);  // 拉取下一个元素
    void (*drop)(void* state);   // 释放迭代器状态
};
```

- `next` 返回 `Maybe t`：`Just t` 表示有下一个元素，`Nothing` 表示流已终止
- 变换操作（`map`、`filter`、`take`）通过包裹 `next` 函数构造新的 Stream
- 终端操作（`fold`、`toList`、`iter`）循环调用 `next` 直到返回 `Nothing`

Stream 构造与消费的两阶段分离：

```kun
// 构造阶段：打开文件，返回 IO (Result (Stream String) IOError)
// 此处 Stream 的 state 包含文件描述符，next 包含 readline 逻辑
lines <-? Stream.readLines p"/tmp/log.txt"

// 消费阶段：iter 循环调用 lines 的 next 函数
// 每次调用 next 从文件读取一行
iter print lines
```

## 错误诊断

### 错误类型体系

运行时定义了四种结构化错误类型，每种携带丰富的诊断上下文：

### `TypeError`

类型检查阶段的错误，包含：

```zig
struct TypeError {
    char*   file;          // 源文件名
    uint32_t line;         // 行号（1-indexed）
    uint32_t column;       // 列号（1-indexed）
    char*   expected;      // 期望类型的可读描述
    char*   actual;        // 实际类型的可读描述
    char*   reason;        // 错误原因描述
    char*   suggestion;    // 修复建议
};
```

示例消息格式：

```
类型错误 [E001]: 类型不匹配
  ┌─ script.kun:12:5
  │
12  │  42 + "hello"
  │  ───┬───
  │     ╰── String 类型不能与 Int 进行 + 运算
  │
  提示：字符串拼接请使用 ++ 操作符
```

### `PermissionError`

权限检查阶段的错误，发生在能力管理器拒绝操作时：

```zig
struct PermissionError {
    char*    resource_type;     // 资源类型（"file"、"network"、"process" 等）
    char*    resource_path;     // 资源路径或标识
    char*    capability_name;   // 所需能力名称
    char*    source_file;       // 源码文件
    uint32_t source_line;       // 源码行号
    char*    deny_reason;       // 拒绝原因详细说明
    char*    suggestion;        // 修改建议（with caps 声明语法模板）
};
```

示例消息格式：

```
权限错误 [E002]: 权限不足
  ┌─ script.kun:15:3
  │
15  │  readFile p"/etc/shadow"
  │  ───────┬───────
  │         ╰── 对文件 /etc/shadow 的读取权限被拒绝
  │
  需要能力: fs.read("/etc/shadow")
  提示：请在脚本头部添加权限声明

    with caps
      fs.read = [Path.cwd, p"/etc/shadow"]
```

### `ValidationError`

参数验证阶段的错误，发生在 CDF 定义的校验约束不满足时：

```zig
struct ValidationError {
    char*   validator_name;    // 验证器名称（"range"、"length"、"regex"、"enum"、"custom"）
    char*   param_name;        // 参数名
    char*   actual_value;      // 实际值的字符串表示
    char*   constraint;        // 约束条件的可读描述
};
```

### `CommandError`

命令执行阶段的错误，发生在调用外部命令失败时：

```zig
struct CommandError {
    char*    command_name;     // 命令名
    int32_t  exit_code;        // 进程退出码（-1 表示未正常退出）
    char*    stderr_output;    // stderr 内容（可能为空）
    char*    source_file;      // 源码文件
    uint32_t source_line;      // 源码行号
};
```

### 错误传播模型

| 错误类型 | 检测阶段 | 传播方式 | 处理方式 |
|---------|---------|---------|---------|
| `TypeError` | 类型检查 | 编译期报错 | 必须修复后重试 |
| `PermissionError` | 运行时 | `IO (Result T PermissionError)` | 调用者通过 `?`/`<-?`/`case` 处理 |
| `ValidationError` | 运行时 | `Result T ValidationError` | 调用者通过 `?`/`case` 处理 |
| `CommandError` | 运行时 | `IO (Result T CommandError)` | 调用者通过 `?`/`<-?`/`case` 处理 |

### 报告管道

```
Source Location
      │
      ▼
Error Structure ← Error Kind + Context
      │
      ├── Compile-time → format → stderr → exit(1)
      │
      └── Runtime → Result T E → user code handles
                         │
                         └── Unhandled Err → format → stderr → exit(exit_code)
```

- 编译期错误（`TypeError`）直接输出到 stderr，进程退出码 1
- 运行时错误（`PermissionError`、`CommandError` 等）通过 `Result T E` 类型传递给用户代码
- 未处理的运行时错误传播到顶层时，运行时自动格式化并输出到 stderr，退出码依据错误类型确定

## 命令加载机制

### 整体架构

```
Kun 脚本中的命令调用
        │
        ▼
  命令加载器
        │
        ├── 内置命令 → 直接执行（Zig 函数调用）
        │
        ├── CDF 适配命令 → dlopen → C ABI 调用
        │
        ├── 未知命令（可适配）→ ptrace 适配层 → stub 注入
        │
        └── 未知命令（不可适配）→ fork/exec → argv 传参
```

### 命令发现策略

命令加载器按以下优先级查找命令：

1. **内置命令**：运行时预置的核心命令（ls、cat、grep 等），编译在运行时二进制中
2. **CDF 适配命令**：有 CDF 描述文件的命令，可通过 dlopen 直接加载
3. **ptrace 适配命令**：无 CDF 但可通过 ptrace 拦截+stub 注入适配的命令
4. **fork/exec 回退**：无法适配的命令通过传统进程创建方式执行

命令查找路径：内置表 → CDF 缓存 → PATH 环境变量搜索

### C ABI 函数签名约定

命令的 C ABI 入口函数遵循以下签名约定：

```zig
// 通用入口函数签名
int32_t command_entry(const CommandArgs* args, CommandResult* result);

// 参数结构体（AOT 编译时根据 CDF 确定精确结构）
typedef struct {
    uint64_t count;              // 参数个数
    CommandArg fields[];         // 参数数组，每个元素为 tagged union
} CommandArgs;

// 返回值结构体
typedef struct {
    int32_t  exit_code;       // 0 = 成功，非0 = 错误码
    Slice    stdout_data;     // 标准输出（二进制或文本）
    Slice    stderr_data;     // 错误输出
    ErrorTag error_tag;       // 错误分类标签（成功/权限/参数/运行时）
} CommandResult;
```

### 参数类型到 C 类型的映射

| Kun 类型 | C ABI 类型 | 说明 |
|---------|-----------|------|
| `Int` | `int64_t` | 直接映射 |
| `Nat` | `int64_t` | 非负约束由类型检查器保证 |
| `Float` | `double` | 直接映射 |
| `Bool` | `uint8_t` | 0 = false, 1 = true |
| `String` | `Slice { uint8_t* ptr, uint64_t len }` | UTF-8 切片 |
| `Bytes` | `Slice { uint8_t* ptr, uint64_t len }` | 二进制切片 |
| `Path` | `Slice { uint8_t* ptr, uint64_t len }` | UTF-8 路径切片 |
| `Char` | `uint32_t` | Unicode 标量值 |
| `Duration` | `int64_t` | 纳秒数 |
| `List t` | `Array { uint8_t* ptr, uint64_t len, uint64_t cap }` | 连续存储 |
| `Maybe t` | `TaggedUnion { uint8_t tag, uint64_t value }` | 0=Nothing, 1=Just |
| `Result t e` | `TaggedUnion { uint8_t tag, uint64_t ok, uint64_t err }` | 0=Ok, 1=Err |

### 结构化参数序列化

对于通过 dlopen 调用的命令，参数以**结构化的二进制块**传递，而非 argv 字符串数组：

```
序列化格式：
┌─────────────────────────────────────────┐
│  Signature Hash (SHA-256, 32 bytes)     │  ← 验证参数结构与 CDF 一致
├─────────────────────────────────────────┤
│  Argument Count (uint64_t)              │
├─────────────────────────────────────────┤
│  Argument 1: Tag + Length + Payload     │
│  Argument 2: Tag + Length + Payload     │
│  ...                                    │
├─────────────────────────────────────────┤
│  Capability Token (optional, 64 bytes)  │  ← 调用者权限令牌
└─────────────────────────────────────────┘
```

- 序列化缓冲区由调用者管理的 Arena 分配
- 单个参数最大 2^31 - 1 字节
- 参数总数上限 2^16 - 1（65535）

### dlopen 符号解析流程

```
命令名 "ls"
    │
    ▼
查找 CDF 缓存 → 找到签名定义
    │
    ▼
计算签名哈希 → 查找已加载的共享库
    │
    ▼
未命中 → 搜索命令路径 → 验证二进制完整性 (SHA-256)
    │
    ▼
生成适配共享库（编译 C ABI 包装器）
    │
    ▼
dlopen 加载 → dlsym 定位入口函数
    │
    ▼
签名验证 → 参数序列化 → 调用 → 结果反序列化
```

### ptrace 适配层

对于没有 CDF 且无法直接 dlopen 的命令，运行时尝试 ptrace 适配：

1. **触发条件**：命令无 CDF 签名，且满足以下任一条件
   - 运行时通过 `--help`/man 手册成功推断出近似签名
   - 用户通过项目级 CDF 提供了签名定义

2. **适配流程**：
   - fork 子进程执行目标命令
   - 父进程通过 ptrace 拦截子进程的系统调用
   - 注入透明 stub：将结构化参数转换为 argv 字符串并传递给子进程
   - 拦截子进程的 write 系统调用，捕获 stdout/stderr

3. **性能模型**：
   - ptrace 适配比直接 dlopen 慢 10-100 倍（取决于参数复杂度和输出大小）
   - 适配结果可缓存（签名的 C ABI 包装器生成后缓存到磁盘）

### fork/exec 回退

当 dlopen 和 ptrace 都不可用时，回退到传统 fork/exec 模型：

1. **适用场景**：
   - 命令为脚本文件（Python、Perl 等），无法通过 dlopen 加载
   - ptrace 适配失败（权限不足、容器环境限制等）
   - 用户强制指定回退模式

2. **进程管理**：
   - fork 子进程 → exec 加载命令 → 传递 argv 字符串数组
   - 父进程 waitpid 收集退出码
   - stdout/stderr 通过管道捕获

3. **退出码收集**：
   - WEXITSTATUS → `ExitCode.success`（0）或 `ExitCode.generalError`（非0）
   - WIFSIGNALED → `CommandError` 包含终止信号编号

### 失败处理链

命令加载和执行失败时，按以下链式报告：

```
命令未找到 → CommandError { command_name, exit_code: -1 }
    │
    ▼
dlopen 失败 → CommandError { 原因: "dlopen failed: <dlerror>" }
    │
    ▼
签名不匹配 → CommandError { 原因: "signature mismatch: expected ... got ..." }
    │
    ▼
ABI 不匹配 → CommandError { 原因: "ABI version mismatch" }
    │
    ▼
运行时崩溃 → CommandError { 原因: "child terminated by signal <n>" }
    │
    ▼
成功 → CommandResult { exit_code: 0, stdout_data, stderr_data }
```

## 类型运行时表示

### 基础类型

| Kun 类型 | C ABI 表示 | 大小 | 对齐 |
|---------|-----------|------|------|
| `Int` | `int64_t` | 8 字节 | 8 |
| `Nat` | `int64_t` | 8 字节 | 8 |
| `Float` | `double` | 8 字节 | 8 |
| `Bool` | `uint8_t` | 1 字节 | 1 |
| `Char` | `uint32_t` | 4 字节 | 4 |
| `Duration` | `int64_t` | 8 字节 | 8 |
| `Unit` | `void` | 0 字节 | — |

### 字符串与字节类型

| Kun 类型 | C ABI 表示 |
|---------|-----------|
| `String` | `Slice { uint8_t* ptr, uint64_t len }` |
| `Bytes` | `Slice { uint8_t* ptr, uint64_t len }` |
| `Path` | `Slice { uint8_t* ptr, uint64_t len }` |

```zig
typedef struct {
    uint8_t* ptr;       // 指向 UTF-8 字节数据的指针
    uint64_t len;       // 字节长度（非字符数）
} Slice;
```

- `Slice` 不拥有内存的所有权，指向 Arena 分配器管理的区域
- `String` 始终是有效的 UTF-8 序列（由类型检查器保证）
- `Path` 与 `String` 运行时表示相同，语义上区分

### 复合类型

#### `List t`

```zig
typedef struct {
    uint8_t* ptr;       // 连续存储的元素数组
    uint64_t len;       // 当前元素个数
    uint64_t cap;       // 分配的容量（元素个数）
} Array;
```

- 元素在内存中连续存储，按元素类型的 ABI 大小对齐
- `len` 和 `cap` 以元素个数为单位（非字节数）
- 追加操作可能触发重新分配（迁移到更大的 Arena 块）

#### `Map k v`

Map 运行时采用哈希表实现：

```zig
typedef struct {
    uint64_t   capacity;        // 桶数量（2 的幂）
    uint64_t   count;           // 已用桶数量
    uint64_t   tombstone;       // 墓碑标记（已删除条目数）
    HashBucket buckets[];       // 桶数组
} HashMap;

typedef struct {
    uint64_t hash;          // 预计算的哈希值（0 = 空桶）
    uint8_t  key[];         // 键的序列化数据（变长）
    uint8_t  value[];       // 值的序列化数据（变长）
} HashBucket;
```

#### `Set t`

Set 运行时采用与 Map 相同的哈希表结构，仅使用键部分，值为空。

### 和类型（ADT）

ADT 在运行时表示为带标记的联合体：

```zig
// Maybe Int
struct Maybe_Int {
    uint8_t tag;        // 0 = Nothing, 1 = Just
    int64_t value;      // 仅 tag==1 时有意义
};

// Result String IOError
struct Result_String_IOError {
    uint8_t tag;          // 0 = Ok, 1 = Err
    Slice   ok_value;     // 仅 tag==0 时有意义
    IOError err_value;    // 仅 tag==1 时有意义
};
```

- `tag` 使用 `uint8_t`，支持最多 256 个变体
- 变体字段在联合体中以最大字段对齐
- 嵌套 ADT 递归展开

自定义 ADT 示例：

```kun
type SocketAddr
  = Tcp IpAddress Port
  | Udp IpAddress Port
```

运行时表示：

```zig
struct SocketAddr {
    // 0 = Tcp, 1 = Udp
    uint8_t tag;
    // 联合体：两个变体都包含 IpAddress + Port
    struct {
        IpAddress ip;
        Port      port;
    } data;
};
```

### Stream

```zig
struct Stream {
    void*    state;                // 迭代器内部状态（堆分配）
    void*    (*next)(void* state); // 拉取下一个元素，返回 Maybe t
    void     (*drop)(void* state); // 释放迭代器状态
    uint64_t elem_size;            // 元素类型大小（用于内存拷贝）
};
```

- `next` 返回 `void*`：非空指针 = `Just t`，NULL = `Nothing`
- 变换操作不修改 `state`，而是创建新的 Stream 结构体包裹前一个 Stream
- `drop` 释放 `state` 持有的所有资源（文件描述符、堆内存等）

### 函数值

```zig
typedef struct {
    void*    (*fn_ptr)(void* env, void* args);    // 函数入口
    void*    env;                                  // 闭包环境
    uint64_t arity;                                // 期望参数个数
    uint64_t env_size;                             // 环境大小
} Closure;
```

- `fn_ptr` 是函数代码的入口指针
- `env` 存储捕获的变量值（闭包环境）
- 部分应用（柯里化）通过返回新的 Closure 实现：
  - 新 Closure 的 `env` 包含已提供的参数 + 原始闭包环境
  - `arity` 减少已提供参数个数
  - `fn_ptr` 指向一个"填充参数并转发"的包装函数

### IO 包装

```zig
struct IO_Thunk {
    void*   (*eval)(void* env, void* result_buf);    // 求值函数指针
    void*   env;                                      // 闭包环境
    uint64_t result_size;                             // 返回值类型大小
};
```

- `eval` 执行副作用操作，将结果写入 `result_buf`
- `>>=` 组合操作：创建新的 `IO_Thunk`，其 `eval` 依次调用两个子 thunk

## 内存管理

### 分配策略

采用**分层分配**策略，核心是 Arena 分配器：

| 层次 | 分配器 | 生命周期 | 用途 |
|------|--------|---------|------|
| 脚本级 | Arena | per 脚本执行 | AST、类型表示、临时字符串 |
| 模块级 | Arena | per 模块加载 | 模块 AST、缓存类型 |
| 全局 | 标准堆 | 运行时进程全周期 | 内置类型表、Primitive 注册表 |

Arena 分配器特性：

- 线性分配（ bump allocation ），无释放操作
- Arena 在阶段结束时整体销毁（无需逐对象回收）
- 大对象（> 64KB）直接 mmap 分配，不占用 Arena 空间
- 长期存活值（如模块缓存）在初始化时预分配到全局堆

### 字符串内部化

- 所有字符串字面量在编译期收集，统一存储到字符串表
- 运行时字符串拼接产生的新字符串由 Arena 分配
- Path 字面量使用与 String 相同的内部化机制
- 短字符串（< 32 字节）直接内联到结构体（Small String Optimization）

### 容器内存布局

| 容器 | 布局 | 元素存储 |
|------|------|---------|
| `List t` | 连续数组 | 元素值连续排列，按元素 ABI 大小计算偏移 |
| `Map k v` | 开地址哈希表 | 键值对存储在桶数组中 |
| `Set t` | 开地址哈希表 | 仅存储键，值与键相同 |
| `Stream` | 堆分配的 state 结构体 | 元素在 `next` 函数中动态分配 |

### 资源清理

资源管理原则：**谁打开谁关闭，Arena 销毁时自动清理**。

```
// 执行阶段开始 → 创建 Arena
//   ↓
//   打开文件 fd → Arena 注册终结器
//   ↓
//   执行 IO 操作 → 结果分配在 Arena 上
//   ↓
//   打开更多文件 → Arena 注册更多终结器
//   ↓
// 执行阶段结束 → 销毁 Arena
//   → 自动调用所有注册的终结器（关闭文件描述符等）
```

关键机制：

- Arena 维护一个终结器（finalizer）列表
- 打开文件等操作向 Arena 注册终结器（关闭 fd、释放内存等）
- Arena 销毁时按注册逆序执行所有终结器
- 文件描述符泄漏检测：Arena 销毁时若有未关闭的 fd，输出告警

### 循环引用保护

Kun 的**不可变性**原则从语言层面消除了循环引用：

- 所有数据结构不可变，无法在创建后修改引用
- 容器不可包含指向自身的引用（类型系统保证）
- 无需 GC 标记-清扫或引用计数

## 模块解析与加载

### 模块搜索路径

模块导入时的搜索顺序：

```
1. 标准库路径:   <runtime_prefix>/lib/kun/
2. 项目本地路径: ./<script_dir>/modules/
3. 用户自定义路径: $KUN_PATH 环境变量指定的目录列表
```

示例：`import List` 的搜索流程：

```
runtime_prefix/lib/kun/List.kun     → 找到，加载
./modules/List.kun                  → 未找到，跳过
$KUN_PATH/List.kun                  → 如果存在同名，优先级低于标准库
```

### 模块加载流程

```
import List with (map)
        │
        ▼
查找 List.kun 文件路径
        │
        ▼
文件存在？──否──→ 编译错误：模块未找到
        │
        ▼是
已在缓存中？──是──→ 返回缓存副本
        │
        ▼否
读取文件内容
        │
        ▼
词法分析 → 语法分析 → 类型检查
        │
        ▼
递归加载依赖模块（检测循环引用）
        │
        ▼
缓存模块 → 绑定到当前作用域
```

### 循环依赖检测

模块加载器维护一个**加载中集合**（loading set）：

```zig
loading_set = {}         // 当前正在加载的模块路径集合
cached_modules = {}      // 已完成的模块缓存

load_module(path):
    if path in cached_modules → return cached_modules[path]
    if path in loading_set → 编译错误：循环依赖 detected
    loading_set.add(path)

    module = parse_and_typecheck(path)
    for each import in module.imports:
        // 递归
        load_module(resolve_path(import))

    loading_set.remove(path)
    cached_modules[path] = module
    return module
```

### 标准库模块

标准库模块分为两类：

| 类别 | 实现方式 | 示例 |
|------|---------|------|
| 纯 Kun 实现 | `.kun` 文件，用语言自身实现 | `List`、`Map`、`Set`、`Maybe`、`Result` |
| Primitive 实现 | Zig 原生函数，注册到内置表 | `IO` 操作、`Stream`、`Args`、文件操作 |

Primitive 模块的处理：

- 运行时初始化时预注册 Primitive 函数表
- 标准库的 `.kun` 文件中声明 Primitive 函数的类型签名
- 类型检查器识别 Primitive 标记，允许无函数体的类型声明

```kun
// 标准库 List.kun 示例（Primitive 实现）
module List export (map, filter, fold, fromList)

// Primitive 函数：仅声明类型签名，函数体在运行时由 Zig 提供
map   : (a -> b) -> List a -> List b
filter : (a -> Bool) -> List a -> List a
fold   : (b -> a -> b) -> b -> List a -> b

// 非 Primitive 函数：用语言自身实现
fromList : Stream t -> List t
fromList = \stream ->
  stream |> fold (\acc elem -> acc ++ [elem]) []
```

## 标准库集成

### Primitive 函数注册表

运行时在初始化阶段注册所有 Primitive 函数：

```zig
// 内置操作函数表
typedef struct {
    // 模块名（如 "List"）
    const char* module_name;
    // 函数名（如 "map"）
    const char* func_name;
    // 函数入口指针
    void*       fn_ptr;
    // 参数个数
    uint64_t    arity;
    // 类型签名
    TypeSignature* signature;
} PrimitiveEntry;

// Primitive 注册表（编译期生成）
PrimitiveEntry BUILTIN_PRIMITIVES[] = {
    { "List",   "map",     list_map,     2, &SIG_LIST_MAP },
    { "List",   "filter",  list_filter,  2, &SIG_LIST_FILTER },
    { "List",   "fold",    list_fold,    3, &SIG_LIST_FOLD },
    { "Stream", "fromList", stream_from_list, 1, &SIG_STREAM_FROM_LIST },
    { "Stream", "range",   stream_range, 2, &SIG_STREAM_RANGE },
    { "Stream", "readLines", stream_read_lines, 1, &SIG_STREAM_READ_LINES },
    // ... 更多 Primitive
};
```

### IO 操作实现模式

IO 操作按以下模式实现为 Primitive：

```zig
// readFile 的 Primitive 实现（Zig 伪代码）
fn readFile(env: void*, args: void*) -> void* {
    let path = *(Slice*)args;

    // 1. 能力检查（委托给 Capability Manager）
    if (!capability_check("fs", "read", path)) {
        return create_permission_error(path, "fs", "read", ...);
    }

    // 2. 执行 POSIX 系统调用
    let fd = posix_open(path.ptr, O_RDONLY);
    if (fd < 0) {
        return create_io_error(errno_to_ioerror(errno), path);
    }

    // 3. 读取文件内容到 Arena
    let content = arena_alloc(arena, file_size);
    posix_read(fd, content.ptr, file_size);
    posix_close(fd);

    // 4. 返回 Result Slice IOError 的 tagged union
    return create_ok_result(content);
}
```

IO 操作的统一模式：

| 步骤 | 说明 |
|------|------|
| 能力检查 | 委托 Capability Manager 检查当前上下文是否拥有所需权限 |
| POSIX 调用 | 执行底层系统调用（open、read、write、stat 等） |
| Arena 分配 | IO 结果从当前脚本的 Arena 中分配 |
| 结果封装 | 返回值包裹为 `Result T E` 或 `IO (Result T E)` |

### Args 模块运行时支持

`Args` 模块的运行时实现分为两层：

1. **C 层辅助**（Primitive）：原始参数解析——将 `List String` 拆分为 flag、option、positional
2. **Kun 层封装**：类型安全的 API 包装（`Args.flag`、`Args.option`、`Args.parse` 等）

```zig
// C 层 Primitive（Zig 伪代码）
fn args_parse_raw(env: void*, args: void*) -> void* {
    // 声明器列表
    let decls = *(Array*)args[0];
    // 原始参数列表
    let raw   = *(Array*)args[1];

    let result = HashMap_new(arena);

    // 扫描原始参数，匹配声明器
    for (let i = 0; i < raw.len; i++) {
        let arg = raw[i];
        if (arg starts_with "--") {
            // 长选项匹配
        } else if (arg starts_with "-" && arg.len == 2) {
            // 短选项匹配
        } else {
            // 位置参数
        }
    }

    return Ok(result);
}
```

### Stream 模块运行时支持

Stream 的惰性求值在运行时通过状态机实现：

```zig
// Stream.readLines 的状态机（Zig 伪代码）
typedef struct {
    // 文件描述符
    int32_t   fd;
    // 读取缓冲区
    uint8_t   buffer[8192];
    // 缓冲区当前位置
    uint64_t  buf_pos;
    // 缓冲区有效数据长度
    uint64_t  buf_end;
    // 文件是否已读完
    bool      eof;
    // 行字符串的分配器
    Arena*    arena;
} ReadLinesState;

void* readlines_next(void* state_ptr) {
    let state = (ReadLinesState*)state_ptr;

    if (state.eof && state.buf_pos >= state.buf_end) {
        // Nothing: 流已终止
        return NULL;
    }

    // 从缓冲区读取直到换行符或 EOF
    let line = read_until_newline(state);
    // Just String
    return line;
}
```

## 类型系统概览

| 类别 | 类型 |
|---|---|
| 基础类型 | `Int`、`Nat`、`Float`、`Bool`、`String`、`Bytes`、`Char`、`Regex`、`Duration`、`Unit`、`Path` |
| 复合类型 | `List`、`Map`、`Set`、`Stream`、`Tuple` |
| 和类型 | `Maybe`、`Result`、自定义和类型 |
| 函数类型 | 命令函数、高阶函数、Lambda |
| Effect 类型 | `IO`（结构化 IO 操作管理） |

详细类型设计见 [类型系统设计文档](../design/type-system.md)。

## 命令签名系统

- **CDF（Command Description File）**：命令描述文件，定义命令的精确签名
- **内置签名**：核心命令（ls、cat、grep、find、sed、awk 等）预置精确签名
- **自动推断**：优先通过 man 手册获取帮助信息，回退到 `--help`/`-h`；能够识别子命令并为每个子命令分别建立独立签名
- **项目级自定义**：项目目录中提供更精确的签名定义
- **参数验证器**：`range`、`length`、`regex`、`enum`、`custom`，支持链式组合

命令签名系统的完整设计将在后续独立文档中展开。

## 安全模型

```
安全层
├── 最小权限原则
│   ├── 默认：工作目录及其子目录
│   └── 扩展：显式权限声明
│       ├── 脚本级声明
│       └── 作用域级声明（with caps）
├── 能力安全（Capability-Based Security）
│   ├── 运行时在启动时根据权限声明授予
│   ├── 父脚本显式传递
│   └── 用户确认后动态授予
├── 命令级安全
│   ├── CDF 导出能力名称用于 Seccomp 规则生成
│   ├── 二进制完整性校验（SHA-256 哈希）
│   ├── CDF 密码学签名（Ed25519）
│   ├── Seccomp 系统调用过滤（基于 CDF 自动推导）
│   ├── 单命令沙箱隔离（高风险命令独立 namespace）
│   └── 信任分级策略（trusted / verified / sandboxed / denied）
└── Linux Namespace 沙箱
    ├── Mount Namespace（文件系统隔离）
    ├── PID Namespace（进程隔离）
    └── 容器环境检测（避免嵌套命名空间）
```

安全模型的完整设计将在后续独立文档中展开。

## 版本历史

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1.0 | 2026-05-27 | 项目初始化，设计文档定型 |
| 0.1.0 | 2026-05-31 | 运行时架构全量扩展：生命周期、执行模型、错误诊断、命令加载、类型表示、内存管理、模块解析、标准库集成 |
