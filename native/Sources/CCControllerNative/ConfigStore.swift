import AppKit
import Foundation
@preconcurrency import ApplicationServices
import Yams

@MainActor
final class ConfigStore: ObservableObject {
    enum StoreError: LocalizedError {
        case invalidName
        case alreadyExists
        case notFound
        case cannotDeleteLast

        var errorDescription: String? {
            switch self {
            case .invalidName:
                return "Name cannot be empty."
            case .alreadyExists:
                return "An item with that name already exists."
            case .notFound:
                return "Item not found."
            case .cannotDeleteLast:
                return "You can’t delete the last profile."
            }
        }
    }

    @Published private(set) var config: CCConfig = .init()

    private let appSupportDir: URL
    private let configURL: URL
    private let appFocus = AppFocus(cacheTTLms: 100)
    private var pendingSave: DispatchWorkItem?

    static let knownContexts: [(key: String, label: String)] = [
        ("default", "Global"),
        ("warp", "Warp"),
        ("arc", "Arc"),
        ("chrome", "Chrome"),
        ("slack", "Slack"),
        ("chatgpt", "ChatGPT"),
        ("claude", "Claude"),
    ]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportDir = base.appendingPathComponent("cc-controller", isDirectory: true)
        configURL = appSupportDir.appendingPathComponent("mappings.yaml", isDirectory: false)

        loadOrSeed()
    }

    func loadOrSeed() {
        do {
            try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        } catch {
            // best-effort
        }

        if !FileManager.default.fileExists(atPath: configURL.path) {
            seedDefaultConfig()
        }
        reload()
    }

    func reload() {
        do {
            let yaml = try String(contentsOf: configURL, encoding: .utf8)
            let decoder = YAMLDecoder()
            config = try decoder.decode(CCConfig.self, from: yaml)
            normalize()
            appFocus.cacheTTLms = config.settings.appFocusCacheTtlMs ?? 100
        } catch {
            // Keep last-good config but avoid crashing the app.
        }
    }

    func save() {
        do {
            pendingSave?.cancel()
            pendingSave = nil
            let encoder = YAMLEncoder()
            let yaml = try encoder.encode(config)
            try yaml.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            // best-effort
        }
    }

    func autosave(after delaySeconds: TimeInterval = 0.25) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.save()
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds, execute: work)
    }

    func openConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
    }

    func resolve(button: String) -> CCActionDef? {
        let context = appFocus.context()
        let profileName = config.profiles.active
        guard let profile = config.profiles.items[profileName] else { return nil }
        if let action = profile.mappings[context]?[button] {
            return action
        }
        return profile.mappings["default"]?[button]
    }

    func profileNames() -> [String] {
        Array(config.profiles.items.keys).sorted()
    }

    func activeProfileName() -> String {
        config.profiles.active
    }

    func setActiveProfile(_ name: String) {
        guard config.profiles.items[name] != nil else { return }
        config.profiles.active = name
        autosave()
    }

    func addProfile(name: String, cloneFrom: String? = nil) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.invalidName }
        guard config.profiles.items[trimmed] == nil else { throw StoreError.alreadyExists }

        let sourceName = cloneFrom ?? config.profiles.active
        let sourceMappings = config.profiles.items[sourceName]?.mappings ?? ["default": [:]]
        config.profiles.items[trimmed] = CCProfileItem(mappings: sourceMappings)
        autosave()
    }

    func duplicateProfile(from source: String) throws -> String {
        guard let src = config.profiles.items[source] else { throw StoreError.notFound }
        let existing = Set(config.profiles.items.keys)
        let base = "\(source) copy"
        var candidate = base
        var n = 2
        while existing.contains(candidate) {
            candidate = "\(base) \(n)"
            n += 1
        }
        config.profiles.items[candidate] = CCProfileItem(mappings: src.mappings)
        autosave()
        return candidate
    }

    func renameProfile(old: String, new: String) throws {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.invalidName }
        guard config.profiles.items[old] != nil else { throw StoreError.notFound }
        guard config.profiles.items[trimmed] == nil else { throw StoreError.alreadyExists }

        config.profiles.items[trimmed] = config.profiles.items.removeValue(forKey: old)
        if config.profiles.active == old {
            config.profiles.active = trimmed
        }
        autosave()
    }

    func deleteProfile(_ name: String) throws {
        guard config.profiles.items[name] != nil else { return }
        guard config.profiles.items.count > 1 else { throw StoreError.cannotDeleteLast }
        config.profiles.items.removeValue(forKey: name)
        if config.profiles.active == name {
            config.profiles.active = profileNames().first ?? "default"
        }
        autosave()
    }

    func contextKeys(forProfile profile: String) -> [String] {
        let base = Set(Self.knownContexts.map { $0.key })
        let existingKeys = config.profiles.items[profile]?.mappings.keys.map { $0 } ?? []
        let existing = Set(existingKeys)
        var all = base.union(existing)
        all.insert("default")
        return ["default"] + all.subtracting(["default"]).sorted()
    }

    func contextLabel(_ context: String) -> String {
        if let match = Self.knownContexts.first(where: { $0.key == context }) {
            return match.label
        }
        if context == "default" { return "Global" }
        return context.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func buttons(forProfile profile: String, context: String) -> [String] {
        let map = config.profiles.items[profile]?.mappings[context] ?? [:]
        return map.keys.sorted()
    }

    func action(profile: String, context: String, button: String) -> CCActionDef? {
        config.profiles.items[profile]?.mappings[context]?[button]
    }

    func setAction(profile: String, context: String, button: String, action: CCActionDef) {
        guard !button.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        var profileItem = config.profiles.items[profile] ?? CCProfileItem()
        var ctx = profileItem.mappings[context] ?? [:]
        ctx[button] = action
        profileItem.mappings[context] = ctx
        config.profiles.items[profile] = profileItem
        autosave()
    }

    func deleteAction(profile: String, context: String, button: String) {
        guard var profileItem = config.profiles.items[profile] else { return }
        var ctx = profileItem.mappings[context] ?? [:]
        ctx.removeValue(forKey: button)
        if ctx.isEmpty {
            profileItem.mappings.removeValue(forKey: context)
        } else {
            profileItem.mappings[context] = ctx
        }
        if profileItem.mappings.isEmpty {
            profileItem.mappings = ["default": [:]]
        } else if profileItem.mappings["default"] == nil {
            profileItem.mappings["default"] = [:]
        }
        config.profiles.items[profile] = profileItem
        autosave()
    }

    static func modifiersString(_ modifiers: [String]?) -> String {
        (modifiers ?? []).joined(separator: ", ")
    }

    static func parseModifiers(_ text: String) -> [String]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let separators = CharacterSet(charactersIn: ",+")
        let parts = trimmed
            .components(separatedBy: separators)
            .flatMap { $0.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return parts.isEmpty ? nil : parts
    }

    func preferredController() -> String {
        let pref = (config.settings.controller?.preferred ?? "auto").trimmingCharacters(in: .whitespacesAndNewlines)
        let norm = pref.lowercased()
        if ["auto", "dualsense", "pro_controller"].contains(norm) { return norm }
        return "auto"
    }

    func setPreferredController(_ value: String) {
        let norm = value.lowercased()
        config.settings.controller = config.settings.controller ?? .init()
        config.settings.controller?.preferred = ["auto", "dualsense", "pro_controller"].contains(norm) ? norm : "auto"
        autosave()
    }

    func wisprSettings() -> CCWisprSettings {
        config.settings.wispr ?? .init()
    }

    func hapticsEnabled() -> Bool {
        config.haptics?.enabled ?? true
    }

    func hapticPattern(_ name: String) -> CCHapticPattern? {
        config.haptics?.patterns?[name]
    }

    func ensureAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func normalize() {
        // Upgrade legacy schema if present.
        if let legacy = config.mappings, !legacy.isEmpty {
            let profileDefault = config.profiles.items["default"]?.mappings["default"] ?? [:]
            let looksEmpty = config.profiles.items.count == 1 && profileDefault.isEmpty
            if looksEmpty {
                config.profiles.items["default"] = CCProfileItem(mappings: legacy)
                config.profiles.active = "default"
                config.mappings = nil
            }
        }

        if config.profiles.items.isEmpty {
            config.profiles.items = ["default": .init()]
        }
        if config.profiles.items[config.profiles.active] == nil {
            config.profiles.active = profileNames().first ?? "default"
        }
    }

    private func seedDefaultConfig() {
        guard let resource = Bundle.module.url(forResource: "mappings", withExtension: "yaml") else {
            return
        }
        do {
            try FileManager.default.copyItem(at: resource, to: configURL)
        } catch {
            // best-effort
        }
    }
}
