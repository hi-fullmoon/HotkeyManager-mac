#!/usr/bin/env bash
# 构建可发布的 macOS ZIP 与 SHA-256 校验文件。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
ARTIFACT_VERSION="${ARTIFACT_VERSION:-$VERSION}"
ARCHS="${ARCHS:-arm64 x86_64}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"

if [[ ! "$ARTIFACT_VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]*$ ]]; then
    echo "错误：ARTIFACT_VERSION 包含不安全的文件名字符：$ARTIFACT_VERSION" >&2
    exit 1
fi

read -r -a architectures <<< "$ARCHS"
if (( ${#architectures[@]} == 2 )) \
    && [[ " ${architectures[*]} " == *" arm64 "* ]] \
    && [[ " ${architectures[*]} " == *" x86_64 "* ]]; then
    architecture_label="universal"
elif (( ${#architectures[@]} == 1 )); then
    architecture_label="${architectures[0]}"
else
    architecture_label="multiarch"
fi

mkdir -p "$DIST_DIR"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hotkeymanager-package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

OUTPUT_DIR="$STAGING_DIR" \
VERSION="$VERSION" \
ARCHS="$ARCHS" \
"$ROOT_DIR/build.sh"

zip_name="HotkeyManager-$ARTIFACT_VERSION-macOS-$architecture_label.zip"
zip_path="$DIST_DIR/$zip_name"
checksum_path="$zip_path.sha256"
rm -f "$zip_path" "$checksum_path"

echo "==> 打包 $zip_name..."
ditto -c -k --sequesterRsrc --keepParent \
    "$STAGING_DIR/HotkeyManager.app" \
    "$zip_path"

(
    cd "$DIST_DIR"
    shasum -a 256 "$zip_name" > "$zip_name.sha256"
)

echo "==> 发布产物：$zip_path"
echo "==> 校验文件：$checksum_path"
