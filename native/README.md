# CC Controller (Native Swift rewrite)

This folder contains the native SwiftUI + GameController implementation intended for easier distribution (no Homebrew `hidapi` dependency).

## Build & Run

- Build (debug): `swift build --package-path native`
- Run from Xcode: open `native/Package.swift` in Xcode and press Run, or run the built binary from `native/.build/.../debug/CCControllerNative`.

## Create a `.app` and Install

- Build an app bundle: `native/scripts/build_app.sh`
- Install to `/Applications` and launch: `native/scripts/install_app.sh`

## Configuration

- User config path: `~/Library/Application Support/cc-controller/mappings.yaml`
- First run will seed the file from `native/Sources/CCControllerNative/Resources/mappings.yaml` if missing.
  - Includes per-app contexts (Warp/Arc/Chrome/Slack/ChatGPT/Claude) and haptics patterns.

## Permissions

CC Controller injects keystrokes via `CGEvent` and requires:

- System Settings → Privacy & Security → Accessibility → enable **CC Controller Native**
