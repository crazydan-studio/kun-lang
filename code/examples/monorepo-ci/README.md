# Monorepo CI/CD 构建流水线

## 场景说明

工程团队维护一个 Go 后端 + JS 前端的 monorepo。每次提交需要：

1. **自动发现服务**：扫描目录结构，识别 `go.mod`（Go）和 `package.json`（JS）
2. **并行构建**：各服务独立构建，`Task.spawn` 并发执行子进程
3. **执行测试**：运行 Go `go test` / JS `npm test`，`Task.spawn` 并行
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
| ADT 枚举 | `Builder.kun` | `type BuildResult = BuildOk ... \| BuildFailed ... \| BuildSkipped ...` |
| ADT 穷举匹配 | `Reporter.kun` | `case result of BuildOk { ... } -> BuildFailed { ... } ->` 全匹配 |
| Record 类型 | `build.kun` | `type BuildConfig = { rootPath: Path, registry: String, ... }` |
| Result 错误处理 | `Dockerizer.kun` | `case buildResult of Ok _ -> ... \| Err err -> ...` 嵌套匹配 |
| Optional ?T | `build.kun` | `services : ?String` 逗号分隔的服务名列表 |
| 纯/效应分离 | `Reporter.kun` | `generateReport` 纯计算 vs `writeReport` 效应写入 |

### 效应系统

| 特性 | 位置 | 示例 |
|------|------|------|
| `do` 块顺序执行 | `build.kun` | 4 个 Phase 依次：构建→测试→Docker→报告 |
| 效应函数自动推断 | `Builder.kun` | `computeChecksum` / `detectServices` / `detectLanguage` 含 `do` 块，编译器自动标记 EffectFn |
| 纯函数 | `Reporter.kun` | `generateReport` 接收数据 → 返回 String，无效应调用 |

### 模式匹配

| 特性 | 位置 | 示例 |
|------|------|------|
| 多模式分支 | `Builder.kun` | `case result of Ok _ -> ... \| Err err -> ...` |
| 嵌套 Record 解构 | `Builder.kun` | `CommandFailed { exitCode, .. }` 部分字段通配 |
| 通配模式 | `Reporter.kun` | `BuildOk _ ->` / `BuildFailed _ ->` |

### 命令系统

| 特性 | 位置 | 示例 |
|------|------|------|
| `Cmd.<bin>` 构造 | `Builder.kun` | `Cmd.go { C = ..., o = ... }` 构造 Command |
| `Cmd.<bin>?` 安全执行 | `Dockerizer.kun` | `Cmd.docker? { t = tag } "build" ...` |
| `Cmd.andThen` | `Builder.kun` | `installCmd \|> Cmd.andThen buildCmd` |
| `Cmd.mergeStderr` | `Builder.kun` | `Cmd.go { ... } \|> Cmd.mergeStderr` |

### 并发

| 特性 | 位置 | 示例 |
|------|------|------|
| `Task.spawn` + `Task.all` | `Builder.kun` / `Tester.kun` / `build.kun` | 并行构建/测试/Docker 批量执行 |

### 函数式编程

| 特性 | 位置 | 示例 |
|------|------|------|
| 管道 `\|>` | `Reporter.kun` | `buildResults \|> List.map formatLine \|> String.join "\n"` |
| Lambda | `build.kun` | `\svc -> D.buildImage svc.name ...` |
| 柯里化 | `Reporter.kun` | `pad : Int -> String -> String` |
| `List.fold` 多值累加 | `Reporter.kun` | `(p, f, s) = acc` 三值折叠 |
| `List.filterMap` | `Builder.kun` | 仅收集 BuildOk 的 artifact 字段 |
| `List.iter` | `build.kun` | `List.iter` 接收效应回调——仅在 k8s-deploy 场景演示 |

### 标准库标识

| 特性 | 位置 |
|------|------|
| `String.repeat` | `Reporter.kun`（分隔线） |
| `DateTime.now` + `Duration` 算术 | `Builder.kun`（构建耗时） |
| `Hash.sha256Stream` / `Bytes.toHex` | `Builder.kun`（产物校验） |
| `File.atomicWriteString` | `Reporter.kun`（原子写入） |
| `Validator` + `Cli.withValidator` | `build.kun`（并行度范围校验） |
| `Path.join` / `++` / `fromString` | 全模块 |
| f-string | 全模块 |

### 模块系统

| 特性 | 位置 | 示例 |
|------|------|------|
| `export (...)` | 各 `lib/*.kun` | `export (BuildResult, BuildResult(..), ...)` |
| `import X as Y` | `build.kun` | `import Builder as B` |
| 薄入口 + `lib/` 库模块 | `build.kun` | 入口仅 CLI + 调度，逻辑在 lib 子模块 |

## 需求覆盖

| 需求 | 状态 |
|------|:--:|
| Go 服务构建 | ✅ |
| JS 服务构建 | ✅ |
| 并行构建（Task.spawn v0.5） | ✅ |
| 测试执行（Task.spawn 并行） | ✅ |
| Docker 镜像构建 + 推送 | ✅ |
| 镜像标签生成（时间戳 + git hash） | ✅ |
| 构建报告（纯/效应分离） | ✅ |
| CLI 参数解析 | ✅ |

## 缺失与不足

| 问题 | 说明 |
|------|------|
| `Task.spawn` 未实现（v0.5） | 代码使用 `Task.spawn` / `Task.all` API，运行时需 v0.5 支持 |
| `Cli.show` 未实现（v0.5） | CLI 错误格式化需 v0.5 |
