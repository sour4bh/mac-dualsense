import SwiftUI

struct ControllerWorkspaceView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var store: ConfigStore
    @ObservedObject private var controller: ControllerManager
    @ObservedObject private var selection: WorkspaceSelection
    @Environment(\.colorScheme) private var colorScheme
    @State private var side: ControllerViewSide = .front

    init(appState: AppState) {
        self.appState = appState
        store = appState.configStore
        controller = appState.controllerManager
        selection = appState.workspaceSelection
    }

    private var profile: String { store.activeProfileName() }
    private var type: ControllerType {
        ControllerType.detect(name: controller.activeController?.name, vendor: controller.activeController?.vendor)
    }
    private var buttons: [String] {
        Set(DualSenseButtonProvider().buttons.keys).union(store.buttons(forProfile: profile, context: selection.editedContext)).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Picker("Profile", selection: Binding(get: { profile }, set: { store.setActiveProfile($0) })) {
                    ForEach(store.profileNames(), id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu).id(colorScheme).labelsHidden().help("Editing profile").frame(minWidth: 100)
                Picker("App", selection: $selection.editedContext) {
                    ForEach(store.contextKeys(forProfile: profile), id: \.self) { Text(store.contextLabel($0)).tag($0) }
                }
                .pickerStyle(.menu).id(colorScheme).labelsHidden().help("Editing app context").frame(minWidth: 100)
                Button { selection.isLearningButton.toggle() } label: {
                    Label(selection.isLearningButton ? "Listening…" : "Learn button", systemImage: "hand.tap")
                        .labelStyle(.iconOnly)
                }
                .help("Select a controller button without sending its shortcut")
            }
            .padding(20)
            Divider()
            if selection.section == .keybinds || !type.supportsVisualEditor {
                List(buttons, id: \.self, selection: $selection.selectedButton) { button in
                    HStack {
                        Text(button.replacingOccurrences(of: "_", with: " ").capitalized)
                        Spacer()
                        Text(bindingLabel(button)).foregroundStyle(.secondary).fontDesign(.monospaced)
                    }
                    .padding(.vertical, 5)
                    .tag(button)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Your controller. Your shortcuts.").font(.title2.bold())
                                Text("Select a button to make it yours.").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("Controller view", selection: $side) {
                                Text("Front").tag(ControllerViewSide.front)
                                Text("Back").tag(ControllerViewSide.back)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 132)
                        }
                        ControllerVisualView(
                            controllerType: type, viewSide: side, pressed: controller.pressed,
                            selectedButton: selection.selectedButton,
                            getAction: { store.action(profile: profile, context: selection.editedContext, button: $0) },
                            onSelectButton: { selection.selectedButton = $0 }
                        )
                        .aspectRatio(side == .front ? 590.0 / 410 : 590.0 / 305, contentMode: .fit)
                        .frame(maxHeight: 410)
                        HStack {
                            Image(systemName: "cursorarrow.click")
                            Text(selection.selectedButton.map { "\($0.replacingOccurrences(of: "_", with: " ").capitalized) · \(bindingLabel($0))" } ?? "Click a button, or use Learn button above.")
                        }
                        .font(.callout).foregroundStyle(.secondary)
                        if controller.activeController == nil {
                            Label("Connect a controller with USB or Bluetooth to try your mappings. You can edit without one.", systemImage: "cable.connector")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding(24)
                }
            }
            Divider()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack {
                    Label(controller.activeController?.name ?? "No controller", systemImage: "gamecontroller").lineLimit(1)
                    Spacer()
                    Text("Live: \(store.currentFocusStatus().appName ?? "None")").lineLimit(1)
                    if !store.accessibilityPermissionGranted() {
                        Button("Enable Accessibility") { store.ensureAccessibilityPermission() }
                    }
                }
                .font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
        .background(.background)
        .onChange(of: selection.selectedButton) { _, button in
            if button != nil { selection.inspectorVisible = true }
        }
        .onChange(of: controller.lastEvent?.id) { _, _ in
            guard selection.isLearningButton, let event = controller.lastEvent, event.state == "Pressed" else { return }
            selection.selectedButton = event.button
            selection.isLearningButton = false
        }
        .onChange(of: store.config.contexts) { _, _ in validateContext() }
        .onChange(of: profile) { _, _ in validateContext() }
        .onAppear { validateContext() }
        .onDisappear { selection.isLearningButton = false; selection.isRecordingShortcut = false }
    }

    private func validateContext() {
        selection.ensureValidContext(store.contextKeys(forProfile: profile), fallback: "default")
    }

    private func bindingLabel(_ button: String) -> String {
        if let action = store.action(profile: profile, context: selection.editedContext, button: button) {
            return ActionFormatter.format(action)
        }
        let fallback = store.action(profile: profile, context: "default", button: button)
        return fallback.map { "Global · \(ActionFormatter.format($0))" } ?? "Unassigned"
    }
}
