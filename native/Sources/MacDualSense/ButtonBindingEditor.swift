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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Binding")
                        .font(.headline)
                    StatusPill(text: button, color: .blue)
                }
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            editorCard {
                LabeledContent("Action") {
                    Picker("", selection: typeBinding) {
                        Text("Keystroke").tag("keystroke")
                        Text("Wispr").tag("wispr")
                        Text("No action").tag("noop")
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            if isKeystroke {
                editorCard {
                    LabeledContent("Key") {
                        TextField("e.g. return, space, a", text: $keyText)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                    }

                    LabeledContent("Modifiers") {
                        TextField("e.g. cmd, shift, alt", text: $modifiersText)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                    }

                    Text("Separate modifiers with commas: cmd, shift, alt, ctrl, fn")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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
                .buttonStyle(.glassProminent)
            }
        }
        .padding(18)
        .frame(width: 360)
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

    @ViewBuilder
    private func editorCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
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
