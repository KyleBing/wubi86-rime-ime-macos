#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/DerivedDataRelease"
APP="$DD/Build/Products/Release/玫枫五笔.app"
IME_SRC="$APP/Contents/Resources/MeifengWubiIME.payload"
IME_DEST="$HOME/Library/Input Methods/MeifengWubiIME.app"
IME_SYSTEM="/Library/Input Methods/MeifengWubiIME.app"
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
# 旧的主 App 进程仍在运行时，末尾 open 只会激活旧进程，界面看不到新改动
killall "玫枫五笔" 2>/dev/null || true
# 兼容旧产物进程名
killall MeifengWubi 2>/dev/null || true

# 注销工程目录里误注册的构建产物，避免列表出现多个同名输入法
for p in \
  "$DD/Build/Products/Release/MeifengWubiIME.app" \
  "$ROOT/build/DerivedData/Build/Products/Debug/MeifengWubiIME.app"
do
  [[ -e "$p" ]] && "$LSREG" -u "$p" 2>/dev/null || true
done

# 系统目录旧包会抢先启动（root 安装），导致用户目录新构建不生效。
if [[ -e "$IME_SYSTEM" ]]; then
  "$LSREG" -u "$IME_SYSTEM" 2>/dev/null || true
  echo "检测到系统目录旧输入法，正在删除（需管理员密码）…"
  if osascript -e "do shell script \"rm -rf \\\"$IME_SYSTEM\\\"\" with administrator privileges" >/dev/null; then
    echo "已删除: $IME_SYSTEM"
  else
    echo "警告: 未能删除 $IME_SYSTEM。若不删，菜单栏仍可能跑旧进程，新改动（含造词图标）不会出现。"
  fi
fi

mkdir -p "$HOME/Library/Input Methods"
[[ -e "$IME_DEST" ]] && "$LSREG" -u "$IME_DEST" 2>/dev/null || true
rm -rf "$IME_DEST"
cp -R "$IME_SRC" "$IME_DEST"

# 预编译词库（缺 build 时输入法无候选）
if [[ ! -f "$HOME/Library/Application Support/MeifengWubi/rime/build/wubi86_jidian.table.bin" ]]; then
  echo "正在编译词库…"
  if [[ -x /tmp/rime_deploy_test ]]; then
    /tmp/rime_deploy_test >/tmp/rime_deploy_out.txt 2>&1 || true
  fi
fi

# 系统设置开着时改输入源容易叠出幽灵行
osascript -e 'tell application "System Settings" to quit' >/dev/null 2>&1 || true

# 先注册用户目录输入法，再打开宿主（打开宿主会扫到包内 payload）
xcrun swiftc "$ROOT/scripts/check_tis.swift" -o /tmp/check_tis_meifeng \
  -framework Foundation -framework Carbon
/tmp/check_tis_meifeng

open "$APP"
# 宿主启动后又会把 .payload 注册进来，再清一次并启用用户目录副本
sleep 1
# 宿主包内 payload + Applications 旧名幽灵路径
for p in \
  "$APP/Contents/Resources/MeifengWubiIME.payload" \
  "/Applications/MeifengWubi.app/Contents/Resources/MeifengWubiIME.payload" \
  "/Applications/玫枫五笔.app/Contents/Resources/MeifengWubiIME.payload" \
  "$DD/Build/Products/Release/MeifengWubiIME.app"
do
  "$LSREG" -u "$p" 2>/dev/null || true
done
/tmp/check_tis_meifeng
# 再杀一次，避免仍挂着系统目录旧进程；下次切换输入法时由系统拉起用户目录副本
killall MeifengWubiIME 2>/dev/null || true
# 这两个进程忽略 SIGTERM，killall 杀不掉，会把登录时的输入法列表一直留到重启
for pid in $(ps -ax -o pid=,command= | awk '/TextInputMenuAgent.app\/Contents\/MacOS\/TextInputMenuAgent|TextInputSwitcher.app\/Contents\/MacOS\/TextInputSwitcher/ {print $1}'); do
  kill -9 "$pid" 2>/dev/null || true
done

echo "已安装到: $IME_DEST"
if [[ -e "$IME_SYSTEM" ]]; then
  echo "注意: $IME_SYSTEM 仍在，请手动删掉后重开输入法。"
fi
echo "菜单栏应显示「玫枫」；设置里名称为「玫枫五笔」。请在文本框试打 gw（瓜）等。"
echo "若仍看不到，关掉系统设置后重跑本脚本；重复项请在「键盘 → 输入法 → 编辑…」用「-」删到一条。"
# 确认当前没有系统目录进程
if pgrep -lf '/Library/Input Methods/MeifengWubiIME' >/dev/null 2>&1; then
  echo "警告: 仍有进程来自 /Library/Input Methods/MeifengWubiIME.app，请删掉该目录后注销重登或重跑本脚本。"
fi
# 确认 LS 不再指向 payload
if "$LSREG" -dump 2>/dev/null | rg -q 'MeifengWubiIME\.payload'; then
  echo "警告: Launch Services 仍登记了 MeifengWubiIME.payload，请再点宿主里的「刷新状态」。"
fi