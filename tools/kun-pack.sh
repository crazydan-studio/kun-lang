#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
KUN_DIR="$ROOT_DIR/code/kun-lang"
OUT_DIR="${1:-$ROOT_DIR/dist}"

echo "===> [kun-pack] 构建..."
cd "$KUN_DIR"
zig build

echo "===> [kun-pack] 打包到 $OUT_DIR ..."
mkdir -p "$OUT_DIR/bin" "$OUT_DIR/lib"

cp "$KUN_DIR/zig-out/bin/kun" "$OUT_DIR/bin/"
cp "$KUN_DIR/zig-out/lib/libkunlang.so" "$OUT_DIR/lib/"

echo "===> [kun-pack] 完成！"
echo "     bin/kun"
echo "     lib/libkunlang.so"
