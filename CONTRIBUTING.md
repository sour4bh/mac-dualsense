# Contributing

Contributions to app behavior, controller compatibility, accessibility, and documentation are welcome. For a substantial change, open an issue describing the problem and proposed behavior first.

## Development

Use an Apple Silicon Mac with macOS 26+ and Xcode 26+ / Swift 6.2+. CI selects Xcode 26.6. Open `native/Package.swift` in Xcode, or use:

```sh
make test       # isolated behavior tests; no controller or Accessibility permission needed
make run        # build a development app and launch it
make verify     # release configuration build plus bundle validation
make docs       # local Markdown link and asset checks
```

`make build` creates `native/dist/mac-dualsense.app`. It does not stop or install apps. `make install` replaces the installed copy and does not launch it. `make run` stops the running app before launching the new local build.

The native app uses SwiftUI and GameController. `ConfigStore` owns YAML persistence and app associations; `AppFocus` resolves the frontmost app; `InputRouter` manages keyboard actions and held modifiers; `ControllerManager` handles devices, events, touchpad input, and haptics. UI sections live under `native/Sources/MacDualSense/Views`.

## Before opening a pull request

- Run the relevant tests, `make verify`, and `make docs`.
- Describe the behavior before and after, plus how you tested it.
- For controller changes, report controller model, connection type, macOS version, and target app. Clearly distinguish automated checks from hardware testing.
- Preserve existing mappings and app associations. Add behavior tests for routing, persistence, or input-lifecycle changes.
- Check light/dark appearance, keyboard access, and a 1000 × 640 workspace for UI changes.

Use small, focused commits and plain commit subjects. PRs should not include credentials, personal mapping files, build outputs, or unsanitized logs. Contributions are covered by the project’s MIT license. Be respectful and constructive when reporting bugs or reviewing work.

## Screenshots

`make capture` launches a debug-only capture mode with isolated configuration and controller discovery disabled. It captures actual app views without editing your mappings. ImageMagick is optional for assembling the short GIF. Release builds do not contain capture mode.

See [release validation](docs/validation.md) and [release setup](docs/releasing.md) for packaging work. Report vulnerabilities through [SECURITY.md](SECURITY.md).
