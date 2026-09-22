# AGENTS.md

Instructions for coding agents working in this repository.

## Overview

mac-dualsense is a native macOS menu bar app (SwiftUI + GameController framework) that maps game controller inputs (DualSense / Pro Controller) to keyboard shortcuts with per-app contexts and profiles.

## Commands

```bash
# Build (debug)
swift build --package-path native

# Build app bundle
native/scripts/build_app.sh

# Build locally and launch
make run

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
- `MouseSender.swift` — CGEvent mouse injection for trackpad mode; `moveCursor()`, `setLeftButton()`, `setRightButton()`, `scroll()`, `releaseAllButtons()`
- `AppFocus.swift` — Frontmost app detection via an injectable provider; routes using the config-owned context registry
- `InputRouter.swift` — Held-key lifecycle and cancellable dictation pulses; injectable keyboard output
- `ControllerHaptics.swift` — Haptic feedback patterns
- `Models.swift` — Codable structs for YAML config (`Config`, `ActionDef`, `ProfileItem`, `TrackpadSettings`, etc.)
- `Views/` — workspace sections and native Settings; `WorkspaceSelection.swift` shares editor selection

### Config (`~/Library/Application Support/mac-dualsense/mappings.yaml`)

Seeded on first run from `native/Sources/MacDualSense/Resources/mappings.yaml`.

Structure:
- `settings.controller.preferred` — `auto`, `dualsense`, or `pro_controller`
- `settings.wispr.mode` — whisper activation: `rcmd_hold`, `lcmd_hold`, `fn_hold` (hold while pressed); `rcmd_pulse`, `lcmd_pulse` (tap for duration); `rcmd_toggle`, `lcmd_toggle` (toggle on/off); `cmd_right` (Cmd+Right keystroke)
- `settings.trackpad.*` — trackpad-mode tunables: `cursor_sensitivity` (default 900 px/unit), `scroll_sensitivity` (40 px/unit), `natural_scroll` (true), `right_click_modifier` (canonical button name held during click; default `l2`, empty string disables)
- `profiles.active` — active profile name
- `profiles.items.<profile>.mappings.<context>.<button>` — action definitions
- `profiles.items.<profile>.trackpad_mode` — when true, DualSense touchpad acts as trackpad (cursor, two-finger scroll, click = mouse button) and the `touchpad` keystroke binding is ignored
- `haptics.enabled`, `haptics.patterns.<name>` — haptic feedback config

Optional `contexts.<id>` entries contain `name` and `bundle_ids`. Missing registry uses built-in defaults; an explicit empty registry is authoritative.

Button names: `dpad_up`, `dpad_down`, `dpad_left`, `dpad_right`, `cross`, `circle`, `triangle`, `square`, `l1`, `r1`, `l2`, `r2`, `l3`, `r3`, `ps`, `options`, `share`, `touchpad`

Context names: `warp`, `arc`, `chrome`, `slack`, `chatgpt`, `claude`, `default`

## Key Patterns

- **Adding a new app context**: Use Apps in the UI or the optional top-level `contexts` registry in YAML (`name`, `bundle_ids`). Associations are shared across profiles; preserve stable context IDs and existing mapping blocks. Duplicate bundle IDs are rejected.
- **Adding a new key**: Add case to `keyCode(for:)` in `KeySender.swift`
- **Adding a new wispr mode**: Update `InputRouter`, Settings, and lifecycle tests.
- **Wiring DualSense-specific inputs**: inside `ControllerManager.attachHandlers()`, cast `profile as? GCDualSenseGamepad` and attach handlers; bridge to config via a `ControllerManager` closure property + `ConfigStore` accessor + wiring in `AppState.init` (mirrors the `trackpadEnabled` / `wisprMode` pattern)
- **Hopping off-main work back to `@MainActor`**: use `DispatchWorkItem { MainActor.assumeIsolated { … } }` dispatched via `DispatchQueue.main.asyncAfter`, or set the `DispatchSource` queue to `DispatchQueue.main`. Do not use `Task { @MainActor in … }` from a `@Sendable` closure that captures a MainActor-isolated `self` — Swift 6 emits an isolation fence at the top of the outer closure and traps on non-main queues (`_swift_task_checkIsolatedSwift` → `dispatch_assert_queue_fail`). See `ConfigStore.autosave`, `startWatchingConfig`, `scheduleReloadFromDisk`.

## TODO

- Complete hardware and notarized-download checks in `docs/validation.md` before publishing the first signed release.

## Testing

Run `swift test --package-path native` for isolated configuration and input tests, `make verify` for app packaging, and `make docs` for documentation links. Validate controller behavior separately on hardware; report unperformed checks. `make capture` generates real UI captures using a debug-only isolated configuration.

## Style

- Swift: SwiftUI conventions; types `UpperCamelCase`, members `lowerCamelCase`
- Prefer `@MainActor` for UI-bound classes
- Use Yams for YAML encode/decode

## Permissions

Requires macOS Accessibility permission: System Settings → Privacy & Security → Accessibility → enable **mac-dualsense**

This app injects keystrokes, so verify Accessibility permission is granted and be deliberate about new mappings.

## Commits & Pull Requests

- Short, imperative subjects; conventional prefixes (`feat:`, `fix:`) are welcome, as used in history.
- A PR states what changed, how it was tested on macOS (controller plus target app), and any updates to `native/Sources/MacDualSense/Resources/mappings.yaml` or context associations.

