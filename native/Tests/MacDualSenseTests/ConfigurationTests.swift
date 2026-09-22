import Foundation
import Testing
import Yams
@testable import MacDualSense

@Suite @MainActor
struct ConfigurationTests {
    private func store(_ yaml: String? = nil, focus: AppFocus? = nil) throws -> (ConfigStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("mappings.yaml")
        if let yaml { try yaml.write(to: file, atomically: true, encoding: .utf8) }
        return (ConfigStore(configURL: file, appFocus: focus, watch: false, automaticallySaves: false), folder)
    }

    @Test func legacyConfigAndFallback() throws {
        let focus = AppFocus(cacheTTLms: 0, frontmostApp: { ("Unknown", "org.example.unknown") })
        let (store, folder) = try store("mappings:\n  default:\n    cross: {type: keystroke, key: return}\n", focus: focus)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(store.lastLoadError == nil)
        #expect(store.resolve(button: "cross")?.key == "return")
        #expect(store.contexts["warp"]?.bundleIDs.count == 2)
    }

    @Test func customRoutingInvalidatesCacheAndPersists() throws {
        let focus = AppFocus(cacheTTLms: 100_000, frontmostApp: { ("Editor", "org.example.editor") })
        let (store, folder) = try store(focus: focus)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(store.currentFocusStatus().context == "default")
        try store.setContext(id: "editor", name: "Editor", bundleIDs: ["org.example.editor"])
        store.setAction(profile: "default", context: "editor", button: "cross", action: ActionDef(type: "keystroke", key: "k"))
        #expect(store.currentFocusStatus().context == "editor")
        #expect(store.resolve(button: "cross")?.key == "k")
        store.save()
        store.reload()
        #expect(store.contexts["editor"]?.name == "Editor")
        store.removeAssociations(context: "editor")
        #expect(store.currentFocusStatus().context == "default")
        #expect(store.action(profile: "default", context: "editor", button: "cross")?.key == "k")
    }

    @Test func rejectsDuplicateAssociations() throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: ContextError.self) { try store.setContext(id: "other", name: "Other", bundleIDs: ["com.google.Chrome"]) }
        #expect(store.contexts["other"] == nil)
    }

    @Test func malformedReloadKeepsLastGoodConfig() throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let previous = store.resolve(button: "cross")
        try "profiles: [broken".write(to: store.configFileURL, atomically: true, encoding: .utf8)
        store.reload()
        #expect(store.lastLoadError != nil)
        #expect(store.resolve(button: "cross") == previous)
    }

    @Test func profileCopyRetainsTrackpad() throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        store.setTrackpadMode(profile: "default", enabled: true)
        let name = try store.duplicateProfile(from: "default")
        #expect(store.trackpadModeEnabled(profile: name))
        try store.addProfile(name: "Work", cloneFrom: "default")
        #expect(store.trackpadModeEnabled(profile: "Work"))
    }

    @Test func disabledBindingDoesNotInherit() throws {
        let focus = AppFocus(cacheTTLms: 0, frontmostApp: { ("Chrome", "com.google.Chrome") })
        let (store, folder) = try store(focus: focus)
        defer { try? FileManager.default.removeItem(at: folder) }
        store.setAction(profile: "default", context: "chrome", button: "cross", action: ActionDef(type: "noop"))
        #expect(store.resolve(button: "cross")?.type == "noop")
        store.deleteAction(profile: "default", context: "chrome", button: "cross")
        #expect(store.resolve(button: "cross")?.key == "return")
    }

    @Test func emptyRegistryIsAuthoritative() throws {
        let (store, folder) = try store("version: 2\ncontexts: {}\n")
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(store.contexts.isEmpty)
    }

    @Test func invalidConfigurationIsNotOverwrittenAndCanRecover() throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let broken = "contexts: [broken"
        try broken.write(to: store.configFileURL, atomically: true, encoding: .utf8)
        store.reload()
        store.save()
        #expect(try String(contentsOf: store.configFileURL, encoding: .utf8) == broken)
        #expect(store.lastSaveError != nil)
        try "version: 2\ncontexts: {}\n".write(to: store.configFileURL, atomically: true, encoding: .utf8)
        store.reload()
        #expect(store.lastLoadError == nil)
        #expect(store.lastSaveError == nil)
        #expect(store.contexts.isEmpty)
    }

    @Test func unassociatedMappingsSurviveRegistryMigration() throws {
        let (store, folder) = try store("version: 2\nmappings:\n  custom:\n    cross: {type: keystroke, key: k}\n")
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(store.allContextIDs.contains("custom"))
        try store.setContext(id: "custom", name: "My editor", bundleIDs: ["org.example.editor"])
        store.save()
        store.reload()
        #expect(store.action(profile: "default", context: "custom", button: "cross")?.key == "k")
        store.removeAssociations(context: "custom")
        #expect(store.action(profile: "default", context: "custom", button: "cross")?.key == "k")
    }

    @Test func watcherAppliesAtomicAndInPlaceEdits() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("mappings.yaml")
        let focus = AppFocus(cacheTTLms: 100_000, frontmostApp: { ("Editor", "org.example.editor") })
        let store = ConfigStore(configURL: file, appFocus: focus, automaticallySaves: false)
        #expect(store.currentFocusStatus().context == "default")
        for atomic in [true, false, true] {
            let id = atomic ? "atomic" : "inplace"
            let yaml = "version: 2\ncontexts:\n  \(id):\n    name: Editor\n    bundle_ids: [org.example.editor]\n"
            try yaml.write(to: file, atomically: atomic, encoding: .utf8)
            for _ in 0..<40 {
                if store.currentFocusStatus().context == id { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(store.currentFocusStatus().context == id)
        }
    }
}
