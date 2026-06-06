#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CLI_TS="$ROOT_DIR/code/lsp-server/shared/src/cli.ts"

if [ $# -lt 1 ]; then
  echo "用法: tools/kun-lint.sh <check|format> <file>..."
  echo ""
  echo "命令:"
  echo "  check   检查 Kun 代码语法/类型/过时模式"
  echo "  format  格式化 Kun 代码"
  echo ""
  echo "示例:"
  echo "  tools/kun-lint.sh check app.kun src/lib.kun"
  echo "  tools/kun-lint.sh format app.kun"
  exit 1
fi

cd "$ROOT_DIR"
pnpm --filter @kun-lang/lsp-shared exec ts-node "$CLI_TS" "$@"