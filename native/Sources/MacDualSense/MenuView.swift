import SwiftUI

struct MenuView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            let focus = appState.configStore.currentFocusStatus()
            let accessibilityGranted = appState.configStore.accessibilityPermissionGranted()

            GlassEffectContainer(spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 30, height: 30)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("mac-dualsense")
                                .font(.headline)
                            Text(appState.configStore.activeProfileName())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        StatusPill(
                            text: appState.isEnabled ? "Enabled" : "Paused",
                            color: appState.isEnabled ? .green : .orange
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Session", systemImage: "gauge.with.needle")
                            .font(.headline)
                        MenuDetailRow(title: "Controller", value: activeControllerSummary)
                        MenuDetailRow(title: "Context", value: appState.configStore.contextLabel(focus.context))
                        MenuDetailRow(
                            title: "Accessibility",
                            value: accessibilityGranted ? "Granted" : "Required"
                        )
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                    Toggle("Enable mappings", isOn: $appState.isEnabled)
                        .toggleStyle(.switch)

                    Button {
                        openWorkspace()
                    } label: {
                        Label("Open mac-dualsense…", systemImage: "macwindow")
                    }
                    .buttonStyle(.glassProminent)

                    HStack(spacing: 8) {
                        Button {
                            appState.configStore.reload()
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }

                        Button {
                            appState.configStore.openConfigInFinder()
                        } label: {
                            Label("Config", systemImage: "folder")
                        }
                    }

                    Divider()

                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                    .keyboardShortcut("q", modifiers: [.command])
                }
                .padding(14)
                .frame(minWidth: 300)
                .controlSize(.regular)
            }
        }
    }

    private var activeControllerSummary: String {
        guard let activeController = appState.controllerManager.activeController else { return "No active controller" }
        if let vendor = activeController.vendor, !vendor.isEmpty {
            return "\(activeController.name) (\(vendor))"
        }
        return activeController.name
    }

    private func openWorkspace() {
        NSApp.activate(ignoringOtherApps: true)
        Task {
            try? await openWindow(id: WorkspaceRootView.windowID, sharingBehavior: .required)
        }
    }
}

private struct MenuDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}
