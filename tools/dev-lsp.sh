#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "=== Kun Language Server Development ==="
echo ""

# Build shared library
echo ">> Building @kun-lang/shared..."
cd "$ROOT_DIR/code/lsp-server/shared"
pnpm build

# Build LSP server
echo ">> Building @kun-lang/lsp-server..."
cd "$ROOT_DIR/code/lsp-server/server"
pnpm build

# Build VS Code plugin
echo ">> Building @kun-lang/vscode-plugin..."
cd "$ROOT_DIR/code/lsp-server/plugin"
pnpm build

echo ""
echo "=== Build complete ==="
echo ""
echo "To start the LSP server in development mode:"
echo "  node code/lsp-server/server/dist/index.js --stdio"
echo ""
echo "To test the VS Code extension:"
echo "  1. Open this project in VS Code"
echo "  2. Press F5 to start the Extension Development Host"
echo "  3. Open a .kun file to activate the LSP"
echo ""
echo "To run type checking for all modules:"
echo "  pnpm --filter @kun-lang/lsp-server typecheck"
echo "  pnpm --filter @kun-lang/vscode-plugin typecheck"
