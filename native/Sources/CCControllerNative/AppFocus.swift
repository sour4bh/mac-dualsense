import AppKit
import Foundation

final class AppFocus {
    var cacheTTLms: Int {
        didSet { ttl = Double(cacheTTLms) / 1000.0 }
    }

    private var ttl: Double
    private var cachedBundleID: String?
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
        let bundleID = frontmostBundleID()
        return contexts[bundleID ?? ""] ?? "default"
    }

    private func frontmostBundleID() -> String? {
        let now = Date().timeIntervalSinceReferenceDate
        if let cachedBundleID, (now - lastRead) < ttl {
            return cachedBundleID
        }

        let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        cachedBundleID = id
        lastRead = now
        return id
    }
}

