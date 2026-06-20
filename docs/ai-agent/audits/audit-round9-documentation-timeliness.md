# 时效性文档审计报告（Round 9）

审计日期：2026-06-20
审计范围：P0(3) + P1(3) + P2(5) + P3(4) = 15 份文档

## 已知修复已验证

| 问题 | 文件 | 状态 |
|------|------|------|
| 缩进规则一致性 | code-formatting.md + syntax.md | ✅ |
| 命名规范统一（PascalCase/kebab-case） | syntax.md + conventions.md | ✅ |
| 示例拆分/模板化 | standard-library.md | ✅ |
| `File.exists`/`File.isDir`/`Std`/`Math` 已移除 | standard-library.md + feature-inventory.md | ✅ |
| `execSafe` 签名更新 | standard-library.md + command-system.md + type-system.md | ✅ |
| 无 `<>` 泛型 | 全部文档 | ✅ |

## 新增问题

### 严重（语法错误/API 不匹配）

1. **S1 — Task 示例中效应匿名函数缺少 `do` 包裹**
   - 文件：`standard-library.md:2620-2624`
   - 问题：`List.iter (\r -> case r of ...)` 中 lambda 体内含 `IO.println` 效应调用，但未被 `do` 包裹。违反 syntax.md 规则："效应匿名函数：函数体必须显式以 `do`/`do in` 包裹，不可省略"
   - 示例：
     ```kun
     // ❌ 当前
     |> List.iter (\r ->
       case r of
         Ok _  -> IO.println "ok"
         Err e -> IO.println f"failed: {CommandError.show e}"
     )
     
     // ✅ 修正
     |> List.iter (\r ->
       do
         case r of
           Ok _  -> IO.println "ok"
           Err e -> IO.println f"failed: {CommandError.show e}"
     )
     ```

2. **S2 — Base64 示例在纯上下文中调用 `IO.println`**
   - 文件：`standard-library.md:2573-2574`
   - 问题：`case Base64.decode "aGVsbG8=" of` 及其分支在外层纯上下文（无 `do` 块）中出现 `IO.println`，这是效应函数在纯上下文中的调用——编译错误
   - 上下文：示例代码位于文件顶部纯上下文区域，`import Base64` 之后没有 `do` 块包裹
   - 示例：
     ```kun
     // ❌ 当前：纯上下文中出现 IO.println
     case Base64.decode "aGVsbG8=" of
       Ok raw  -> ...
       Err _   -> IO.println "invalid base64"
     ```

3. **S3 — Path 示例中未绑定 case 结果，分支类型不一致**
   - 文件：`standard-library.md:973-975`
   - 问题：`case Path.fromBytes ... of Ok path -> Path.toString path | Err _ -> p"/tmp/fallback"` 处于纯上下文且结果未绑定，两分支返回类型不同（`String` vs `Path`）。编译器将告警未消费表达式，纯上下文丢弃 case 结果无意义
   - 示例：
     ```kun
     // ❌ 当前
     case Path.fromBytes 0x2F746D702FBAADF00D of
       Ok path  -> Path.toString path
       Err _    -> p"/tmp/fallback"
     
     // ✅ 修正：绑定结果或统一分支类型
     path_ =
       case Path.fromBytes 0x2F746D702FBAADF00D of
         Ok path  -> path
         Err _    -> p"/tmp/fallback"
     ```

### 中等（格式/命名/一致性）

4. **M1 — `Cli.show` 缺少 `[推迟 v0.5]` 标注**
   - 文件：`standard-library.md:1668`
   - 描述：推迟特性一览表列出 `Cli.parse / Cli.show` 为 v0.5，但 API 中 `show : CliError -> String` 无 `[推迟 v0.5]` 标注，而 `parse` 有（line 1664）
   - 注：`show` 是纯函数（ADT 模式匹配），可能不需要推迟——表与标注不一致

5. **M2 — `List.sum` 签名与注释不一致**
   - 文件：`standard-library.md:1301-1302`
   - 描述：签名 `sum : List Int -> Int`（固定 Int），注释"元素类型须支持 + 运算符"暗示泛型。二者选一

6. **M3 — `code-formatting.md` `readConfig` 示例中 `let in` 嵌套位置语义模糊**
   - 文件：`code-formatting.md:362-380`
   - 描述：`do in` 的 `in` 部分中包含 bound case 分支使用 `let in`。虽经分析在 bound 分支中合法（bound 打断 do 链），但容易误解为违反"同一 scope 内 do/let 互斥"规则。建议在示例旁加注释说明为何合法

7. **M4 — 命令系统文档 `Cmd.date` 无选项省略示例但 `Cmd.cat` 在示例中频繁使用**
   - 文件：`command-system.md:22-26` + `standard-library.md` + `log-analyzer.kun`
   - 描述：标准库和示例中大量用 `Cmd.cat path`、`Cmd.ls {} p"/path"` 等形式，但无选项 Record 省略的正式语法定义在 command-system.md 中仅通过注释提及。`log-analyzer.kun:40` 使用 `Cmd.cat logPath` 无选项 Record 是合法用法，但未明确文档化

### 轻微（措辞/可读性）

8. **Mi1 — Function 示例引用 `List.map` 和 `Float.sqrt` 无 import**
   - 文件：`standard-library.md:547-557`
   - 描述：Function 模块缺省可用，但 `List.map` 和 `Float.sqrt` 需显式 `import`。示例未显示 import 语句

9. **Mi2 — `Stream.range` 2 参数语法糖在 API 中不体现**
   - 文件：`standard-library.md:1806`
   - 描述：文字说明 `range start end` 是 `range start end 1` 的语法糖，但 API 列表仅有 `range : Int -> Int -> Int -> Stream Int`。2 参数形式在 API 中无独立展示

10. **Mi3 — `Stream.filterMap` 无独立 tagged union 变体说明位置**
    - 文件：`standard-library.md:1878` + `system-baseline.md:192`
    - 描述：`system-baseline.md` 说 filterMap 展开为 mapped + 过滤，但 `standard-library.md` 将其列为独立函数。两者对齐但位置不易关联

11. **Mi4 — `app-overview.md:57` 描述"严格求值作为默认策略"但无 `let` 延迟求值的交叉引用**
    - 描述：严格求值描述正确但缺少指向 `let` 延迟求值交叉引用

12. **Mi5 — `basic.kun` 库模块导出 `processLog`（效应函数）**
    - 文件：`basic.kun:7`
    - 描述：`processLog : Path -> Unit` 是效应函数（含 `do` 块 + `Cmd.cat`），从库模块导出是合法的（虽然罕见）。无语法错误，仅备注意

## 交叉引用一致性问题

| 引用对 | 状态 | 说明 |
|--------|------|------|
| standard-library.md Cli API ↔ cli.md Cli API | ✅ 一致 | 所有签名、描述匹配 |
| standard-library.md Cmd API ↔ command-system.md Cmd API | ✅ 一致 | 所有签名、分类匹配 |
| standard-library.md type system ↔ type-system.md types | ✅ 一致 | 基础类型对齐 |
| feature-inventory.md ↔ standard-library.md | ✅ 一致 | 功能清单与 API 定义对齐 |
| code-formatting.md 缩进规则 ↔ syntax.md 语法规则 | ⚠️ 见 M3 | 唯一歧义点在 `do in` 内 bound 分支 `let in` 使用 |
| cli.md 类型结构 ↔ standard-library.md Cli API | ✅ 一致 | CliSpec/CliArg/CliMeta/CliError 一致 |
| command-system.md Cmd 分类 ↔ standard-library.md Cmd 分类 | ✅ 一致 | 纯/效应分类一致 |
| mvp.md 推迟特性 ↔ standard-library.md 推迟表 | ✅ 一致 | 推迟版本匹配 |
| conventions.md 命名规范 ↔ syntax.md 模块命名 | ✅ 一致 | PascalCase/kebab-case 一致 |

## 示例代码问题汇总

| 文件 | 严重 | 中等 | 轻微 |
|------|------|------|------|
| standard-library.md | 3 (S1,S2,S3) | 2 (M1,M2) | 2 (Mi1,Mi2) |
| code-formatting.md | 0 | 1 (M3) | 0 |
| log-analyzer.kun | 0 | 0 | 0 |
| basic.kun | 0 | 0 | 1 (Mi5) |
| 其他文档 | 0 | 0 | 2 (Mi3,Mi4) |

## 建议修复清单

| 优先级 | 问题 | 对应文件 | 修复方式 |
|--------|------|---------|---------|
| P0 | S1: Task 示例缺少 `do` 包裹 | standard-library.md:2620-2624 | 在 `\r ->` 后添加 `do` 和缩进 |
| P0 | S2: Base64 示例效应调用在纯上下文 | standard-library.md:2572-2574 | 包裹 `do` 块或修改用例 |
| P0 | S3: Path 示例未绑定 case 结果 | standard-library.md:973-975 | 绑定结果到变量或统一分支类型 |
| P1 | M1: `Cli.show` 推迟标注 | standard-library.md:1668 | 添加 `[推迟 v0.5]` 或更新推迟表 |
| P1 | M2: `List.sum` 签名/注释 | standard-library.md:1301 | 统一签名与注释 |
| P2 | M3: `readConfig` 示例语义澄清 | code-formatting.md:362-380 | 添加注释说明 bound 分支打断 do 链 |
| P2 | M4: 无选项 Record 省略语法正式化 | command-system.md:22-26 | 在语法入口章节增加正式说明 |
| P3 | Mi1: Function 示例补充 import | standard-library.md:547 | 添加 `import List`/`import Float` |
| P3 | Mi2: Stream.range 2-arg 入 API 列表 | standard-library.md:1770 | 添加 `range : Int -> Int -> Stream Int` 或注明 sugar |
