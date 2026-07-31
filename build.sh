#!/bin/bash
# HotkeyManager 一键构建脚本：编译 Release 版 → 组装 HotkeyManager.app → ad-hoc 签名
set -e

cd "$(dirname "$0")"

echo "==> 编译中..."
swift build -c release

APP="HotkeyManager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/HotkeyManager "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

echo "==> ad-hoc 签名（稳定 TCC 授权记录）..."
codesign --force --sign - "$APP"

echo ""
echo "==> 构建完成：$(pwd)/$APP"
echo "==> 运行方式：open $APP"
echo "==> 配置文件：~/.hotkeymanager.json（首启自动创建）"
echo "==> 使用 minimize 模式需在 系统设置 → 隐私与安全性 → 辅助功能 中授权"
