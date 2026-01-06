#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${ROOT_DIR}/scripts/build_app.sh"

APP_NAME="CC Controller Native"
SRC_APP="${ROOT_DIR}/dist/${APP_NAME}.app"
DST_APP="/Applications/${APP_NAME}.app"

rm -rf "${DST_APP}"
ditto "${SRC_APP}" "${DST_APP}"

echo "Installed: ${DST_APP}"
open "${DST_APP}"

