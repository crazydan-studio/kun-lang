#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_DIR="$PROJECT_ROOT/docs"

echo "==> 安装文档依赖..."
cd "$DOCS_DIR"
pnpm install

echo "==> 启动本地预览服务..."
pnpm dev
