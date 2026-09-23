import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section("Controller") {
                Picker("Preferred controller", selection: Binding(get: { store.preferredController() }, set: { store.setPreferredController($0) })) {
                    Text("Automatic").tag("auto")
                    Text("DualSense").tag("dualsense")
                    Text("Pro Controller").tag("pro_controller")
                }
                Toggle("Haptic feedback", isOn: Binding(get: { store.hapticsEnabled() }, set: { store.setHapticsEnabled($0) }))
            }
            Section("Voice dictation") {
                Picker("Trigger", selection: Binding(get: { store.wisprSettings().mode ?? "rcmd_hold" }, set: { value in
                    store.updateSettings { $0.wispr = $0.wispr ?? .init(); $0.wispr?.mode = value }
                })) {
                    Text("Hold right Command").tag("rcmd_hold")
                    Text("Hold left Command").tag("lcmd_hold")
                    Text("Hold Fn").tag("fn_hold")
                    Text("Toggle right Command").tag("rcmd_toggle")
                    Text("Toggle left Command").tag("lcmd_toggle")
                    Text("Pulse right Command").tag("rcmd_pulse")
                    Text("Pulse left Command").tag("lcmd_pulse")
                    Text("Command + Right Arrow").tag("cmd_right")
                }
                Stepper("Pulse duration: \(store.wisprSettings().holdMs ?? 450) ms", value: Binding(get: { store.wisprSettings().holdMs ?? 450 }, set: { value in
                    store.updateSettings { $0.wispr = $0.wispr ?? .init(); $0.wispr?.holdMs = value }
                }), in: 50...3000, step: 50)
                Text("Match the shortcut configured in your dictation app. Wispr Flow is optional and installed separately.").font(.caption).foregroundStyle(.secondary)
            }
            Section("DualSense trackpad") {
                Slider(value: trackpad(\.cursorSensitivity, fallback: 900), in: 100...2400, step: 50) { Text("Pointer speed") }
                Slider(value: trackpad(\.scrollSensitivity, fallback: 40), in: 5...120, step: 5) { Text("Scroll speed") }
                Toggle("Natural scrolling", isOn: Binding(get: { store.trackpadSettings().naturalScroll ?? true }, set: { value in
                    store.updateSettings { $0.trackpad = $0.trackpad ?? .init(); $0.trackpad?.naturalScroll = value }
                }))
                Picker("Right-click modifier", selection: Binding(get: { store.trackpadSettings().rightClickModifier ?? "l2" }, set: { value in
                    store.updateSettings { $0.trackpad = $0.trackpad ?? .init(); $0.trackpad?.rightClickModifier = value }
                })) {
                    Text("None").tag("")
                    ForEach(["l1", "l2", "r1", "r2"], id: \.self) { Text($0.uppercased()).tag($0) }
                }
                Text("Enable trackpad mode for individual profiles in the Profiles section.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).frame(width: 520, height: 560)
    }

    private func trackpad(_ key: WritableKeyPath<TrackpadSettings, Double?>, fallback: Double) -> Binding<Double> {
        Binding(get: { store.trackpadSettings()[keyPath: key] ?? fallback }, set: { value in
            store.updateSettings { $0.trackpad = $0.trackpad ?? .init(); $0.trackpad?[keyPath: key] = value }
        })
    }
}
