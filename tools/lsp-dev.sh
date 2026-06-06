#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "===> [lsp-dev] 安装依赖..."
cd "$ROOT_DIR"
pnpm install --frozen-lockfile 2>/dev/null || pnpm install

echo "===> [lsp-dev] 构建 @kun-lang/shared..."
pnpm lsp:shared:build

echo "===> [lsp-dev] 构建 @kun-lang/lsp-server..."
pnpm lsp:build

echo "===> [lsp-dev] 构建 @kun-lang/vscode-plugin..."
pnpm lsp:plugin:build

echo "===> [lsp-dev] 完成！"
echo ""
echo "  启动 LSP 服务端 (stdio mode):"
echo "    node code/lsp-server/server/dist/index.js --stdio"
echo ""
echo "  在 VS Code 中测试:"
echo "    1. 按 F5 启动 Extension Development Host"
echo "    2. 打开 .kun 文件激活 LSP"