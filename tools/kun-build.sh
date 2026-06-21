#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
KUN_DIR="$ROOT_DIR/code/kun-lang"

echo "===> [kun-build] 构建 kun..."
cd "$KUN_DIR"
zig build

echo "===> [kun-build] 测试..."
zig build test

echo "===> [kun-build] 完成！"
echo "     二进制: $KUN_DIR/zig-out/bin/kun"
echo "     共享库: $KUN_DIR/zig-out/lib/libkunlang.so"
