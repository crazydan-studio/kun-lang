# kun-lang — 核心语言运行时

产出 `kun`（CLI 工具）和 `libkunlang.so`（共享解释器核心）。

## 职责

解析 `.kun` 源文件、类型检查、执行脚本。实现 Kun 语言的全部语义——包括 HM 类型推断、效应系统、`do` 块求值、命令调用（fork-exec）、惰性 Stream。

## 内部组织

```
src/
├── main.zig                  # kun CLI 入口：子命令路由（默认执行 / fmt / lint / check / doc / cmd init）
├── lib.zig                   # libkunlang.so 库入口：导出解释器公共 API
│
├── lexer/
│   └── lexer.zig             # 词法分析器：源码 → Token 序列
│
├── parser/
│   └── parser.zig            # 语法分析器：Token 序列 → AST（Expr 枚举）
│
├── ast/
│   ├── ast.zig               # AST 节点定义（Expr 联合体：int_literal / lambda / do_block / case_expr / cmd_call …）
│   └── typed.zig             # 类型化 AST（TypedExpr + TypeId）+ Type 联合体
│
├── typecheck/
│   ├── infer.zig             # HM 类型推断：约束生成 + 合一求解
│   ├── env.zig               # TypeEnv 类型环境
│   └── effect.zig            # 效应检查器：AST 标记 do 块为 EffectFn
│
├── runtime/
│   ├── eval.zig              # 求值器：标记 switch 分发 TypedExpr 节点求值
│   ├── value.zig             # Value 联合体（int / float / string / bytes / list / map / closure / stream …）
│   ├── arena.zig             # Arena 分配器（per 脚本执行，线程安全标注）
│   └── env.zig               # RuntimeEnv：变量帧栈 + Primitive 函数表 + locale + 沙箱状态
│
├── command/
│   ├── cmd.zig               # Cmd.<bin> 语法：camelCase→kebab-case 映射 + Command 值构造
│   ├── exec.zig              # fork-exec 执行器 + pipe 捕获 stdout/stderr + waitpid
│   └── stream.zig            # Stream tagged union 状态机（cmd / mapped / filtered / taken / dropped / lines …）
│
├── cli/
│   ├── spec.zig              # CliSpec / CliArg / CliMeta / CliError 数据模型
│   └── parse.zig             # 安全参数 + 全局选项解析引擎（与 kun-shell 共享）
│
├── security/
│   ├── sandbox.zig            # 沙箱编排：父进程 Landlock/mount ns + 子进程 seccomp/rlimit
│   ├── landlock.zig           # Landlock LSM 文件控制（5.13+）/ 网络控制（6.7+）
│   ├── seccomp.zig            # seccomp-BPF 系统调用过滤（per 子进程 fork 后安装）
│   └── rlimit.zig             # rlimit 资源限制（CPU / AS / NOFILE / NPROC）
│
├── i18n/
│   ├── locale.zig             # locale 检测：KUN_LOCALE → LANG → LC_MESSAGES → 缺省 en
│   └── msg.zig                # 消息翻译：msgid 查表 + 编译期 .po 嵌入 + 外挂 .po 加载
│
└── stdlib/
    ├── primitive.zig          # Primitive 函数表：编译期常量的 [Primitive] 函数注册 + 受保护模块名集合
    ├── int.zig                # Int 内置绑定：abs / min / max / pow / clamp / fromString / toFloat / toString
    ├── float.zig              # Float 内置绑定：sin / cos / tan / exp / log / sqrt / floor / ceil / round …
    ├── string.zig             # String 内置绑定：length / slice + toString（编译器级泛型）
    ├── bytes.zig              # Bytes 内置绑定：length / slice / fromHex / toHex
    ├── list.zig               # List 结构操作：length / head / last / get / append / reverse / sort / slice …
    ├── map.zig                # Map 结构操作：get / keys / values / size / insert / remove
    ├── set.zig                # Set 结构操作：size / contains / insert / remove
    ├── regex.zig              # Regex 引擎：PCRE2/regexec 绑定
    ├── io.zig                 # IO Primitive：print / println / readln / readAll / readBytes / eprint …
    ├── env.zig                # Env Primitive：getenv / list / contains
    ├── file.zig               # File Primitive：readString / writeString / stat / list / mkdir / glob …
    ├── process.zig            # Process Primitive：exit / pid / uid / gid / kill / wait / sleep
    ├── cmd.zig                # Cmd 执行 Primitive：pipe? / exec / execSafe / which …
    ├── hash.zig               # Hash：SHA-256
    ├── base64.zig             # Base64 编解码
    └── stream.zig             # Stream 终端操作：fromList / toList / iter / fold / string / bytes
```

## 关键约束

- 所有 Zig 源码遵循 `docs/ai-agent/context/zig-patterns.md` 的惯用模式
- Arena 分配器传递规范：每个公开函数显式接收 `*Arena` 或 `*RuntimeEnv`
- 标记 switch（labeled switch）用于求值器节点分发——利用 `continue :eval` 实现尾递归消除和分支预测优化
- 闭包环境使用 `[]const Value` COW 切片的浅拷贝——不可变，不嵌套深拷贝
- `libkunlang.so` 通过 C ABI 导出公共 API，供 `kun-shell` 和 `kun-lsp` 调用
- 标准库导出函数通过 Primitive 函数表注册，受保护模块名集合防用户代码覆写

## 测试

```bash
cd code/kun-lang
zig build test       # 全量单元测试
zig build run        # 构建并运行示例脚本
```
