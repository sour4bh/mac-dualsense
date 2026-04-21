import SwiftUI

struct ButtonBindingEditor: View {
    let button: String
    @Binding var action: ActionDef
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @FocusState private var isCapturing: Bool

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
    }

    var body: some View {
        let type = action.type.lowercased()
        let isKeystroke = type == "keystroke"
        let isWispr = type == "wispr"

        VStack(alignment: .leading, spacing: 16) {
            header

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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Shortcut")
                            .font(.subheadline.weight(.medium))
                        captureArea
                        if let warning = invalidKeyWarning {
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text("Click the box above and press any key combination.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Modifiers")
                            .font(.subheadline.weight(.medium))
                        modifierChips
                    }
                }
            }

            previewRow

            if isWispr {
                Text("Configure Wispr trigger in Settings → Wispr.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Button(role: .destructive) {
                        onDelete()
                        onDismiss()
                    } label: {
                        Label("Unbind", systemImage: "trash")
                    }
                    Text("Removes this binding so the button does nothing.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
        .frame(width: 380)
        .onAppear {
            if action.type.lowercased() == "noop" {
                action.type = "keystroke"
            }
            if action.type.lowercased() == "keystroke" {
                isCapturing = true
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
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
            .keyboardShortcut(.cancelAction)
        }
    }

    private var captureArea: some View {
        let display = captureDisplay
        return HStack {
            Text(display.text)
                .font(.system(size: 15, weight: display.isPlaceholder ? .regular : .semibold, design: .monospaced))
                .foregroundStyle(display.isPlaceholder ? .secondary : .primary)
            Spacer()
            if isCapturing {
                Text("Recording…")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isCapturing ? Color.accentColor : Color.primary.opacity(0.15),
                    lineWidth: isCapturing ? 2 : 1
                )
        )
        .focusable(true)
        .focused($isCapturing)
        .onTapGesture {
            isCapturing = true
        }
        .onKeyPress(phases: .down) { keyPress in
            handleKeyPress(keyPress)
        }
    }

    private var modifierChips: some View {
        HStack(spacing: 8) {
            ForEach(Self.chipOrder, id: \.canonical) { chip in
                ModifierChip(
                    label: chip.symbol,
                    isOn: modifierBinding(for: chip.canonical)
                )
            }
            Spacer()
        }
    }

    private var previewRow: some View {
        HStack {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            PreviewPill(text: previewText, isMuted: action.type.lowercased() == "noop" || previewIsPlaceholder)
        }
    }

    // MARK: - Derived state

    private struct CaptureDisplay {
        let text: String
        let isPlaceholder: Bool
    }

    private var captureDisplay: CaptureDisplay {
        let key = (action.key ?? "").trimmingCharacters(in: .whitespaces)
        if key.isEmpty {
            return CaptureDisplay(text: "Press a key…", isPlaceholder: true)
        }
        return CaptureDisplay(text: key, isPlaceholder: false)
    }

    private var previewText: String {
        switch action.type.lowercased() {
        case "noop":
            return "Unbound"
        case "wispr":
            return "🎤 Wispr"
        default:
            let formatted = ActionFormatter.formatKeystroke(key: action.key, modifiers: action.modifiers)
            if formatted == "Click to bind" {
                let mods = action.modifiers ?? []
                if mods.isEmpty {
                    return "Set a key"
                }
                let modSymbols = mods.map { modSymbol(for: $0) }.joined()
                return "\(modSymbols)…"
            }
            return formatted
        }
    }

    private var previewIsPlaceholder: Bool {
        let key = (action.key ?? "").trimmingCharacters(in: .whitespaces)
        return action.type.lowercased() == "keystroke" && key.isEmpty
    }

    private var invalidKeyWarning: String? {
        guard action.type.lowercased() == "keystroke" else { return nil }
        let key = (action.key ?? "").trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        if KeySender.keyCode(for: key) == nil {
            return "⚠ Unknown key '\(key)'"
        }
        return nil
    }

    // MARK: - Bindings

    private var typeBinding: Binding<String> {
        Binding(
            get: { action.type.lowercased() },
            set: { newType in
                let normalized = newType.lowercased()
                action.type = normalized
                if normalized != "keystroke" {
                    action.key = nil
                    action.modifiers = nil
                    isCapturing = false
                } else {
                    isCapturing = true
                }
            }
        )
    }

    private func modifierBinding(for canonical: String) -> Binding<Bool> {
        Binding(
            get: { (action.modifiers ?? []).contains(canonical) },
            set: { isOn in
                var set = Set(action.modifiers ?? [])
                if isOn { set.insert(canonical) } else { set.remove(canonical) }
                let ordered = Self.chipOrder
                    .map(\.canonical)
                    .filter { set.contains($0) }
                action.modifiers = ordered.isEmpty ? nil : ordered
            }
        )
    }

    // MARK: - Key capture

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard action.type.lowercased() == "keystroke" else { return .ignored }

        // Ignore solo modifier presses — wait for a real key.
        if let name = Self.keyName(for: keyPress) {
            action.key = name
            action.modifiers = canonicalModifiers(from: keyPress.modifiers)
            return .handled
        }
        return .ignored
    }

    private func canonicalModifiers(from eventMods: EventModifiers) -> [String]? {
        var set: Set<String> = []
        if eventMods.contains(.control) { set.insert("ctrl") }
        if eventMods.contains(.option) { set.insert("alt") }
        if eventMods.contains(.shift) { set.insert("shift") }
        if eventMods.contains(.command) { set.insert("cmd") }
        let ordered = Self.chipOrder
            .map(\.canonical)
            .filter { set.contains($0) }
        return ordered.isEmpty ? nil : ordered
    }

    private static func keyName(for keyPress: KeyPress) -> String? {
        switch keyPress.key {
        case .return: return "return"
        case .space: return "space"
        case .tab: return "tab"
        case .escape: return "escape"
        case .delete, .deleteForward: return keyPress.key == .deleteForward ? "forward_delete" : "backspace"
        case .upArrow: return "up"
        case .downArrow: return "down"
        case .leftArrow: return "left"
        case .rightArrow: return "right"
        case .home: return "home"
        case .end: return "end"
        case .pageUp: return "pageup"
        case .pageDown: return "pagedown"
        case .clear: return "help"
        default: break
        }

        let chars = keyPress.characters
        let trimmed = chars.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 1 {
            return trimmed.lowercased()
        }
        if !trimmed.isEmpty {
            return trimmed.lowercased()
        }
        return nil
    }

    private func modSymbol(for canonical: String) -> String {
        switch canonical {
        case "cmd": return "⌘"
        case "shift": return "⇧"
        case "alt": return "⌥"
        case "ctrl": return "⌃"
        case "fn": return "fn"
        default: return canonical
        }
    }

    // MARK: - Static config

    private struct ChipSpec {
        let canonical: String
        let symbol: String
    }

    private static let chipOrder: [ChipSpec] = [
        .init(canonical: "ctrl", symbol: "⌃"),
        .init(canonical: "alt", symbol: "⌥"),
        .init(canonical: "shift", symbol: "⇧"),
        .init(canonical: "cmd", symbol: "⌘"),
        .init(canonical: "fn", symbol: "fn"),
    ]

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
}

// MARK: - Modifier Chip

private struct ModifierChip: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 28)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .background(
                    Capsule().fill(isOn ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                )
                .overlay(
                    Capsule().strokeBorder(
                        isOn ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.15),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview Pill

private struct PreviewPill: View {
    let text: String
    let isMuted: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isMuted ? Color.secondary : Color.primary)
            .background(
                Capsule().fill(Color.primary.opacity(isMuted ? 0.04 : 0.08))
            )
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }
}
