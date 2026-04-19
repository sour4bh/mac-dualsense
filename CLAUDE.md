# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

mac-dualsense is a native macOS menu bar app (SwiftUI + GameController framework) that maps game controller inputs (DualSense / Pro Controller) to keyboard shortcuts with per-app contexts and profiles.

## Commands

```bash
# Build (debug)
swift build --package-path native

# Build app bundle
native/scripts/build_app.sh

# Install to /Applications and launch
native/scripts/install_app.sh

# Open in Xcode
open native/Package.swift
```

## Architecture

### Event Flow

```
GCController → button handler → canonicalButton() → ConfigStore.resolve(button) → KeySender
                                                            ↑
                                                    AppFocus.context() (bundle ID → context name)
```

### Key Files (`native/Sources/MacDualSense/`)

- `MacDualSenseApp.swift` — SwiftUI app entry, menu bar setup
- `ControllerManager.swift` — GameController framework integration; `canonicalButton()` maps GCInput names to config button names; handles button press/release events and dispatches actions
- `ConfigStore.swift` — YAML config loading/saving via Yams; `resolve(button:)` returns action based on current app context and active profile
- `KeySender.swift` — CGEvent keystroke injection; `sendKeystroke()`, `setModifier()`, `toggleModifier()`, `holdModifier()`
- `AppFocus.swift` — Frontmost app detection via NSWorkspace; `contexts` dict maps bundle IDs to context names
- `ControllerHaptics.swift` — Haptic feedback patterns
- `Models.swift` — Codable structs for YAML config (`CCConfig`, `CCActionDef`, etc.)
- `PreferencesView.swift` — Settings UI for profiles, mappings, controller selection

### Config (`~/Library/Application Support/mac-dualsense/mappings.yaml`)

Seeded on first run from `native/Sources/MacDualSense/Resources/mappings.yaml`.

Structure:
- `settings.controller.preferred` — `auto`, `dualsense`, or `pro_controller`
- `settings.wispr.mode` — whisper activation: `rcmd_hold`, `lcmd_hold`, `fn_hold` (hold while pressed); `rcmd_pulse`, `lcmd_pulse` (tap for duration); `rcmd_toggle`, `lcmd_toggle` (toggle on/off); `cmd_right` (Cmd+Right keystroke)
- `profiles.active` — active profile name
- `profiles.items.<profile>.mappings.<context>.<button>` — action definitions
- `haptics.enabled`, `haptics.patterns.<name>` — haptic feedback config

Button names: `dpad_up`, `dpad_down`, `dpad_left`, `dpad_right`, `cross`, `circle`, `triangle`, `square`, `l1`, `r1`, `l2`, `r2`, `l3`, `r3`, `ps`, `options`, `share`, `touchpad`

Context names: `warp`, `arc`, `chrome`, `slack`, `chatgpt`, `claude`, `default`

## Key Patterns

- **Adding a new app context**: Add bundle ID → context mapping to `contexts` dict in `AppFocus.swift`, add context to `knownContexts` in `ConfigStore.swift`, then add mappings under `profiles.items.<profile>.mappings.<context>` in `mappings.yaml`
- **Adding a new key**: Add case to `keyCode(for:)` in `KeySender.swift`
- **Adding a new wispr mode**: Add case to `handleWispr()` in `ControllerManager.swift`

## Testing

No formal test suite. Validate changes by building and running the app, connecting a controller, and confirming button events trigger expected keystrokes.

## Style

- Swift: SwiftUI conventions; types `UpperCamelCase`, members `lowerCamelCase`
- Prefer `@MainActor` for UI-bound classes
- Use Yams for YAML encode/decode

## Permissions

Requires macOS Accessibility permission: System Settings → Privacy & Security → Accessibility → enable **mac-dualsense**
