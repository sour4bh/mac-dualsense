#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${APP_VERSION:?Set APP_VERSION to X.Y.Z}"
: "${SIGNING_IDENTITY:?Set a Developer ID Application identity}"
: "${NOTARY_PROFILE:?Store notarization credentials in a keychain profile first}"
[[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] || { echo "Refusing unsigned distribution" >&2; exit 1; }
export CONFIGURATION=release
"$ROOT_DIR/scripts/build_app.sh"
APP="$ROOT_DIR/dist/mac-dualsense.app"
ZIP="$ROOT_DIR/dist/mac-dualsense-${APP_VERSION}-arm64.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN"); fi
xcrun notarytool submit "$ZIP" "${NOTARY_ARGS[@]}" --wait --output-format json > "$ROOT_DIR/dist/notarization.json"
/usr/bin/plutil -extract status raw "$ROOT_DIR/dist/notarization.json" | /usr/bin/grep -qx Accepted
xcrun stapler staple "$APP"
"$ROOT_DIR/scripts/verify_app.sh" "$APP" --distribution
ditto -c -k --keepParent "$APP" "$ZIP"
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$ZIP" "$VERIFY_DIR"
"$ROOT_DIR/scripts/verify_app.sh" "$VERIFY_DIR/mac-dualsense.app" --distribution
(cd "$ROOT_DIR/dist" && shasum -a 256 "$(basename "$ZIP")" > SHA256SUMS)
echo "Distribution ready: $ZIP"
