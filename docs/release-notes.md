# mac-dualsense 0.1.0

Your controller. Your Mac. Your shortcuts.

A native macOS menu bar companion with a visual controller editor, app-specific shortcuts, profiles, and DualSense touchpad control.

## Highlights

- A refreshed native workspace with front/back controller views and a collapsible binding inspector.
- Choose your own apps and associate shortcuts by bundle ID.
- Safe first-launch input testing and clear Accessibility setup.
- Native Settings for controller preference, dictation triggers, haptics, and trackpad sensitivity.
- Explicit inherited and disabled bindings, plus improved held-input cleanup.

## Requirements

Apple Silicon, macOS 26 or later. Accessibility permission is required to send shortcuts. DualSense and Nintendo Switch Pro Controller use Apple’s GameController support; device-specific behavior still needs the hardware checks recorded in `docs/validation.md`.

## Installation after signed assets are attached

Download the ARM64 ZIP, extract it, move mac-dualsense.app to Applications, and open it. Follow the setup screen to grant Accessibility permission. Existing profiles and mappings are kept at their current location.

## Release preparation

This release remains a draft until Developer ID signing, notarization, final ZIP validation, and the hardware smoke test are complete. No unsigned binary is a substitute for the signed release asset. See `docs/releasing.md` for the credential setup and validation steps.
