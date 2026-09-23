import SwiftUI

struct ProfilesView: View {
    @ObservedObject var store: ConfigStore
    @State private var selected: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("One controller. Many ways to work.").font(.title2.bold())
                Text("Keep a set of shortcuts for every workflow.").foregroundStyle(.secondary)
            }.padding(24)
            List(store.profileNames(), id: \.self, selection: $selected) { name in
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up").foregroundStyle(.blue)
                    Text(name)
                    Spacer()
                    if name == store.activeProfileName() { Label("Active", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                }.padding(.vertical, 8).tag(name)
            }
            HStack {
                Button("Add", systemImage: "plus") {
                    guard let name = AppKitDialogs.promptText(title: "New profile", message: "Name", defaultValue: "") else { return }
                    perform { try store.addProfile(name: name, cloneFrom: selected); selected = name.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                Button("Duplicate") { perform { selected = try store.duplicateProfile(from: selected ?? store.activeProfileName()) } }
                Button("Rename") {
                    guard let selected, let name = AppKitDialogs.promptText(title: "Rename profile", message: "Name", defaultValue: selected) else { return }
                    perform { try store.renameProfile(old: selected, new: name); self.selected = name.trimmingCharacters(in: .whitespacesAndNewlines) }
                }.disabled(selected == nil)
                Button("Delete", role: .destructive) {
                    guard let selected, AppKitDialogs.confirm(title: "Delete profile?", message: "Delete “\(selected)” and its mappings?", okTitle: "Delete") else { return }
                    perform { try store.deleteProfile(selected); self.selected = store.activeProfileName() }
                }.disabled(selected == nil || store.profileNames().count == 1)
                Spacer()
                Button("Make active") { if let selected { store.setActiveProfile(selected) } }
                    .buttonStyle(.glassProminent).disabled(selected == nil || selected == store.activeProfileName())
            }.padding(20)
            Divider()
            if let selected {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Use DualSense touchpad as a trackpad", isOn: Binding(
                        get: { store.trackpadModeEnabled(profile: selected) },
                        set: { store.setTrackpadMode(profile: selected, enabled: $0) }
                    ))
                    Text("Move the pointer, scroll with two fingers, and click. This replaces the touchpad shortcut in this profile. Adjust sensitivity and the right-click modifier in Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
        }
        .onAppear { selected = selected ?? store.activeProfileName() }
        .onChange(of: store.profileNames()) { _, names in
            if let selected, !names.contains(selected) { self.selected = store.activeProfileName() }
        }
        .alert("Couldn’t update profile", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { self.error = error.localizedDescription }
    }
}
