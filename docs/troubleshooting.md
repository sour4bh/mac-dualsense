# Troubleshooting

## Buttons appear but shortcuts do not run

Check that mappings are enabled in the menu bar and Accessibility is enabled for the installed copy of **mac-dualsense**. Setup testing, Learn button, and shortcut recording intentionally suppress output. Exit those modes, focus your target app, and try again.

After replacing a locally built app, macOS may require you to remove and re-add its Accessibility entry. Keep one installed copy to avoid confusing permissions.

## The controller does not appear

Use a data-capable USB cable, or reconnect in macOS Bluetooth settings. For DualSense pairing, hold Create and PS until the light flashes. Check Diagnostics for connected controllers. Another app or macOS may reserve particular buttons; not every controller exposes every input through GameController.

## A shortcut runs in the wrong app

The Apps screen matches bundle IDs, not display names. Confirm the live app and context in Diagnostics. An unassigned app uses Global. Profiles have separate mappings; check which profile is active.

To suppress a global shortcut for one app, use **Disabled**, not **Reset binding**.

## Configuration could not load or save

The workspace displays the error and offers **Reveal config** and **Retry**. Correct YAML syntax or duplicate bundle-ID assignments, then retry. A failed load keeps the last good in-memory configuration. Check folder permissions if saving fails. Keep a backup before replacing your configuration with the bundled defaults.

## Where did the window go?

Closing the workspace keeps the menu bar companion running. Click its controller icon and choose **Open mac-dualsense…**. Use Quit in the menu bar to stop the app.

## Download and Gatekeeper

The initial notarized download is still being prepared. Local source builds are ad-hoc signed and are intended for development. A published distribution will carry a Developer ID signature and notarization ticket. Do not disable Gatekeeper globally or strip quarantine as an installation step. If a future signed download is rejected, report the release version and the exact macOS message.

[Back to README](../README.md)
