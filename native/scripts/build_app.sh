#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CC Controller Native"
APP_BUNDLE="${ROOT_DIR}/dist/${APP_NAME}.app"

swift build -c release --package-path "${ROOT_DIR}" >/dev/null
BIN_DIR="$(swift build -c release --package-path "${ROOT_DIR}" --show-bin-path)"
BIN_PATH="${BIN_DIR}/CCControllerNative"
RES_BUNDLE="${BIN_DIR}/CCControllerNative_CCControllerNative.bundle"

if [[ ! -f "${BIN_PATH}" ]]; then
  echo "Missing built binary: ${BIN_PATH}" >&2
  exit 1
fi

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${ROOT_DIR}/AppBundle/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/CCControllerNative"

if [[ -d "${RES_BUNDLE}" ]]; then
  cp -R "${RES_BUNDLE}" "${APP_BUNDLE}/Contents/Resources/"
fi

codesign -s - --force --deep "${APP_BUNDLE}" >/dev/null 2>&1 || true

echo "Built: ${APP_BUNDLE}"
