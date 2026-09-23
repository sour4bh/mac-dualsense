import SwiftUI

struct BindingInspector: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var selection: WorkspaceSelection
    private var profile: String { store.activeProfileName() }

    var body: some View {
        ScrollView {
            if let button = selection.selectedButton {
                ButtonBindingEditor(button: button, action: Binding(
                    get: { store.action(profile: profile, context: selection.editedContext, button: button) ?? ActionDef(type: "inherit") },
                    set: { action in
                        if action.type == "inherit" {
                            store.deleteAction(profile: profile, context: selection.editedContext, button: button)
                        } else {
                            store.setAction(profile: profile, context: selection.editedContext, button: button, action: action)
                        }
                    }
                ), onDelete: {
                    store.deleteAction(profile: profile, context: selection.editedContext, button: button)
                }, onCaptureChange: { selection.isRecordingShortcut = $0 })
                .id(button + selection.editedContext + profile)
                if selection.editedContext != "default" {
                    Text("Global: \(ActionFormatter.format(store.action(profile: profile, context: "default", button: button)))")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }
            } else {
                ContentUnavailableView("Select a button", systemImage: "cursorarrow.click", description: Text("Choose a button on the controller or in Keybinds."))
            }
        }

    }
}
