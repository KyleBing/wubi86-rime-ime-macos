#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/DerivedDataRelease"
APP="$DD/Build/Products/Release/MeifengWubi.app"
IME_SRC="$APP/Contents/Resources/MeifengWubiIME.payload"
IME_DEST="$HOME/Library/Input Methods/MeifengWubiIME.app"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cd "$ROOT"
if [[ ! -d MeifengWubi.xcodeproj ]]; then
  echo "缺少 xcodeproj，请先 xcodegen generate"
  exit 1
fi

# Release：避免 Debug 的 .debug.dylib 结构
xcodebuild -project MeifengWubi.xcodeproj -scheme MeifengWubi \
  -configuration Release -derivedDataPath "$DD" build

killall MeifengWubiIME 2>/dev/null || true

# 注销工程目录里误注册的构建产物，避免列表出现多个同名输入法
for p in \
  "$DD/Build/Products/Release/MeifengWubiIME.app" \
  "$ROOT/build/DerivedData/Build/Products/Debug/MeifengWubiIME.app"
do
  [[ -e "$p" ]] && "$LSREG" -u "$p" 2>/dev/null || true
done

rm -rf "$IME_DEST"
cp -R "$IME_SRC" "$IME_DEST"

# 预编译词库（缺 build 时输入法无候选）
if [[ ! -f "$HOME/Library/Application Support/MeifengWubi/rime/build/wubi86_jidian.table.bin" ]]; then
  echo "正在编译词库…"
  # 使用已链接的 librime 小工具若存在，否则依赖 IME 启动时 forceFullCheck
  if [[ -x /tmp/rime_deploy_test ]]; then
    /tmp/rime_deploy_test >/tmp/rime_deploy_out.txt 2>&1 || true
  fi
fi

killall TextInputMenuAgent 2>/dev/null || true

# 启用输入源
xcrun swiftc "$ROOT/scripts/check_tis.swift" -o /tmp/check_tis_meifeng -framework Carbon -framework Foundation
/tmp/check_tis_meifeng

open "$APP"
open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension" || true
echo "已安装到: $IME_DEST"
echo "菜单栏应显示「五」；设置里名称为「玫枫五笔」。请在文本框试打 gw（瓜）等。"
