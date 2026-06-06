# Kun LSP 语言服务

Kun 编程语言的 Language Server Protocol 实现，包含 VS Code 扩展。

## 项目结构

```
code/lsp-server/
├── shared/                # @kun-lang/lsp-shared — 语法规则、类型定义、AST
├── server/                # @kun-lang/lsp-server — LSP 服务端
├── plugin/                # @kun-lang/lsp-plugin — VS Code 扩展
├── tsconfig.base.json
└── package.json
```

## 功能特性

- **诊断**：注释风格验证、废弃语法检测、类型命名检查、泛型检查、IO 绑定上下文检测、分号检测
- **格式化**：2 空格缩进、注释风格修正、尾随空格清理、分号移除
- **自动补全**：关键字、内置类型、文档注释模板
- **悬停提示**：关键字/类型/运算符文档

## 开发

```bash
# 安装依赖（从项目根目录执行）
pnpm install

# 构建所有模块
cd code/lsp-server && pnpm build

# 类型检查
cd code/lsp-server && pnpm typecheck

# 独立启动 LSP 服务端
cd code/lsp-server && pnpm start
```

## 构建脚本

`tools/lsp-dev.sh` 按依赖顺序构建所有模块（install → shared → server → plugin）。
