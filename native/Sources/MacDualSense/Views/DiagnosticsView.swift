import SwiftUI

struct DiagnosticsWorkspaceView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var store: ConfigStore
    @ObservedObject private var controller: ControllerManager

    init(appState: AppState) {
        self.appState = appState
        self.store = appState.configStore
        self.controller = appState.controllerManager
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let focus = store.currentFocusStatus()
            let accessibilityGranted = store.accessibilityPermissionGranted()
            let recentEvents = Array(controller.recentEvents.suffix(8).reversed())

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsPageHeader(
                        subtitle: "Runtime state, permissions, config health, and recent controller activity."
                    )

                    SettingsSectionCard("Runtime", systemImage: "gauge.with.needle") {
                        HStack {
                            Toggle("Input enabled", isOn: $appState.isEnabled)
                                .toggleStyle(.switch)
                            Spacer()
                            StatusPill(
                                text: accessibilityGranted ? "Accessibility Granted" : "Accessibility Needed",
                                color: accessibilityGranted ? .green : .orange
                            )
                        }

                        DiagnosticsValueRow(title: "Active profile", value: store.activeProfileName())
                        DiagnosticsValueRow(title: "Connected controllers", value: "\(controller.controllers.count)")
                        DiagnosticsValueRow(
                            title: "Active controller",
                            value: activeControllerSummary
                        )

                        if let lastEvent = controller.lastEvent {
                            DiagnosticsValueRow(
                                title: "Last event",
                                value: "\(lastEvent.state) \(lastEvent.button) -> \(lastEvent.action)"
                            )
                        } else {
                            DiagnosticsValueRow(title: "Last event", value: "No controller input yet")
                        }
                    }

                    SettingsSectionCard("App Focus", systemImage: "app.badge") {
                        DiagnosticsValueRow(title: "Frontmost app", value: focus.appName ?? "—")
                        DiagnosticsValueRow(title: "Bundle ID", value: focus.bundleID ?? "—", monospaced: true)
                        DiagnosticsValueRow(
                            title: "Resolved context",
                            value: "\(store.contextLabel(focus.context)) (\(focus.context))"
                        )
                    }

                    SettingsSectionCard("Files & Permissions", systemImage: "folder.badge.gearshape") {
                        DiagnosticsValueRow(title: "Config file", value: store.configFileURL.path, monospaced: true)
                        DiagnosticsValueRow(title: "Log file", value: Logger.shared.logFileURL.path, monospaced: true)
                        DiagnosticsValueRow(
                            title: "Last reload",
                            value: formattedTimestamp(store.lastLoadedAt)
                        )
                        DiagnosticsValueRow(
                            title: "Last save",
                            value: formattedTimestamp(store.lastSavedAt)
                        )

                        if let error = store.lastLoadError {
                            DiagnosticsValueRow(title: "Reload error", value: error)
                        }
                        if let error = store.lastSaveError {
                            DiagnosticsValueRow(title: "Save error", value: error)
                        }

                        HStack(spacing: 10) {
                            Button("Request Accessibility Access") {
                                store.ensureAccessibilityPermission()
                            }
                            Button("Open Config") {
                                store.openConfigInFinder()
                            }
                            Button("Open Support Folder") {
                                store.openSupportFolderInFinder()
                            }
                        }
                    }

                    SettingsSectionCard("Recent Events", systemImage: "waveform.path.ecg") {
                        if recentEvents.isEmpty {
                            Text("No recent controller events.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(recentEvents) { event in
                                    RecentControllerEventRow(event: event)
                                    if event.id != recentEvents.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    private var activeControllerSummary: String {
        guard let activeController = controller.activeController else { return "None" }
        if let vendor = activeController.vendor, !vendor.isEmpty {
            return "\(activeController.name) (\(vendor))"
        }
        return activeController.name
    }

    private func formattedTimestamp(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .standard)
    }
}

