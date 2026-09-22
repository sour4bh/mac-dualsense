# Release validation

This file separates automated evidence from checks requiring hardware or signing credentials. A successful source build is not a signed-release certification.

## Automated checks

- 17 Swift behavior tests: configuration compatibility, app routing and cache invalidation, association conflicts, malformed YAML recovery, profile duplication, disabled bindings, capture suppression, held-input cleanup, touchpad click routing, atomic/in-place file watching, and pulse cancellation.
- Bundle checks: ARM64 executable, macOS 26 minimum, icon, bundled configuration and schematics, and signature integrity.
- GitHub Actions syntax and local documentation links.
- Debug-only captures of the actual workspace in light/dark mode and at 1000 × 640, with isolated configuration and no controller connection.

Local validation passed on macOS 26.6.2 with Xcode 27 / Swift 6.4: all 17 tests, the release-configuration ARM64 build, bundle/signature integrity checks, Actions syntax, and local documentation links. Missing signing credentials correctly stop the distribution script before building. Light/dark screenshots and the 1000 × 640 binding inspector were visually reviewed. The explicit installer also passed initial installation and replacement into an isolated temporary destination; the existing configuration file was unchanged in both cases. These are development builds with ad-hoc signatures.

The implementation task records CI results in its PR. CI must pass on the final release commit.

## Manual checks before publishing

- [ ] First launch on a fresh macOS user account: setup, permission denial, granting permission, and returning from System Settings.
- [ ] Launch after setup: menu bar only; reopen the editor; close it without stopping mappings; quit cleanly.
- [ ] Keyboard-only navigation and VoiceOver: sidebar, controller actions, binding recording, profiles, Apps, and Settings.
- [ ] DualSense USB and Bluetooth: face/shoulder buttons, connection changes, app switching, haptics, touchpad pointer, two-finger scroll, left/right clicks.
- [ ] Dictation hold/pulse/toggle: release input when pausing, disconnecting, changing profiles, entering learn mode, or switching the focused app while holding a trigger.
- [ ] Pro Controller USB/Bluetooth: canonical button mappings and list editor fallback.
- [ ] External configuration changes and malformed-YAML recovery with a real editor.
- [ ] Upgrade an existing installation: retain profiles, app associations, and trackpad preferences.
- [ ] Download the final ZIP onto a clean Mac; verify checksum, Gatekeeper acceptance, and offline ticket validation.

No physical-controller or notarized-download checks have been claimed by this refresh. Signing credentials and hands-on hardware checks remain required before the draft becomes a public release.
