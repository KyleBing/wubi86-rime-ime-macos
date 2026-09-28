#!/bin/bash
# 构建 VitePress 说明站，并同步到线上 /var/www/html/wubi/macos。
# iOS 说明以后放在同级的 /var/www/html/wubi/ios，本脚本只更新 macOS。
#
#   ./scripts/update_site.sh
#
# 可覆盖：
#   DEPLOY_HOST=root@kylebing.cn
#   DEPLOY_DIR=/var/www/html/wubi/macos
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="$ROOT/site"
DIST="$SITE/docs/.vitepress/dist"
HOST="${DEPLOY_HOST:-root@kylebing.cn}"
DEST="${DEPLOY_DIR:-/var/www/html/wubi/macos}"

if ! command -v npm >/dev/null 2>&1; then
  echo "需要本机已安装 Node.js / npm"
  exit 1
fi

cd "$SITE"
if [[ ! -d node_modules/vitepress ]]; then
  echo "正在安装说明站依赖…"
  npm install
fi

echo "正在构建说明站…"
npm run docs:build

if [[ ! -f "$DIST/index.html" ]]; then
  echo "构建产物不存在: $DIST"
  exit 1
fi

echo "同步到 ${HOST}:${DEST}"
ssh "$HOST" "mkdir -p '$DEST'"
# 只替换这个目录里的站点文件，不动同级的 ios。
rsync -avz --delete "$DIST/" "${HOST}:${DEST}/"

echo "已更新 https://kylebing.cn/wubi/macos/"
