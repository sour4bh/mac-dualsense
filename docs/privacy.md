# Permissions and local data

mac-dualsense uses macOS Accessibility permission to send keyboard and mouse events on your behalf. It reads the frontmost app’s name and bundle ID to select mappings, and receives controller events through Apple’s GameController framework.

The app does not create an account, send analytics, or contact a backend. Configuration and logs are stored locally. Source builds fetch Yams from GitHub; distribution notarization submits the built application to Apple. These are development/release operations, not app telemetry.

- Configuration: `~/Library/Application Support/mac-dualsense/mappings.yaml`
- Logs: `~/Library/Logs/mac-dualsense.log`
- Preferences: the app’s macOS UserDefaults domain, `com.sour4bh.mac-dualsense`

Logs may include controller identifiers, button names, configured shortcuts, configuration paths, and errors. They are not a recording of everything you type. Review logs and screenshots before sharing a bug report; they can reveal personal app names or mappings. Logs currently have no automatic rotation and can be deleted after quitting the app.

Accessibility is requested from setup or the workspace’s permission action. You can revoke it in System Settings → Privacy & Security → Accessibility. Without permission, mappings do not inject input. Controller discovery and editing remain available.

Wispr Flow and other dictation applications have their own permissions and privacy policies. mac-dualsense only sends the configured key gesture and does not process audio.

[Back to README](../README.md)
