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
}

struct SettingsRootView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        PreferencesView(appState: appState)
            .frame(minWidth: 920, minHeight: 640)
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
    @AppStorage("settings.selection") private var storedSelection = PreferencesSection.controller.rawValue

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                ForEach(PreferencesSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }
            }
            .listStyle(.sidebar)
        } detail: {
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
        .frame(minWidth: 860, minHeight: 560)
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

    @State private var editingButton: String? = nil

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

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Controller")
                        .font(.largeTitle.weight(.semibold))
                    Spacer()
                    Button("Save") {
                        configStore.save()
                    }
                    .keyboardShortcut("s", modifiers: [.command])
                }

                HStack(alignment: .firstTextBaseline, spacing: 16) {
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
                    .frame(maxWidth: 280)

                    Spacer(minLength: 0)
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(viewInstruction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(liveInputSummary)
                        .foregroundStyle(.secondary)
                        .monospaced()
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                ForEach(availableViews) { side in
                    VStack(alignment: .leading, spacing: 6) {
                        if availableViews.count > 1 {
                            Text(side.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
                        ControllerVisualView(
                            controllerType: controllerType,
                            viewSide: side,
                            pressed: controllerManager.pressed,
                            getAction: { configStore.resolve(button: $0) },
                            onEditButton: { button in
                                editingButton = button
                            }
                        )
                        .aspectRatio(aspectRatio(for: side), contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .popover(item: $editingButton) { button in
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
                onDismiss: {
                    editingButton = nil
                }
            )
        }
    }

    private var liveInputSummary: String {
        let down = controllerManager.pressed.sorted().joined(separator: ", ")
        if let last = controllerManager.lastEvent?.button {
            return "Last: \(last)  •  Down: \(down.isEmpty ? "—" : down)"
        }
        return "—"
    }

    private func aspectRatio(for side: ControllerViewSide) -> CGFloat {
        if let box = controllerType.viewBox(for: side), box.height > 0 {
            return box.width / box.height
        }
        return 590.0 / 410.0
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

struct ProfilesPreferencesView: View {
    @ObservedObject var appState: AppState
    @State private var selectedProfile: String? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        let store = appState.configStore
        let profiles = store.profileNames()
        let active = store.activeProfileName()

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Profiles")
                    .font(.largeTitle.weight(.semibold))
                Spacer()

                Button("Open Config") { store.openConfigInFinder() }
                Button("Reload") { store.reload() }
                Button("Save") { store.save() }
                    .keyboardShortcut("s", modifiers: [.command])
            }

            Picker("Active profile", selection: Binding(
                get: { store.activeProfileName() },
                set: { store.setActiveProfile($0) }
            )) {
                ForEach(profiles, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .frame(maxWidth: 420)

            List(selection: $selectedProfile) {
                ForEach(profiles, id: \.self) { name in
                    HStack(spacing: 8) {
                        Text(name)
                        Spacer()
                        if name == active {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(name as String?)
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
                .disabled(selectedProfile == nil || selectedProfile == active)
            }
        }
        .padding(20)
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
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Diagnostics")
                                .font(.largeTitle.weight(.semibold))
                            Text("Runtime state, permissions, config health, and recent controller activity.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reload Config") { store.reload() }
                        Button("Reveal Logs") { Logger.shared.revealLogFileInFinder() }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
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
                    } label: {
                        Label("Runtime", systemImage: "gauge.with.needle")
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            DiagnosticsValueRow(title: "Frontmost app", value: focus.appName ?? "—")
                            DiagnosticsValueRow(title: "Bundle ID", value: focus.bundleID ?? "—", monospaced: true)
                            DiagnosticsValueRow(
                                title: "Resolved context",
                                value: "\(store.contextLabel(focus.context)) (\(focus.context))"
                            )
                        }
                    } label: {
                        Label("App Focus", systemImage: "app.badge")
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
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
                    } label: {
                        Label("Files & Permissions", systemImage: "folder.badge.gearshape")
                    }

                    GroupBox {
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
                    } label: {
                        Label("Recent Events", systemImage: "waveform.path.ecg")
                    }
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
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

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Keybinds")
                    .font(.largeTitle.weight(.semibold))
                Spacer()

                Button("Open Config") { store.openConfigInFinder() }
                Button("Reload") { store.reload() }
                Button("Save") { store.save() }
                    .keyboardShortcut("s", modifiers: [.command])
            }

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

            if learnNextButton {
                Text("Press a controller button to select / create a mapping.")
                    .foregroundStyle(.secondary)
            }

            List(selection: $selectedButton) {
                ForEach(buttons, id: \.self) { button in
                    KeybindRow(
                        button: button,
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
                        onDelete: {
                            store.deleteAction(profile: editingProfile, context: editingContext, button: button)
                            if selectedButton == button {
                                selectedButton = nil
                            }
                        }
                    )
                    .tag(button as String?)
                }
            }
        }
        .padding(20)
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

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct KeybindRow: View {
    let button: String
    @Binding var action: ActionDef
    let onDelete: () -> Void

    @State private var keyText: String
    @State private var modifiersText: String

    init(
        button: String,
        action: Binding<ActionDef>,
        onDelete: @escaping () -> Void
    ) {
        self.button = button
        self._action = action
        self.onDelete = onDelete
        _keyText = State(initialValue: action.wrappedValue.key ?? "")
        _modifiersText = State(initialValue: ConfigStore.modifiersString(action.wrappedValue.modifiers))
    }

    var body: some View {
        let isKeystroke = action.type.lowercased() == "keystroke"

        HStack(spacing: 12) {
            Text(button)
                .monospaced()
                .frame(width: 160, alignment: .leading)

            Picker("", selection: typeBinding) {
                Text("Keystroke").tag("keystroke")
                Text("Wispr").tag("wispr")
                Text("No action").tag("noop")
            }
            .labelsHidden()
            .frame(width: 140)

            TextField("key", text: $keyText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .disabled(!isKeystroke)

            TextField("modifiers", text: $modifiersText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .disabled(!isKeystroke)

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
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
