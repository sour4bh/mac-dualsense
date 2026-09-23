import Foundation

struct Config: Codable {
    var contexts: [String: AppContext]? = nil
    var version: Int = 2
    var settings: Settings = .init()
    var profiles: Profiles = .init()
    var mappings: [String: [String: ActionDef]]? = nil // legacy (pre-profiles)
    var haptics: Haptics? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 2
        settings = try values.decodeIfPresent(Settings.self, forKey: .settings) ?? .init()
        profiles = try values.decodeIfPresent(Profiles.self, forKey: .profiles) ?? .init()
        mappings = try values.decodeIfPresent([String: [String: ActionDef]].self, forKey: .mappings)
        haptics = try values.decodeIfPresent(Haptics.self, forKey: .haptics)
        contexts = try values.decodeIfPresent([String: AppContext].self, forKey: .contexts)
    }
}

struct Settings: Codable {
    var pollIntervalMs: Int? = 10
    var appFocusCacheTtlMs: Int? = 100
    var controller: ControllerSettings? = .init()
    var wispr: WisprSettings? = .init()
    var trackpad: TrackpadSettings? = .init()

    enum CodingKeys: String, CodingKey {
        case pollIntervalMs = "poll_interval_ms"
        case appFocusCacheTtlMs = "app_focus_cache_ttl_ms"
        case controller
        case wispr
        case trackpad
    }
}

struct ControllerSettings: Codable {
    var preferred: String? = "auto" // auto, dualsense, pro_controller
}

struct WisprSettings: Codable {
    var mode: String? = "rcmd_hold" // rcmd_hold, lcmd_hold, cmd_right (legacy)
    var holdMs: Int? = 450

    enum CodingKeys: String, CodingKey {
        case mode
        case holdMs = "hold_ms"
    }
}

struct TrackpadSettings: Codable {
    var cursorSensitivity: Double? = 900
    var scrollSensitivity: Double? = 40
    var naturalScroll: Bool? = true
    var rightClickModifier: String? = "l2"

    enum CodingKeys: String, CodingKey {
        case cursorSensitivity = "cursor_sensitivity"
        case scrollSensitivity = "scroll_sensitivity"
        case naturalScroll = "natural_scroll"
        case rightClickModifier = "right_click_modifier"
    }
}

struct Profiles: Codable {
    var active: String = "default"
    var items: [String: ProfileItem] = ["default": .init()]
}

struct ProfileItem: Codable {
    var mappings: [String: [String: ActionDef]] = ["default": [:]]
    var trackpadMode: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case mappings
        case trackpadMode = "trackpad_mode"
    }
}

struct ActionDef: Codable, Hashable {
    var type: String = "noop" // keystroke, wispr, noop
    var key: String? = nil
    var modifiers: [String]? = nil
}

struct Haptics: Codable {
    var enabled: Bool? = true
    var patterns: [String: CCHapticPattern]? = nil
}

struct CCHapticPattern: Codable, Hashable {
    var intensity: Int? = nil
    var durationMs: Int? = nil
    var repeatCount: Int? = nil

    enum CodingKeys: String, CodingKey {
        case intensity
        case durationMs = "duration_ms"
        case repeatCount = "repeat"
    }
}

struct AppContext: Codable, Equatable {
    var name: String
    var bundleIDs: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case bundleIDs = "bundle_ids"
    }

    static let defaults: [String: AppContext] = [
        "warp": .init(name: "Warp", bundleIDs: ["dev.warp.Warp-Stable", "dev.warp.Warp"]),
        "arc": .init(name: "Arc", bundleIDs: ["company.thebrowser.Browser"]),
        "chrome": .init(name: "Chrome", bundleIDs: ["com.google.Chrome"]),
        "slack": .init(name: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"]),
        "chatgpt": .init(name: "ChatGPT", bundleIDs: ["com.openai.chat"]),
        "claude": .init(name: "Claude", bundleIDs: ["com.anthropic.claudefordesktop"]),
    ]

    static func validate(_ contexts: [String: AppContext]) throws {
        var assigned = Set<String>()
        for (id, context) in contexts {
            guard id != "default", !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !context.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ContextError.invalidName
            }
            for bundleID in context.bundleIDs {
                guard bundleID.contains("."), !bundleID.contains(where: { $0.isWhitespace }),
                      !bundleID.hasPrefix("."), !bundleID.hasSuffix(".") else {
                    throw ContextError.invalidBundleID(bundleID)
                }
                guard assigned.insert(bundleID).inserted else {
                    throw ContextError.duplicateBundleID(bundleID)
                }
            }
        }
    }
}

enum ContextError: LocalizedError {
    case invalidName
    case invalidBundleID(String)
    case duplicateBundleID(String)

    var errorDescription: String? {
        switch self {
        case .invalidName: "Give the app context a name. Global is reserved."
        case .invalidBundleID(let id): "Invalid bundle ID: \(id)"
        case .duplicateBundleID(let id): "\(id) is already assigned to an app context."
        }
    }
}
