#!/bin/zsh
# 构建 Go2Term.app（arm64 原生）
set -e
cd "$(dirname "$0")"

IDENTITY="Developer ID Application: Manku LLC (8KT244CY2B)"
APP=build/Go2Term.app

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译 (arm64)"
swiftc -O -target arm64-apple-macos12.0 Sources/main.swift -o "$APP/Contents/MacOS/Go2Term"

echo "==> 生成图标"
swift make_icon.swift
iconutil -c icns AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf AppIcon.iconset

cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

echo "==> 签名"
codesign --force --options runtime --timestamp \
    --entitlements entitlements.plist \
    --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "==> 完成: $APP"
