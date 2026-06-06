#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "===> [docs-build] 安装依赖..."
cd "$ROOT_DIR"
pnpm install --frozen-lockfile 2>/dev/null || pnpm install

echo "===> [docs-build] 构建文档..."
pnpm docs:build

echo "===> [docs-build] 完成！"
echo "     输出目录: docs/.vitepress/dist"