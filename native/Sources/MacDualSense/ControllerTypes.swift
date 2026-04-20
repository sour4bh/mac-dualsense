import SwiftUI

// MARK: - Path Cache

final class PathCache: @unchecked Sendable {
    static let shared = PathCache()
    private var cache: [CacheKey: Path] = [:]
    private let lock = NSLock()

    private init() {}

    func path(for button: ControllerButton) -> Path {
        lock.lock()
        defer { lock.unlock() }

        let key = CacheKey(pathData: button.pathData, transform: TransformKey(button.transform))

        if let cached = cache[key] {
            return cached
        }

        var parsed = SVGPathParser.parse(button.pathData)
        if let transform = button.transform {
            parsed = parsed.applying(transform)
        }

        cache[key] = parsed
        return parsed
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }

    private struct CacheKey: Hashable {
        let pathData: String
        let transform: TransformKey
    }

    private struct TransformKey: Hashable {
        let a: CGFloat
        let b: CGFloat
        let c: CGFloat
        let d: CGFloat
        let tx: CGFloat
        let ty: CGFloat

        init(_ transform: CGAffineTransform?) {
            let t = transform ?? .identity
            a = t.a
            b = t.b
            c = t.c
            d = t.d
            tx = t.tx
            ty = t.ty
        }

        static func == (lhs: TransformKey, rhs: TransformKey) -> Bool {
            lhs.a == rhs.a &&
            lhs.b == rhs.b &&
            lhs.c == rhs.c &&
            lhs.d == rhs.d &&
            lhs.tx == rhs.tx &&
            lhs.ty == rhs.ty
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(a)
            hasher.combine(b)
            hasher.combine(c)
            hasher.combine(d)
            hasher.combine(tx)
            hasher.combine(ty)
        }
    }
}

enum ControllerViewSide: String, CaseIterable, Identifiable {
    case front
    case back

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

// MARK: - Controller Type

enum ControllerType {
    case dualSense
    case proController

    var supportsVisualEditor: Bool {
        switch self {
        case .dualSense: return true
        case .proController: return false
        }
    }

    var availableViews: [ControllerViewSide] {
        switch self {
        case .dualSense: return [.front, .back]
        case .proController: return [.front]
        }
    }

    var displayName: String {
        switch self {
        case .dualSense: return "DualSense"
        case .proController: return "Pro Controller"
        }
    }

    func svgResourceName(for viewSide: ControllerViewSide) -> String? {
        switch self {
        case .dualSense:
            return viewSide == .front
                ? DualSenseVisuals.frontResourceName
                : DualSenseVisuals.backResourceName
        case .proController:
            return nil
        }
    }

    func viewBox(for viewSide: ControllerViewSide) -> CGRect? {
        switch self {
        case .dualSense:
            return viewSide == .front
                ? DualSenseVisuals.frontViewBox
                : DualSenseVisuals.backViewBox
        case .proController:
            return nil
        }
    }

    func buttonProvider(for viewSide: ControllerViewSide) -> ControllerButtonProvider? {
        switch self {
        case .dualSense:
            return viewSide == .front ? DualSenseButtonProvider() : DualSenseBackButtonProvider()
        case .proController:
            return nil
        }
    }

    static func detect(name: String?, vendor: String?) -> ControllerType {
        let combined = "\(name ?? "") \(vendor ?? "")".lowercased()
        if combined.contains("pro controller") || combined.contains("nintendo") {
            return .proController
        }
        return .dualSense
    }
}

// MARK: - Button Provider Protocol

protocol ControllerButtonProvider {
    var viewBox: CGRect { get }
    var buttons: [String: ControllerButton] { get }
}

// MARK: - Controller Button

struct ControllerButton {
    let id: String
    let pathData: String
    let label: String
    let color: Color?
    let transform: CGAffineTransform?

    init(
        id: String,
        pathData: String,
        label: String,
        color: Color? = nil,
        transform: CGAffineTransform? = nil
    ) {
        self.id = id
        self.pathData = pathData
        self.label = label
        self.color = color
        self.transform = transform
    }

    var path: Path {
        PathCache.shared.path(for: self)
    }

    var bounds: CGRect {
        path.boundingRect
    }
}

// MARK: - Action Formatter

enum ActionFormatter {
    static func format(_ action: ActionDef?) -> String {
        guard let action else { return "Click to bind" }

        switch action.type.lowercased() {
        case "keystroke":
            return formatKeystroke(key: action.key, modifiers: action.modifiers)
        case "wispr":
            return "🎤 Wispr"
        default:
            return "Click to bind"
        }
    }

    static func formatKeystroke(key: String?, modifiers: [String]?) -> String {
        let key = key ?? ""
        if key.isEmpty { return "Click to bind" }

        let modSymbols = (modifiers ?? []).map { mod -> String in
            switch mod.lowercased() {
            case "cmd", "command": return "⌘"
            case "shift": return "⇧"
            case "alt", "option": return "⌥"
            case "ctrl", "control": return "⌃"
            case "fn": return "fn"
            default: return mod
            }
        }

        return modSymbols.isEmpty ? key : "\(modSymbols.joined())\(key)"
    }
}
