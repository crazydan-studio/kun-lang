#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${1:-5173}"

echo "===> [docs-dev] 安装依赖..."
cd "$ROOT_DIR"
pnpm install --frozen-lockfile 2>/dev/null || pnpm install

echo "===> [docs-dev] 启动文档开发服务器 (port $PORT)..."
pnpm docs:dev --port "$PORT"