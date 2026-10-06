#!/usr/bin/env bash
# 爱快 iKuai 4 应用市场 ipkg 打包脚本
#
# 用法: bash packaging/ikuai-ipkg/build-ipkg.sh [amd64|arm64] [版本号X.Y.Z]
#   - 需要先执行 `pnpm run build` 生成 dist/
#   - 版本号缺省时读取 package.json
# 输出: release/network-panel-ikuai-<arch>.ipkg
#
# ipkg 本质是 tar.gz：<name>/manifest.json + app/docker-compose.yaml + docker_image.tar.gz 等，
# 爱快通过 docker load 导入镜像后用 docker-compose 启动。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_NAME="network-panel"
IMAGE_TAG="network-panel:ikuai"
TEMPLATE_DIR="$SCRIPT_DIR/$APP_NAME"

ARCH="${1:-amd64}"
case "$ARCH" in
  amd64|x86_64) ARCH=amd64; LABEL=x86_64 ;;
  arm64|aarch64) ARCH=arm64; LABEL=arm64 ;;
  *) echo "Unsupported arch: $ARCH (amd64|arm64)" >&2; exit 1 ;;
esac

RAW_VERSION="${2:-$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$PROJECT_DIR/package.json" | head -1)}"
RAW_VERSION="${RAW_VERSION#v}"
if [[ "$RAW_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+) ]]; then
  VERSION="${BASH_REMATCH[1]}"
else
  echo "Invalid ipkg version: $RAW_VERSION (need X.Y.Z)" >&2
  exit 1
fi

[ -f "$PROJECT_DIR/dist/index.html" ] || { echo "dist/ not found, run 'pnpm run build' first" >&2; exit 1; }

STAGE_DIR="$PROJECT_DIR/.ipkg-stage-$ARCH"
PKG_STAGE="$STAGE_DIR/package/$APP_NAME"
OUT_DIR="$PROJECT_DIR/release"
OUT_FILE="$OUT_DIR/$APP_NAME-ikuai-$LABEL.ipkg"

echo "=== 构建 $APP_NAME v$VERSION ipkg ($LABEL) ==="
rm -rf "$STAGE_DIR"
mkdir -p "$PKG_STAGE/log" "$OUT_DIR"
cp -R "$TEMPLATE_DIR/." "$PKG_STAGE/"
rm -f "$PKG_STAGE/manifest.template.json"
: > "$PKG_STAGE/log/install.log"
: > "$PKG_STAGE/log/run.log"
sed "s/__IPKG_VERSION__/$VERSION/g" "$TEMPLATE_DIR/manifest.template.json" > "$PKG_STAGE/manifest.json"
python3 -m json.tool "$PKG_STAGE/manifest.json" >/dev/null

# 构建目标架构镜像（复用根目录 Dockerfile），amd64 用经典 builder 以兼容爱快较老的 docker
cd "$PROJECT_DIR"
if [ "$ARCH" = amd64 ] && [ "$(uname -m)" = x86_64 ]; then
  docker pull --platform linux/amd64 nginx:stable-alpine
  DOCKER_BUILDKIT=0 docker build -t "$IMAGE_TAG" .
else
  docker buildx build --platform "linux/$ARCH" --load -t "$IMAGE_TAG" .
fi

docker save "$IMAGE_TAG" | gzip > "$PKG_STAGE/docker_image.tar.gz"
tar -czf "$OUT_FILE" -C "$STAGE_DIR/package" "$APP_NAME/"
rm -rf "$STAGE_DIR"

echo "输出: $OUT_FILE ($(du -h "$OUT_FILE" | cut -f1))"
echo "安装: 爱快 Web → 应用工具 → 应用管理 → 应用市场 → 本地安装"
