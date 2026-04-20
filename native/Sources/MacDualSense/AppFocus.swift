import AppKit
import Foundation

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

    // Bundle ID to context name mapping
    private let contexts: [String: String] = [
        "dev.warp.Warp-Stable": "warp",
        "dev.warp.Warp": "warp",
        "company.thebrowser.Browser": "arc",
        "com.google.Chrome": "chrome",
        "com.tinyspeck.slackmacgap": "slack",
        "com.openai.chat": "chatgpt",
        "com.anthropic.claudefordesktop": "claude",
    ]

    init(cacheTTLms: Int) {
        self.cacheTTLms = cacheTTLms
        ttl = Double(cacheTTLms) / 1000.0
    }

    func context() -> String {
        status().context
    }

    func status() -> Status {
        let now = Date().timeIntervalSinceReferenceDate
        if let cachedStatus, (now - lastRead) < ttl {
            return cachedStatus
        }

        let app = NSWorkspace.shared.frontmostApplication
        let status = Status(
            appName: app?.localizedName,
            bundleID: app?.bundleIdentifier,
            context: contexts[app?.bundleIdentifier ?? ""] ?? "default"
        )
        cachedStatus = status
        lastRead = now
        return status
    }
}
