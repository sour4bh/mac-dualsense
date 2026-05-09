import Foundation

enum WorkspaceSection: String, CaseIterable, Hashable, Identifiable {
    case controller
    case keybinds
    case profiles
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controller:
            return "Controller"
        case .keybinds:
            return "Keybinds"
        case .profiles:
            return "Profiles"
        case .diagnostics:
            return "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .controller:
            return "gamecontroller"
        case .keybinds:
            return "keyboard"
        case .profiles:
            return "square.stack.3d.up"
        case .diagnostics:
            return "stethoscope"
        }
    }

    var detail: String {
        switch self {
        case .controller:
            return "Live routing and visual editor"
        case .keybinds:
            return "Profiles, contexts, and mappings"
        case .profiles:
            return "Manage mapping sets"
        case .diagnostics:
            return "Permissions, focus, and logs"
        }
    }
}

@MainActor
final class WorkspaceSelection: ObservableObject {
    private static let sectionDefaultsKey = "workspace.section"
    private static let contextDefaultsKey = "workspace.context"

    @Published var section: WorkspaceSection {
        didSet {
            UserDefaults.standard.set(section.rawValue, forKey: Self.sectionDefaultsKey)
            if section != .controller {
                isLearningButton = false
            }
        }
    }

    @Published var editedContext: String {
        didSet {
            let normalized = Self.normalizeContext(editedContext)
            if normalized != editedContext {
                editedContext = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: Self.contextDefaultsKey)
            hasPersistedContext = true
            selectedButton = nil
            isLearningButton = false
        }
    }

    @Published var selectedButton: String? = nil
    @Published var isLearningButton: Bool = false

    private var hasPersistedContext: Bool

    init() {
        let defaults = UserDefaults.standard
        let sectionRaw = defaults.string(forKey: Self.sectionDefaultsKey) ?? WorkspaceSection.controller.rawValue
        section = WorkspaceSection(rawValue: sectionRaw) ?? .controller

        if let storedContext = defaults.string(forKey: Self.contextDefaultsKey) {
            editedContext = Self.normalizeContext(storedContext)
            hasPersistedContext = true
        } else {
            editedContext = "default"
            hasPersistedContext = false
        }
    }

    func seedEditedContext(from focusContext: String) {
        guard !hasPersistedContext else { return }
        editedContext = Self.normalizeContext(focusContext)
    }

    func ensureValidContext(_ contexts: [String], fallback: String) {
        let normalizedFallback = Self.normalizeContext(fallback)
        let target = contexts.contains(editedContext) ? editedContext : normalizedFallback
        guard target != editedContext else { return }
        editedContext = target
    }

    private static func normalizeContext(_ context: String) -> String {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "default" : trimmed
    }
}
