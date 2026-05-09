import SwiftUI

struct WorkspaceRootView: View {
    static let windowID = "workspace"

    @ObservedObject var appState: AppState
    let onFirstAppearance: () -> Void

    @State private var didRecordLaunch = false

    var body: some View {
        WorkspaceView(appState: appState)
            .frame(minWidth: 1120, minHeight: 720)
            .onAppear {
                if !didRecordLaunch {
                    didRecordLaunch = true
                    onFirstAppearance()
                }
                appState.workspaceSelection.seedEditedContext(from: appState.configStore.currentFocusStatus().context)
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
            .onDisappear {
                NSApp.setActivationPolicy(.accessory)
            }
    }
}

struct WorkspaceView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var configStore: ConfigStore
    @ObservedObject private var selection: WorkspaceSelection

    init(appState: AppState) {
        self.appState = appState
        self.configStore = appState.configStore
        self.selection = appState.workspaceSelection
    }

    var body: some View {
        NavigationSplitView {
            List(selection: sectionBinding) {
                ForEach(WorkspaceSection.allCases) { section in
                    NavigationLink(value: section) {
                        WorkspaceSidebarRow(section: section)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspaceSidebarSummary(appState: appState)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 236, max: 280)
        } detail: {
            Group {
                switch selection.section {
                case .controller:
                    ControllerWorkspaceView(appState: appState)
                case .profiles:
                    ProfilesWorkspaceView(appState: appState)
                case .keybinds:
                    KeybindsWorkspaceView(appState: appState)
                case .diagnostics:
                    DiagnosticsWorkspaceView(appState: appState)
                }
            }
            .navigationTitle(selection.section.title)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    Picker("Profile", selection: Binding(
                        get: { configStore.activeProfileName() },
                        set: { configStore.setActiveProfile($0) }
                    )) {
                        ForEach(configStore.profileNames(), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                } label: {
                    Label(configStore.activeProfileName(), systemImage: "person.crop.square")
                }
                .help("Active profile")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $appState.isEnabled) {
                    Label(
                        appState.isEnabled ? "Enabled" : "Paused",
                        systemImage: appState.isEnabled ? "power.circle.fill" : "power.circle"
                    )
                }
                .toggleStyle(.button)
                .help(appState.isEnabled ? "Pause input mapping" : "Resume input mapping")

                Button {
                    configStore.reload()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
                .help("Reload mappings from disk")
            }
        }
    }

    private var sectionBinding: Binding<WorkspaceSection?> {
        Binding(
            get: { selection.section },
            set: { selection.section = $0 ?? .controller }
        )
    }
}

struct ControllerWorkspaceView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var controllerManager: ControllerManager
    @ObservedObject private var configStore: ConfigStore
    @ObservedObject private var selection: WorkspaceSelection

    @State private var inspectorAction: ActionDef = .init()

    init(appState: AppState) {
        self.appState = appState
        self.controllerManager = appState.controllerManager
        self.configStore = appState.configStore
        self.selection = appState.workspaceSelection
    }

    private struct InspectorTarget: Equatable {
        let profile: String
        let context: String
        let button: String?
    }

    private var controllerType: ControllerType {
        guard let active = controllerManager.activeController else { return .dualSense }
        return ControllerType.detect(name: active.name, vendor: active.vendor)
    }

    private var activeProfile: String {
        configStore.activeProfileName()
    }

    private var inspectorTarget: InspectorTarget {
        InspectorTarget(profile: activeProfile, context: selection.editedContext, button: selection.selectedButton)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let focus = configStore.currentFocusStatus()
            let availableContexts = configStore.contextKeys(forProfile: activeProfile)

            HSplitView {
                ControllerWorkspaceSidebar(
                    appState: appState,
                    controllerType: controllerType,
                    focus: focus,
                    availableContexts: availableContexts,
                    openKeybinds: { selection.section = .keybinds }
                )
                .frame(minWidth: 290, idealWidth: 320, maxWidth: 360)

                ControllerVisualPane(
                    controllerType: controllerType,
                    controllerManager: controllerManager,
                    configStore: configStore,
                    profile: activeProfile,
                    context: selection.editedContext,
                    selectedButton: $selection.selectedButton,
                    openKeybinds: { selection.section = .keybinds }
                )
                .frame(minWidth: 460, idealWidth: 620, maxWidth: .infinity)

                ControllerInspectorPane(
                    button: selection.selectedButton,
                    action: $inspectorAction,
                    inheritedAction: inheritedAction(for: selection.selectedButton),
                    onClearSelection: { selection.selectedButton = nil },
                    onDelete: deleteSelectedAction
                )
                .frame(minWidth: 340, idealWidth: 380, maxWidth: 420)
            }
            .onAppear {
                syncEditedContext(fallbackContext: focus.context)
                syncInspectorAction()
            }
            .onChange(of: activeProfile) { _, _ in
                syncEditedContext(fallbackContext: focus.context)
                syncInspectorAction()
            }
            .onChange(of: selection.editedContext) { _, _ in
                syncInspectorAction()
            }
            .onChange(of: selection.selectedButton) { _, _ in
                syncInspectorAction()
            }
            .onChange(of: controllerManager.lastEvent?.id) { _, _ in
                handleLearnModeEvent()
            }
            .onChange(of: inspectorAction) { _, updated in
                persistInspectorAction(updated)
            }
        }
    }

    private func syncEditedContext(fallbackContext: String) {
        let contexts = configStore.contextKeys(forProfile: activeProfile)
        let fallback = contexts.contains(fallbackContext) ? fallbackContext : "default"
        selection.ensureValidContext(contexts, fallback: fallback)
    }

    private func syncInspectorAction() {
        guard let button = selection.selectedButton else {
            inspectorAction = .init()
            return
        }
        inspectorAction = configStore.action(profile: activeProfile, context: selection.editedContext, button: button) ?? .init()
    }

    private func handleLearnModeEvent() {
        guard selection.isLearningButton,
              let event = controllerManager.lastEvent,
              event.state == "Pressed"
        else { return }

        selection.isLearningButton = false
        selection.selectedButton = event.button
    }

    private func persistInspectorAction(_ updated: ActionDef) {
        guard let button = selection.selectedButton else { return }

        let existing = configStore.action(profile: activeProfile, context: selection.editedContext, button: button)
        if normalized(action: updated) == normalized(action: existing) {
            return
        }

        if isNoop(updated) {
            if existing != nil {
                configStore.deleteAction(profile: activeProfile, context: selection.editedContext, button: button)
            }
            return
        }

        configStore.setAction(
            profile: activeProfile,
            context: selection.editedContext,
            button: button,
            action: updated
        )
    }

    private func deleteSelectedAction() {
        guard let button = selection.selectedButton else { return }
        configStore.deleteAction(profile: activeProfile, context: selection.editedContext, button: button)
        inspectorAction = .init()
    }

    private func inheritedAction(for button: String?) -> ActionDef? {
        guard let button, selection.editedContext != "default" else { return nil }
        return configStore.action(profile: activeProfile, context: "default", button: button)
    }

    private func isNoop(_ action: ActionDef) -> Bool {
        action.type.lowercased() == "noop"
    }

    private func normalized(action: ActionDef?) -> ActionDef? {
        guard var action else { return nil }
        action.type = action.type.lowercased()
        return action
    }
}

struct ProfilesWorkspaceView: View {
    @ObservedObject var appState: AppState
    @State private var selectedProfile: String? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        let store = appState.configStore
        let profiles = store.profileNames()
        let active = store.activeProfileName()

        SettingsPageScrollView(maxWidth: 820) {
            SettingsPageHeader(
                subtitle: "Keep separate mapping sets for different workflows and swap between them instantly."
            )

            SettingsSectionCard("Active Profile", systemImage: "checkmark.circle") {
                Picker("Active profile", selection: Binding(
                    get: { store.activeProfileName() },
                    set: { store.setActiveProfile($0) }
                )) {
                    ForEach(profiles, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(maxWidth: 420)

                Toggle("Trackpad mode", isOn: Binding(
                    get: { store.trackpadModeEnabled(profile: active) },
                    set: { store.setTrackpadMode(profile: active, enabled: $0) }
                ))
                Text("When on, the touchpad moves the cursor, two fingers scroll, and click acts as a mouse button (hold L2 and click for right-click). The touchpad's own keystroke binding is ignored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    StatusPill(text: "\(profiles.count) Profiles", color: .secondary)
                    StatusPill(text: "Current: \(active)", color: .blue)
                }
            }

            SettingsSectionCard("Library", systemImage: "square.stack.3d.up") {
                VStack(spacing: 0) {
                    ForEach(Array(profiles.enumerated()), id: \.element) { index, name in
                        HStack(spacing: 8) {
                            Text(name)
                            Spacer()
                            if name == active {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedProfile == name ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedProfile = name }
                        if index < profiles.count - 1 {
                            Divider()
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        let newName = AppKitDialogs.promptText(
                            title: "New Profile",
                            message: "Profile name:"
                        )
                        guard let newName else { return }

                        do {
                            try store.addProfile(name: newName, cloneFrom: selectedProfile ?? active)
                            selectedProfile = newName
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }

                    Button {
                        guard let src = selectedProfile ?? profiles.first else { return }
                        do {
                            let name = try store.duplicateProfile(from: src)
                            selectedProfile = name
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }

                    Button {
                        guard let src = selectedProfile else { return }
                        let newName = AppKitDialogs.promptText(
                            title: "Rename Profile",
                            message: "New name:",
                            defaultValue: src
                        )
                        guard let newName, newName != src else { return }
                        do {
                            try store.renameProfile(old: src, new: newName)
                            selectedProfile = newName
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        guard let name = selectedProfile else { return }
                        guard AppKitDialogs.confirm(
                            title: "Delete Profile",
                            message: "Delete “\(name)”?",
                            okTitle: "Delete"
                        ) else { return }

                        do {
                            try store.deleteProfile(name)
                            selectedProfile = store.activeProfileName()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Spacer()

                    Button("Make Active") {
                        guard let sel = selectedProfile, sel != active else { return }
                        store.setActiveProfile(sel)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(selectedProfile == nil || selectedProfile == active)
                }
            }
        }
        .onAppear {
            selectedProfile = selectedProfile ?? active
        }
        .alert("Profiles Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { showing in if !showing { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

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

struct KeybindsWorkspaceView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var store: ConfigStore
    @State private var profile: String = ""
    @State private var context: String = "default"
    @State private var selectedButton: String? = nil
    @State private var errorMessage: String? = nil

    init(appState: AppState) {
        self.appState = appState
        self.store = appState.configStore
    }

    var body: some View {

        let profiles = store.profileNames()
        let active = store.activeProfileName()
        let editingProfile = profiles.contains(profile) ? profile : active
        let contexts = store.contextKeys(forProfile: editingProfile)
        let editingContext = contexts.contains(context) ? context : "default"
        let buttons = store.buttons(forProfile: editingProfile, context: editingContext)

        SettingsPageScrollView(maxWidth: 920) {
            SettingsPageHeader(
                subtitle: "Edit mappings by profile and app context, or use the controller workspace for visual editing."
            )

            SettingsSectionCard("Editing Scope", systemImage: "slider.horizontal.3") {
                HStack(spacing: 14) {
                    Picker("Profile", selection: Binding(
                        get: { editingProfile },
                        set: { profile = $0 }
                    )) {
                        ForEach(profiles, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .frame(maxWidth: 260)

                    Button("Make Active") {
                        store.setActiveProfile(editingProfile)
                    }
                    .buttonStyle(.bordered)
                    .disabled(editingProfile == active)

                    Picker("Context", selection: Binding(
                        get: { editingContext },
                        set: { context = $0 }
                    )) {
                        ForEach(contexts, id: \.self) { ctx in
                            Text(store.contextLabel(ctx)).tag(ctx)
                        }
                    }
                    .frame(maxWidth: 260)

                    Spacer()
                }

                HStack(spacing: 8) {
                    StatusPill(text: editingProfile, color: .blue)
                    StatusPill(text: store.contextLabel(editingContext), color: .secondary)
                }
            }

            SettingsSectionCard("Mappings", systemImage: "keyboard") {
                HStack {
                    Text("Mappings for \(store.contextLabel(editingContext))")
                        .font(.headline)
                    Spacer()
                    Button {
                        let btn = AppKitDialogs.promptText(
                            title: "Add Mapping",
                            message: "Button name (e.g. cross, dpad_up):"
                        )
                        guard let btn else { return }
                        let action = ActionDef(type: "noop", key: nil, modifiers: nil)
                        store.setAction(profile: editingProfile, context: editingContext, button: btn, action: action)
                        selectedButton = btn
                    } label: {
                        Label("Add Mapping…", systemImage: "plus")
                    }
                }

                if buttons.isEmpty {
                    ContentUnavailableView(
                        "No Mappings Yet",
                        systemImage: "keyboard.badge.ellipsis",
                        description: Text("Add a button manually or use the Controller section for visual editing.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(buttons.enumerated()), id: \.element) { index, button in
                            KeybindRow(
                                button: button,
                                isSelected: selectedButton == button,
                                action: Binding(
                                    get: {
                                        store.action(profile: editingProfile, context: editingContext, button: button)
                                            ?? ActionDef(type: "noop", key: nil, modifiers: nil)
                                    },
                                    set: { updated in
                                        store.setAction(
                                            profile: editingProfile,
                                            context: editingContext,
                                            button: button,
                                            action: updated
                                        )
                                    }
                                ),
                                onSelect: { selectedButton = button },
                                onDelete: {
                                    store.deleteAction(profile: editingProfile, context: editingContext, button: button)
                                    if selectedButton == button {
                                        selectedButton = nil
                                    }
                                }
                            )
                            if index < buttons.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if profile.isEmpty {
                profile = active
            }
            context = editingContext
        }
        .onChange(of: profiles) { _, _ in
            if !profiles.contains(profile) {
                profile = active
            }
        }
        .alert("Keybinds Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { showing in if !showing { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private struct WorkspaceSidebarSummary: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var controller: ControllerManager

    init(appState: AppState) {
        self.appState = appState
        self.controller = appState.controllerManager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("mac-dualsense")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            HStack(spacing: 6) {
                StatusPill(
                    text: appState.isEnabled ? "Enabled" : "Paused",
                    color: appState.isEnabled ? .green : .orange
                )
                Text(appState.configStore.activeProfileName())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Image(systemName: "gamecontroller")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(controllerShortName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var controllerShortName: String {
        guard let activeController = controller.activeController else { return "No controller" }
        return activeController.name
    }
}

private struct WorkspaceSidebarRow: View {
    let section: WorkspaceSection

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .lineLimit(1)
                Text(section.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct SettingsPageScrollView<Content: View>: View {
    let maxWidth: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

private struct ControllerWorkspaceSidebar: View {
    @ObservedObject var appState: AppState
    let controllerType: ControllerType
    let focus: AppFocus.Status
    let availableContexts: [String]
    let openKeybinds: () -> Void

    @ObservedObject private var configStore: ConfigStore
    @ObservedObject private var controllerManager: ControllerManager
    @ObservedObject private var selection: WorkspaceSelection

    init(
        appState: AppState,
        controllerType: ControllerType,
        focus: AppFocus.Status,
        availableContexts: [String],
        openKeybinds: @escaping () -> Void
    ) {
        self.appState = appState
        self.controllerType = controllerType
        self.focus = focus
        self.availableContexts = availableContexts
        self.openKeybinds = openKeybinds
        self.configStore = appState.configStore
        self.controllerManager = appState.controllerManager
        self.selection = appState.workspaceSelection
    }

    var body: some View {
        let activeProfile = configStore.activeProfileName()
        let pressedNow = controllerManager.pressed.sorted().joined(separator: ", ")
        let lastButton = controllerManager.lastEvent?.button ?? "—"
        let explicitButtons = configStore.buttons(forProfile: activeProfile, context: selection.editedContext)
        let accessibilityGranted = configStore.accessibilityPermissionGranted()

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSectionCard("Editing Scope", systemImage: "slider.horizontal.3") {
                    Picker("Active profile", selection: Binding(
                        get: { activeProfile },
                        set: { configStore.setActiveProfile($0) }
                    )) {
                        ForEach(configStore.profileNames(), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }

                    Picker("Edited context", selection: Binding(
                        get: { selection.editedContext },
                        set: { selection.editedContext = $0 }
                    )) {
                        ForEach(availableContexts, id: \.self) { context in
                            Text(configStore.contextLabel(context)).tag(context)
                        }
                    }

                    HStack(spacing: 8) {
                        StatusPill(text: configStore.contextLabel(selection.editedContext), color: .blue)
                        StatusPill(text: "Live: \(configStore.contextLabel(focus.context))", color: .secondary)
                    }

                    Button("Use Current App Context") {
                        selection.editedContext = focus.context
                    }
                    .buttonStyle(.bordered)

                    if controllerType.supportsVisualEditor {
                        Toggle("Learn next button", isOn: $selection.isLearningButton)
                            .toggleStyle(.switch)

                        if selection.isLearningButton {
                            Text("Press a controller button to select it in the inspector.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsSectionCard("Controller", systemImage: "gamecontroller") {
                    Picker("Preferred controller", selection: Binding(
                        get: { configStore.preferredController() },
                        set: { configStore.setPreferredController($0) }
                    )) {
                        Text("Auto").tag("auto")
                        Text("DualSense").tag("dualsense")
                        Text("Pro Controller").tag("pro_controller")
                    }

                    Picker("Active device", selection: Binding(
                        get: { controllerManager.activeController?.id ?? "" },
                        set: { controllerManager.setActiveController(id: $0.isEmpty ? nil : $0) }
                    )) {
                        Text("—").tag("")
                        ForEach(controllerManager.controllers) { controller in
                            Text(controller.vendor != nil ? "\(controller.name) (\(controller.vendor!))" : controller.name)
                                .tag(controller.id)
                        }
                    }

                    HStack(spacing: 8) {
                        StatusPill(text: controllerType.displayName, color: .secondary)
                        if controllerManager.activeController == nil {
                            StatusPill(text: "No Controller", color: .orange)
                        }
                    }

                    DiagnosticsValueRow(title: "Last button", value: lastButton, monospaced: true)
                    DiagnosticsValueRow(title: "Pressed now", value: pressedNow.isEmpty ? "—" : pressedNow, monospaced: true)
                }

                SettingsSectionCard("Setup", systemImage: "checklist") {
                    if !accessibilityGranted {
                        SetupHint(
                            title: "Accessibility permission is required",
                            detail: "Grant access before expecting macOS keystrokes to fire."
                        )
                        Button("Request Accessibility Access") {
                            configStore.ensureAccessibilityPermission()
                        }
                    }

                    if controllerManager.activeController == nil {
                        SetupHint(
                            title: "No active controller connected",
                            detail: "You can still edit bindings, but live input and learn mode need a connected controller."
                        )
                    }

                    if !controllerType.supportsVisualEditor {
                        SetupHint(
                            title: "\(controllerType.displayName) uses the list editor",
                            detail: "This controller does not have a visual map yet. Use the Keybinds section for bulk editing."
                        )
                        Button("Open Keybinds") {
                            openKeybinds()
                        }
                    }

                    if explicitButtons.isEmpty {
                        SetupHint(
                            title: "No explicit mappings in this context",
                            detail: "Buttons will fall back to Global mappings until you add a context-specific override."
                        )
                    }

                    if accessibilityGranted,
                       controllerManager.activeController != nil,
                       controllerType.supportsVisualEditor,
                       !explicitButtons.isEmpty
                    {
                        SetupHint(
                            title: "Ready to edit",
                            detail: "Choose a button on the controller map or enable learn mode to drive the inspector."
                        )
                    }
                }
            }
            .padding(16)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

private struct ControllerVisualPane: View {
    let controllerType: ControllerType
    @ObservedObject var controllerManager: ControllerManager
    @ObservedObject var configStore: ConfigStore
    let profile: String
    let context: String
    @Binding var selectedButton: String?
    let openKeybinds: () -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsPageHeader(
                    subtitle: controllerType.supportsVisualEditor
                        ? "Live controller view for \(configStore.contextLabel(context)). Select a button to inspect or override its mapping."
                        : "This controller falls back to the list editor. The live button stream still appears in Diagnostics."
                )

                if controllerType.supportsVisualEditor {
                    ForEach(controllerType.availableViews) { side in
                        SettingsSectionCard(
                            controllerType.availableViews.count > 1 ? side.label : "Controller Map",
                            systemImage: side == .front ? "gamecontroller" : "rectangle.3.group"
                        ) {
                            ControllerVisualView(
                                controllerType: controllerType,
                                viewSide: side,
                                pressed: controllerManager.pressed,
                                selectedButton: selectedButton,
                                getAction: { button in
                                    configStore.action(profile: profile, context: context, button: button)
                                },
                                onSelectButton: { selectedButton = $0 }
                            )
                            .aspectRatio(aspectRatio(for: side), contentMode: .fit)
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    SettingsSectionCard("Controller Map", systemImage: "gamecontroller") {
                        ContentUnavailableView(
                            "\(controllerType.displayName) visual editor unavailable",
                            systemImage: "gamecontroller",
                            description: Text("Open Keybinds to edit mappings for this controller.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)

                        Button("Open Keybinds") {
                            openKeybinds()
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func aspectRatio(for side: ControllerViewSide) -> CGFloat {
        if let box = controllerType.viewBox(for: side), box.height > 0 {
            return box.width / box.height
        }
        return 590.0 / 410.0
    }
}

private struct ControllerInspectorPane: View {
    let button: String?
    @Binding var action: ActionDef
    let inheritedAction: ActionDef?
    let onClearSelection: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsPageHeader(
                    subtitle: "The inspector edits the explicit mapping for the selected button in the current context."
                )

                SettingsSectionCard("Binding Inspector", systemImage: "sidebar.right") {
                    if let button {
                        if let inheritedAction {
                            DiagnosticsValueRow(
                                title: "Global fallback",
                                value: ActionFormatter.format(inheritedAction),
                                monospaced: true
                            )
                        }

                        ButtonBindingEditor(
                            button: button,
                            action: $action,
                            onDelete: onDelete
                        )

                        Button("Clear Selection") {
                            onClearSelection()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        ContentUnavailableView(
                            "No Button Selected",
                            systemImage: "cursorarrow.click",
                            description: Text("Select a button from the controller map to inspect or override its mapping.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    }
                }
            }
            .padding(16)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

private struct SetupHint: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsPageHeader: View {
    let subtitle: String

    init(subtitle: String) {
        self.subtitle = subtitle
    }

    var body: some View {
        Text(subtitle)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct DiagnosticsValueRow: View {
    let title: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .body)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct RecentControllerEventRow: View {
    let event: ControllerManager.ButtonEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(event.time.formatted(date: .omitted, time: .standard))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)

            StatusPill(
                text: event.state,
                color: event.state == "Pressed" ? .green : .secondary
            )

            Text(event.button)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 120, alignment: .leading)

            Text(event.action)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .glassEffect(.regular.tint(color.opacity(0.2)).interactive(), in: Capsule())
    }
}

private struct KeybindRow: View {
    let button: String
    let isSelected: Bool
    @Binding var action: ActionDef
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var keyText: String
    @State private var modifiersText: String

    init(
        button: String,
        isSelected: Bool = false,
        action: Binding<ActionDef>,
        onSelect: @escaping () -> Void = {},
        onDelete: @escaping () -> Void
    ) {
        self.button = button
        self.isSelected = isSelected
        self._action = action
        self.onSelect = onSelect
        self.onDelete = onDelete
        _keyText = State(initialValue: action.wrappedValue.key ?? "")
        _modifiersText = State(initialValue: ConfigStore.modifiersString(action.wrappedValue.modifiers))
    }

    var body: some View {
        let isKeystroke = action.type.lowercased() == "keystroke"

        HStack(spacing: 12) {
            Text(button)
                .monospaced()
                .frame(width: 140, alignment: .leading)

            Picker("", selection: typeBinding) {
                Text("Keystroke").tag("keystroke")
                Text("Wispr").tag("wispr")
                Text("No action").tag("noop")
            }
            .labelsHidden()
            .frame(width: 130)

            TextField("key", text: $keyText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                .disabled(!isKeystroke)

            TextField("modifiers", text: $modifiersText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .disabled(!isKeystroke)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onAppear(perform: syncFromAction)
        .onChange(of: action) { _, _ in syncFromAction() }
        .onChange(of: keyText) { _, newValue in
            guard isKeystroke else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            action.key = trimmed.isEmpty ? nil : trimmed
        }
        .onChange(of: modifiersText) { _, newValue in
            guard isKeystroke else { return }
            action.modifiers = ConfigStore.parseModifiers(newValue)
        }
    }

    private var typeBinding: Binding<String> {
        Binding(
            get: { action.type.lowercased() },
            set: { newType in
                let normalized = newType.lowercased()
                action.type = normalized
                if normalized != "keystroke" {
                    action.key = nil
                    action.modifiers = nil
                    keyText = ""
                    modifiersText = ""
                }
            }
        )
    }

    private func syncFromAction() {
        if action.type.lowercased() != "keystroke" {
            keyText = ""
            modifiersText = ""
            return
        }

        let desiredKey = action.key ?? ""
        if keyText != desiredKey {
            keyText = desiredKey
        }

        let desiredMods = ConfigStore.modifiersString(action.modifiers)
        if modifiersText != desiredMods {
            modifiersText = desiredMods
        }
    }
}
