# Repository Guidelines

CC Controller maps game-controller inputs (DualSense / Pro Controller) to macOS keyboard shortcuts, with per-app contexts and profiles. This repo contains a Python implementation and a native Swift menu bar app; both use the same YAML config file.

## Project Structure & Module Organization

- `cc_controller/`: Python daemon + PyObjC UI.
  - `daemon.py`: entry point (`cc-controller`) and main loop.
  - `app_focus.py`: frontmost-app detection and context mapping by bundle ID.
  - `mapper.py`: resolves `button -> Action` using YAML mappings.
  - `keyboard.py`: Quartz keystroke injection (requires Accessibility permission).
  - `controllers/` + `haptics/`: device-specific integrations.
  - `ui/`: status bar app + preferences window.
- `native/`: SwiftUI + `GameController` app.
  - `Sources/CCControllerNative/`: menu bar app, preferences, YAML editor, live input.
  - `scripts/`: `build_app.sh`, `install_app.sh`.
- `config/mappings.yaml`: bundled defaults (copied on first run to `~/Library/Application Support/cc-controller/mappings.yaml`).
- Packaging/ops: `setup_app.py` (py2app), `cc_controller.spec` (PyInstaller), `com.sour4bh.cc-controller.plist` (launchd).

## Build, Test, and Development Commands

- Create a venv + install dev deps: `python -m venv venv && source venv/bin/activate && python -m pip install -e ".[dev]"`.
- Run daemon: `python -m cc_controller.daemon` (logs to `~/Library/Logs/cc-controller.log`) or `cc-controller` after install.
- Run UI: `python -m cc_controller.ui` or `cc-controller-ui`.
- Lint/format: `ruff check .` and `ruff format .`.
- Swift build: `swift build --package-path native` (or open `native/Package.swift` in Xcode).
- Native app bundle + install: `native/scripts/install_app.sh` (installs to `/Applications`).
- Optional app builds (requires extra tools): `python setup_app.py py2app` or `pyinstaller cc_controller.spec`.

## Coding Style & Naming Conventions

- Python ≥3.10, 4-space indentation, type hints encouraged.
- Swift: SwiftUI conventions; types `UpperCamelCase`, members `lowerCamelCase`.
- Names: modules/functions `snake_case`, classes `PascalCase`, constants `UPPER_SNAKE_CASE`.
- `config/mappings.yaml` conventions:
  - Buttons use canonical names (e.g., `dpad_up`, `l1`, `cross`).
  - Context keys match `cc_controller/app_focus.py` (e.g., `warp`, `arc`, `chrome`).

## Testing Guidelines

- No formal test suite yet. Validate changes by running the native app or daemon and confirming live events + expected key output.
- If adding pure logic, add `pytest` tests under `tests/` and name files `test_*.py`.

## Commit & Pull Request Guidelines

- Prefer short, imperative subjects; conventional prefixes are welcome (`feat:`, `fix:`) as used in history.
- PRs should include: what changed, how you tested on macOS (controller + target app), and any updates to `config/mappings.yaml` or bundle IDs in `cc_controller/app_focus.py`.

## Security & Configuration Notes

- This project injects keystrokes; be cautious with new mappings and verify Accessibility permissions in macOS settings.
