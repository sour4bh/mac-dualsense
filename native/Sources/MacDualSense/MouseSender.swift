import AppKit
import CoreGraphics
import Foundation

final class MouseSender: @unchecked Sendable {
    private let source = CGEventSource(stateID: .combinedSessionState)
    private var leftDown = false
    private var rightDown = false

    var anyButtonDown: Bool { leftDown || rightDown }

    func moveCursor(deltaX: Double, deltaY: Double) {
        let current = CGEvent(source: nil)?.location ?? .zero
        let newPos = CGPoint(x: current.x + deltaX, y: current.y + deltaY)

        let type: CGEventType
        let button: CGMouseButton
        if leftDown {
            type = .leftMouseDragged
            button = .left
        } else if rightDown {
            type = .rightMouseDragged
            button = .right
        } else {
            type = .mouseMoved
            button = .left
        }

        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: newPos,
            mouseButton: button
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    func setLeftButton(down: Bool) {
        guard down != leftDown else { return }
        leftDown = down
        let pos = CGEvent(source: nil)?.location ?? .zero
        let type: CGEventType = down ? .leftMouseDown : .leftMouseUp
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: pos,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    func setRightButton(down: Bool) {
        guard down != rightDown else { return }
        rightDown = down
        let pos = CGEvent(source: nil)?.location ?? .zero
        let type: CGEventType = down ? .rightMouseDown : .rightMouseUp
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: pos,
            mouseButton: .right
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    func scroll(deltaY: Double, deltaX: Double = 0) {
        let y = Int32(clamping: Int(deltaY.rounded()))
        let x = Int32(clamping: Int(deltaX.rounded()))
        guard y != 0 || x != 0 else { return }
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: y,
            wheel2: x,
            wheel3: 0
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    func releaseAllButtons() {
        if leftDown { setLeftButton(down: false) }
        if rightDown { setRightButton(down: false) }
    }
}
