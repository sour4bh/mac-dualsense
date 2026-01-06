import SwiftUI

enum PreferencesSection: Hashable {
    case controller
    case keybinds
    case profiles
}

struct PreferencesView: View {
    @ObservedObject var appState: AppState
    @State private var selection: PreferencesSection? = .controller

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink("Controller", value: PreferencesSection.controller)
                NavigationLink("Profiles", value: PreferencesSection.profiles)
                NavigationLink("Keybinds", value: PreferencesSection.keybinds)
            }
        } detail: {
            switch selection {
            case .controller:
                ControllerPreferencesView(appState: appState)
            case .profiles:
                ProfilesPreferencesView(appState: appState)
            case .keybinds:
                KeybindsPreferencesView(appState: appState)
            case .none:
                ControllerPreferencesView(appState: appState)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

struct ControllerPreferencesView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        let controllerManager = appState.controllerManager
        let configStore = appState.configStore

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Controller")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("Save") {
                    configStore.save()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }

            Form {
                Picker("Preferred controller", selection: Binding(
                    get: { configStore.preferredController() },
                    set: { configStore.setPreferredController($0) }
                )) {
                    Text("Auto").tag("auto")
                    Text("DualSense").tag("dualsense")
                    Text("Pro Controller").tag("pro_controller")
                }

                Picker("Active controller", selection: Binding(
                    get: { controllerManager.activeController?.id ?? "" },
                    set: { controllerManager.setActiveController(id: $0.isEmpty ? nil : $0) }
                )) {
                    Text("—").tag("")
                    ForEach(controllerManager.controllers) { c in
                        Text(c.vendor != nil ? "\(c.name) (\(c.vendor!))" : c.name).tag(c.id)
                    }
                }

                HStack {
                    Text("Live input")
                    Spacer()
                    Text(liveInputSummary(controllerManager))
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }

            Table(controllerManager.recentEvents) {
                TableColumn("Time") { e in
                    Text(timeString(e.time)).monospaced()
                }.width(90)
                TableColumn("State") { e in
                    Text(e.state)
                }.width(90)
                TableColumn("Button") { e in
                    Text(e.button).monospaced()
                }.width(160)
                TableColumn("Action") { e in
                    Text(e.action).monospaced()
                }
            }
        }
        .padding(20)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    private func liveInputSummary(_ manager: ControllerManager) -> String {
        let down = manager.pressed.sorted().joined(separator: ", ")
        if let last = manager.lastEvent?.button {
            return "Last: \(last)  •  Down: \(down.isEmpty ? "—" : down)"
        }
        return "—"
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

struct KeybindsPreferencesView: View {
    @ObservedObject var appState: AppState
    @State private var profile: String = ""
    @State private var context: String = "default"
    @State private var learnNextButton: Bool = false
    @State private var selectedButton: String? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        let store = appState.configStore
        let controller = appState.controllerManager

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
                    let action = CCActionDef(type: "keystroke", key: "return", modifiers: nil)
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
                                    ?? CCActionDef(type: "noop", key: nil, modifiers: nil)
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
        .onChange(of: profiles) { _ in
            if !profiles.contains(profile) {
                profile = active
            }
        }
        .onChange(of: controller.lastEvent?.id) { _ in
            guard learnNextButton, let event = controller.lastEvent, event.state == "Pressed" else { return }
            learnNextButton = false
            let btn = event.button

            if store.action(profile: editingProfile, context: editingContext, button: btn) == nil {
                let action = CCActionDef(type: "keystroke", key: "return", modifiers: nil)
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

private struct KeybindRow: View {
    let button: String
    @Binding var action: CCActionDef
    let onDelete: () -> Void

    @State private var keyText: String
    @State private var modifiersText: String

    init(
        button: String,
        action: Binding<CCActionDef>,
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
        .onChange(of: action) { _ in syncFromAction() }
        .onChange(of: keyText) { newValue in
            guard isKeystroke else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            action.key = trimmed.isEmpty ? nil : trimmed
        }
        .onChange(of: modifiersText) { newValue in
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
