# 单元测试设计

> **相关文档**：[`Cli` 模块 - `kun test` 运行器](cli.md#kun-test-运行器)、[`kun` CLI 工具 - `test` 子命令](kun-cli-tool.md#子命令)、[语法设计 - 测试与 `Test` 效应](syntax.md#测试与-test-效应)、[类型系统 - `handle` 表达式](type-system.md#handle-表达式限入口函数)、[标准库 `Test` 模块](standard-library.md#test-测试断言与结果)

## 设计原则

Kun 单元测试系统遵循 6 项核心原则：

1. **文件命名约定**：测试与模块同目录共置，仅使用 `<module>_test.kun` 文件（如 `lib/List.kun` 对应 `lib/List_test.kun`）。不另设 `tests/` 目录、不识别 `test-*` 文件名模式。

2. **`kun test` 命令统一入口**：提供 `--filter <pattern>`、`--timeout <duration>`（单测试超时）、`--parallel <n>`、`--fail-fast`、`--report <format>` 五个选项。无全局 `before*`/`after*` 钩子。

3. **`Test` 类型值即用例**：测试用例是**导出的 `Test` 类型值**，而非 `test*` 前缀函数。仅 `export` 列表中的 `Test` 值会被运行器收集执行。

4. **严格并行执行、绝对安全**：Kun 不可变语义 + 每测试独立 `handle with` 效应上下文 + 每测试沙箱（独立临时目录、独立 stdout/stderr 捕获、独立 Cmd 子进程沙箱）三层保障，使并行执行无副作用泄漏。

5. **可读测试报告**：默认 text 报告（按模块分组，含 ✓/✗/- 状态、耗时、失败原因）；可选 `--report json` 输出结构化 JSON。

6. **无黑魔法、无隐式全局钩子**：不提供 `beforeAll`/`afterAll`/`beforeEach`/`afterEach` 隐式钩子。Setup/teardown 通过 `defer` + handler 组合（`>>`）显式完成。测试失败是 `Test` 效应的 `abort` 控制流，与普通 handler 语义完全一致——**没有 panic 黑魔法**。

## 测试文件约定

### `<module>_test.kun` 命名

测试文件与被测模块同目录共置，命名严格遵循 `<module>_test.kun`：

```
lib/
  List.kun          ← 被测模块
  List_test.kun     ← 测试文件（模块名 List_test）
  UserService.kun
  UserService_test.kun
```

每个 `_test.kun` 文件本身是一个**模块**，模块名按目录路径推导（如 `lib/List_test.kun` → 模块 `List_test`）。

### 测试发现

`kun test` 子命令扫描 `lib/` 目录下所有 `*_test.kun` 文件（递归），将每个文件作为独立模块加载，依据编译期类型信息收集所有**导出的 `Test` 类型值**：

```kun
// lib/List_test.kun
import List (reverse, map, filter)
import Test (Test, Test(..), assert, fail, skip)

export (testReverse, testMap, testFilterSkipped)   // ← 仅导出的 Test 值才会被运行

testReverse : Test =
  Test
    { name = "reverse preserves elements"
    , ...
    }
```

> **仅 `export` 列出的 `Test` 值会被收集**。未导出的 `Test` 类型绑定视为辅助构造（如共享 fixture、参数化测试模板），不参与执行。这避免了"按命名约定隐式收集"导致的意外行为，与 Kun 模块系统「默认私有、显式公开」原则一致。

### `--filter <pattern>` 匹配规则

- 匹配目标是 `Test.name` 字段（不是绑定名），便于在重命名绑定时不影响 filter
- 使用 glob 模式（`*`/`?`/`[abc]`），如 `--filter "reverse*"`、`--filter "*Sort*"`
- 跨模块匹配：所有 `*_test.kun` 模块中 `Test.name` 命中模式的用例都会执行

## Test 类型

`Test` 是一个 Record 类型，描述单个测试用例的全部信息：

```kun
type Test =
  Test
    { name : String
    , description : ?String
    , timeout : ?Duration
    , body : Unit ! {Test, e}
    , with : ?(Handler {e} Unit ! {r})
    }
```

| 字段 | 类型 | 语义 |
|------|------|------|
| `name` | `String` | 测试名，用于 `--filter` 匹配与报告显示。建议人类可读短句（`"reverse preserves elements"`） |
| `description` | `?String` | 可选详细描述，仅用于文档化，不参与匹配 |
| `timeout` | `?Duration` | 可选单测试超时，覆盖 `--timeout` 全局默认值。`Nil` 表示沿用全局 |
| `body` | `Unit ! {Test, e}` | 零参效应函数，测试逻辑本体。`!` 后缀调用（`test.body!`）触发执行。效应集含 `Test`（断言效应）+ 用户效应 `e` |
| `with` | `?(Handler {e} Unit ! {r})` | 可选 handler，消解用户效应 `e`。`Nil` 表示 `e` 必须为空或仅含内置效应（由运行时沙箱消解） |

**约束**：

- `body` 必须是零参效应函数（`Unit ! {Test, e}`），不接受参数——所有测试输入通过闭包捕获
- `body` 的效应集中**必须**含 `Test`（断言/失败/跳过操作依赖此效应），可选含用户效应 `e`
- `with` 字段类型为 `Handler {e} Unit ! {r}`，即消解 `e` 后产生内置效应 `r`；多个用户效应通过 `>>` 组合为单一 handler

## Test 效应

`Test` 是一个**标准库效应**（非保留名——与 `DB`/`Log` 等用户效应同构），提供三个测试操作：

```kun
effect Test =
  { assert : Bool -> Unit        // assert cond；cond=false → abort (Fail "assertion failed")
  , fail : String -> Unit        // 显式失败 → abort (Fail msg)
  , skip : String -> Unit        // 跳过 → abort (Skip reason)
  }
```

### `assert`/`fail`/`skip` 的 abort 语义

三个操作均通过 `abort` 终止当前测试，**不使用 panic**：

| 操作 | cond=true / cond=false | abort 值 | 测试结果 |
|------|------|------|------|
| `assert cond` | `true` → `continue ()`；`false` → `abort (Fail "assertion failed")` | `Fail "assertion failed"`（含位置信息） | `Fail` |
| `fail msg` | 始终 `abort (Fail msg)` | `Fail msg` | `Fail` |
| `skip reason` | 始终 `abort (Skip reason)` | `Skip reason` | `Skip` |

> **关键洞察：测试失败就是 handler 控制流**。`assert`/`fail`/`skip` 在 `testHandler` 内通过 `abort` 提前返回，与任何用户效应 handler 的 `abort` 语义完全一致——**没有 panic 黑魔法**。这意味着测试失败可被 `defer` 正常清理、可被嵌套 handler 拦截、不触发 unwind 重型机制。

`assert`/`fail`/`skip` 是 `Test` 效应的操作，可在**任何效应集含 `Test` 的函数**中使用，不限 `Test.body`：

```kun
import Test (Test, Test(..), assert)

checkPositive : Int -> Unit ! {Test}
checkPositive n =
  assert (n >= 0)

testFoo : Test =
  Test
    { name = "foo"
    , body = \ ->
        let
          checkPositive 5          // ← 在辅助函数中调用 assert，效应冒泡到 body
          checkPositive (-1)        // ← abort (Fail "assertion failed")，body 提前终止
        in
          ()
    , with = Nil
    }
```

## testHandler

`testHandler` 是 `kun` 二进制内置的 handler（运行器提供，与 IO/File 等内置效应默认 handler 同级），消解 `Test` 效应为 `TestResult`：

```kun
testHandler : Handler {Test} TestResult ! {IO}
testHandler =
  handler Test of
    assert cond ->
      if cond then continue () else abort (Fail "assertion failed")
    fail msg -> abort (Fail msg)
    skip reason -> abort (Skip reason)
```

**`TestResult` 类型**（保留既有定义）：

```kun
type TestResult =
  Pass
  | Fail String      // 失败消息
  | Skip String      // 跳过原因
```

`testHandler` 仅消解 `Test` 效应；用户效应 `e` 由 `Test.with` 字段指定的 handler 消解，内置效应由运行时沙箱默认 handler 消解。

## 测试执行模型

运行器对每个 `Test` 值按以下顺序执行：

```kun
// 1. 包装：将 body 完成正常返回（Unit）转为 Pass
let
  wrapped = let test.body! in Pass     // : TestResult ! {Test, e}

  // 2. 消解用户效应 e：用 Test.with 指定的 handler（若有）
  resolved =
    case test.with of
      Nil    -> wrapped                 // : TestResult ! {Test, e_builtin}
      Some h -> handle wrapped with h   // : TestResult ! {Test, h_produced}

  // 3. 消解 Test 效应：用 testHandler 转为 TestResult
  result = handle resolved with testHandler   // : TestResult ! {IO 或其他内置}
in
  result
```

**步骤解析**：

1. **包装为 Pass**：`body!` 正常返回 `Unit` 时，外层 `let in Pass` 将其包装为 `Pass`；若 `body` 内 `assert false`/`fail`/`skip` 已通过 `testHandler` 的 `abort` 提前终止，则 `wrapped` 直接产出 `Fail`/`Skip`，不再执行 `Pass` 包装
2. **消解用户效应**：`Test.with = Some h` 时，`handle wrapped with h` 将用户效应 `e` 转换为 handler 产生的内置效应；`Test.with = Nil` 时，`e` 必须为空或仅含内置效应，由运行时沙箱消解
3. **消解 Test 效应**：`testHandler` 将 `Test` 效应的 `assert`/`fail`/`skip` 转为 `TestResult`

> **入口级 `handle with` 上下文**：上述伪代码中的 `handle ... with h` 和 `handle ... with testHandler` 都由运行器在入口级上下文执行。因此 `Test` 值的 `body` 字段内**可以**使用 `handle with`（业务函数不可），这是 `body` 与普通业务函数的关键区别。详见 [类型系统 - `handle` 表达式](type-system.md#handle-表达式限入口函数)。

## 并行执行与隔离

### 并行度

`--parallel <n>` 控制并发度（默认 = CPU 核心数）。每个 `Test` 在独立的 `handle with` 上下文中执行，互不干扰。

### 三层隔离保障

1. **不可变语义**：Kun 数据默认不可变，`List`/`Map`/`Set`/`Record` 等均无共享可变状态。多个测试并行读取同一 fixture 不会互相干扰。

2. **Handler 隔离**：每个 `Test` 通过自身 `with` 字段携带独立 handler 实例。Mock handler（`mockDbHandler`、`mockLogHandler`）提供确定性、无副作用的行为，可被任意多个测试并行复用。

3. **每测试沙箱**（运行器对内置效应提供）：

   | 内置效应 | 隔离机制 |
   |---------|---------|
   | `File` | 每测试独立临时目录（`File` 操作重定向到该目录） |
   | `IO` | 每测试独立 stdout/stderr 缓冲区，运行器捕获后按测试分组报告，不交错 |
   | `Cmd` | 每测试在独立沙箱（Landlock + mount ns + seccomp，详见 [系统基线 - 安全隔离](../architecture/system-baseline.md#安全隔离)）中执行子进程 |
   | `Random` | 每测试独立 PRNG 种子（默认从全局 CSPRNG 派生，可固定） |
   | `DateTime` | 每测试可注入固定时间（消除并行时序不确定性） |

### 超时与中断

- 单测试超时优先级：`Test.timeout` > `--timeout`（默认 30s）
- 超时触发：运行器终止测试（标记 `Fail "timeout after <duration>"`）
- 实现机制：每个测试运行在独立的 arena/线程中，超时后运行器销毁 arena，释放所有资源（包括子进程、临时文件、内存）
- `--fail-fast`：首个 `Fail` 后停止所有未启动的测试；已启动的测试运行至完成或超时

## 生命周期管理

### 显式 `defer`（无钩子）

**Kun 不提供 `beforeAll`/`afterAll`/`beforeEach`/`afterEach` 隐式全局钩子**。Setup/teardown 通过 `defer` 显式表达：

```kun
testWithTempFile : Test =
  Test
    { name = "parse config file"
    , body = \ ->
        let
          path = File.createTemp!           // setup：创建临时文件
          defer (File.remove path)          // cleanup：测试退出时执行（无论 Pass/Fail）
          File.write path "key=value"
          config = parseConfig (File.read path)
          assert (config.key == "value")
        in
          ()
    , with = Nil
    }
```

`defer` 绑定最近 `let in` 块，LIFO 逆序执行。**`defer` 在 `Test` 效应的 `abort`（Fail/Skip）路径下也会执行**——因为 `abort` 是 handler 控制流，不是 panic unwind，`defer` 在 handler 接管前正常清理。这保证测试资源（临时文件、子进程、网络连接）在任何测试结果下都被回收。

### Handler 组合实现效应隔离

多个用户效应通过 `>>` 组合为单一 handler，赋给 `Test.with`：

```kun
testFetchUser : Test =
  Test
    { name = "fetchUser returns user"
    , body = \ ->
        let
          result = fetchUser (UserId "1")   // ! {DB, Log, IO}
          case result of
            Ok user -> assert (user.name == "alice")
            Err _ -> fail "expected Ok, got Err"
        in
          ()
    , with = Some (mockDbHandler >> mockLogHandler)
    //        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    //        DB/Log 被消解为确定性 mock 行为，剩余 IO 由沙箱消解
    }
```

无全局钩子意味着无隐式状态泄漏：每个 `Test` 是自包含的、可独立运行的、可并行调度的最小单元。

## `kun test` 命令

### 子命令与参数

```bash
kun test                              # 运行 lib/ 下所有 *_test.kun
kun test lib/List_test.kun            # 运行指定测试文件
kun test lib/                         # 运行目录下所有 *_test.kun
kun test --filter "reverse"           # 按 Test.name 过滤（glob 模式）
kun test --timeout 10s                # 单测试超时（默认 30s）
kun test --parallel 4                 # 并行度（默认 = CPU 核心数）
kun test --fail-fast                  # 首个失败后停止
kun test --report json                # 输出格式：text（默认）/ json
kun test --allow-ffi                  # 允许测试体使用 FFI（与 `kun run` 同语义）
```

| 参数 | 默认 | 说明 |
|------|------|------|
| `--filter <pattern>` | 无 | glob 模式匹配 `Test.name`，跨所有 `*_test.kun` 模块 |
| `--timeout <duration>` | `30s` | 单测试超时上限；`Test.timeout` 字段可覆盖 |
| `--parallel <n>` | CPU 核心数 | 并行执行度；`1` 表示串行 |
| `--fail-fast` | 关闭 | 首个 `Fail` 后停止未启动的测试 |
| `--report <format>` | `text` | 报告格式：`text`（人类可读）/ `json`（结构化） |
| `--allow-ffi` | 关闭 | 测试体触发 FFI 效应时放行（与 `kun run --allow-ffi` 同语义，详见 [`kun` CLI 工具 - 安全控制](kun-cli-tool.md#安全控制-实现推迟-v02)） |

### 退出码

| 退出码 | 含义 |
|--------|------|
| 0 | 所有测试 `Pass` 或 `Skip`（无 `Fail`） |
| 1 | 至少一个测试 `Fail` |
| 2 | 用法错误（无效 CLI 参数、`*_test.kun` 文件未找到、类型检查失败） |

## 测试报告

### Text 格式（默认）

```
Running 8 tests in lib/ (parallel: 8)

List_test
  ✓ reverse preserves elements (2ms)
  ✓ map applies function (1ms)
  ✗ filter predicate (5ms) — TIMEOUT (exceeded 3s)
  - sort stable — SKIPPED (not implemented)

UserService_test
  ✓ fetchUser returns user (15ms)
  ✗ updateUser validates (8ms)
    Fail: assertion failed at UserService_test.kun:42

  4 passed, 2 failed, 1 skipped (31ms total)
```

**符号说明**：

- `✓`：Pass
- `✗`：Fail（附原因：TIMEOUT / assertion failed / 显式 fail msg）
- `-`：Skip（附原因）

### JSON 格式（`--report json`）

```json
{
  "total": 8,
  "passed": 4,
  "failed": 2,
  "skipped": 1,
  "duration_ms": 31,
  "suites": [
    {
      "module": "List_test",
      "tests": [
        { "name": "reverse preserves elements", "status": "pass", "duration_ms": 2 },
        { "name": "map applies function", "status": "pass", "duration_ms": 1 },
        { "name": "filter predicate", "status": "fail", "duration_ms": 5, "reason": "TIMEOUT (exceeded 3s)" },
        { "name": "sort stable", "status": "skip", "reason": "not implemented" }
      ]
    },
    {
      "module": "UserService_test",
      "tests": [
        { "name": "fetchUser returns user", "status": "pass", "duration_ms": 15 },
        { "name": "updateUser validates", "status": "fail", "duration_ms": 8, "reason": "assertion failed at UserService_test.kun:42" }
      ]
    }
  ]
}
```

JSON 输出适合 CI/CD 集成（解析状态、生成趋势图、与历史结果对比）。

## 完整示例

### `lib/List_test.kun`

```kun
import List (reverse, map, filter)
import Test (Test, Test(..), assert, fail, skip)

export (testReverse, testMap, testFilterSkipped)

testReverse : Test =
  Test
    { name = "reverse preserves elements"
    , description = Some "reverse returns elements in opposite order"
    , timeout = Some 5s
    , body = \ ->
        let
          result = reverse [1, 2, 3]
          assert (result == [3, 2, 1])
        in
          ()
    , with = Nil
    }

testMap : Test =
  Test
    { name = "map applies function"
    , description = Nil
    , timeout = Nil
    , body = \ ->
        let
          result = map (\x -> x * 2) [1, 2, 3]
          assert (result == [2, 4, 6])
        in
          ()
    , with = Nil
    }

testFilterSkipped : Test =
  Test
    { name = "filter predicate"
    , description = Nil
    , timeout = Nil
    , body = \ -> skip "not implemented"
    , with = Nil
    }
```

### `lib/UserService_test.kun`

```kun
import UserService (fetchUser)
import User (UserId)
import Test (Test, Test(..), assert, fail)
import DB.Mock (mockDbHandler)
import Log.Mock (mockLogHandler)

export (testFetchUser)

testFetchUser : Test =
  Test
    { name = "fetchUser returns user"
    , description = Some "Uses mock DB and Log handlers"
    , timeout = Some 10s
    , body = \ ->
        let
          result = fetchUser (UserId "1")
          case result of
            Ok user -> assert (user.name == "alice")
            Err _ -> fail "expected Ok, got Err"
        in
          ()
    , with = Some (mockDbHandler >> mockLogHandler)
    }
```

### 运行示例

```bash
# 运行全部测试
kun test

# 仅运行 List_test，按 reverse 过滤
kun test lib/List_test.kun --filter "reverse*"

# 串行运行 + JSON 报告
kun test --parallel 1 --report json

# 失败即停
kun test --fail-fast --timeout 5s
```

## 与现有设计的关系

本次设计**替换**了基于 `test*` 前缀函数的旧方案。关键变化：

| 维度 | 旧设计（2026.07.15） | 新设计（2026.07.16） |
|------|---------------------|---------------------|
| **用例载体** | `test*` 前缀函数（`testFoo : Unit ! {IO}`） | `Test` 类型值（`testFoo : Test = Test {...}`） |
| **文件约定** | `tests/` 目录下 `test-*.kun` 文件 | `<module>_test.kun` 同目录共置 |
| **用例发现** | 命名约定（`test` 前缀）隐式收集 | `export` 列表显式声明 + 类型 `Test` 双重过滤 |
| **断言机制** | `assert : Bool -> Unit`（panic 失败） | `assert : Bool -> Unit ! {Test}`（abort 失败，handler 控制流） |
| **结果类型** | `TestResult`（`Pass`/`Fail`/`Skip`，函数显式返回）或 `Unit`（panic 失败） | `TestResult`（仅由 `testHandler` 产出） |
| **生命周期** | 隐式全局钩子（`beforeAll`/`afterAll`/`beforeEach`/`afterEach`） | 显式 `defer` + handler 组合 |
| **效应隔离** | 入口级 `handle with` | `Test.with` 字段指定 handler |
| **并行安全** | 未明确 | 不可变 + handler 隔离 + 每测试沙箱 三层保障 |
| **超时** | 未提供 | `--timeout` + `Test.timeout` 字段 |
| **报告** | 未提供 | text（默认）/ json |

### 兼容性与迁移

- **`test*` 前缀函数已废弃**：2026.07.16 起不再作为测试用例识别规则；旧的 `test*` 函数视为普通业务函数（仍可定义但不再被 `kun test` 收集）
- **`assert : Bool -> Unit`（panic 版）已废弃**：替换为 `Test` 效应的 `assert` 操作；旧形式仅出现在「已废弃」上下文中
- **入口级 `handle with` 限制扩展**：`handle with` 现在可在 `main` 与 `Test` 值的 `body` 字段中使用（运行器提供入口级上下文）；旧的"`test*` 函数内可用"措辞被替换
- **`TestResult` 类型保留**：仍是测试结果的唯一表示，但仅由 `testHandler` 产出，不再由测试函数显式返回

> 详见 [讨论记录 - 单元测试设计](../discussions/discussion-unit-testing-design.md)。

## 版本历史

| 版本 | 变更 |
|------|------|
| 2026.07.16 | 单元测试系统重设计：替换 `test*` 前缀函数为 `Test` 类型值（`type Test = Test { name, description, timeout, body, with }`）；测试文件约定改为 `<module>_test.kun` 同目录共置（废弃 `tests/` 目录与 `test-*.kun` 命名）；`assert`/`fail`/`skip` 改为 `Test` 效应操作（`effect Test = { assert, fail, skip }`），通过 `abort` 终止测试（不再 panic）；新增 `testHandler` 运行器内置 handler；新增 `Test.with` 字段指定用户效应 handler；废弃 `beforeAll`/`afterAll`/`beforeEach`/`afterEach` 隐式钩子，改用 `defer` + handler 组合；`kun test` 新增 `--filter`/`--timeout`/`--parallel`/`--fail-fast`/`--report` 选项；新增 text/json 双格式报告；明确并行执行三层隔离保障（不可变 + handler 隔离 + 每测试沙箱）；入口级 `handle with` 限制扩展为 `main` 与 `Test.body`（替换 `test*` 函数措辞）；新建本文档 |
