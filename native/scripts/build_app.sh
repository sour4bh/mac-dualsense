#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_BUNDLE="${ROOT_DIR}/dist/mac-dualsense.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

swift build -c "$CONFIGURATION" --arch arm64 --package-path "$ROOT_DIR" --disable-automatic-resolution
BIN_DIR="$(swift build -c "$CONFIGURATION" --arch arm64 --package-path "$ROOT_DIR" --show-bin-path)"
RESOURCE_BUNDLE="${BIN_DIR}/MacDualSense_MacDualSense.bundle"
[[ -x "$BIN_DIR/MacDualSense" && -d "$RESOURCE_BUNDLE" ]] || { echo "Missing executable or resource bundle" >&2; exit 1; }

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$ROOT_DIR/AppBundle/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/../LICENSE" "$APP_BUNDLE/Contents/Resources/LICENSE.txt"
cp "$ROOT_DIR/../docs/third-party-notices.txt" "$APP_BUNDLE/Contents/Resources/ThirdPartyNotices.txt"
cp "$BIN_DIR/MacDualSense" "$APP_BUNDLE/Contents/MacOS/"
ditto "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/$(basename "$RESOURCE_BUNDLE")"

ICONSET="$ROOT_DIR/dist/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$ROOT_DIR/AppBundle/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$ROOT_DIR/AppBundle/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
if [[ -n "${APP_VERSION:-}" ]]; then
  [[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "APP_VERSION must be X.Y.Z" >&2; exit 1; }
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_BUNDLE/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$APP_BUNDLE/Contents/Info.plist"
fi
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP_BUNDLE"
else
  [[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] || { echo "Distribution requires a Developer ID Application identity" >&2; exit 1; }
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"
echo "Built: $APP_BUNDLE"
