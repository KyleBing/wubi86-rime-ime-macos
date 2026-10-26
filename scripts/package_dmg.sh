#!/bin/bash
# 打出可分发的 DMG：Release 通用二进制、Developer ID 签名、拖到「应用程序」安装。
# 不安装、不结束本机输入法进程。
#
# 公证（发给别人、避免 Gatekeeper 拦截）使用钥匙串里已保存的凭据。
# 本机配置名是 meifeng-notary。未设置 NOTARY_KEYCHAIN_PROFILE 时会自动用它。
# 也可临时传入：NOTARY_KEYCHAIN_PROFILE、或 APPLE_ID + APPLE_APP_PASSWORD。
#
# 也可临时传入：APPLE_ID、APPLE_APP_PASSWORD（App 专用密码）、APPLE_TEAM_ID。
# 指定证书：SIGN_IDENTITY="Developer ID Application: …"，或直接给 40 位 SHA-1。
# ADHOC_SIGN=1：没有 Developer ID 证书时（如 CI 未配密钥）打出自签名包，跳过公证。
set -euo pipefail

# 登录会话的 __CF_USER_TEXT_ENCODING 常是 MacRoman（0x0）。
# 证书显示名含中文时，codesign 会把 UTF-8 当成 MacRoman，报 no identity found。
if [[ -n "${__CF_USER_TEXT_ENCODING:-}" ]]; then
  _cf_uid="${__CF_USER_TEXT_ENCODING%%:*}"
  # 0x08000100 = kCFStringEncodingUTF8
  export __CF_USER_TEXT_ENCODING="${_cf_uid}:0x8000100:0x0"
  unset _cf_uid
fi
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/DerivedDataDist"
APP_NAME="玫枫五笔"
TEAM_ID="${APPLE_TEAM_ID:-4J6QFDHMK2}"
VOL_NAME="$APP_NAME"

cd "$ROOT"
if [[ ! -d MeifengWubi.xcodeproj ]]; then
  echo "缺少 xcodeproj，请先 xcodegen generate"
  exit 1
fi

# 用证书 SHA-1 签名。显示名里的中文即使修正了编码，哈希也不受本地化影响。
SIGN_WANT="${SIGN_IDENTITY:-}"
SIGN_HASH=""
SIGN_LABEL=""
while IFS=$'\t' read -r hash label; do
  [[ -z "$hash" ]] && continue
  if [[ -n "$SIGN_WANT" ]]; then
    if [[ "$SIGN_WANT" == "$hash" || "$SIGN_WANT" == "$label" || "$label" == *"$SIGN_WANT"* ]]; then
      SIGN_HASH="$hash"
      SIGN_LABEL="$label"
      break
    fi
  elif [[ "$label" == *"($TEAM_ID)"* ]]; then
    SIGN_HASH="$hash"
    SIGN_LABEL="$label"
    break
  fi
done < <(security find-identity -v -p codesigning | awk '
  /Developer ID Application/ {
    hash = $2
    label = $0
    sub(/^[^"]*"/, "", label)
    sub(/"$/, "", label)
    print hash "\t" label
  }
')
if [[ -z "$SIGN_HASH" ]]; then
  # CI 或没有证书的机器：允许退化成自签名，打出的包只适合自用或测试
  if [[ "${ADHOC_SIGN:-0}" == "1" ]]; then
    ADHOC="1"
    SIGN_IDENTITY="-"
    SIGN_LABEL="自签名（未配置 Developer ID 证书）"
    echo "未找到 Developer ID Application 证书，按 ADHOC_SIGN=1 自签名，跳过公证。"
  else
    echo "未找到 Developer ID Application 证书。开发证书打出的包不能分发给别人。"
    exit 1
  fi
else
  SIGN_IDENTITY="$SIGN_HASH"
fi
ADHOC="${ADHOC:-0}"

echo "签名身份: $SIGN_LABEL"
echo "正在编译 Release（arm64 + x86_64）…"
# 交给下面的 codesign 统一签，避免 xcodebuild 在 CI 上找不到签名证书而失败
xcodebuild -project MeifengWubi.xcodeproj -scheme MeifengWubi \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DD" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}" \
  build

BUILT="$DD/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$BUILT" ]]; then
  echo "找不到构建产物: $BUILT"
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT/Contents/Info.plist")"
BUILD_NO="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUILT/Contents/Info.plist")"
DIST="$ROOT/build/dist"
STAGE="$DIST/stage"
DMG="$DIST/${APP_NAME}-${VERSION}.dmg"
RW_DMG="$DIST/${APP_NAME}-rw.dmg"
BG_PNG="$DIST/background.png"

rm -rf "$STAGE"
mkdir -p "$STAGE"
# ditto 保留包结构，避免 cp 弄坏签名资源
ditto "$BUILT" "$STAGE/${APP_NAME}.app"
xattr -cr "$STAGE/${APP_NAME}.app"

# 由内向外签。不要带上 get-task-allow，公证会拒。
sign_bundle() {
  local target="$1"
  if [[ "$ADHOC" == "1" ]]; then
    # 自签名没有时间戳服务，省掉 --timestamp
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$target"
  else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$target"
  fi
}

PAYLOAD="$STAGE/${APP_NAME}.app/Contents/Resources/MeifengWubiIME.payload"
PREFPANE="$PAYLOAD/Contents/Resources/Preferences.prefPane"
SPARKLE="$STAGE/${APP_NAME}.app/Contents/Frameworks/Sparkle.framework"
echo "正在签名…"
sign_bundle "$PREFPANE"
sign_bundle "$PAYLOAD"
# Sparkle 是 SPM 下载的预签名框架，签名团队和我们不同；
# 强化运行时（library validation）会因此拒绝加载，必须先按自己的证书重签整棵子树
if [[ -d "$SPARKLE" ]]; then
  if [[ "$ADHOC" == "1" ]]; then
    codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$SPARKLE"
  else
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE"
  fi
fi
# 主 App 带「允许加载不同签名的库」授权，重签时必须显式带上，否则会被丢掉
APP_ENTITLEMENTS="$ROOT/App/MeifengWubi.entitlements"
if [[ "$ADHOC" == "1" ]]; then
  codesign --force --options runtime --entitlements "$APP_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$STAGE/${APP_NAME}.app"
else
  codesign --force --options runtime --timestamp --entitlements "$APP_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$STAGE/${APP_NAME}.app"
fi
codesign --verify --deep --strict --verbose=2 "$STAGE/${APP_NAME}.app"

# 窗口背景：箭头 + 一句安装说明。失败也不影响出包。
swift - "$BG_PNG" <<'SWIFT' || true
import AppKit
import Foundation

let out = CommandLine.arguments[1]
let w: CGFloat = 660
let h: CGFloat = 420
let image = NSImage(size: NSSize(width: w, height: h))
image.lockFocus()
NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.97, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: h)).fill()
let arrow = "→" as NSString
let arrowAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 36, weight: .light),
    .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1),
]
let arrowSize = arrow.size(withAttributes: arrowAttrs)
arrow.draw(
    at: NSPoint(x: (w - arrowSize.width) / 2, y: (h - arrowSize.height) / 2 + 8),
    withAttributes: arrowAttrs
)
let hint = "拖到「应用程序」即可安装" as NSString
let hintAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1),
]
let hintSize = hint.size(withAttributes: hintAttrs)
hint.draw(at: NSPoint(x: (w - hintSize.width) / 2, y: 36), withAttributes: hintAttrs)
image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("背景生成失败\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: out))
SWIFT

# 可写镜像，用来排图标位置；体积按暂存目录留余量
STAGE_MB="$(du -sm "$STAGE" | awk '{ print $1 }')"
IMG_MB="$((STAGE_MB + 30))"
rm -f "$RW_DMG" "$DMG"
hdiutil create -size "${IMG_MB}m" -fs HFS+ -volname "$VOL_NAME" -ov "$RW_DMG" >/dev/null

ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
MOUNT="$(printf '%s\n' "$ATTACH_OUT" | sed -n 's/.*\(\/Volumes\/.*\)/\1/p' | head -1)"
cleanup_mount() {
  if [[ -n "${MOUNT:-}" && -d "$MOUNT" ]]; then
    hdiutil detach "$MOUNT" >/dev/null 2>&1 || hdiutil detach -force "$MOUNT" >/dev/null 2>&1 || true
  fi
}
trap cleanup_mount EXIT

ditto "$STAGE/${APP_NAME}.app" "$MOUNT/${APP_NAME}.app"
ln -s /Applications "$MOUNT/Applications"
if [[ -f "$ROOT/App/AppIcon.icns" ]]; then
  cp "$ROOT/App/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -a C "$MOUNT" || true
  fi
fi
if [[ -f "$BG_PNG" ]]; then
  mkdir -p "$MOUNT/.background"
  cp "$BG_PNG" "$MOUNT/.background/background.png"
fi

# 排版失败时仍保留可用的拖拽安装盘
osascript <<APPLESCRIPT || echo "警告: 未能设置 Finder 窗口排版，DMG 仍可用。"
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 120, 1060, 540}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 13
    try
      set background picture of viewOptions to file ".background:background.png"
    end try
    set position of item "$APP_NAME.app" of container window to {160, 175}
    set position of item "Applications" of container window to {480, 175}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT

sync
# 先解除 trap，避免下面主动卸载后又被 trap 再卸一次
trap - EXIT
hdiutil detach "$MOUNT"
MOUNT=""

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
rm -f "$RW_DMG"
if [[ "$ADHOC" == "1" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" "$DMG"
else
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
codesign --verify --verbose=2 "$DMG"

echo "已生成: $DMG"
echo "版本: ${VERSION} (${BUILD_NO})，架构: $(lipo -archs "$STAGE/${APP_NAME}.app/Contents/MacOS/${APP_NAME}")"

notarize() {
  local dmg="$1"
  echo "正在提交公证…"
  if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    xcrun notarytool submit "$dmg" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_PASSWORD" \
      --team-id "$TEAM_ID" \
      --wait
  else
    return 1
  fi
  # 票据已经 Accepted，但 stapler 还要联网去 Apple 取回来。
  # CI 上偶发 -1005「The network connection was lost」会返回 Error 68，重试几次即可。
  local attempt
  for attempt in 1 2 3 4 5; do
    if xcrun stapler staple "$dmg" && xcrun stapler validate "$dmg"; then
      echo "公证并装订完成。"
      return 0
    fi
    if [[ "$attempt" -lt 5 ]]; then
      echo "装订第 ${attempt} 次失败（多为网络瞬时故障），$((attempt * 10)) 秒后重试…"
      sleep $((attempt * 10))
    fi
  done
  # 没装订上不阻断发版：公证已通过，用户联网首次打开仍可正常校验
  echo "::warning::票据装订失败，DMG 已公证但未 staple，用户首次打开需联网校验。"
  echo "警告: 未能装订公证票据，DMG 已公证但未 staple。"
  return 0
}

# 未指定时，用钥匙串里已经存好的公证配置。没有该配置时 notarytool 会立刻报错，不会联网。
# 自签名包不能公证，直接跳过。
if [[ "$ADHOC" == "0" && -z "${NOTARY_KEYCHAIN_PROFILE:-}" && -z "${APPLE_ID:-}" ]]; then
  for candidate in meifeng-notary meifeng; do
    err="$(xcrun notarytool history --keychain-profile "$candidate" 2>&1 >/dev/null || true)"
    [[ "$err" == *"No Keychain password item found"* ]] && continue
    NOTARY_KEYCHAIN_PROFILE="$candidate"
    echo "使用已保存的公证凭据: $candidate"
    break
  done
fi

if [[ "$ADHOC" == "1" ]]; then
  echo "自签名包未公证，其他人下载后需右键打开或 xattr 去除隔离属性。"
elif [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" || -n "${APPLE_ID:-}" ]]; then
  notarize "$DMG"
else
  echo "尚未公证。本机已用 Developer ID 签名，但别人的 Mac 仍会被 Gatekeeper 拦截。"
  echo "钥匙串里没有 meifeng-notary / meifeng。存好凭据后重跑本脚本即可公证："
  echo "  xcrun notarytool store-credentials meifeng-notary --apple-id \"你的 Apple ID\" --team-id ${TEAM_ID}"
  echo "  ./scripts/package_dmg.sh"
fi
