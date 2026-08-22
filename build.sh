#!/usr/bin/env bash
# HotkeyManager 构建脚本：编译 → 组装 .app → 签名。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="HotkeyManager"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/.build/architectures}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-13.0}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")}"

read -r -a ARCHITECTURES <<< "${ARCHS:-$(uname -m)}"

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
    echo "错误：CONFIGURATION 只能是 debug 或 release" >&2
    exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "错误：VERSION 必须是 X.Y.Z 格式，当前值为 $VERSION" >&2
    exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "错误：BUILD_NUMBER 必须是非负整数，当前值为 $BUILD_NUMBER" >&2
    exit 1
fi

if (( ${#ARCHITECTURES[@]} == 0 )); then
    echo "错误：ARCHS 不能为空" >&2
    exit 1
fi

for arch in "${ARCHITECTURES[@]}"; do
    if [[ "$arch" != "arm64" && "$arch" != "x86_64" ]]; then
        echo "错误：不支持的架构 $arch（仅支持 arm64 和 x86_64）" >&2
        exit 1
    fi
done

mkdir -p "$OUTPUT_DIR"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

BINARIES=()
for arch in "${ARCHITECTURES[@]}"; do
    echo "==> 编译 $CONFIGURATION / $arch..."
    swift_args=(
        --package-path "$ROOT_DIR"
        --configuration "$CONFIGURATION"
        --scratch-path "$BUILD_ROOT/$arch"
        --triple "$arch-apple-macosx$MACOS_DEPLOYMENT_TARGET"
    )
    swift build "${swift_args[@]}"
    bin_dir="$(swift build "${swift_args[@]}" --show-bin-path)"
    BINARIES+=("$bin_dir/$APP_NAME")
done

if (( ${#BINARIES[@]} == 1 )); then
    cp "${BINARIES[0]}" "$APP_PATH/Contents/MacOS/$APP_NAME"
else
    echo "==> 合并 Universal 2 可执行文件..."
    lipo -create "${BINARIES[@]}" -output "$APP_PATH/Contents/MacOS/$APP_NAME"
fi

cp "$INFO_PLIST" "$APP_PATH/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"

if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
    echo "==> ad-hoc 签名（稳定 TCC 授权记录）..."
    codesign --force --sign - "$APP_PATH"
else
    echo "==> 使用身份签名：$CODE_SIGN_IDENTITY"
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP_PATH"
fi

plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP_PATH"

echo ""
echo "==> 构建完成：$APP_PATH"
echo "==> 版本：$VERSION ($BUILD_NUMBER)"
echo "==> 架构：$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")"
echo "==> 运行方式：open \"$APP_PATH\""
echo "==> 配置文件：~/.hotkeymanager.json（首启自动创建）"
