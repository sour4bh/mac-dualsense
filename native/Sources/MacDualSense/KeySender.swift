import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

final class KeySender: @unchecked Sendable {
    private let source = CGEventSource(stateID: .combinedSessionState)
    private var heldModifiers: Set<String> = []

    func sendKeystroke(key: String, modifiers: [String]?) -> Bool {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let code = Self.keyCode(for: key) else {
            Logger.shared.warning("Unsupported key mapping: \(normalized)")
            return false
        }
        let flags = Self.flags(from: modifiers)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else {
            Logger.shared.error("Failed to create keyboard events for key: \(normalized)")
            return false
        }

        down.flags = flags
        up.flags = flags

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    func setModifier(_ modifier: String, down: Bool) -> Bool {
        let mod = modifier.lowercased()
        guard let keycode = Self.modifierKeyCode(for: mod) else { return false }

        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keycode, keyDown: down) else {
            return false
        }
        event.flags = down ? Self.modifierFlag(for: mod) : []
        event.post(tap: .cghidEventTap)

        if down {
            heldModifiers.insert(mod)
        } else {
            heldModifiers.remove(mod)
        }
        return true
    }

    func toggleModifier(_ modifier: String) -> Bool {
        let mod = modifier.lowercased()
        return setModifier(mod, down: !heldModifiers.contains(mod))
    }

    func holdModifier(_ modifier: String, holdMs: Int) -> Bool {
        guard setModifier(modifier, down: true) else { return false }
        Thread.sleep(forTimeInterval: Double(max(0, holdMs)) / 1000.0)
        _ = setModifier(modifier, down: false)
        return true
    }

    func releaseAllModifiers() {
        for mod in heldModifiers {
            _ = setModifier(mod, down: false)
        }
    }

    private static func modifierKeyCode(for mod: String) -> CGKeyCode? {
        switch mod {
        case "lcmd": return CGKeyCode(kVK_Command)
        case "rcmd": return CGKeyCode(kVK_RightCommand)
        case "lshift": return CGKeyCode(kVK_Shift)
        case "rshift": return CGKeyCode(kVK_RightShift)
        case "lctrl": return CGKeyCode(kVK_Control)
        case "rctrl": return CGKeyCode(kVK_RightControl)
        case "lalt", "loption": return CGKeyCode(kVK_Option)
        case "ralt", "roption": return CGKeyCode(kVK_RightOption)
        case "fn": return CGKeyCode(kVK_Function)
        default: return nil
        }
    }

    private static func modifierFlag(for mod: String) -> CGEventFlags {
        switch mod {
        case "lcmd", "rcmd", "cmd", "command": return .maskCommand
        case "lshift", "rshift", "shift": return .maskShift
        case "lctrl", "rctrl", "ctrl", "control": return .maskControl
        case "lalt", "ralt", "loption", "roption", "alt", "option": return .maskAlternate
        case "fn": return .maskSecondaryFn
        default: return []
        }
    }

    private static func flags(from modifiers: [String]?) -> CGEventFlags {
        var flags: CGEventFlags = []
        for raw in modifiers ?? [] {
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "cmd", "command", "lcmd", "rcmd":
                flags.insert(.maskCommand)
            case "shift", "lshift", "rshift":
                flags.insert(.maskShift)
            case "alt", "option", "lalt", "ralt", "loption", "roption":
                flags.insert(.maskAlternate)
            case "ctrl", "control", "lctrl", "rctrl":
                flags.insert(.maskControl)
            case "fn":
                flags.insert(.maskSecondaryFn)
            default:
                break
            }
        }
        return flags
    }

    static func keyCode(for key: String) -> CGKeyCode? {
        let raw = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }

        let lower = raw.lowercased()
        switch lower {
        // Basic keys
        case "return", "enter":
            return CGKeyCode(kVK_Return)
        case "escape", "esc":
            return CGKeyCode(kVK_Escape)
        case "tab":
            return CGKeyCode(kVK_Tab)
        case "space", "spacebar":
            return CGKeyCode(kVK_Space)
        case "capslock", "caps_lock":
            return CGKeyCode(kVK_CapsLock)
        case "backspace", "delete":
            return CGKeyCode(kVK_Delete)
        // Arrow keys
        case "up":
            return CGKeyCode(kVK_UpArrow)
        case "down":
            return CGKeyCode(kVK_DownArrow)
        case "left":
            return CGKeyCode(kVK_LeftArrow)
        case "right":
            return CGKeyCode(kVK_RightArrow)
        // Navigation keys
        case "home":
            return CGKeyCode(kVK_Home)
        case "end":
            return CGKeyCode(kVK_End)
        case "pageup", "page_up":
            return CGKeyCode(kVK_PageUp)
        case "pagedown", "page_down":
            return CGKeyCode(kVK_PageDown)
        case "forwarddelete", "forward_delete", "delete_forward":
            return CGKeyCode(kVK_ForwardDelete)
        case "help":
            return CGKeyCode(kVK_Help)
        // Function keys
        case "f1":
            return CGKeyCode(kVK_F1)
        case "f2":
            return CGKeyCode(kVK_F2)
        case "f3":
            return CGKeyCode(kVK_F3)
        case "f4":
            return CGKeyCode(kVK_F4)
        case "f5":
            return CGKeyCode(kVK_F5)
        case "f6":
            return CGKeyCode(kVK_F6)
        case "f7":
            return CGKeyCode(kVK_F7)
        case "f8":
            return CGKeyCode(kVK_F8)
        case "f9":
            return CGKeyCode(kVK_F9)
        case "f10":
            return CGKeyCode(kVK_F10)
        case "f11":
            return CGKeyCode(kVK_F11)
        case "f12":
            return CGKeyCode(kVK_F12)
        case "comma":
            return CGKeyCode(kVK_ANSI_Comma)
        case "period", "dot":
            return CGKeyCode(kVK_ANSI_Period)
        case "slash", "forward_slash", "forwardslash":
            return CGKeyCode(kVK_ANSI_Slash)
        case "semicolon":
            return CGKeyCode(kVK_ANSI_Semicolon)
        case "quote", "apostrophe":
            return CGKeyCode(kVK_ANSI_Quote)
        case "minus", "hyphen":
            return CGKeyCode(kVK_ANSI_Minus)
        case "equal", "equals":
            return CGKeyCode(kVK_ANSI_Equal)
        case "grave", "backtick", "backquote":
            return CGKeyCode(kVK_ANSI_Grave)
        case "backslash":
            return CGKeyCode(kVK_ANSI_Backslash)
        case "left_bracket", "leftbracket":
            return CGKeyCode(kVK_ANSI_LeftBracket)
        case "right_bracket", "rightbracket":
            return CGKeyCode(kVK_ANSI_RightBracket)
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
            case "`":
                return CGKeyCode(kVK_ANSI_Grave)
            case "\\":
                return CGKeyCode(kVK_ANSI_Backslash)
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
