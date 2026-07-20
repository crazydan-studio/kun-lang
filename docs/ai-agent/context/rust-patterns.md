# Rust 模式指南

> 本文件记录 Kun 项目实现中 Rust 语言的惯用模式、注意事项和最佳实践，供 LLM 代码生成时参考。
>
> **最后更新**：2026.07.20，基于 Rust 1.97。
> **官方文档**：https://forge.rust-lang.org/index.html

## 版本

- **Rust 版本**：**Rust 1.97**，作为 Kun 宿主语言。Rust 1.0 自 2015 年发布以来无 breaking change，Edition 机制（2015/2018/2021/2024）保证向后兼容性。
  - 官方文档：https://forge.rust-lang.org/index.html
  - 工具链管理：`rustup`
- **构建系统**：`Cargo`（`Cargo.toml` + `Cargo.lock`）
- **版本锁定**：`rust-toolchain.toml` 固定版本：
  ```toml
  [toolchain]
  channel = "1.97"
  targets = ["x86_64-unknown-linux-gnu", "x86_64-unknown-linux-musl"]
  ```

### Rust 1.97 关键特性

| 特性 | 说明 |
|------|------|
| Edition 2024 | 默认 Edition（可用 `#[rustfmt::skip]` 等稳定特性） |
| `let-else` | 稳定（`let Some(x) = expr else { return; };`） |
| `let-chains` | 稳定（`if let Some(x) = a && let Some(y) = b { }`） |
| `async fn` in traits | 稳定 |
| `impl Trait` in return | 稳定 |
| Generic Associated Types | 稳定 |
| `#[inline]` / `#[cold]` | 稳定（分支预测提示） |

## 内存管理

### Arena 分配器（唯一策略）

Kun 项目中**所有运行时分配**均通过 per-script Arena 完成。使用 `bumpalo` crate：

```rust
use bumpalo::Bump;

// ✅ 正确：使用 Arena 分配
let arena = Bump::new();
let result: &mut [u8] = arena.alloc_slice_fill_default(1024);

// ✅ 正确：AST 节点分配在 Arena 上
let node = arena.alloc(Expr::IntLit { value: 42 });

// ❌ 错误：不应使用全局堆分配（Box/Vec）做运行时 AST
let node = Box::new(Expr::IntLit { value: 42 });  // 禁止
```

**Arena 生命周期**：

```rust
// per-script Arena：脚本执行期间所有 AST/类型/运行时值分配在此
// 脚本退出时整体销毁，无 per-node free
pub struct RuntimeEnv {
    arena: Bump,
    // ...
}

impl RuntimeEnv {
    pub fn alloc<T>(&self, val: T) -> &mut T {
        self.arena.alloc(val)
    }
}
```

### Arena × 借用检查器

Rust 的借用检查器与 Arena 分配有摩擦——Arena 分配的引用 `&'arena T` 生命周期绑定到 Arena，不能逃逸。解决方案：

```rust
// ✅ 方案 1：Arena + 生命周期参数
pub struct Expr<'a> {
    kind: ExprKind<'a>,
    span: Span,
}

pub enum ExprKind<'a> {
    IntLit { value: i64 },
    App { func: &'a Expr<'a>, args: &'a [&'a Expr<'a>] },
    // ...
}

// ✅ 方案 2：Arena + ID 索引（避免生命周期蔓延）
pub struct ExprPool {
    exprs: Vec<Expr>,  // 仅在构建期用 Vec，构建完成后转为 Arena
}
pub type ExprId = u32;  // 索引，无生命周期

// 推荐方案 1（生命周期参数），LLM 对此模式生成质量高
```

### 禁止的模式

```rust
// ❌ 禁止：全局堆分配做运行时 AST/类型
let x = Box::new(Expr::IntLit { value: 42 });

// ❌ 禁止：Rc<RefCell<>> 做热路径 AST 遍历（性能开销）
let x = Rc::new(RefCell::new(Expr::IntLit { value: 42 }));

// ❌ 禁止：Vec 在 Arena 内部分配（Arena 分配的是 &mut [T]，不是 Vec）
let x = arena.alloc(Vec::new());  // 语义错误

// ✅ 正确：Arena 分配切片
let x: &mut [Expr] = arena.alloc_slice_fill_default(10);
```

## AST 和类型检查器

### Tagged Union（enum）

Kun 的 AST/类型表示使用 Rust `enum`（tagged union），`match` 做穷举模式匹配：

```rust
#[derive(Debug, Clone)]
pub enum Expr<'a> {
    IntLit { value: i64, span: Span },
    FloatLit { value: f64, span: Span },
    StringLit { value: &'a str, span: Span },
    Var { name: &'a str, span: Span },
    App { func: &'a Expr<'a>, args: &'a [&'a Expr<'a>], span: Span },
    Lambda { params: &'a [&'a str], body: &'a Expr<'a>, span: Span },
    LetIn { stmts: &'a [Stmt<'a>], result: &'a Expr<'a>, span: Span },
    Do { stmts: &'a [Stmt<'a>], with: Option<&'a Handler<'a>>, span: Span },
    Case { scrutinee: &'a Expr<'a>, branches: &'a [Branch<'a>], span: Span },
    // ...
}

// 求值器：match 分发
fn eval(expr: &Expr, env: &Env) -> Result<Value, EvalError> {
    match expr {
        Expr::IntLit { value, .. } => Ok(Value::Int(*value)),
        Expr::App { func, args, .. } => {
            let f = eval(func, env)?;
            let evaluated: Vec<Value> = args.iter()
                .map(|a| eval(a, env))
                .collect::<Result<_, _>>()?;
            apply(f, &evaluated)
        }
        // ... 穷举所有变体
    }
}
```

### 类型表示

```rust
#[derive(Debug, Clone, PartialEq)]
pub enum Type {
    Int,
    Float,
    Bool,
    String,
    Bytes,
    Char,
    Unit,
    Path,
    Duration,
    Regex,
    Fun { param: Box<Type>, result: Box<Type>, effects: EffectSet },
    Record { fields: Vec<(&'static str, Type)> },
    Tuple { elems: Vec<Type> },
    ADT { name: &'static str, args: Vec<Type> },
    Nilable(Box<Type>),
    Var(TypeVar),           // 类型变量 (HM 推断)
    Opaque(&'static str),   // 不透明类型 (TestCase 等)
}

#[derive(Debug, Clone, PartialEq)]
pub enum EffectSet {
    Empty,                  // ! {}
    Singleton(Effect),      // ! {IO}
    Union(Vec<Effect>),     // ! {IO, File}
    Var(TypeVar),           // ! e (效应多态)
}

#[derive(Debug, Clone, PartialEq)]
pub enum Effect {
    IO, File, Cmd, Random, DateTime, Signal, FFI,
    Env, Process, Test,
    User(&'static str),     // 用户自定义效应 (DB/Log 等)
}
```

### HM 类型推断

```rust
use std::cell::RefCell;

pub struct TypeEnv {
    // 类型变量表：TypeVar → Type
    bindings: RefCell<Vec<(TypeVar, Type)>>,
    // 效应变量表
    effect_bindings: RefCell<Vec<(TypeVar, EffectSet)>>,
    next_var: RefCell<u32>,
}

impl TypeEnv {
    pub fn fresh_type_var(&self) -> TypeVar {
        let mut next = self.next_var.borrow_mut();
        let v = TypeVar(*next);
        *next += 1;
        v
    }

    pub fn fresh_effect_var(&self) -> TypeVar {
        self.fresh_type_var()  // 效应变量复用类型变量编号
    }

    // 合一（unification）
    pub fn unify(&self, t1: &Type, t2: &Type) -> Result<(), TypeError> {
        match (t1, t2) {
            (Type::Int, Type::Int) => Ok(()),
            (Type::Var(v), other) | (other, Type::Var(v)) => {
                self.bind_var(*v, other.clone())
            }
            (Type::Fun { param: p1, result: r1, effects: e1 },
             Type::Fun { param: p2, result: r2, effects: e2 }) => {
                self.unify(p1, p2)?;
                self.unify(r1, r2)?;
                self.unify_effects(e1, e2)
            }
            // ... 其他情况
            _ => Err(TypeError::Mismatch(t1.clone(), t2.clone())),
        }
    }

    pub fn unify_effects(&self, e1: &EffectSet, e2: &EffectSet) -> Result<(), TypeError> {
        match (e1, e2) {
            (EffectSet::Empty, EffectSet::Empty) => Ok(()),
            (EffectSet::Var(v), other) | (other, EffectSet::Var(v)) => {
                // occurs check
                if self.occurs_in_effect(*v, other) {
                    return Err(TypeError::OccursCheck(*v));
                }
                self.effect_bindings.borrow_mut().push((*v, other.clone()));
                Ok(())
            }
            (EffectSet::Singleton(e1), EffectSet::Singleton(e2)) if e1 == e2 => Ok(()),
            (EffectSet::Union(es1), EffectSet::Union(es2)) => {
                // 无序集合比较：排序后比较
                let mut s1 = es1.clone();
                let mut s2 = es2.clone();
                s1.sort();
                s2.sort();
                if s1 == s2 { Ok(()) } else { Err(TypeError::EffectMismatch(e1.clone(), e2.clone())) }
            }
            _ => Err(TypeError::EffectMismatch(e1.clone(), e2.clone())),
        }
    }
}
```

## 子进程管理

### fork-exec + pipe 捕获

使用 `std::process::Command`：

```rust
use std::process::{Command, Stdio};
use std::io::Read;

// Cmd.exec：执行，丢弃 stdout，失败 panic
pub fn cmd_exec(cmd: &CommandValue) {
    let status = build_command(cmd)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .expect("command execution failed");
    if !status.success() {
        panic!("CommandFailed: exit code {:?}", status.code());
    }
}

// Cmd.execSafe：执行，返回 Result (Stream String) CommandError
pub fn cmd_exec_safe(cmd: &CommandValue) -> Result<StreamString, CommandError> {
    let mut child = build_command(cmd)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| CommandError::SpawnFailed(e.to_string()))?;

    // pipe 捕获 stdout 为 Stream
    let stdout = child.stdout.take().unwrap();
    Ok(StreamString::from_reader(stdout))
}

// Cmd.stream：执行，返回 Stream，失败 panic
pub fn cmd_stream(cmd: &CommandValue) -> StreamString {
    cmd_exec_safe(cmd).expect("command execution failed")
}

fn build_command(cmd: &CommandValue) -> Command {
    let mut c = Command::new(&cmd.name);
    c.args(&cmd.subcommands);
    // 选项 → argv（camelCase → kebab-case 映射）
    for opt in &cmd.options {
        c.args(&opt.to_argv());
    }
    c.args(&cmd.args);
    if cmd.use_dash && !cmd.args.is_empty() {
        c.arg("--");
    }
    c
}
```

### withStdin 死锁预防

```rust
use std::io::Write;
use std::os::unix::io::AsRawFd;

// 单线程非阻塞 poll 策略
pub fn with_stdin_poll(mut child: std::process::Child, input: &[u8]) {
    let mut stdin = child.stdin.take().unwrap();
    let mut stdout = child.stdout.take().unwrap();

    // 使用 poll(2) 交替读 stdout / 写 stdin
    let stdout_fd = stdout.as_raw_fd();
    let stdin_fd = stdin.as_raw_fd();

    let mut written = 0;
    let mut buf = [0u8; 4096];

    loop {
        let mut fds = [pollfd { fd: stdout_fd, events: POLLIN, revents: 0 }];
        if written < input.len() {
            fds[0].events |= POLLOUT; // 不推荐，应分两个 fd
        }
        // 简化：优先读 stdout，EAGAIN 时写 stdin
        // ...（完整实现见 system-baseline.md withStdin 死锁预防策略）
    }
}
```

## Landlock / seccomp 安装

### Landlock

使用 `nix` crate 或直接 `unsafe` syscall：

```rust
use nix::sys::landlock::*;

// 安装 Landlock 文件控制规则
pub fn install_landlock(allowed_paths: &[(String, AccessMode)]) -> Result<(), LandlockError> {
    // 1. 创建 ruleset
    let ruleset_attr = LandlockRulesetAttr {
        handled_access_fs: AccessFs::all(),
        handled_access_net: AccessNet::all(),
    };
    let fd = landlock_create_ruleset(&ruleset_attr, 0)
        .map_err(|e| LandlockError::CreateFailed(e))?;

    // 2. 添加规则
    for (path, mode) in allowed_paths {
        let path_rule = LandlockPathBeneathAttr {
            allowed_access: mode.to_access_fs(),
            parent_fd: open(path, OFlag::PATH, Mode::empty())?,
        };
        landlock_add_rule(fd, &path_rule)?;
    }

    // 3. PR_SET_NO_NEW_PRIVS（前提）
    prctl_set_no_new_privs()?;

    // 4. enforce
    landlock_restrict_self(fd)?;
    Ok(())
}
```

### seccomp-BPF

```rust
use nix::sys::prctl::*;

// 安装 seccomp-BPF 过滤器
pub fn install_seccomp() -> Result<(), SeccompError> {
    // 禁止的危险 syscall 列表
    let blocked = vec![
        Sysno::ptrace,
        Sysno::process_vm_readv,
        Sysno::process_vm_writev,
        Sysno::pidfd_getfd,
        Sysno::init_module,
        Sysno::finit_module,
        Sysno::delete_module,
        Sysno::kexec_load,
        Sysno::kexec_file_load,
        Sysno::bpf,
        Sysno::mount,
        Sysno::umount2,
        Sysno::pivot_root,
        Sysno::unshare,     // 含 CLONE_NEWNS/CLONE_NEWUSER 标志时
        Sysno::setns,
        // ...
    ];

    // 构建 BPF 过滤器
    let filter = build_seccomp_filter(&blocked);
    seccomp_set_mode_filter(&filter)?;
    Ok(())
}
```

### CLONE_NEWUSER + 沙箱顺序

```rust
use nix::sched::{unshare, CloneFlags};
use nix::sys::prctl::*;
use nix::unistd::getuid;

pub fn install_sandbox() -> Result<(), SandboxError> {
    // 1. PR_SET_NO_NEW_PRIVS
    prctl(PrctlOption::PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)?;

    // 2. PR_SET_DUMPABLE(0)
    prctl(PrctlOption::PR_SET_DUMPABLE, 0, 0, 0, 0)?;

    // 3. CLONE_NEWUSER（非特权用户无需特权）
    match unshare(CloneFlags::CLONE_NEWUSER) {
        Ok(()) => {
            // 成功：在新 user ns 内拥有全部 capability
            // 4. capset 清零所有 capability
            drop_all_capabilities()?;
            // 5. CLONE_NEWNS（mount namespace，在新 user ns 内可用）
            unshare(CloneFlags::CLONE_NEWNS)?;
            // 6. pivot_root 加固
            pivot_root_to_sandbox()?;
        }
        Err(_) => {
            // CLONE_NEWUSER 不可用（sysctl 禁用）
            if getuid() == 0 {
                // 特权进程：跳过 CLONE_NEWUSER，直接 capset + CLONE_NEWNS
                drop_all_capabilities()?;
                unshare(CloneFlags::CLONE_NEWNS)?;
                pivot_root_to_sandbox()?;
            } else {
                // 非特权 + user ns 禁用：降级为 Landlock + seccomp
                eprintln!("warning: user namespaces disabled, sandbox degraded \
                           (no mount namespace isolation)");
                // 不做 capset（无 CAP_SYS_ADMIN 可清零）
                // 不做 CLONE_NEWNS（需要 CAP_SYS_ADMIN）
            }
        }
    }

    // 7. CLONE_NEWNET（始终创建，不需要特权——在 user ns 内）
    let _ = unshare(CloneFlags::CLONE_NEWNET); // 尽力，失败则告警

    // 8. CLONE_NEWIPC
    let _ = unshare(CloneFlags::CLONE_NEWIPC);

    // 9. Landlock 文件控制
    install_landlock(&[])?;

    // 10. seccomp-BPF
    install_seccomp()?;

    Ok(())
}
```

## 系统调用

### 直接 syscall（nix crate 不足时）

```rust
use std::os::raw::{c_int, c_long, c_void};

// 直接 syscall 包装（nix crate 未覆盖时）
extern "C" {
    fn syscall(num: c_long, ...) -> c_long;
}

const SYS_LANDLOCK_CREATE_RULESET: c_long = 444;
const SYS_LANDLOCK_ADD_RULE: c_long = 445;
const SYS_LANDLOCK_RESTRICT_SELF: c_long = 446;

pub fn landlock_create_ruleset_raw(
    attr: *const c_void,
    size: usize,
    flags: c_int,
) -> Result<c_int, nix::Error> {
    let ret = unsafe {
        syscall(SYS_LANDLOCK_CREATE_RULESET, attr, size, flags)
    };
    if ret < 0 {
        Err(nix::Error::last())
    } else {
        Ok(ret as c_int)
    }
}
```

### signalfd

```rust
use nix::sys::signalfd::*;

// 创建 signalfd 用于信号处理
pub fn create_signalfd(signals: &[Signal]) -> Result<RawFd, SignalError> {
    let mut mask = SigSet::empty();
    for s in signals {
        mask.add(*s);
    }
    mask.block()?;  // 阻塞信号，使其通过 signalfd 接收
    let fd = signalfd(-1, &mask, SfdFlags::SFD_CLOEXEC | SfdFlags::SFD_NONBLOCK)?;
    Ok(fd)
}
```

## 错误处理

### Result + thiserror

Kun 的 Rust 实现使用 `Result<T, E>` + `thiserror` 派生错误类型：

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum TypeError {
    #[error("Type Mismatch: expected {expected}, got {got}")]
    Mismatch { expected: Type, got: Type },
    #[error("Occurs Check: variable {0} occurs in {1}")]
    OccursCheck(TypeVar, Type),
    #[error("Effect Mismatch: expected {expected}, got {got}")]
    EffectMismatch { expected: EffectSet, got: EffectSet },
    #[error("Unhandled User Effect: {effect}")]
    UnhandledEffect { effect: Effect },
    #[error("Nested Nilable: ??T is forbidden")]
    NestedNilable,
    // ...
}

#[derive(Error, Debug)]
pub enum EvalError {
    #[error("Panic: {0}")]
    Panic(String),
    #[error("Division by zero")]
    DivisionByZero,
    #[error("Index out of bounds: {index} >= {len}")]
    IndexOutOfBounds { index: usize, len: usize },
    // ...
}

// ✅ 正确：Result 传播
fn eval(expr: &Expr, env: &Env) -> Result<Value, EvalError> {
    match expr {
        Expr::IntLit { value, .. } => Ok(Value::Int(*value)),
        Expr::App { func, args, .. } => {
            let f = eval(func, env)?;
            // ...
        }
        _ => Err(EvalError::Panic("not implemented".into())),
    }
}
```

### panic = abort

`Cargo.toml` 配置 `panic = "abort"` 消除 hidden control flow（unwind）：

```toml
[profile.release]
panic = "abort"
lto = "fat"
codegen-units = 1
strip = true

[profile.dev]
panic = "abort"
```

Kun 的 panic 语义（unwind → defer LIFO → 子进程回收 → Arena 销毁）在 Rust 中通过显式 `Result` + `drop` 顺序实现，不依赖 `panic = unwind`。

## Primitive 函数表

### 静态注册表

```rust
use std::collections::HashMap;

pub type PrimitiveFn = fn(&mut RuntimeEnv, &[Value]) -> Result<Value, EvalError>;

pub struct PrimitiveTable {
    table: HashMap<(&'static str, &'static str), PrimitiveFn>,
}

impl PrimitiveTable {
    pub fn new() -> Self {
        let mut table = HashMap::new();
        // IO 模块
        table.insert(("IO", "println"), io_println as PrimitiveFn);
        table.insert(("IO", "readln"), io_readln as PrimitiveFn);
        // File 模块
        table.insert(("File", "read"), file_read as PrimitiveFn);
        table.insert(("File", "write"), file_write as PrimitiveFn);
        // Cmd 模块
        table.insert(("Cmd", "exec"), cmd_exec as PrimitiveFn);
        table.insert(("Cmd", "execSafe"), cmd_exec_safe as PrimitiveFn);
        // ... 全部 Primitive 函数
        Self { table }
    }

    pub fn lookup(&self, module: &str, func: &str) -> Option<PrimitiveFn> {
        // 注意：HashMap lookup 需要 'static 生命周期，实际实现用 String key 或 interning
        self.table.get_key_value(&(module, func)).map(|(_, f)| *f)
    }
}
```

### 受保护模块

```rust
// 受保护模块列表——不可被用户 .kun 文件覆盖
const PROTECTED_MODULES: &[&str] = &[
    "IO", "File", "Cmd", "Random", "DateTime", "Signal", "FFI",
    "Env", "Process", "Test",
    "Int", "Float", "String", "Bytes", "Char", "Regex",
    "List", "Map", "Set", "Stream", "Result", "Nilable",
    "Path", "Duration", "Equal", "Hash", "Base64", "Decimal",
];

pub fn is_protected_module(name: &str) -> bool {
    PROTECTED_MODULES.contains(&name)
}
```

## 格式化

### f-string → Rust format!

Kun 的 f-string 在 Rust 实现中映射为 `format!` 宏：

```rust
// Kun: f"found {List.length entries} errors"
// Rust 实现：
let result = format!("found {} errors", entries.len());
```

### i18n 消息格式化

```rust
// Kun 的位置插值 {s}/{d}/{f} 在 Rust 中实现为格式化函数
pub fn format_message(template: &str, args: &[FormatArg]) -> String {
    // {s} → String 插值
    // {d} → Int 插值
    // {f} → Float 插值（6 位小数）
    // ...
}
```

## 常见陷阱

### 1. Arena 引用不能逃逸

```rust
// ❌ 错误：Arena 引用逃逸到 Arena 生命周期外
fn parse(input: &str) -> &Expr {  // &Expr 的生命周期绑定到谁？
    let arena = Bump::new();
    let expr = arena.alloc(parse_expr(input));
    expr  // ❌ arena 在函数结束时销毁，expr 悬垂
}

// ✅ 正确：Arena 作为参数传入
fn parse<'a>(input: &str, arena: &'a Bump) -> &'a Expr<'a> {
    arena.alloc(parse_expr(input, arena))
}
```

### 2. RefCell 借用冲突

```rust
// ❌ 错误：RefCell 嵌套借用导致 panic
let env: Rc<RefCell<Env>> = Rc::new(RefCell::new(Env::new()));
let binding = env.borrow();
let inner = env.borrow();  // ❌ panic: already borrowed

// ✅ 正确：先释放再借
let value = env.borrow().get("x").clone();
env.borrow_mut().set("y", value);
```

### 3. enum tag 布局

```rust
// ✅ 控制 tag 布局（与 C ABI 兼容）
#[repr(u8, C)]
pub enum ValueTag {
    Int = 0,
    Float = 1,
    Bool = 2,
    String = 3,
    // ...
}

// ✅ ADT 运行时布局：tag-first
#[repr(C)]
pub struct Value {
    tag: ValueTag,
    payload: ValuePayload,
}

#[repr(C)]
pub union ValuePayload {
    int: i64,
    float: f64,
    bool: bool,
    string: *const str,  // Arena 分配的 &str 的裸指针
    // ...
}
```

### 4. unsafe 边界标注

```rust
// ✅ unsafe 块必须有 SAFETY 注释说明为什么是安全的
// SAFETY: fd 是刚创建的 signalfd，权限正确，flags 在有效范围内。
let fd = unsafe { signalfd(-1, &mask, flags) }?;
```

### 5. 不要在热路径用 Box/Vec

```rust
// ❌ 热路径（求值器分发循环）中的堆分配
fn eval(expr: &Expr) -> Result<Value, EvalError> {
    let args: Vec<Value> = expr.args.iter().map(eval).collect::<Result<_, _>>()?;  // Vec 分配
    // ...
}

// ✅ 使用 Arena 分配或栈分配
fn eval<'a>(expr: &'a Expr, arena: &'a Bump) -> Result<Value<'a>, EvalError> {
    // 在 Arena 上分配临时数组
    let args: &mut [Value] = arena.alloc_slice_fill_default(expr.args.len());
    for (i, a) in expr.args.iter().enumerate() {
        args[i] = eval(a, arena)?;
    }
    // ...
}
```

## 构建配置

### Cargo.toml

```toml
[package]
name = "kun"
version = "0.1.0"
edition = "2024"

[dependencies]
bumpalo = "3"          # Arena 分配器
nix = "0.29"           # Linux syscall 包装
regex = "1"            # 正则引擎
libc = "0.2"           # C FFI
thiserror = "2"        # 错误类型派生

[lib]
name = "kunlang"
crate-type = ["cdylib", "rlib"]  # libkunlang.so + rlib

[[bin]]
name = "kun"
path = "src/main.rs"

[profile.release]
panic = "abort"
lto = "fat"
codegen-units = 1
strip = true
opt-level = 3

[profile.dev]
panic = "abort"
```

### rust-toolchain.toml

```toml
[toolchain]
channel = "1.97"
targets = ["x86_64-unknown-linux-gnu", "x86_64-unknown-linux-musl"]
components = ["rustfmt", "clippy"]
```

## 参考

- [语言评估](../analysis/language-evaluation.md)
- [系统基线](../architecture/system-baseline.md)
- [宿主语言重新评估讨论](../discussions/discussion-host-language-reevaluation.md)
- [Zig 模式指南（已归档）](zig-patterns.md)
