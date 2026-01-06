# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

CC Controller maps game-controller inputs (DualSense / Pro Controller) to macOS keyboard shortcuts with per-app contexts and profiles. Two implementations: Python daemon (PyObjC) and native Swift menu bar app—both share the same YAML config format.

## Commands

```bash
# Setup
python -m venv venv && source venv/bin/activate && python -m pip install -e ".[dev]"

# Run daemon
python -m cc_controller.daemon   # logs to ~/Library/Logs/cc-controller.log
# or after install: cc-controller

# Run UI
python -m cc_controller.ui
# or after install: cc-controller-ui

# Lint
ruff check . && ruff format .

# Swift build
swift build --package-path native
# or open native/Package.swift in Xcode

# Install native app to /Applications
native/scripts/install_app.sh

# Optional packaging (requires extra tools)
python setup_app.py py2app
pyinstaller cc_controller.spec
```

## Architecture

### Python (`cc_controller/`)

- `daemon.py` — entry point; `CCControllerDaemon` runs the main loop coordinating controller polling, app focus detection, and keystroke injection
- `detector.py` — auto-detects connected controllers; returns first working `BaseController`
- `controllers/base.py` — abstract `BaseController` with `poll_loop()`, `get_events()`, `trigger_haptic()`
- `controllers/dualsense.py`, `pro_controller.py` — device-specific implementations
- `mapper.py` — `Mapper.resolve(button)` returns `Action` (keystroke/wispr/noop) based on current app context and active profile
- `app_focus.py` — `AppFocus` detects frontmost app via NSWorkspace; `APP_CONTEXTS` dict maps bundle IDs to context names
- `keyboard.py` — Quartz `CGEvent` keystroke injection; `send_keystroke()`, `set_modifier()`, `trigger_wispr()`
- `haptics/` — controller-specific haptic feedback patterns
- `ui/` — PyObjC status bar app

### Native Swift (`native/`)

- `Sources/CCControllerNative/` — menu bar app, preferences, YAML editor, live input
- `scripts/` — `build_app.sh`, `install_app.sh`

Key files:
- `CCControllerNativeApp.swift` — SwiftUI app entry, menu bar
- `ControllerManager.swift` — GameController framework integration
- `ConfigStore.swift` — YAML config loading via Yams
- `KeySender.swift` — CGEvent keystroke injection
- `AppFocus.swift` — frontmost app detection

### Packaging

- `setup_app.py` — py2app config
- `cc_controller.spec` — PyInstaller spec
- `com.sour4bh.cc-controller.plist` — launchd service

### Config (`config/mappings.yaml`)

Copied on first run to `~/Library/Application Support/cc-controller/mappings.yaml`.

Structure:
- `settings.controller.preferred` — `auto`, `dualsense`, or `pro_controller`
- `settings.wispr.mode` — whisper activation mode (`rcmd_hold`, `lcmd_pulse`, etc.)
- `profiles.active` — active profile name
- `profiles.items.<profile>.mappings.<context>.<button>` — action definitions

Button names: `dpad_up`, `cross`, `circle`, `triangle`, `square`, `l1`, `r1`, `l2`, `r2`, `l3`, `r3`, `ps`, `options`, `share`, `touchpad`

Context names match keys in `APP_CONTEXTS` (`app_focus.py`): `warp`, `arc`, `chrome`, `slack`, `chatgpt`, `claude`, `default`

## Key Patterns

- Adding a new app context: add bundle ID mapping to `APP_CONTEXTS` in `app_focus.py`, then add context key under `profiles.items.<profile>.mappings` in `mappings.yaml`
- Adding a new controller: subclass `BaseController`, implement required methods, add to `CONTROLLER_CLASSES` in `detector.py`

## Testing

No formal test suite yet. Validate changes by running the native app or daemon and confirming live events + expected key output. If adding pure logic, add pytest tests under `tests/` named `test_*.py`.

## Style

- Python ≥3.10, type hints encouraged
- Swift: SwiftUI conventions; types `UpperCamelCase`, members `lowerCamelCase`
- Names: modules/functions `snake_case`, classes `PascalCase`, constants `UPPER_SNAKE_CASE`

## Commits

Prefer short, imperative subjects with conventional prefixes (`feat:`, `fix:`). PRs should note what changed, how tested on macOS, and any updates to `mappings.yaml` or bundle IDs.

## Permissions

Requires macOS Accessibility permission: System Settings → Privacy & Security → Accessibility
