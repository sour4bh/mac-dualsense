import AppKit
import Foundation

@MainActor
final class AppFocus {
    struct Status {
        let appName: String?
        let bundleID: String?
        let context: String
    }

    var cacheTTLms: Int {
        didSet { ttl = Double(cacheTTLms) / 1000.0 }
    }

    private var ttl: Double
    private var cachedStatus: Status?
    private var lastRead: TimeInterval = 0

    var contexts: [String: AppContext] = AppContext.defaults {
        didSet { cachedStatus = nil }
    }
    private let frontmostApp: () -> (name: String?, bundleID: String?)

    init(cacheTTLms: Int, frontmostApp: @escaping () -> (name: String?, bundleID: String?) = {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.localizedName, app?.bundleIdentifier)
    }) {
        self.cacheTTLms = cacheTTLms
        ttl = Double(cacheTTLms) / 1000.0
        self.frontmostApp = frontmostApp
    }

    func context() -> String {
        status().context
    }

    func status() -> Status {
        let now = Date().timeIntervalSinceReferenceDate
        if let cachedStatus, (now - lastRead) < ttl {
            return cachedStatus
        }

        let app = frontmostApp()
        let status = Status(
            appName: app.name,
            bundleID: app.bundleID,
            context: contexts.first { $0.value.bundleIDs.contains(app.bundleID ?? "") }?.key ?? "default"
        )
        cachedStatus = status
        lastRead = now
        return status
    }
}
