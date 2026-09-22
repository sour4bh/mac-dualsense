# Configuration

mac-dualsense keeps settings in `~/Library/Application Support/mac-dualsense/mappings.yaml`. The first launch copies the bundled defaults. Edits in the app save automatically; external edits reload automatically. A malformed document leaves the last good in-memory configuration running and displays a recovery message. Back up the file before making large manual changes.

## Apps and profiles

App associations are shared across profiles. Button mappings belong to individual profiles. The app’s bundle ID selects an app context; a missing binding falls back to that profile’s `default` context.

```yaml
version: 2
contexts:
  editor:
    name: My Editor
    bundle_ids: [org.example.editor]
profiles:
  active: work
  items:
    work:
      trackpad_mode: false
      mappings:
        default:
          cross: {type: keystroke, key: return}
        editor:
          cross: {type: keystroke, key: s, modifiers: [cmd]}
          triangle: {type: noop}
```

When `contexts` is absent, built-in associations for Warp, Arc, Chrome, Slack, ChatGPT, and Claude apply. The next save writes those associations explicitly. An explicit empty dictionary (`contexts: {}`) means no app associations. Existing context IDs and mapping blocks are retained.

Each context has a stable ID, a display `name`, and zero or more `bundle_ids`. Renaming the display label does not change the ID. One bundle ID can belong to only one context. Global (`default`) is reserved and always available.

In **Apps**, add a context or edit an existing one, choose a `.app` or enter its bundle ID, and save. Several apps can share one context. Removing associations leaves the mappings available for reuse; empty contexts are shown as unassigned.

## Binding states

| State | Stored representation | Behavior |
| --- | --- | --- |
| Inherit global | No entry for that button | Uses the current profile’s global binding, if present |
| Shortcut | `type: keystroke` | Sends `key` with optional `modifiers` |
| Voice dictation | `type: wispr` | Uses the trigger chosen in Settings |
| Disabled | `type: noop` | Sends nothing, including no global fallback |

Resetting a binding removes its override. To stop a globally mapped button in one app, choose **Disabled**.

Supported keys include letters, digits, punctuation, arrows, Return, Escape, Tab, Space, navigation keys, and F1–F12. Modifier names are `cmd`, `shift`, `alt`, `ctrl`, and `fn`. Key codes follow a US keyboard layout; layouts can produce different characters.

Canonical button names: `dpad_up`, `dpad_down`, `dpad_left`, `dpad_right`, `cross`, `circle`, `triangle`, `square`, `l1`, `r1`, `l2`, `r2`, `l3`, `r3`, `ps`, `options`, `share`, `touchpad`. Pro Controller inputs use these canonical mapping names too.

## Settings

```yaml
settings:
  controller:
    preferred: auto # auto, dualsense, pro_controller
  wispr:
    mode: rcmd_hold
    hold_ms: 450
  trackpad:
    cursor_sensitivity: 900
    scroll_sensitivity: 40
    natural_scroll: true
    right_click_modifier: l2
haptics:
  enabled: true
  patterns:
    confirm: {intensity: 128, duration_ms: 50}
```

Dictation modes: `rcmd_hold`, `lcmd_hold`, `fn_hold`, `rcmd_toggle`, `lcmd_toggle`, `rcmd_pulse`, `lcmd_pulse`, `cmd_right`. Match the trigger in your dictation app. Pulse duration uses milliseconds.

Trackpad mode is enabled separately for each profile. It replaces the touchpad’s keystroke binding. Move one finger to move the pointer, use two fingers to scroll, and press to click. Hold the configured modifier while clicking for a right click; an empty modifier disables right click. Sensitivity settings are global.

Learn mode, shortcut recording, and setup testing suppress shortcut injection. Pausing or changing routing releases held modifiers and mouse buttons.

[Back to README](../README.md)
