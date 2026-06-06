#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "=== Kun AI Agent Development Server ==="
echo ""

# Build shared library
echo ">> Building @kun/lsp-shared..."
cd "$ROOT_DIR/code/lsp-shared"
pnpm build 2>/dev/null || echo "  Note: @kun/lsp-shared is type-only, no build step needed"

# Build LSP server
echo ">> Building @kun/lsp-server..."
cd "$ROOT_DIR/tools/ai-agent/server"
pnpm build

# Build VS Code plugin
echo ">> Building @kun/vscode-plugin..."
cd "$ROOT_DIR/tools/ai-agent/plugin"
pnpm build

echo ""
echo "=== Build complete ==="
echo ""
echo "To start the LSP server in development mode:"
echo "  node tools/ai-agent/server/out/index.js"
echo ""
echo "To test the VS Code extension:"
echo "  1. Open this project in VS Code"
echo "  2. Press F5 to start the Extension Development Host"
echo "  3. Open a .kun file to activate the LSP"
echo ""
echo "To run type checking:"
echo "  pnpm typecheck"
