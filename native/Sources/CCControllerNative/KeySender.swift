import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum CCModifier: String {
    case cmd
    case shift
    case alt
    case ctrl
}

final class KeySender {
    private let source = CGEventSource(stateID: .combinedSessionState)

    func sendKeystroke(key: String, modifiers: [String]?) -> Bool {
        guard let code = Self.keyCode(for: key) else { return false }
        let flags = Self.flags(from: modifiers)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else { return false }

        down.flags = flags
        up.flags = flags

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    func setRightCommand(down: Bool) -> Bool {
        let code = CGKeyCode(kVK_RightCommand)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else {
            return false
        }
        event.flags = down ? .maskCommand : []
        event.post(tap: .cghidEventTap)
        return true
    }

    private static func flags(from modifiers: [String]?) -> CGEventFlags {
        var flags: CGEventFlags = []
        for raw in modifiers ?? [] {
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "alt", "option":
                flags.insert(.maskAlternate)
            case "ctrl", "control":
                flags.insert(.maskControl)
            default:
                break
            }
        }
        return flags
    }

    private static func keyCode(for key: String) -> CGKeyCode? {
        let raw = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }

        let lower = raw.lowercased()
        switch lower {
        case "return", "enter":
            return CGKeyCode(kVK_Return)
        case "escape", "esc":
            return CGKeyCode(kVK_Escape)
        case "tab":
            return CGKeyCode(kVK_Tab)
        case "space":
            return CGKeyCode(kVK_Space)
        case "backspace", "delete":
            return CGKeyCode(kVK_Delete)
        case "up":
            return CGKeyCode(kVK_UpArrow)
        case "down":
            return CGKeyCode(kVK_DownArrow)
        case "left":
            return CGKeyCode(kVK_LeftArrow)
        case "right":
            return CGKeyCode(kVK_RightArrow)
        default:
            break
        }

        if raw.count == 1, let scalar = raw.unicodeScalars.first {
            switch scalar {
            case "a"..."z":
                return ansiLetterKeyCode(for: lower)
            case "A"..."Z":
                return ansiLetterKeyCode(for: lower)
            case "0"..."9":
                return ansiDigitKeyCode(for: raw)
            case "[":
                return CGKeyCode(kVK_ANSI_LeftBracket)
            case "]":
                return CGKeyCode(kVK_ANSI_RightBracket)
            case ",":
                return CGKeyCode(kVK_ANSI_Comma)
            case ".":
                return CGKeyCode(kVK_ANSI_Period)
            case "/":
                return CGKeyCode(kVK_ANSI_Slash)
            case ";":
                return CGKeyCode(kVK_ANSI_Semicolon)
            case "'":
                return CGKeyCode(kVK_ANSI_Quote)
            case "-":
                return CGKeyCode(kVK_ANSI_Minus)
            case "=":
                return CGKeyCode(kVK_ANSI_Equal)
            default:
                break
            }
        }

        return nil
    }

    private static func ansiLetterKeyCode(for lower: String) -> CGKeyCode? {
        guard lower.count == 1 else { return nil }
        switch lower {
        case "a": return CGKeyCode(kVK_ANSI_A)
        case "b": return CGKeyCode(kVK_ANSI_B)
        case "c": return CGKeyCode(kVK_ANSI_C)
        case "d": return CGKeyCode(kVK_ANSI_D)
        case "e": return CGKeyCode(kVK_ANSI_E)
        case "f": return CGKeyCode(kVK_ANSI_F)
        case "g": return CGKeyCode(kVK_ANSI_G)
        case "h": return CGKeyCode(kVK_ANSI_H)
        case "i": return CGKeyCode(kVK_ANSI_I)
        case "j": return CGKeyCode(kVK_ANSI_J)
        case "k": return CGKeyCode(kVK_ANSI_K)
        case "l": return CGKeyCode(kVK_ANSI_L)
        case "m": return CGKeyCode(kVK_ANSI_M)
        case "n": return CGKeyCode(kVK_ANSI_N)
        case "o": return CGKeyCode(kVK_ANSI_O)
        case "p": return CGKeyCode(kVK_ANSI_P)
        case "q": return CGKeyCode(kVK_ANSI_Q)
        case "r": return CGKeyCode(kVK_ANSI_R)
        case "s": return CGKeyCode(kVK_ANSI_S)
        case "t": return CGKeyCode(kVK_ANSI_T)
        case "u": return CGKeyCode(kVK_ANSI_U)
        case "v": return CGKeyCode(kVK_ANSI_V)
        case "w": return CGKeyCode(kVK_ANSI_W)
        case "x": return CGKeyCode(kVK_ANSI_X)
        case "y": return CGKeyCode(kVK_ANSI_Y)
        case "z": return CGKeyCode(kVK_ANSI_Z)
        default: return nil
        }
    }

    private static func ansiDigitKeyCode(for raw: String) -> CGKeyCode? {
        guard raw.count == 1 else { return nil }
        switch raw {
        case "0": return CGKeyCode(kVK_ANSI_0)
        case "1": return CGKeyCode(kVK_ANSI_1)
        case "2": return CGKeyCode(kVK_ANSI_2)
        case "3": return CGKeyCode(kVK_ANSI_3)
        case "4": return CGKeyCode(kVK_ANSI_4)
        case "5": return CGKeyCode(kVK_ANSI_5)
        case "6": return CGKeyCode(kVK_ANSI_6)
        case "7": return CGKeyCode(kVK_ANSI_7)
        case "8": return CGKeyCode(kVK_ANSI_8)
        case "9": return CGKeyCode(kVK_ANSI_9)
        default: return nil
        }
    }
}

