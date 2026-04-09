# mac-dualsense

Use a DualSense (or Pro Controller) as a keyboard shortcut remote on macOS — per-app context switching, profiles, haptic feedback, and voice activation, all driven by a single YAML config file.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6-orange) ![License](https://img.shields.io/badge/license-MIT-green)

---

## What it does

- **Context-aware mappings** — buttons do different things in Warp, Arc, Slack, Claude, ChatGPT, Chrome, and a global fallback
- **Profiles** — switch full mapping sets on the fly
- **Wispr integration** — hold or toggle a button to activate [Wispr Flow](https://wisprflow.ai/) voice dictation (multiple trigger modes)
- **Haptic feedback** — configurable patterns on connect/action/error
- **Live visual feedback** — menu bar icon shows active controller and context
- **Zero runtime dependencies** — native SwiftUI + GameController framework, no drivers or Homebrew packages required

## Requirements

- macOS 13 Ventura or later
- DualSense (PS5) or Nintendo Pro Controller connected via USB or Bluetooth
- Accessibility permission (to inject keystrokes)

## Install

### Download (recommended)

1. Download the latest `.zip` from [Releases](../../releases/latest)
2. Unzip and drag **CC Controller Native.app** to `/Applications`
3. Launch it — a controller icon appears in the menu bar
4. Go to **System Settings → Privacy & Security → Accessibility** and enable **CC Controller Native**

> First launch: macOS may warn "unidentified developer." Right-click the app → Open → Open to bypass.

### Build from source

```bash
git clone https://github.com/sour4bh/mac-dualsense.git
cd mac-dualsense
native/scripts/install_app.sh   # builds, installs to /Applications, and launches
```

Requires Xcode 16+ / Swift 6 toolchain. Or open `native/Package.swift` in Xcode and press Run.

## Configuration

On first launch the config is seeded to:

```
~/Library/Application Support/cc-controller/mappings.yaml
```

Edit it with any text editor. The app hot-reloads changes on save.

### Config structure

```yaml
settings:
  controller:
    preferred: auto          # auto | dualsense | pro_controller
  wispr:
    mode: rcmd_hold          # see Wispr modes below

profiles:
  active: default
  items:
    default:
      mappings:
        default:             # fallback for all apps
          cross:
            type: keystroke
            key: return
        warp:                # overrides when Warp is frontmost
          square:
            type: keystroke
            key: k
            modifiers: [cmd]
```

### Button names

| DualSense | Name | | DualSense | Name |
|---|---|---|---|---|
| Cross (×) | `cross` | | L1 | `l1` |
| Circle (○) | `circle` | | R1 | `r1` |
| Triangle (△) | `triangle` | | L2 | `l2` |
| Square (□) | `square` | | R2 | `r2` |
| D-pad up | `dpad_up` | | L3 (stick click) | `l3` |
| D-pad down | `dpad_down` | | R3 (stick click) | `r3` |
| D-pad left | `dpad_left` | | PS button | `ps` |
| D-pad right | `dpad_right` | | Options | `options` |
| Touchpad click | `touchpad` | | Share/Create | `share` |

### App contexts

| Context key | App |
|---|---|
| `warp` | Warp terminal |
| `arc` | Arc browser |
| `chrome` | Google Chrome |
| `slack` | Slack |
| `chatgpt` | ChatGPT desktop |
| `claude` | Claude desktop |
| `default` | Everything else |

To add a new app: add its bundle ID to `AppFocus.swift` and add a context block to your YAML.

### Action types

```yaml
# Send a keystroke
type: keystroke
key: return
modifiers: [cmd, shift]   # optional: cmd, shift, alt, ctrl

# Activate Wispr voice dictation
type: wispr

# Hold/release a modifier key
type: modifier
modifier: rcmd
action: hold              # hold | release | toggle
```

### Wispr modes

| Mode | Behavior |
|---|---|
| `rcmd_hold` | Hold right ⌘ while button is pressed |
| `lcmd_hold` | Hold left ⌘ while button is pressed |
| `fn_hold` | Hold Fn while button is pressed |
| `rcmd_pulse` | Tap right ⌘ for `hold_ms`, then release |
| `lcmd_pulse` | Tap left ⌘ for `hold_ms`, then release |
| `rcmd_toggle` | Toggle right ⌘ on/off |
| `lcmd_toggle` | Toggle left ⌘ on/off |
| `cmd_right` | Send Cmd+Right keystroke |

## Default mappings

<details>
<summary>Global (all apps)</summary>

| Button | Action |
|---|---|
| D-pad | Arrow keys |
| Cross | Return |
| Circle | Escape |
| Square | Tab |
| Triangle / PS | Wispr voice dictation |
| L1 / R1 | Cmd+Shift+[ / ] (prev/next tab) |
| L2 / R2 | Alt+Up / Alt+Down |
| L3 | Ctrl+C |
| R3 | Ctrl+D |

</details>

<details>
<summary>Warp, Arc, Chrome, Slack, ChatGPT, Claude</summary>

See [`native/Sources/CCControllerNative/Resources/mappings.yaml`](native/Sources/CCControllerNative/Resources/mappings.yaml) for the full per-app default bindings.

</details>

## Contributing

Bug reports, new context mappings, and controller support PRs are welcome. See [`AGENTS.md`](AGENTS.md) for contribution guidelines.

## License

[MIT](LICENSE)
