#!/usr/bin/env bash
set -euo pipefail

# 从 Git 跟踪的当前源码全新构建，避免本地旧 .app 中的残留资源进入发行包。
# 新增、移动或删除文件后，先 git add，再运行本脚本。
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p build/releases
WORK_DIR="$(mktemp -d "$ROOT_DIR/build/.release-work.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
SOURCE_DIR="$WORK_DIR/source"
mkdir -p "$SOURCE_DIR"

git ls-files -z > "$WORK_DIR/tracked-files"
while IFS= read -r -d '' source_file; do
    # 工作区中已删除的旧资源不再进入隔离源码目录。
    [ -f "$source_file" ] || continue
    mkdir -p "$SOURCE_DIR/$(dirname "$source_file")"
    ditto --norsrc --noextattr --noacl "$source_file" "$SOURCE_DIR/$source_file"
done < "$WORK_DIR/tracked-files"

PLIST="$SOURCE_DIR/resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo 'Info.plist 需要 x.y.z 格式的软件版本与整数构建号。' >&2
    exit 1
fi

echo "==> 全新构建 TeXMini ${VERSION}（构建 ${BUILD_NUMBER}）..."
(cd "$SOURCE_DIR" && ./build.sh)
APP_PATH="$SOURCE_DIR/build/TeXMini.app"
APP_PLIST="$APP_PATH/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")" = "$BUILD_NUMBER"
ARCH="$(lipo -archs "$APP_PATH/Contents/MacOS/TeXMini")"
case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "不支持的发行架构：$ARCH" >&2; exit 1 ;;
esac
test "$ARCH" = "$(uname -m)"
codesign --verify --deep --strict "$APP_PATH"

PACKAGE_NAME="TeXMini-$VERSION-macOS-$ARCH"
PACKAGE_DIR="$WORK_DIR/packages"
DMG_SOURCE="$WORK_DIR/dmg"
mkdir -p "$PACKAGE_DIR" "$DMG_SOURCE"
ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP_PATH" "$PACKAGE_DIR/$PACKAGE_NAME.zip"
ditto --norsrc --noextattr --noacl "$APP_PATH" "$DMG_SOURCE/TeXMini.app"
ln -s /Applications "$DMG_SOURCE/Applications"
hdiutil create -volname "TeXMini $VERSION" -srcfolder "$DMG_SOURCE" \
    -format UDZO "$PACKAGE_DIR/$PACKAGE_NAME.dmg"
hdiutil verify "$PACKAGE_DIR/$PACKAGE_NAME.dmg"

# 同时检查 ZIP 解压后的签名，确保可下载的压缩包完整。
ditto -x -k "$PACKAGE_DIR/$PACKAGE_NAME.zip" "$WORK_DIR/zip-check"
codesign --verify --deep --strict "$WORK_DIR/zip-check/TeXMini.app"
(cd "$PACKAGE_DIR" && shasum -a 256 "$PACKAGE_NAME.zip" "$PACKAGE_NAME.dmg" > SHA256SUMS.txt)
mv "$PACKAGE_DIR/$PACKAGE_NAME.zip" "$PACKAGE_DIR/$PACKAGE_NAME.dmg" \
    "$PACKAGE_DIR/SHA256SUMS.txt" "$ROOT_DIR/build/releases/"
echo "==> 发行包已生成：build/releases/$PACKAGE_NAME.{zip,dmg}"
echo "==> SHA-256 校验值：build/releases/SHA256SUMS.txt"
