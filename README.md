# mac-dualsense

**Your DualSense is a 18-button programmable keyboard for macOS.**

Navigate terminals, browsers, and AI chat apps from your couch — without touching the keyboard. Context-aware mappings, Wispr voice dictation on one button, haptic feedback, zero dependencies.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange) ![License: MIT](https://img.shields.io/badge/license-MIT-green) ![GameController](https://img.shields.io/badge/GameController-framework-purple)

---

<!-- Add a GIF here showing controller buttons triggering actions in Warp/Claude -->

## Why

You're on a call, reading docs, or chatting with an AI assistant. You keep reaching for the keyboard just to scroll, switch tabs, or trigger voice dictation. Your PS5 controller is sitting right there.

mac-dualsense maps every button to any keystroke, per app, with no drivers:

- **In Warp**: D-pad scrolls blocks, L1/R1 navigates tabs, Options runs the command
- **In Claude/ChatGPT**: Cross sends, Triangle triggers Wispr voice dictation, L1/R1 moves between chats
- **In Arc/Chrome**: Circle goes back, L1/R1 switches tabs, L3 focuses the URL bar
- **Everywhere**: D-pad = arrows, Cross = Return, Circle = Escape — the basics just work

Mappings switch automatically when you change the focused app.

## Install

### Download

1. Grab the latest `.zip` from [**Releases →**](../../releases/latest)
2. Drag **mac-dualsense.app** to `/Applications`
3. Launch — a controller icon appears in the menu bar
4. System Settings → Privacy & Security → Accessibility → enable **mac-dualsense**

> macOS Gatekeeper warning on first launch: right-click the app → Open → Open.

### Build from source

Requires Xcode 16+ / Swift 6.

```bash
git clone https://github.com/sour4bh/mac-dualsense.git
cd mac-dualsense
native/scripts/install_app.sh
```

This builds, installs to `/Applications`, and launches.

## Setup in 2 minutes

1. Connect your DualSense via USB or Bluetooth
2. Open the app — it auto-detects the controller
3. The default config works immediately (D-pad, face buttons, shoulder buttons all mapped)
4. Edit `~/Library/Application Support/mac-dualsense/mappings.yaml` to customize — the app hot-reloads on save

## Wispr voice dictation

Hold Triangle (or the PS button) to activate [Wispr Flow](https://wisprflow.ai/). Dictate, release, done. Eight trigger modes available:

| Mode | How it works |
|---|---|
| `rcmd_hold` | Holds right ⌘ while the button is pressed |
| `rcmd_toggle` | Toggles right ⌘ on/off with each press |
| `rcmd_pulse` | Taps right ⌘ for `hold_ms` then releases |
| `fn_hold` | Holds Fn while pressed |
| `cmd_right` | Sends Cmd+Right |

Set `settings.wispr.mode` in your config to switch modes.

## Features

- **Context-aware mappings** — different actions per frontmost app, with a global fallback
- **Profiles** — define multiple full mapping sets and switch between them
- **Haptic feedback** — configurable intensity/duration patterns on connect, action, and error
- **Visual controller map** — interactive button layout in Preferences, click to assign
- **Extended key support** — letters, digits, arrow/navigation keys, common punctuation, and `F1`-`F12`
- **Wispr activation modes** — hold, pulse, toggle, and `Cmd+Right` trigger options for dictation workflows
- **Multi-controller** — auto-detects DualSense or Pro Controller, or pin a preference
- **No runtime dependencies** — native GameController framework, no HID drivers, no Homebrew

## Supported controllers

| Controller | Connection |
|---|---|
| Sony DualSense (PS5) | USB / Bluetooth |
| Nintendo Switch Pro Controller | USB / Bluetooth |

## Default mappings

<details>
<summary>Global fallback (all apps)</summary>

| Button | Action |
|---|---|
| D-pad | Arrow keys |
| Cross (×) | Return |
| Circle (○) | Escape |
| Square (□) | Tab |
| Triangle (△) / PS | Wispr voice dictation |
| L1 / R1 | Cmd+Shift+[ / ] |
| L2 / R2 | Alt+↑ / Alt+↓ |
| L3 | Ctrl+C |
| R3 | Ctrl+D |

</details>

<details>
<summary>Per-app overrides (Warp, Arc, Chrome, Slack, ChatGPT, Claude)</summary>

Full bindings in [`native/Sources/MacDualSense/Resources/mappings.yaml`](native/Sources/MacDualSense/Resources/mappings.yaml).

</details>

## Configuration reference

Config lives at `~/Library/Application Support/mac-dualsense/mappings.yaml`, seeded from `native/Sources/MacDualSense/Resources/mappings.yaml` on first run.

<details>
<summary>Full config structure</summary>

```yaml
version: 2

settings:
  controller:
    preferred: auto          # auto | dualsense | pro_controller
  wispr:
    mode: rcmd_hold
    hold_ms: 450

profiles:
  active: default
  items:
    default:
      mappings:
        default:             # global fallback
          cross:
            type: keystroke
            key: return
          triangle:
            type: wispr
        warp:                # active when Warp is frontmost
          square:
            type: keystroke
            key: k
            modifiers: [cmd]

haptics:
  enabled: true
  patterns:
    confirm:
      intensity: 128
      duration_ms: 50
```

</details>

<details>
<summary>Button names</summary>

| Button | Name | | Button | Name |
|---|---|---|---|---|
| Cross (×) | `cross` | | L1 | `l1` |
| Circle (○) | `circle` | | R1 | `r1` |
| Triangle (△) | `triangle` | | L2 | `l2` |
| Square (□) | `square` | | R2 | `r2` |
| D-pad up | `dpad_up` | | L3 (click) | `l3` |
| D-pad down | `dpad_down` | | R3 (click) | `r3` |
| D-pad left | `dpad_left` | | PS | `ps` |
| D-pad right | `dpad_right` | | Options | `options` |
| Touchpad click | `touchpad` | | Share/Create | `share` |

</details>

<details>
<summary>Action types</summary>

```yaml
# Keystroke with optional modifiers
type: keystroke
key: k
modifiers: [cmd, shift]   # cmd | shift | alt | ctrl

# Punctuation can be written as literal characters or named aliases.
# Examples: [, ], comma, period, slash, semicolon, quote, minus, equal, backtick, backslash

# Wispr voice dictation
type: wispr
```

</details>

<details>
<summary>Adding a new app context</summary>

1. Find the app's bundle ID: `osascript -e 'id of app "AppName"'`
2. Add it to the `contexts` dict in `AppFocus.swift`
3. Add it to `knownContexts` in `ConfigStore.swift`
4. Add a mapping block in `mappings.yaml` under `profiles.items.<profile>.mappings.<context>`

</details>

## Contributing

PRs welcome — especially new app context mappings and controller support. See [`AGENTS.md`](AGENTS.md).

## License

[MIT](LICENSE) — © 2025 Sourabh Sharma
