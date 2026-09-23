import AppKit
import Darwin
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

    @Published private(set) var config: Config = .init()
    @Published private(set) var lastLoadError: String? = nil
    @Published private(set) var lastSaveError: String? = nil
    @Published private(set) var lastLoadedAt: Date? = nil
    @Published private(set) var lastSavedAt: Date? = nil

    private let appSupportDir: URL
    private let configURL: URL
    private let appFocus: AppFocus
    private let automaticallySaves: Bool
    var onRoutingChange: (() -> Void)?
    var onControllerPreferenceChange: (() -> Void)?
    private var pendingSave: DispatchWorkItem?
    private var pendingReload: DispatchWorkItem?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var configWatcher: DispatchSourceFileSystemObject?

    init(configURL: URL? = nil, appFocus: AppFocus? = nil, watch: Bool = true, automaticallySaves: Bool = true) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.configURL = configURL ?? base.appendingPathComponent("mac-dualsense/mappings.yaml")
        appSupportDir = self.configURL.deletingLastPathComponent()
        self.appFocus = appFocus ?? AppFocus(cacheTTLms: 100)
        self.automaticallySaves = automaticallySaves
        loadOrSeed()
        if watch { startWatchingConfig() }
    }

    isolated deinit {
        configWatcher?.cancel()
        fileWatcher?.cancel()
        pendingSave?.cancel()
        pendingReload?.cancel()
    }

    var configFileURL: URL { configURL }

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
            let loaded = try decoder.decode(Config.self, from: yaml)
            try AppContext.validate(loaded.contexts ?? AppContext.defaults)
            pendingSave?.cancel()
            onRoutingChange?()
            config = loaded
            normalize()
            appFocus.contexts = contexts
            appFocus.cacheTTLms = config.settings.appFocusCacheTtlMs ?? 100
            onControllerPreferenceChange?()
            lastLoadError = nil
            lastSaveError = nil
            lastLoadedAt = Date()
            Logger.shared.info("Reloaded config from \(configURL.path)")
        } catch {
            lastLoadError = error.localizedDescription
            Logger.shared.error("Failed to reload config: \(error.localizedDescription)")
            // Keep last-good config but avoid crashing the app.
        }
    }

    func save() {
        guard lastLoadError == nil else {
            lastSaveError = "Fix the configuration error and reload before saving. Your file has been preserved."
            return
        }
        do {
            pendingSave?.cancel()
            pendingSave = nil
            config.contexts = contexts
            let encoder = YAMLEncoder()
            let yaml = try encoder.encode(config)
            try yaml.write(to: configURL, atomically: true, encoding: .utf8)
            lastSaveError = nil
            lastSavedAt = Date()
            Logger.shared.info("Saved config to \(configURL.path)")
        } catch {
            lastSaveError = error.localizedDescription
            Logger.shared.error("Failed to save config: \(error.localizedDescription)")
        }
    }

    func autosave(after delaySeconds: TimeInterval = 0.25) {
        guard automaticallySaves else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.save()
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds, execute: work)
    }

    func openConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
    }

    func openSupportFolderInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([appSupportDir])
    }

    func resolve(button: String) -> ActionDef? {
        let context = appFocus.context()
        let profileName = config.profiles.active
        guard let profile = config.profiles.items[profileName] else { return nil }
        if let action = profile.mappings[context]?[button] {
            return action
        }
        return profile.mappings["default"]?[button]
    }

    var contexts: [String: AppContext] { config.contexts ?? AppContext.defaults }

    var allContextIDs: [String] {
        let mappings = config.profiles.items.values.flatMap { $0.mappings.keys }
        return Set(contexts.keys).union(mappings).subtracting(["default"]).sorted()
    }

    func setContext(id: String, name: String, bundleIDs: [String]) throws {
        var updated = contexts
        updated[id] = AppContext(name: name.trimmingCharacters(in: .whitespacesAndNewlines), bundleIDs: bundleIDs)
        try AppContext.validate(updated)
        onRoutingChange?()
        config.contexts = updated
        appFocus.contexts = updated
        autosave()
    }

    func removeAssociations(context id: String) {
        guard var context = contexts[id] else { return }
        context.bundleIDs = []
        config.contexts = contexts
        config.contexts?[id] = context
        onRoutingChange?()
        appFocus.contexts = contexts
        autosave()
    }

    func updateSettings(_ update: (inout Settings) -> Void) {
        onRoutingChange?()
        update(&config.settings)
        autosave()
    }

    func setHapticsEnabled(_ enabled: Bool) {
        config.haptics = config.haptics ?? .init()
        config.haptics?.enabled = enabled
        autosave()
    }

    func profileNames() -> [String] {
        Array(config.profiles.items.keys).sorted()
    }

    func activeProfileName() -> String {
        config.profiles.active
    }

    func setActiveProfile(_ name: String) {
        guard config.profiles.items[name] != nil else { return }
        onRoutingChange?()
        config.profiles.active = name
        autosave()
    }

    func addProfile(name: String, cloneFrom: String? = nil) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.invalidName }
        guard config.profiles.items[trimmed] == nil else { throw StoreError.alreadyExists }

        let sourceName = cloneFrom ?? config.profiles.active
        config.profiles.items[trimmed] = config.profiles.items[sourceName] ?? ProfileItem()
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
        config.profiles.items[candidate] = src
        autosave()
        return candidate
    }

    func renameProfile(old: String, new: String) throws {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.invalidName }
        guard config.profiles.items[old] != nil else { throw StoreError.notFound }
        guard config.profiles.items[trimmed] == nil else { throw StoreError.alreadyExists }

        onRoutingChange?()
        config.profiles.items[trimmed] = config.profiles.items.removeValue(forKey: old)
        if config.profiles.active == old {
            config.profiles.active = trimmed
        }
        autosave()
    }

    func deleteProfile(_ name: String) throws {
        guard config.profiles.items[name] != nil else { return }
        guard config.profiles.items.count > 1 else { throw StoreError.cannotDeleteLast }
        onRoutingChange?()
        config.profiles.items.removeValue(forKey: name)
        if config.profiles.active == name {
            config.profiles.active = profileNames().first ?? "default"
        }
        autosave()
    }

    func contextKeys(forProfile profile: String) -> [String] {
        let base = Set(contexts.keys)
        let existingKeys = config.profiles.items[profile]?.mappings.keys.map { $0 } ?? []
        let existing = Set(existingKeys)
        var all = base.union(existing)
        all.insert("default")
        return ["default"] + all.subtracting(["default"]).sorted()
    }

    func contextLabel(_ context: String) -> String {
        if let match = contexts[context] { return match.name }
        if context == "default" { return "Global" }
        return context.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func buttons(forProfile profile: String, context: String) -> [String] {
        let map = config.profiles.items[profile]?.mappings[context] ?? [:]
        return map.keys.sorted()
    }

    func action(profile: String, context: String, button: String) -> ActionDef? {
        config.profiles.items[profile]?.mappings[context]?[button]
    }

    func setAction(profile: String, context: String, button: String, action: ActionDef) {
        guard !button.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        onRoutingChange?()
        var profileItem = config.profiles.items[profile] ?? ProfileItem()
        var ctx = profileItem.mappings[context] ?? [:]
        ctx[button] = action
        profileItem.mappings[context] = ctx
        config.profiles.items[profile] = profileItem
        autosave()
    }

    func deleteAction(profile: String, context: String, button: String) {
        guard var profileItem = config.profiles.items[profile] else { return }
        onRoutingChange?()
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
        onControllerPreferenceChange?()
        autosave()
    }

    func wisprSettings() -> WisprSettings {
        config.settings.wispr ?? .init()
    }

    func trackpadSettings() -> TrackpadSettings {
        config.settings.trackpad ?? .init()
    }

    func trackpadModeEnabled(profile: String) -> Bool {
        config.profiles.items[profile]?.trackpadMode ?? false
    }

    func currentTrackpadMode() -> Bool {
        trackpadModeEnabled(profile: config.profiles.active)
    }

    func setTrackpadMode(profile: String, enabled: Bool) {
        onRoutingChange?()
        var profileItem = config.profiles.items[profile] ?? ProfileItem()
        profileItem.trackpadMode = enabled ? true : nil
        config.profiles.items[profile] = profileItem
        autosave()
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

    func accessibilityPermissionGranted() -> Bool {
        AXIsProcessTrusted()
    }

    func currentFocusStatus() -> AppFocus.Status {
        appFocus.status()
    }

    private func startWatchingConfig() {
        let fd = open(appSupportDir.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib, .link, .revoke],
            queue: DispatchQueue.main
        )

        watcher.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleReloadFromDisk()
            }
        }
        watcher.setCancelHandler {
            close(fd)
        }

        configWatcher = watcher
        watcher.resume()
        watchConfigFile()
    }

    private func watchConfigFile() {
        fileWatcher?.cancel()
        let fd = open(configURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        watcher.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReloadFromDisk() }
        }
        watcher.setCancelHandler { close(fd) }
        fileWatcher = watcher
        watcher.resume()
    }

    private func scheduleReloadFromDisk(after delaySeconds: TimeInterval = 0.15) {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.reload()
                self?.watchConfigFile()
            }
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds, execute: work)
    }

    private func normalize() {
        // Upgrade legacy schema if present.
        if let legacy = config.mappings, !legacy.isEmpty {
            let profileDefault = config.profiles.items["default"]?.mappings["default"] ?? [:]
            let looksEmpty = config.profiles.items.count == 1 && profileDefault.isEmpty
            if looksEmpty {
                config.profiles.items["default"] = ProfileItem(mappings: legacy)
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
