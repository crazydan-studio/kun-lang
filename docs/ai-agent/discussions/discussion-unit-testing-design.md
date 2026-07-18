# 单元测试系统设计

> **日期**：2026-07-16
> **状态**：已定稿
> **相关文档**：[单元测试设计](../design/testing.md)、[`Cli` 模块 - `kun test` 运行器](../design/cli.md#kun-test-运行器)、[`kun` CLI 工具 - `test` 子命令](../design/kun-cli-tool.md#子命令)、[语法设计 - 测试与 `Test` 效应](../design/syntax.md#测试与-test-效应)、[类型系统 - `handle` 表达式](../design/type-system.md#handle-表达式限入口函数)、[标准库 `Test` 模块](../design/standard-library.md#test-测试断言与结果)

## 背景

Kun 的旧单元测试设计（2026.07.15）基于 `test*` 前缀函数：

- 文件约定：`tests/` 目录下 `test-*.kun` 文件
- 用例识别：函数名以 `test` 开头 + 签名为零参效应函数 `Unit ! {E}` 或 `TestResult ! {E}`
- 断言机制：`assert : Bool -> Unit`（panic 失败，由运行器捕获）
- 隐式钩子：未明确说明但语义上暗示 `beforeAll`/`afterAll`/`beforeEach`/`afterEach` 钩子需求
- 报告：仅汇总 `Pass`/`Fail`/`Skip` 统计

该设计存在 6 项问题：

1. **用例发现基于命名约定**：`test` 前缀是隐式契约，无法在编译期严格过滤「这是测试用例还是辅助函数」
2. **panic 黑魔法**：`assert` 失败靠 panic，与 Kun 代数效应系统「handler 控制流」哲学不一致——panic 应保留给真正的运行时异常
3. **测试文件脱离模块**：`tests/` 目录隔离导致被测模块与测试代码物理分离，不利于共置维护
4. **效应隔离缺失**：旧设计未说明如何为每个测试提供独立 handler 上下文，并行执行时可能产生副作用泄漏
5. **生命周期隐式化**：缺乏显式 setup/teardown 机制，依赖隐式全局钩子导致测试间状态泄漏
6. **缺乏现代测试运行器特性**：无 `--filter`/`--timeout`/`--parallel`/`--fail-fast`/`--report` 选项，无 JSON 报告

本次讨论决定全面替换旧设计，以「`Test` 类型值 + `_test.kun` 文件约定 + handler 隔离 + `defer` 生命周期」为核心的新方案。

## 设计决策

### 1. `Test` 类型值取代 `test*` 函数

**决策**：测试用例是导出的 `Test` 类型值，而非 `test` 前缀函数。

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

**理由**：

- **显式优于隐式**：`export (testFoo)` 明确声明「这是要运行的测试」，与 Kun 模块系统「默认私有、显式公开」哲学一致；命名约定 `test*` 是隐式契约，易误判
- **类型安全**：编译期可校验 `Test` 类型的字段完整性（`name` 必填、`body` 必须是零参效应函数、效应集含 `Test`）；旧 `test*` 函数仅靠命名 + 签名两重过滤
- **携带元信息**：`name`/`description`/`timeout`/`with` 字段使测试用例自描述，运行器无需额外配置
- **与 `--filter` 协同**：`--filter` 匹配 `Test.name`（人类可读短句），而非绑定名（`testReverse`），重命名绑定不影响 filter

### 2. `<module>_test.kun` 同目录共置

**决策**：测试文件与被测模块同目录共置，命名 `<module>_test.kun`。

**理由**：

- **共置便于维护**：修改 `lib/List.kun` 时，`lib/List_test.kun` 就在同目录，立即可见；`tests/` 目录隔离导致测试代码物理远离被测代码
- **明确归属**：`List_test.kun` 显式表达「这是 `List` 模块的测试」，避免 `tests/list_test.kun` 与 `tests/test_list.kun` 等命名混乱
- **模块名推导一致**：`lib/List_test.kun` → 模块 `List_test`，与 Kun 既有的「目录即命名空间」模块系统一致
- **不另设 `tests/` 目录**：减少目录层级，降低心智负担

### 3. `Test` 效应取代 panic `assert`

**决策**：`assert`/`fail`/`skip` 是 `Test` 效应的操作，通过 `abort` 终止测试，**不使用 panic**。

```kun
effect Test =
  { assert : Bool -> Unit        // cond=false → abort (Fail "assertion failed")
  , fail : String -> Unit        // abort (Fail msg)
  , skip : String -> Unit        // abort (Skip reason)
  }
```

**理由**：

- **无黑魔法**：测试失败是 `testHandler` 内的 `abort` 控制流，与任何用户效应 handler 的 `abort` 语义完全一致——`defer` 正常清理、可被嵌套 handler 拦截、不触发 unwind 重型机制
- **与代数效应哲学一致**：Kun 的核心是「效应 = handler 控制流」，测试失败作为效应操作是自然延伸；panic 应保留给真正的运行时异常（除零、栈溢出、不可恢复的内存错误）
- **可组合**：`Test` 效应可与其他用户效应（`DB`/`Log`）组合在 `Test.body` 的效应集中，由 `testHandler` 消解 `Test`、由 `Test.with` 消解其他用户效应
- **非保留名**：`Test` 是标准库效应，与 `DB`/`Log` 等用户效应同构；`testHandler` 是 `kun` 二进制内置 handler，与 IO/File 等内置效应默认 handler 同级

### 4. `Test.with` 字段取代入口级 `handle with`

**决策**：每个 `Test` 通过 `with` 字段携带消解用户效应的 handler，而非依赖 `test*` 函数内 `handle with`。

```kun
testFetchUser : Test =
  Test
    { name = "fetchUser returns user"
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

**理由**：

- **声明式效应隔离**：`with` 字段在 `Test` 值构造时声明，运行器统一应用；避免每个测试函数内重复写 `handle ... with ...` 模板
- **运行器接管执行**：运行器在入口级上下文执行 `body`（包装 → `Test.with` 消解用户效应 → `testHandler` 消解 `Test` 效应），`Test.body` 内仍可使用 `handle with`（入口级上下文提供）
- **handler 组合**：多个用户效应通过 `>>` 组合为单一 handler，赋给 `with` 字段
- **`with = Nil` 简化纯测试**：不依赖用户效应的测试可设 `with = Nil`，效应集仅含 `Test` + 内置效应

### 5. 无隐式全局钩子，`defer` + handler 组合

**决策**：**不提供** `beforeAll`/`afterAll`/`beforeEach`/`afterEach` 隐式全局钩子。Setup/teardown 通过 `defer` 显式表达；效应隔离通过 handler 组合实现。

**理由**：

- **无隐式状态泄漏**：隐式全局钩子（特别是 `beforeEach`/`afterEach`）容易在测试间引入未察觉的状态污染；`defer` 绑定最近 `let in` 块，作用域明确
- **`defer` 在 `abort` 路径下执行**：因为 `Test` 效应的 `abort` 是 handler 控制流（非 panic unwind），`defer` 在 handler 接管前正常清理——这保证测试资源（临时文件、子进程、网络连接）在任何测试结果下都被回收
- **handler 组合替代 `beforeEach`**：若多个测试共享相同 mock handler，可在模块级定义 `mockHandler = mockDbHandler >> mockLogHandler`，各 `Test` 引用 `Some mockHandler`；这比 `beforeEach` 全局注入更显式
- **共享 fixture 通过辅助函数**：复杂的 setup 抽取为辅助函数（如 `makeTempConfig : Unit -> Config ! {File}`），各 `Test.body` 内显式调用——比 `beforeAll` 全局可变状态更安全

### 6. 严格并行 + 三层隔离

**决策**：`--parallel <n>`（默认 = CPU 核心数）并行执行，三层隔离保障绝对安全。

**理由**：

- **不可变语义**：Kun 数据默认不可变，`List`/`Map`/`Set`/`Record` 等无共享可变状态——多个测试并行读取同一 fixture 不会互相干扰
- **Handler 隔离**：每个 `Test` 通过 `with` 字段携带独立 handler 实例；mock handler 提供确定性、无副作用行为
- **每测试沙箱**：File 重定向到独立临时目录、IO 输出捕获到独立缓冲区、Cmd 在独立沙箱中执行——彻底隔离副作用
- **超时安全**：超时触发后运行器销毁测试 arena，释放所有资源（包括子进程、临时文件、内存）

## 与旧设计的对比

| 维度 | 旧设计（2026.07.15） | 新设计（2026.07.16） |
|------|---------------------|---------------------|
| **用例载体** | `test*` 前缀函数（`testFoo : Unit ! {IO}`） | `Test` 类型值（`testFoo : Test = Test {...}`） |
| **文件约定** | `tests/` 目录下 `test-*.kun` 文件 | `<module>_test.kun` 同目录共置 |
| **用例发现** | 命名约定（`test` 前缀）隐式收集 | `export` 列表显式声明 + 类型 `Test` 双重过滤 |
| **断言机制** | `assert : Bool -> Unit`（panic 失败） | `assert : Bool -> Unit ! {Test}`（abort 失败，handler 控制流） |
| **结果类型** | `TestResult`（函数显式返回）或 `Unit`（panic 失败） | `TestResult`（仅由 `testHandler` 产出） |
| **生命周期** | 隐式全局钩子（`beforeAll`/`afterAll`/`beforeEach`/`afterEach`） | 显式 `defer` + handler 组合 |
| **效应隔离** | 入口级 `handle with`（写在测试函数内） | `Test.with` 字段指定 handler（声明式） |
| **并行安全** | 未明确 | 不可变 + handler 隔离 + 每测试沙箱 三层保障 |
| **超时** | 未提供 | `--timeout` + `Test.timeout` 字段 |
| **报告** | 仅汇总统计 | text（默认）/ json 双格式 |
| **filter** | 未提供 | `--filter <pattern>` glob 匹配 `Test.name` |
| **入口级 `handle with`** | `main` 与 `test*` 函数 | `main` 函数与 `Test.body` 字段 |
| **`assert` 适用范围** | 仅 `test*` 函数内 | 任何效应集含 `Test` 的函数 |

## 落盘清单

| 文件 | 变更 |
|---|---|
| `docs/ai-agent/design/testing.md` | 新建——单元测试系统完整设计（设计原则、文件约定、`Test` 类型、`Test` 效应、`testHandler`、执行模型、并行隔离、生命周期、`kun test` 命令、报告格式、完整示例、与现有设计关系、版本历史） |
| `docs/ai-agent/design/cli.md` | 替换「`kun test` 运行器」章节——从「`tests/` 目录 + `test*` 函数」改为「`lib/` 下 `*_test.kun` + 导出 `Test` 值」；新增 `--filter`/`--timeout`/`--parallel`/`--fail-fast`/`--report` 选项说明；新增并行安全与生命周期章节；交叉引用 `testing.md`；版本历史 |
| `docs/ai-agent/design/kun-cli-tool.md` | 更新 `test` 子命令行——引用 `*_test.kun` 文件与 `Test` 值，列出全部新选项；「`main` 与 `test*` 的 `handle with` 限制」章节更名为「`main` 与 `Test.body` 的 `handle with` 限制」；版本历史 |
| `docs/ai-agent/design/syntax.md` | 替换「测试函数与 `assert`」章节为「测试与 `Test` 效应」——`Test` 类型值、`Test` 效应、`testHandler`、`Test.with` 字段、入口级 `handle with` 改为 `main`/`Test.body`；`handle with` 表达式章节同步更新；版本历史 |
| `docs/ai-agent/design/type-system.md` | 更新 `handle` 表达式章节——入口级从 `main`/`test*` 改为 `main`/`Test.body`；测试用例识别规则改为 `Test` 类型值；纯函数返回 `Unit` 例外说明改为 `Test` 效应；内置效应 Handler 章节补充 `testHandler`；版本历史 |
| `docs/ai-agent/design/standard-library.md` | 重写 `Test` 模块章节——`type Test` Record + `effect Test` + `testHandler` + `TestResult`（保留）；`assert` 从 panic 函数改为 `Test` 效应操作；模块分类表 Test 行同步更新；版本历史 |
| `docs/ai-agent/design/feature-inventory.md` | 更新测试相关功能行——`Test` 类型值、`_test.kun` 约定、`kun test` 新选项、`assert` 为 `Test` 效应操作；新增「已废弃」行记录旧 `test*` 函数；版本历史 |
| `docs/ai-agent/design/index.md` | 文件列表新增 `testing.md` 行 |
| `docs/ai-agent/design/app-overview.md` | 跨文档一致性更新——`handle with` 限入口小节从 `main`/`test*` 改为 `main`/`Test.body`（2 处）；安全模型小节同步更新（1 处）；录制/回放章节 `testReplay` 示例迁移为 `Test` 类型值 |
| `docs/ai-agent/design/command-system.md` | 跨文档一致性更新——内置 Cmd handler 章节中 `main`/`test*` 措辞改为 `main`/`Test.body` |
| `docs/ai-agent/discussions/discussion-unit-testing-design.md` | 新建本讨论记录 |
| `docs/ai-agent/discussions/index.md` | 新增本讨论记录的索引行 |
