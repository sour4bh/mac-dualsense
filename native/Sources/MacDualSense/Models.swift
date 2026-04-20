import Foundation

struct Config: Codable {
    var version: Int = 2
    var settings: Settings = .init()
    var profiles: Profiles = .init()
    var mappings: [String: [String: ActionDef]]? = nil // legacy (pre-profiles)
    var haptics: Haptics? = nil
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
