#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT_DIR/dist/mac-dualsense.app}"
PLIST="$APP/Contents/Info.plist"
plutil -lint "$PLIST"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")" == "26.0" ]]
[[ "$(lipo -archs "$APP/Contents/MacOS/MacDualSense")" == "arm64" ]]
[[ -s "$APP/Contents/Resources/AppIcon.icns" ]]
BUNDLE="$APP/Contents/Resources/MacDualSense_MacDualSense.bundle"
[[ -d "$BUNDLE" ]]
for RESOURCE in mappings.yaml DualSense_front.svg DualSense_back.svg; do
  [[ -f "$BUNDLE/$RESOURCE" || -f "$BUNDLE/Contents/Resources/$RESOURCE" ]] || { echo "Missing $RESOURCE" >&2; exit 1; }
done
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ "${2:-}" == "--distribution" ]]; then
  codesign --display --verbose=4 "$APP" 2>&1 | rg 'Authority=Developer ID Application:'
  codesign --display --verbose=4 "$APP" 2>&1 | rg 'flags=.*runtime'
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
fi
echo "App bundle verified."
