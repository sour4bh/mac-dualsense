#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT_DIR/scripts/build_app.sh"
APP="$ROOT_DIR/dist/mac-dualsense.app"
DESTINATION="${INSTALL_DIR:-/Applications}/mac-dualsense.app"
pkill -x MacDualSense 2>/dev/null || true
rm -rf "$DESTINATION"
ditto "$APP" "$DESTINATION"
echo "Installed: $DESTINATION"
