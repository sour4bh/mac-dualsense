# Repository Guidelines

CC Controller maps game-controller inputs (DualSense / Pro Controller) to macOS keyboard shortcuts, with per-app contexts and profiles. This repo is a native Swift menu bar app that uses a YAML config file.

## Project Structure & Module Organization

- `native/`: SwiftUI + `GameController` app.
  - `Sources/CCControllerNative/`: menu bar app, preferences, YAML editor, live input.
  - `scripts/`: `build_app.sh`, `install_app.sh`.
- Default config: `native/Sources/CCControllerNative/Resources/mappings.yaml` (seeded on first run to `~/Library/Application Support/cc-controller/mappings.yaml`).

## Build, Test, and Development Commands

- Swift build: `swift build --package-path native` (or open `native/Package.swift` in Xcode).
- Native app bundle + install: `native/scripts/install_app.sh` (installs to `/Applications`).

## Coding Style & Naming Conventions

- Swift: SwiftUI conventions; types `UpperCamelCase`, members `lowerCamelCase`.
- Names: modules/functions `snake_case`, classes `PascalCase`, constants `UPPER_SNAKE_CASE`.
- `mappings.yaml` conventions:
  - Buttons use canonical names (e.g., `dpad_up`, `l1`, `cross`).
  - Context keys match `native/Sources/CCControllerNative/AppFocus.swift` (e.g., `warp`, `arc`, `chrome`).

## Testing Guidelines

- No formal test suite yet. Validate changes by running the native app and confirming live button events + expected key output.

## Commit & Pull Request Guidelines

- Prefer short, imperative subjects; conventional prefixes are welcome (`feat:`, `fix:`) as used in history.
- PRs should include: what changed, how you tested on macOS (controller + target app), and any updates to `native/Sources/CCControllerNative/Resources/mappings.yaml` or bundle IDs in `native/Sources/CCControllerNative/AppFocus.swift`.

## Security & Configuration Notes

- This project injects keystrokes; be cautious with new mappings and verify Accessibility permissions in macOS settings.
