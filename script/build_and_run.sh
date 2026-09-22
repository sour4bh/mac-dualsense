#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
case "$MODE" in run|--verify|--logs|--telemetry|--debug) ;; *) echo "Usage: $0 [run|--verify|--logs|--telemetry|--debug]" >&2; exit 2 ;; esac
pkill -x MacDualSense 2>/dev/null || true
CONFIGURATION=debug "$ROOT_DIR/native/scripts/build_app.sh"
APP="$ROOT_DIR/native/dist/mac-dualsense.app"
if [[ "$MODE" == --debug ]]; then
  lldb -- "$APP/Contents/MacOS/MacDualSense"
else
  open -n "$APP"
  case "$MODE" in
    --verify) sleep 2; pgrep -x MacDualSense >/dev/null ;;
    --logs) log stream --info --style compact --predicate 'process == "MacDualSense"' ;;
    --telemetry) log stream --info --style compact --predicate 'subsystem == "com.sour4bh.mac-dualsense"' ;;
  esac
fi
