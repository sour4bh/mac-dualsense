#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT_DIR/docs/assets"
CONFIGURATION=debug "$ROOT_DIR/native/scripts/build_app.sh"
mkdir -p "$OUTPUT"
rm -f "$OUTPUT/capture.txt"
open -n "$ROOT_DIR/native/dist/mac-dualsense.app" --args --capture-demo "$OUTPUT"
for ((ATTEMPT=0; ATTEMPT<40; ATTEMPT++)); do
  [[ -f "$OUTPUT/capture.txt" ]] && break
  sleep 1
done
[[ -f "$OUTPUT/capture.txt" ]] || { echo "Capture did not finish. Check ~/Library/Logs/mac-dualsense.log" >&2; exit 1; }
if command -v magick >/dev/null; then
  magick -delay 180 "$OUTPUT/controller-light.png" "$OUTPUT/binding-light.png" "$OUTPUT/apps-light.png" "$OUTPUT/profiles-light.png" -resize 960x624 -loop 0 "$OUTPUT/demo.gif"
fi
echo "Screenshots: $OUTPUT"
