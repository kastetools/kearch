#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Kearch"
BUNDLE="${APP_NAME}.app"
VERSION="${VERSION:-0.1.0}"     # 由 CI 从 tag 注入;本地默认 0.1.0
BUILD="${BUILD:-1}"

echo "==> swift build (${CONFIG})"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "error: built binary not found at ${BIN_PATH}" >&2
    exit 1
fi

# 图标缺失则自动生成(iconutil/sips/swift 均为 macOS 自带)。
if [[ ! -f icon/AppIcon.icns ]]; then
    echo "==> 生成图标 (icon/make-icons.sh)"
    ( cd icon && ./make-icons.sh )
fi

echo "==> assembling ${BUNDLE} (v${VERSION})"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "${BIN_PATH}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${BUNDLE}/Contents/MacOS/${APP_NAME}"

# 注入版本号
sed -e "s/__VERSION__/${VERSION}/g" -e "s/__BUILD__/${BUILD}/g" \
    Info.plist > "${BUNDLE}/Contents/Info.plist"

cp icon/AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "${BUNDLE}" 2>/dev/null || echo "   (codesign skipped)"

echo "==> done: ${BUNDLE}"
echo "    run: open ${BUNDLE}"
