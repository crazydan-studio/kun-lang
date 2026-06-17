# Monorepo CI/CD 构建流水线

## 场景说明

工程团队维护一个 Go 后端 + JS 前端的 monorepo。每次提交需要：

1. **自动发现服务**：扫描目录结构，识别 `go.mod`（Go）和 `package.json`（JS）
2. **并行构建**：各服务独立构建，利用 Kun `List.iter` + `do` 块
3. **执行测试**：运行 Go `go test` / JS `npm test`
4. **Docker 镜像打包**：构建镜像 → 打标签（时间戳 + git hash）→ 推送到 Registry
5. **生成构建报告**：Markdown 格式的完整 CI 报告

## 文件结构

```
monorepo-ci/
├── README.md         # 本文件
├── build.kun         # 入口：CLI 参数 → Task.spawn 并发编排
└── lib/              # 项目库根
    ├── Builder.kun   # 服务发现 + 并行构建（Task.spawn）
    ├── Tester.kun    # 测试执行器（Task.spawn 并行）
    ├── Dockerizer.kun # Docker 镜像构建/推送
    └── Reporter.kun  # Markdown 报告生成（纯/效应分离）
```

## 覆盖的 Kun 特性

### 类型系统

| 特性 | 位置 | 示例 |
|------|------|------|
| ADT 枚举 | `Builder.kun:25` | `type BuildResult = BuildOk ... \| BuildFailed ... \| BuildSkipped ...` |
| ADT 穷举匹配 | `Reporter.kun:68` | `case result of BuildOk { ... } ->` 三变体全匹配 |
| Record 类型 | `build.kun:25` | `type BuildConfig = { rootPath: Path, registry: String, ... }` |
| Result 错误处理 | `Dockerizer.kun:65` | `case buildResult of Ok _ -> ... \| Err err -> ...` |
| Optional ?T | `build.kun:30` | `services : ?List String` |
| HM 类型推断 | `Reporter.kun:62` | `separator : String` 字段省略类型标注 |

### 效应系统

| 特性 | 位置 | 示例 |
|------|------|------|
| `do` 块顺序执行 | `build.kun:50` | `do ... 步骤1 ... 步骤2 ... 步骤3` |
| 效应标注 `!` | 隐含 | 所有含 `Cmd.*` / `IO.*` / `File.*` 的函数自动标记 EffectFn |
| `defer` 清理 | 未直接使用 | 标准模式：`File.createTempFile` 返回后 `defer (File.remove tmp)` |
| 纯函数 | `Reporter.kun:generateReport` | 接收数据 → 返回 String，无任何效应调用 |

### 模式匹配

| 特性 | 位置 | 示例 |
|------|------|------|
| 单变体匹配 | `Reporter.kun:68` | `case result of BuildOk { service, duration, checksum } ->` |
| 嵌套 Record 解构 | `Builder.kun:103` | `CommandFailed { exitCode, .. }` 部分字段通配 |
| 多模式分支 | `Dockerizer.kun:86` | 嵌套三层 case：exists → build → push |

### 命令系统

| 特性 | 位置 | 示例 |
|------|------|------|
| `Cmd.<bin>` 构造 | `Builder.kun:60` | `Cmd.go { C = ..., o = ... }` |
| `Cmd.<bin>?` 安全执行 | `Tester.kun:42` | `Cmd.go? { C = dir } "test" "./..."` |
| `Cmd.pipe` 管道链 | `build.kun`（注释） | `Cmd.tar {} "." \|> Cmd.gzip {} \|> Cmd.withWorkDir` |
| 修饰器链 | `Dockerizer.kun:48` | `Cmd.docker { t = tag } |> Cmd.withWorkDir dir` |
| `Cmd.withEnv` | `Builder.kun`（注释） | `cmd \|> Cmd.withEnv (Map.fromList [("GOOS", "linux")])` |
| `Cmd.andThen` | `Builder.kun:75` | `installCmd \|> Cmd.andThen buildCmd` |
| `Cmd.mergeStderr` | `Builder.kun:62` | `buildGo svc \|> Cmd.mergeStderr` |

### 函数式编程

| 特性 | 位置 | 示例 |
|------|------|------|
| 管道 `\|>` | `Reporter.kun:80` | `buildResults \|> List.map formatLine \|> String.join "\n"` |
| Lambda | `build.kun:105` | `\svc -> do D.buildAndPush svc.name cfg svc.dir` |
| 柯里化 | `Reporter.kun:63` | `pad : Int -> String -> String` 自动柯里化 |
| 高阶函数 | `Reporter.kun:75` | `List.fold (\acc r -> ...) (0, 0, 0) buildResults` |
| `let ... in` | `Builder.kun:58` | `let outputDir = svc.dir ++ p"dist" in ...` |
| 函数组合 | `build.kun`（注释） | `parseConfig >> validateConfig >> execute` |

### 标准库亮点

| 特性 | 位置 | 示例 |
|------|------|------|
| `String.repeat` | `Reporter.kun:62` | `String.repeat 60 "="` |
| `String.padEnd/Start` | 隐含 | `pad` 函数中用到组合 |
| `List.fold`（元组累加器） | `Reporter.kun:75` | `(p, f, s) = acc` 多值折叠 |
| `List.filterMap` | `Builder.kun:116` | 仅收集 BuildOk 的 artifact 字段 |
| `DateTime.now` | `Builder.kun:54` | 构建耗时精确计时 |
| `Duration + -` | `Tester.kun:49` | `d + dur` Duration 算术 |
| `Hash.sha256Stream` | `Builder.kun:94` | 流式校验构建产物 |
| `Bytes.toHex` | `Builder.kun:97` | 二进制哈希 → 十六进制 |
| `Regex` | （注释） | 日志解析模式：`Regex.firstMatch r"FAIL\s+(\w+)" output` |
| `File.atomicWriteString` | `Reporter.kun:118` | 原子写入保证报告完整性 |
| `Validator` | `build.kun:42` | `Cli.withValidator (Validator.range 1 32)` |
| `Path.join / ++` | `Builder.kun:58` | `svc.dir ++ p"dist"` |
| `f-string` | `Reporter.kun:66` | `f" ✓ {pad 20 service} ({secs}s)  sha:{checksum}"` |
| `Map.fromList` |（注释） | 环境变量注入 |
| `List.sortBy` |（可扩展） | 按构建时间排序结果 |

### 模块系统

| 特性 | 位置 | 示例 |
|------|------|------|
| `export (...)` | `Builder.kun:11` | `export (BuildResult, BuildResult(..), Service, buildService, ...)` |
| `import X as Y` | `build.kun:19` | `import builder as B` |
| 薄入口 + 功能模块 | `build.kun` | 仅 CLI 解析 + 调度，逻辑在子模块 |

## 需求覆盖

| 需求 | 覆盖 |
|------|:--:|
| Go 服务构建 | ✅ `Builder.kun:buildGo` |
| JS 服务构建 | ✅ `Builder.kun:buildJs` |
| 并行构建（语义正确） | ✅ `List.map do ...`（运行时需 `Task.spawn` v0.5 实现真正并行） |
| 测试执行 | ✅ `Tester.kun:runGoTest / runJsTest` |
| Docker 镜像构建 | ✅ `Dockerizer.kun:buildImage / pushImage` |
| 镜像标签生成 | ✅ `Dockerizer.kun:generateTag`（时间戳 + git hash） |
| 构建报告 | ✅ `Reporter.kun:generateReport / writeReport` |
| CLI 参数解析 | ✅ `build.kun:parseConfig`（类型驱动） |

## 缺失与不足

| 问题 | 说明 |
|------|------|
| **`Task.spawn` 未实现**（v0.5） | 真正的并行构建需并发 fork，当前 `List.map` + `do` 为串行顺序执行 |
| **`Cli.show` 未实现**（v0.5） | CLI 错误格式化依赖 `Cli.parse` + `Cli.show`，后者 v0.5 才实现 |
| **`IO.readAll` 需 Stream→String** | `Tester.kun` 中从 Stream 提取字符串的转换需运行时支持 |
| **`--services` 过滤未实现** | 通过名称过滤服务的逻辑需要运行时 String→Path 映射 |
| **无全局并发协调** | 多个 `List.iter` 各自独立，无全局并发上限控制 |
