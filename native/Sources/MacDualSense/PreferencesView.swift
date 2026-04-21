import SwiftUI

enum PreferencesSection: String, CaseIterable, Hashable, Identifiable {
    case controller
    case keybinds
    case profiles
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controller:
            return "Controller"
        case .keybinds:
            return "Keybinds"
        case .profiles:
            return "Profiles"
        case .diagnostics:
            return "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .controller:
            return "gamecontroller"
        case .keybinds:
            return "keyboard"
        case .profiles:
            return "square.stack.3d.up"
        case .diagnostics:
            return "stethoscope"
        }
    }

    var detail: String {
        switch self {
        case .controller:
            return "Live routing and visual editor"
        case .keybinds:
            return "Profiles, contexts, and mappings"
        case .profiles:
            return "Manage mapping sets"
        case .diagnostics:
            return "Permissions, focus, and logs"
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        PreferencesView(appState: appState)
            .frame(minWidth: 820, minHeight: 520)
            .onAppear {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
            .onDisappear {
                NSApp.setActivationPolicy(.accessory)
            }
    }
}

struct PreferencesView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var configStore: ConfigStore
    @ObservedObject private var controllerManager: ControllerManager
    @AppStorage("settings.selection") private var storedSelection = PreferencesSection.controller.rawValue

    init(appState: AppState) {
        self.appState = appState
        self.configStore = appState.configStore
        self.controllerManager = appState.controllerManager
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                ForEach(PreferencesSection.allCases) { section in
                    NavigationLink(value: section) {
                        SettingsSidebarRow(section: section)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top, spacing: 0) {
                SettingsSidebarSummary(appState: appState)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 236, max: 280)
        } detail: {
            Group {
                switch selectedSection {
                case .controller:
                    ControllerPreferencesView(appState: appState)
                case .profiles:
                    ProfilesPreferencesView(appState: appState)
                case .keybinds:
                    KeybindsPreferencesView(appState: appState)
                case .diagnostics:
                    DiagnosticsPreferencesView(appState: appState)
                case .none:
                    ControllerPreferencesView(appState: appState)
                }
            }
            .navigationTitle(selectedSection?.title ?? "Settings")
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

    private var selectedSection: PreferencesSection? {
        PreferencesSection(rawValue: storedSelection) ?? .controller
    }

    private var selectionBinding: Binding<PreferencesSection?> {
        Binding(
            get: { selectedSection },
            set: { newValue in
                storedSelection = newValue?.rawValue ?? PreferencesSection.controller.rawValue
            }
        )
    }
}

struct ControllerPreferencesView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var controllerManager: ControllerManager
    @ObservedObject var configStore: ConfigStore

    init(appState: AppState) {
        self.appState = appState
        self.controllerManager = appState.controllerManager
        self.configStore = appState.configStore
    }

    private var controllerType: ControllerType {
        guard let active = controllerManager.activeController else { return .dualSense }
        return ControllerType.detect(name: active.name, vendor: active.vendor)
    }

    var body: some View {
        let activeProfile = configStore.activeProfileName()
        let context = "default"
        let availableViews = controllerType.availableViews
        let viewInstruction = controllerType.supportsVisualEditor
            ? "Click a button to edit its binding"
            : "Use the Keybinds tab to edit mappings for this controller."
        let pressedNow = controllerManager.pressed.sorted().joined(separator: ", ")
        let lastButton = controllerManager.lastEvent?.button ?? "—"

        SettingsPageScrollView(maxWidth: 900) {
            ControllerPageHeader(
                configStore: configStore,
                controllerManager: controllerManager,
                controllerType: controllerType,
                lastButton: lastButton,
                pressedNow: pressedNow,
                viewInstruction: viewInstruction
            )

            ForEach(availableViews) { side in
                SettingsSectionCard(
                    availableViews.count > 1 ? side.label : "Controller Map",
                    systemImage: side == .front ? "gamecontroller" : "rectangle.3.group"
                ) {
                    ControllerVisualView(
                        controllerType: controllerType,
                        viewSide: side,
                        pressed: controllerManager.pressed,
                        getAction: { configStore.resolve(button: $0) }
                    ) { button, dismiss in
                        ButtonBindingEditor(
                            button: button,
                            action: Binding(
                                get: {
                                    configStore.action(profile: activeProfile, context: context, button: button)
                                        ?? ActionDef(type: "noop", key: nil, modifiers: nil)
                                },
                                set: { updated in
                                    configStore.setAction(
                                        profile: activeProfile,
                                        context: context,
                                        button: button,
                                        action: updated
                                    )
                                }
                            ),
                            onDelete: {
                                configStore.deleteAction(profile: activeProfile, context: context, button: button)
                            },
                            onDismiss: dismiss
                        )
                    }
                    .aspectRatio(aspectRatio(for: side), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func aspectRatio(for side: ControllerViewSide) -> CGFloat {
        if let box = controllerType.viewBox(for: side), box.height > 0 {
            return box.width / box.height
        }
        return 590.0 / 410.0
    }

}

struct ProfilesPreferencesView: View {
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

struct DiagnosticsPreferencesView: View {
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

struct KeybindsPreferencesView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var store: ConfigStore
    @ObservedObject var controller: ControllerManager
    @State private var profile: String = ""
    @State private var context: String = "default"
    @State private var learnNextButton: Bool = false
    @State private var selectedButton: String? = nil
    @State private var errorMessage: String? = nil

    init(appState: AppState) {
        self.appState = appState
        self.store = appState.configStore
        self.controller = appState.controllerManager
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
                subtitle: "Edit mappings by profile and app context, or learn the next button from the controller."
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

                    Toggle("Learn next button", isOn: $learnNextButton)
                        .toggleStyle(.switch)
                }

                HStack(spacing: 8) {
                    StatusPill(text: editingProfile, color: .blue)
                    StatusPill(text: store.contextLabel(editingContext), color: .secondary)
                    if learnNextButton {
                        StatusPill(text: "Learning", color: .green)
                    }
                }

                if learnNextButton {
                    Text("Press a controller button to select or create a mapping.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        let action = ActionDef(type: "keystroke", key: "return", modifiers: nil)
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
                        description: Text("Add a button manually or enable learning and press a controller button.")
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
        .onChange(of: controller.lastEvent?.id) { _, _ in
            guard learnNextButton, let event = controller.lastEvent, event.state == "Pressed" else { return }
            learnNextButton = false
            let btn = event.button

            if store.action(profile: editingProfile, context: editingContext, button: btn) == nil {
                let action = ActionDef(type: "keystroke", key: "return", modifiers: nil)
                store.setAction(profile: editingProfile, context: editingContext, button: btn, action: action)
            }
            selectedButton = btn
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

private struct SettingsSidebarSummary: View {
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

private struct SettingsSidebarRow: View {
    let section: PreferencesSection

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

private struct ControllerPageHeader: View {
    @ObservedObject var configStore: ConfigStore
    @ObservedObject var controllerManager: ControllerManager
    let controllerType: ControllerType
    let lastButton: String
    let pressedNow: String
    let viewInstruction: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Picker("Preferred", selection: Binding(
                    get: { configStore.preferredController() },
                    set: { configStore.setPreferredController($0) }
                )) {
                    Text("Auto").tag("auto")
                    Text("DualSense").tag("dualsense")
                    Text("Pro Controller").tag("pro_controller")
                }
                .frame(maxWidth: 240)

                Picker("Active", selection: Binding(
                    get: { controllerManager.activeController?.id ?? "" },
                    set: { controllerManager.setActiveController(id: $0.isEmpty ? nil : $0) }
                )) {
                    Text("—").tag("")
                    ForEach(controllerManager.controllers) { c in
                        Text(c.vendor != nil ? "\(c.name) (\(c.vendor!))" : c.name).tag(c.id)
                    }
                }
                .frame(maxWidth: 340)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    StatusPill(text: controllerType.displayName, color: .secondary)
                    if controllerManager.activeController == nil {
                        StatusPill(text: "No Controller", color: .orange)
                    }
                }
            }

            HStack(spacing: 6) {
                Text(viewInstruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("Last:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(lastButton)
                    .font(.system(size: 12, design: .monospaced))
                if !pressedNow.isEmpty {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(pressedNow)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.bottom, 4)
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
