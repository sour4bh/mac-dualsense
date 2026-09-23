# Native app

SwiftUI + GameController, built with SwiftPM. Requires Apple Silicon, macOS 26+, and Xcode 26+ / Swift 6.2+.

From the repository root:

```sh
make test
make run
make verify
```

Builds create `native/dist/mac-dualsense.app`. Source builds are ad-hoc signed. `make install` installs without launching; `make run` builds and opens the local development app.

See [contributing](../CONTRIBUTING.md), [configuration](../docs/configuration.md), and [signed release setup](../docs/releasing.md).
