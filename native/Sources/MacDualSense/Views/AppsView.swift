import SwiftUI
import UniformTypeIdentifiers

struct AppsView: View {
    @ObservedObject var store: ConfigStore
    @State private var selected: String?
    @State private var editor: ContextDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("A different shortcut for every app.").font(.title2.bold())
                Text("App associations apply to every profile. Each profile keeps its own button mappings.")
                    .foregroundStyle(.secondary)
            }.padding(24)
            List(selection: $selected) {
                ForEach(store.allContextIDs, id: \.self) { id in
                    HStack(spacing: 12) {
                        Image(systemName: "app.dashed").font(.title2).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.contextLabel(id)).font(.headline)
                            Text(store.contexts[id]?.bundleIDs.joined(separator: ", ").nilIfEmpty ?? "No apps associated · mappings preserved")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { edit(id) }
                            .accessibilityLabel("Edit \(store.contextLabel(id)) app context")
                    }
                    .padding(.vertical, 8).tag(id)
                    .contextMenu {
                        Button("Edit association") { edit(id) }
                        Button("Remove app associations") { store.removeAssociations(context: id) }
                    }
                }
            }
            HStack {
                Button { editor = ContextDraft() } label: { Label("Add app context", systemImage: "plus") }
                Spacer()
                Text("Other apps use Global mappings.").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
        .sheet(item: $editor) { draft in ContextEditor(store: store, draft: draft) }
    }

    private func edit(_ id: String) {
        editor = ContextDraft(id: id, name: store.contextLabel(id), bundleIDs: store.contexts[id]?.bundleIDs ?? [], isNew: false)
    }
}

struct ContextDraft: Identifiable {
    var id = UUID().uuidString.lowercased()
    var name = ""
    var bundleIDs: [String] = []
    var isNew = true
}

private struct ContextEditor: View {
    @ObservedObject var store: ConfigStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ContextDraft
    @State private var bundleText: String
    @State private var error: String?

    init(store: ConfigStore, draft: ContextDraft) {
        self.store = store
        _draft = State(initialValue: draft)
        _bundleText = State(initialValue: draft.bundleIDs.joined(separator: "\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(draft.isNew ? "Add app context" : "Edit app context").font(.title2.bold())
            TextField("Display name", text: $draft.name)
            Button("Choose an app…", systemImage: "folder") { chooseApp() }
            VStack(alignment: .leading, spacing: 8) {
                Text("Bundle IDs").font(.headline)
                Text("One per line. Choose an app above or enter its bundle ID manually.").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $bundleText).font(.body.monospaced()).frame(height: 100)
                    .border(.quaternary).accessibilityLabel("App bundle IDs")
            }
            Text("Removing an app association keeps its button mappings. An empty list leaves this context unassigned.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    do {
                        try store.setContext(id: draft.id, name: draft.name, bundleIDs: bundleText.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.glassProminent)
            }
        }
        .padding(28).frame(width: 460)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            error = "This app has no bundle identifier. Enter its bundle ID manually."
            return
        }
        if draft.name.isEmpty { draft.name = url.deletingPathExtension().lastPathComponent }
        bundleText += bundleText.isEmpty ? id : "\n" + id
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
