import Foundation

protocol KeyboardOutput: AnyObject {
    func sendKeystroke(key: String, modifiers: [String]?) -> Bool
    func setModifier(_ modifier: String, down: Bool) -> Bool
    func toggleModifier(_ modifier: String) -> Bool
    func releaseAllModifiers()
}

protocol MouseOutput: AnyObject {
    var anyButtonDown: Bool { get }
    func moveCursor(deltaX: Double, deltaY: Double)
    func setLeftButton(down: Bool)
    func setRightButton(down: Bool)
    func scroll(deltaY: Double, deltaX: Double)
    func releaseAllButtons()
}

extension KeySender: KeyboardOutput {}
extension MouseSender: MouseOutput {}

@MainActor
final class InputRouter {
    private let keyboard: any KeyboardOutput
    private var held: [String: String] = [:]
    private var pulses: [String: DispatchWorkItem] = [:]

    init(keyboard: any KeyboardOutput) { self.keyboard = keyboard }

    @discardableResult
    func handle(button: String, pressed: Bool, action: ActionDef?, mode: String, holdMs: Int, enabled: Bool) -> Bool {
        if !pressed {
            if let modifier = held.removeValue(forKey: button), !held.values.contains(modifier) {
                return keyboard.setModifier(modifier, down: false)
            }
            return false
        }
        guard enabled, let action else { return false }
        if action.type.lowercased() == "keystroke", let key = action.key {
            return keyboard.sendKeystroke(key: key, modifiers: action.modifiers)
        }
        guard action.type.lowercased() == "wispr" else { return false }
        let mode = mode.lowercased()
        if ["cmd_right", "cmd+right", "cmd-right"].contains(mode) {
            return keyboard.sendKeystroke(key: "right", modifiers: ["cmd"])
        }
        let modifier = mode.contains("lcmd") ? "lcmd" : mode.contains("fn") ? "fn" : "rcmd"
        if mode.contains("toggle") { return keyboard.toggleModifier(modifier) }
        if mode.contains("pulse") {
            pulses[modifier]?.cancel()
            let succeeded = keyboard.setModifier(modifier, down: true)
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pulses.removeValue(forKey: modifier)
                    if !self.held.values.contains(modifier) {
                        _ = self.keyboard.setModifier(modifier, down: false)
                    }
                }
            }
            pulses[modifier] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(max(0, holdMs)) / 1000, execute: work)
            return succeeded
        }
        held[button] = modifier
        return keyboard.setModifier(modifier, down: true)
    }

    func releaseAll() {
        pulses.values.forEach { $0.cancel() }
        pulses.removeAll()
        held.removeAll()
        keyboard.releaseAllModifiers()
    }
}
