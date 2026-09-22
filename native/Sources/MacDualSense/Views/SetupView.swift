import SwiftUI

struct SetupView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var controller: ControllerManager
    let done: () -> Void

    init(appState: AppState, done: @escaping () -> Void) {
        self.appState = appState
        controller = appState.controllerManager
        self.done = done
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 36)).foregroundStyle(.blue)
                Text("Make yourself comfortable.").font(.largeTitle.bold())
                Text("Turn your controller into a shortcut remote for your Mac.").foregroundStyle(.secondary)
                ScrollView {
                  GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(controller.activeController == nil ? "1. Connect your controller" : "1. Controller connected", systemImage: controller.activeController == nil ? "cable.connector" : "checkmark.circle.fill")
                        Text("Plug in with USB, or pair through System Settings → Bluetooth. For DualSense, hold Create and PS until the light flashes.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Divider()
                        Label(appState.configStore.accessibilityPermissionGranted() ? "2. Accessibility enabled" : "2. Allow keyboard and mouse shortcuts", systemImage: "hand.raised")
                        Text("mac-dualsense needs Accessibility access to send the shortcuts you assign. Your configuration and logs stay on this Mac.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Enable Accessibility…") { appState.configStore.ensureAccessibilityPermission() }
                        Divider()
                        Label("3. Try a button safely", systemImage: "hand.tap")
                        Text(controller.lastEvent.map { "\($0.button) · \($0.state)" } ?? "Press any controller button. Shortcuts are paused while this screen is open.")
                            .font(.callout.monospaced()).foregroundStyle(.secondary)
                    }.padding(12)
                  }
                }
                HStack {
                    Text("You can set up your mappings without a controller.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open workspace", action: done).buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                }
            }
            .padding(24).frame(width: 560, height: 580)
        }
    }
}
