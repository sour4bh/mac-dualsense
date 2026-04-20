import SwiftUI

struct ButtonBindingEditor: View {
    let button: String
    @Binding var action: ActionDef
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @State private var keyText: String
    @State private var modifiersText: String

    init(
        button: String,
        action: Binding<ActionDef>,
        onDelete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.button = button
        self._action = action
        self.onDelete = onDelete
        self.onDismiss = onDismiss
        _keyText = State(initialValue: action.wrappedValue.key ?? "")
        _modifiersText = State(initialValue: ConfigStore.modifiersString(action.wrappedValue.modifiers))
    }

    var body: some View {
        let isKeystroke = action.type.lowercased() == "keystroke"

        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Edit: \(button)")
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Action type
            HStack {
                Text("Action")
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: typeBinding) {
                    Text("Keystroke").tag("keystroke")
                    Text("Wispr").tag("wispr")
                    Text("No action").tag("noop")
                }
                .labelsHidden()
                .frame(width: 140)
            }

            // Key (only for keystroke)
            if isKeystroke {
                HStack {
                    Text("Key")
                        .frame(width: 80, alignment: .leading)
                    TextField("e.g. return, space, a", text: $keyText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }

                HStack {
                    Text("Modifiers")
                        .frame(width: 80, alignment: .leading)
                    TextField("e.g. cmd, shift, alt", text: $modifiersText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }

                Text("Separate modifiers with commas: cmd, shift, alt, ctrl, fn")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Actions
            HStack {
                Button(role: .destructive) {
                    onDelete()
                    onDismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Spacer()

                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
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
