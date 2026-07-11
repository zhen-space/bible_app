#!/usr/bin/env bash
# Render 靜態網站建置腳本：下載 Flutter → 準備 sqlite wasm → 編譯網頁版
set -euo pipefail

FLUTTER_VERSION=3.32.5
FLUTTER_DIR="$HOME/flutter-sdk"

if [ ! -x "$FLUTTER_DIR/flutter/bin/flutter" ]; then
  echo "==> Downloading Flutter $FLUTTER_VERSION"
  mkdir -p "$FLUTTER_DIR"
  curl -sSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C "$FLUTTER_DIR"
fi
export PATH="$PATH:$FLUTTER_DIR/flutter/bin"
git config --global --add safe.directory "$FLUTTER_DIR/flutter" || true

echo "==> flutter pub get"
flutter pub get

echo "==> sqflite web binaries (sqlite3.wasm / sqflite_sw.js)"
dart run sqflite_common_ffi_web:setup

echo "==> flutter build web"
# --pwa-strategy=none：不產生 service worker（舊版快取常在版本更新時卡白屏）
flutter build web --release --no-web-resources-cdn --pwa-strategy=none

echo "==> Done. Output in build/web"
