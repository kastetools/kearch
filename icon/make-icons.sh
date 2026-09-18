#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "==> 渲染 appicon.png (1024)"
swift GenerateAppIcon.swift

echo "==> 生成 iconset"
ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"; mkdir "$ICONSET"
for sz in 16 32 128 256 512; do
    sips -z "$sz" "$sz" appicon.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
    d=$((sz * 2))
    sips -z "$d" "$d" appicon.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done

echo "==> iconutil 打包 AppIcon.icns"
iconutil -c icns "$ICONSET" -o AppIcon.icns
rm -rf "$ICONSET"

echo "==> 生成 README 用 logo (../assets/logo.png, 256)"
mkdir -p ../assets
sips -z 256 256 appicon.png --out ../assets/logo.png >/dev/null

echo "==> done: icon/AppIcon.icns, assets/logo.png"
