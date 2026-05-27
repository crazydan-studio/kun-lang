#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_DIR="$PROJECT_ROOT/docs"
PORT="${1:-5173}"

echo "==> 安装文档依赖..."
cd "$DOCS_DIR"
mkdir -p public/diagrams
pnpm install || exit $?

echo "==> 启动本地预览服务..."
pnpm dev --port "$PORT"
