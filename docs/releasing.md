# Preparing a signed release

Distribution targets Apple Silicon and macOS 26+. Local builds use ad-hoc signing; release builds require **Developer ID Application** signing and notarization. The release scripts never substitute an unsigned artifact when credentials or notarization are unavailable.

## One-time Apple setup

An Apple Developer account is available, but a Developer ID Application identity was not installed on the development Mac during this refresh. An Apple Development identity cannot sign this distribution.

1. In your Apple Developer account/Xcode, create a **Developer ID Application** certificate. Keep its private key in your login keychain.
2. Verify it appears in `security find-identity -v -p codesigning`.
3. For CI, export that identity and private key from Keychain Access as a password-protected `.p12`.
4. Create an Apple app-specific password for notarization. Never put the password, private key, or certificate export in this repository or an issue.

See [Apple’s Developer ID guide](https://developer.apple.com/developer-id/) and [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## GitHub configuration

Use the repository’s **release** environment, restricted to the main branch. Add these secrets securely in GitHub Settings → Environments → release:

| Secret | Value |
| --- | --- |
| `SIGNING_CERTIFICATE_BASE64` | Base64 encoding of the exported Developer ID `.p12` |
| `SIGNING_CERTIFICATE_PASSWORD` | Password protecting that `.p12` |
| `APPLE_ID` | Apple account used for notarization |
| `APPLE_TEAM_ID` | Developer team ID |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |

Add environment variable `SIGNING_IDENTITY` with the full certificate name, for example `Developer ID Application: Your Name (TEAMID)`.

The workflow imports the certificate into a temporary keychain, stores a notarization profile there, and deletes the keychain and certificate export on exit. Pull-request CI uses no signing secrets.

## Release workflow

1. Merge the reviewed changes to main. Confirm CI passes for the selected commit.
2. Run **Prepare signed release** from the main branch with a version such as `0.1.0` and the full 40-character commit SHA. The workflow requires that SHA to be on main.
3. It tests that commit, builds ARM64, signs with hardened runtime and a secure timestamp, submits to Apple, and requires an Accepted response.
4. It staples the ticket, verifies the bundle, recreates the ZIP, extracts it into a temporary directory, and verifies that extracted copy again.
5. Only then does it attach `mac-dualsense-0.1.0-arm64.zip` and `SHA256SUMS` to a **draft** release. It refuses to modify a published release.
6. Complete the manual checks in [validation](validation.md), update the notes, then publish the draft as a separate launch action. Update the README’s download section after the release is public.

There is no automatic publishing on tags or pushes.

## Local notarization

Store a `notarytool` credential profile through its interactive prompt:

```sh
xcrun notarytool store-credentials mac-dualsense-release
```

Then supply the non-secret identity and profile name:

```sh
APP_VERSION=0.1.0 \
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE=mac-dualsense-release \
native/scripts/release.sh
```

For a profile in a custom keychain, also set `NOTARY_KEYCHAIN` to that keychain’s path. `APP_VERSION` is an `X.Y.Z` value; both bundle version fields are derived from it. The bundle identifier and configuration location remain stable across upgrades.

A notarization failure leaves diagnostics at `native/dist/notarization.json` and no uploaded release asset. Use the submission ID with `xcrun notarytool log` to investigate. Validate signing failures directly instead of disabling Gatekeeper or suppressing `codesign` errors.

## Artwork and social preview

The original icon source is `native/AppBundle/AppIcon.png`; app bundles generate the required `.icns` sizes. The GitHub social preview is `docs/assets/social-preview.jpg` (under GitHub’s 1 MB upload limit). Upload it in repository Settings → General → Social preview; GitHub does not provide a supported repository REST endpoint for this upload.
