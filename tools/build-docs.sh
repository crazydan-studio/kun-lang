#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_DIR="$PROJECT_ROOT/docs"

echo "==> 安装文档依赖..."
cd "$DOCS_DIR"
pnpm install

echo "==> 构建文档..."
pnpm build

echo "==> 文档构建完成！输出目录：$DOCS_DIR/.vitepress/dist"
