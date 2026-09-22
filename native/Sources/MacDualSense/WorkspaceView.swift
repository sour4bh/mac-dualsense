import SwiftUI

struct WorkspaceRootView: View {
    static let windowID = "workspace"
    @ObservedObject var appState: AppState
    let onFirstAppearance: () -> Void
    @AppStorage("setup.completed") private var setupCompleted = false
    @State private var showsSetup = false

    var body: some View {
        WorkspaceView(appState: appState)
            .frame(minWidth: 1000, minHeight: 588)
            .onAppear {
                #if DEBUG
                if DemoCapture.outputDirectory == nil { onFirstAppearance() }
                #else
                onFirstAppearance()
                #endif
                showsSetup = !setupCompleted
                #if DEBUG
                if DemoCapture.outputDirectory != nil {
                    showsSetup = false
                    DemoCapture.start(appState: appState)
                }
                #endif
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
            .onDisappear {
                appState.workspaceSelection.isLearningButton = false
                appState.workspaceSelection.isRecordingShortcut = false
                NSApp.setActivationPolicy(.accessory)
            }
            .sheet(isPresented: $showsSetup) {
                SetupView(appState: appState) {
                    setupCompleted = true
                    showsSetup = false
                }
            }
    }
}

struct WorkspaceView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var store: ConfigStore
    @ObservedObject private var selection: WorkspaceSelection

    init(appState: AppState) {
        self.appState = appState
        store = appState.configStore
        selection = appState.workspaceSelection
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<WorkspaceSection?>(get: { selection.section }, set: { selection.section = $0 ?? .controller })) {
                Section("Workspace") {
                    ForEach(WorkspaceSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage).tag(section)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(appState.isEnabled ? "Mappings enabled" : "Mappings paused", systemImage: appState.isEnabled ? "checkmark.circle.fill" : "pause.circle")
                        .foregroundStyle(appState.isEnabled ? .green : .secondary)
                    Text("Made for your Mac.").foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            VStack(spacing: 0) {
                if let error = store.lastLoadError ?? store.lastSaveError {
                    HStack {
                        Label(error, systemImage: "exclamationmark.triangle.fill").lineLimit(2)
                        Spacer()
                        Button("Reveal config") { store.openConfigInFinder() }
                        Button("Retry") { store.reload() }
                    }
                    .font(.callout)
                    .padding(12)
                    .background(.orange.opacity(0.12))
                }
                HStack(spacing: 0) {
                    Group {
                        switch selection.section {
                        case .controller, .keybinds: ControllerWorkspaceView(appState: appState)
                        case .apps: AppsView(store: store)
                        case .profiles: ProfilesView(store: store)
                        case .diagnostics: DiagnosticsWorkspaceView(appState: appState)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    if selection.inspectorVisible && [.controller, .keybinds].contains(selection.section) {
                        Divider()
                        BindingInspector(store: store, selection: selection)
                            .frame(width: 320)
                            .background(.bar)
                    }
                }
            }
            .navigationTitle(selection.section.title)
        }
        #if DEBUG
        .preferredColorScheme(selection.previewColorScheme)
        #endif
        .navigationSplitViewStyle(.balanced)
        .tint(.blue)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $appState.isEnabled) {
                    Label(appState.isEnabled ? "Pause mappings" : "Resume mappings", systemImage: appState.isEnabled ? "pause" : "play")
                }
                .toggleStyle(.button)
                .help(appState.isEnabled ? "Pause mappings" : "Resume mappings")
            }
            ToolbarItem {
                if [.controller, .keybinds].contains(selection.section) {
                    Button { selection.inspectorVisible.toggle() } label: { Label("Binding inspector", systemImage: "sidebar.right") }
                }
            }
            ToolbarItem {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}
