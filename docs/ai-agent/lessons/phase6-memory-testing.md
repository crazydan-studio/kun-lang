# Phase 6 教训：内存策略与测试超时

## 内存分配策略

### 问题

Phase 6 审核过程中，为"修复"测试泄漏检测器的泄漏报告，引入 `std.heap.page_allocator` 混用作返回值分配器。这制造了三个问题：

1. **分配模型混乱**：`env.allocator`（Arena）、`page_allocator`（OS malloc）、`std.testing.allocator`（泄漏检测器）三者并存，无一致规则
2. **假性修复**：用 `page_allocator` 绕过泄漏检测，而非修复根因——测试未正确模拟生产 Arena 语义
3. **冗余 `.free()`**：ArenaAllocator 的 `free()` 是 no-op，但代码中存在大量 `defer env.allocator.free(x)` 调用，仅在"制造在做清理"的假象

### 根因

测试中 `RuntimeEnv` 直接使用 `std.testing.allocator`：

```zig
// ❌ 错误：泄漏检测器捕捉 Arena 语义的正常分配
var renv = RuntimeEnv{ .allocator = std.testing.allocator, ... };
```

### 正确方案

生产环境 `env.allocator` 是 per-script ArenaAllocator，脚本退出时整体销毁。测试需用 Arena 包裹泄漏检测器来模拟这一语义：

```zig
// ✅ 正确：Arena 包裹泄漏检测器，defer deinit 一把清空
var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
defer arena.deinit();
var renv = RuntimeEnv{ .allocator = arena.allocator(), ... };
```

### 原则

| 规则 | 说明 |
|------|------|
| **实现代码只用 `env.allocator`** | 禁止 `page_allocator`、`c_alloc` 等其他分配器 |
| **不单独释放 Arena 内存** | `allocator.free()` 在 Arena 上是 no-op，不应使用 |
| **测试用 Arena 包裹** | `ArenaAllocator.init(std.testing.allocator)` + `defer arena.deinit()` |
| **唯一释放点在 `deinit`** | 所有内存通过 Arena.deinit() 一次性释放 |

## 测试超时

### 问题

IO 阻塞测试（如 `IO.readln` 等待 stdin、`walkDir` 遍历大目录）在无输入环境或大文件系统中挂死，导致整体测试运行超时。

### 方案

测试命令必须携带 `--test-timeout` 参数：

```bash
zig build test --test-timeout 5s
```

### 原则

| 规则 | 说明 |
|------|------|
| **始终使用 `--test-timeout 5s`** | 每个测试 5 秒超时，避免阻塞测试挂死整体 |
| **避免 IO 阻塞测试** | `readln`/`readAll` 等在无 stdin 环境不应被测试调用 |
| **控制测试数据集规模** | 文件系统测试用临时小目录，不用 `/tmp` 等大目录 |

## Zig 格式化陷阱

### `{}` vs `{f}`

Zig 的 `{}` 格式描述符对结构体使用**默认字段打印**（逐字段展开），而非调用自定义 `format` 方法。要调用 `format(self, writer)` 方法，必须使用 `{f}` 或 `{any}`：

```zig
// ❌ {} 调用默认字段打印，可能导致 SIGSEGV（undefined 字段）
try writer.print("at {}", .{span});

// ✅ {f} 调用 Span.format(self, writer)
try writer.print("at {f}", .{span});
```

### 自定义 format 签名

与 `{f}` 兼容的签名是 2 参数：

```zig
pub fn format(self: Span, writer: anytype) !void {
    try writer.print("{d}:{d}", .{ self.start.line, self.start.col });
}
```

