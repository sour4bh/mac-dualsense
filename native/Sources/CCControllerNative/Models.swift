import Foundation

struct CCConfig: Codable {
    var version: Int = 2
    var settings: CCSettings = .init()
    var profiles: CCProfiles = .init()
    var mappings: [String: [String: CCActionDef]]? = nil // legacy (pre-profiles)
    var haptics: CCHaptics? = nil
}

struct CCSettings: Codable {
    var pollIntervalMs: Int? = 10
    var appFocusCacheTtlMs: Int? = 100
    var controller: CCControllerSettings? = .init()
    var wispr: CCWisprSettings? = .init()

    enum CodingKeys: String, CodingKey {
        case pollIntervalMs = "poll_interval_ms"
        case appFocusCacheTtlMs = "app_focus_cache_ttl_ms"
        case controller
        case wispr
    }
}

struct CCControllerSettings: Codable {
    var preferred: String? = "auto" // auto, dualsense, pro_controller
}

struct CCWisprSettings: Codable {
    var mode: String? = "rcmd_hold" // rcmd_hold, lcmd_hold, cmd_right (legacy)
    var holdMs: Int? = 450

    enum CodingKeys: String, CodingKey {
        case mode
        case holdMs = "hold_ms"
    }
}

struct CCProfiles: Codable {
    var active: String = "default"
    var items: [String: CCProfileItem] = ["default": .init()]
}

struct CCProfileItem: Codable {
    var mappings: [String: [String: CCActionDef]] = ["default": [:]]
}

struct CCActionDef: Codable, Hashable {
    var type: String = "noop" // keystroke, wispr, noop
    var key: String? = nil
    var modifiers: [String]? = nil
}

struct CCHaptics: Codable {
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
