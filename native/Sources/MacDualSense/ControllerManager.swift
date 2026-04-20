import Foundation
import GameController

@MainActor
final class ControllerManager: ObservableObject {
    struct ConnectedController: Identifiable, Hashable {
        let id: String
        let name: String
        let vendor: String?
    }

    struct ButtonEvent: Identifiable {
        let id = UUID()
        let time: Date
        let state: String
        let button: String
        let action: String
    }

    @Published private(set) var controllers: [ConnectedController] = []
    @Published private(set) var activeController: ConnectedController? = nil
    @Published private(set) var pressed: Set<String> = []
    @Published private(set) var lastEvent: ButtonEvent? = nil
    @Published private(set) var recentEvents: [ButtonEvent] = []

    var isEnabled: (() -> Bool)?
    var preferredController: (() -> String)?
    var resolveAction: ((String) -> ActionDef?)?
    var accessibilityPrompt: (() -> Void)?
    var wisprMode: (() -> String)?
    var wisprHoldMs: (() -> Int)?
    var hapticsEnabled: (() -> Bool)?
    var hapticPattern: ((String) -> CCHapticPattern?)?
    var trackpadEnabled: (() -> Bool)?
    var trackpadSettings: (() -> TrackpadSettings)?

    private let keySender = KeySender()
    private let mouseSender = MouseSender()
    private let haptics = ControllerHaptics()
    private var wisprHeldButton: String? = nil
    private var controllerRefs: [String: GCController] = [:]
    private var lastPrimary: (x: Double, y: Double)? = nil
    private var lastSecondary: (x: Double, y: Double)? = nil

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidConnect(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidDisconnect(_:)),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        refreshConnectedControllers()
        GCController.startWirelessControllerDiscovery {}
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        keySender.releaseAllModifiers()
        mouseSender.releaseAllButtons()
    }

    func setActiveController(id: String?) {
        let previousActiveID = activeController?.id
        if let id, let ctrl = controllers.first(where: { $0.id == id }) {
            activeController = ctrl
        } else {
            activeController = pickActiveController()
        }
        resetTransientState(releaseModifiers: activeController?.id != previousActiveID)
    }

    @objc private func controllerDidConnect(_ note: Notification) {
        refreshConnectedControllers()
    }

    @objc private func controllerDidDisconnect(_ note: Notification) {
        refreshConnectedControllers()
    }

    private func refreshConnectedControllers() {
        let previousActiveID = activeController?.id
        let current = GCController.controllers()
        Logger.shared.info("refreshConnectedControllers: found \(current.count) controller(s)")
        var next: [ConnectedController] = []
        var refs: [String: GCController] = [:]
        for c in current {
            let stableID = String(ObjectIdentifier(c).hashValue)
            Logger.shared.info("  - \(c.productCategory) (\(c.vendorName ?? "unknown"))")
            next.append(
                ConnectedController(
                    id: stableID,
                    name: c.productCategory,
                    vendor: c.vendorName
                )
            )
            refs[stableID] = c
        }
        controllers = next
        controllerRefs = refs
        if activeController == nil || (activeController != nil && !next.contains(activeController!)) {
            activeController = pickActiveController()
            resetTransientState(releaseModifiers: previousActiveID != nil)
            Logger.shared.info("Active controller set to: \(activeController?.name ?? "none")")
        }
        if let activeController, activeController.id != previousActiveID {
            triggerHaptic(name: "connect")
        }
        attachHandlers()
    }

    private func activeGCController() -> GCController? {
        guard let activeController else { return nil }
        return controllerRefs[activeController.id]
    }

    private func resetTransientState(releaseModifiers: Bool) {
        pressed.removeAll()
        wisprHeldButton = nil
        releaseTrackpadState()
        if releaseModifiers {
            keySender.releaseAllModifiers()
        }
    }

    private func releaseTrackpadState() {
        lastPrimary = nil
        lastSecondary = nil
        mouseSender.releaseAllButtons()
    }

    private func attachHandlers() {
        Logger.shared.info("attachHandlers: attaching to \(controllerRefs.count) controller(s)")
        for (id, controller) in controllerRefs {
            let profile = controller.physicalInputProfile
            Logger.shared.info("  Controller \(id): \(profile.buttons.count) buttons, \(profile.dpads.count) dpads")

            for (name, button) in profile.buttons {
                button.pressedChangedHandler = { [weak self] _, _, pressed in
                    Task { @MainActor in
                        self?.handle(controllerID: id, buttonName: name, pressed: pressed)
                    }
                }
            }

            if let dpad = profile.dpads[GCInputDirectionPad] {
                Logger.shared.info("  D-pad found, attaching handlers")
                dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
                    Task { @MainActor in self?.handle(controllerID: id, buttonName: "dpad_up", pressed: pressed) }
                }
                dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
                    Task { @MainActor in self?.handle(controllerID: id, buttonName: "dpad_down", pressed: pressed) }
                }
                dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
                    Task { @MainActor in self?.handle(controllerID: id, buttonName: "dpad_left", pressed: pressed) }
                }
                dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
                    Task { @MainActor in self?.handle(controllerID: id, buttonName: "dpad_right", pressed: pressed) }
                }
            }

            if let ds = profile as? GCDualSenseGamepad {
                Logger.shared.info("  DualSense detected, attaching continuous touchpad handlers")
                ds.touchpadPrimary.valueChangedHandler = { [weak self] _, x, y in
                    Task { @MainActor in
                        self?.handleTouchpadPrimary(controllerID: id, x: Double(x), y: Double(y))
                    }
                }
                ds.touchpadSecondary.valueChangedHandler = { [weak self] _, x, y in
                    Task { @MainActor in
                        self?.handleTouchpadSecondary(controllerID: id, x: Double(x), y: Double(y))
                    }
                }
                ds.touchpadButton.pressedChangedHandler = { [weak self] _, _, pressed in
                    Task { @MainActor in
                        self?.handleTouchpadClick(controllerID: id, pressed: pressed)
                    }
                }
            }
        }
    }

    private func canonicalButton(from physicalName: String) -> String? {
        if physicalName == GCInputButtonA { return "cross" }
        if physicalName == GCInputButtonB { return "circle" }
        if physicalName == GCInputButtonX { return "square" }
        if physicalName == GCInputButtonY { return "triangle" }

        if physicalName == GCInputLeftShoulder { return "l1" }
        if physicalName == GCInputRightShoulder { return "r1" }
        if physicalName == GCInputLeftTrigger { return "l2" }
        if physicalName == GCInputRightTrigger { return "r2" }

        if physicalName == GCInputLeftThumbstickButton { return "l3" }
        if physicalName == GCInputRightThumbstickButton { return "r3" }

        if physicalName == GCInputButtonMenu { return "options" }
        if physicalName == GCInputButtonOptions { return "share" }
        if physicalName == GCInputButtonHome { return "ps" }

        // Fallbacks for vendor-specific names.
        let lower = physicalName.lowercased()
        if lower.contains("touchpad") { return "touchpad" }
        if lower.contains("home") { return "ps" }
        return nil
    }

    private func handle(controllerID: String, buttonName: String, pressed: Bool) {
        Logger.shared.debug("handle: button=\(buttonName) pressed=\(pressed) controllerID=\(controllerID) activeID=\(activeController?.id ?? "nil")")
        guard activeController?.id == controllerID else {
            Logger.shared.debug("  -> ignored (controller mismatch)")
            return
        }
        let canonical = canonicalButton(from: buttonName) ?? buttonName

        if pressed {
            self.pressed.insert(canonical)
        } else {
            self.pressed.remove(canonical)
        }

        let actionDef = resolveAction?(canonical)
        let actionSummary = summarize(actionDef)
        let event = ButtonEvent(
            time: Date(),
            state: pressed ? "Pressed" : "Released",
            button: canonical,
            action: pressed ? actionSummary : "—"
        )
        lastEvent = event
        recentEvents.append(event)
        if recentEvents.count > 200 {
            recentEvents.removeFirst(recentEvents.count - 200)
        }

        guard isEnabled?() == true else { return }

        // Ensure we can inject keys; prompt if needed.
        accessibilityPrompt?()

        // In trackpad mode, the touchpad click is driven by handleTouchpadClick;
        // skip the keystroke dispatch so the configured "touchpad" action doesn't double-fire.
        if canonical == "touchpad", trackpadEnabled?() == true {
            return
        }

        guard let actionDef else { return }
        var shouldTriggerHaptic = false
        var hapticName: String = "confirm"
        switch actionDef.type.lowercased() {
        case "keystroke":
            if pressed, let key = actionDef.key {
                let ok = keySender.sendKeystroke(key: key, modifiers: actionDef.modifiers)
                shouldTriggerHaptic = true
                hapticName = ok ? "confirm" : "error"
            }
        case "wispr":
            if pressed {
                let ok = handleWispr(button: canonical, pressed: pressed)
                shouldTriggerHaptic = true
                hapticName = ok ? "confirm" : "error"
            } else {
                _ = handleWispr(button: canonical, pressed: pressed)
            }
        default:
            break
        }

        if shouldTriggerHaptic {
            triggerHaptic(name: hapticName)
        }
    }

    @discardableResult
    private func handleWispr(button: String, pressed: Bool) -> Bool {
        let mode = (wisprMode?() ?? "rcmd_hold").lowercased()
        let holdMs = wisprHoldMs?() ?? 450

        if pressed {
            wisprHeldButton = button
            switch mode {
            case "cmd_right", "cmd+right", "cmd-right":
                return keySender.sendKeystroke(key: "right", modifiers: ["cmd"])
            case "lcmd_pulse", "pulse_lcmd":
                DispatchQueue.global().async { [keySender] in
                    _ = keySender.holdModifier("lcmd", holdMs: holdMs)
                }
                return true
            case "lcmd_toggle", "toggle_lcmd":
                return keySender.toggleModifier("lcmd")
            case "lcmd_hold", "hold_lcmd":
                return keySender.setModifier("lcmd", down: true)
            case "rcmd_pulse", "pulse_rcmd":
                DispatchQueue.global().async { [keySender] in
                    _ = keySender.holdModifier("rcmd", holdMs: holdMs)
                }
                return true
            case "rcmd_toggle", "toggle_rcmd":
                return keySender.toggleModifier("rcmd")
            case "rcmd_hold", "hold_rcmd":
                return keySender.setModifier("rcmd", down: true)
            case "fn_hold", "hold_fn":
                return keySender.setModifier("fn", down: true)
            default:
                return keySender.sendKeystroke(key: "right", modifiers: ["cmd"])
            }
        } else {
            guard wisprHeldButton == button else { return false }
            wisprHeldButton = nil
            switch mode {
            case "lcmd_hold", "hold_lcmd":
                _ = keySender.setModifier("lcmd", down: false)
            case "rcmd_hold", "hold_rcmd":
                _ = keySender.setModifier("rcmd", down: false)
            case "fn_hold", "hold_fn":
                _ = keySender.setModifier("fn", down: false)
            default:
                break
            }
            return true
        }
    }

    private func handleTouchpadPrimary(controllerID: String, x: Double, y: Double) {
        guard activeController?.id == controllerID else { return }
        guard isEnabled?() == true, trackpadEnabled?() == true else {
            if lastPrimary != nil || mouseSender.anyButtonDown {
                releaseTrackpadState()
            }
            return
        }

        let touched = !(x == 0 && y == 0)
        if !touched {
            // Finger lifted — release any mouse button we were holding.
            if mouseSender.anyButtonDown {
                mouseSender.releaseAllButtons()
            }
            lastPrimary = nil
            return
        }

        guard let prev = lastPrimary else {
            lastPrimary = (x, y)
            return
        }

        // Two-finger gesture: secondary drives scroll, suppress cursor from primary.
        if lastSecondary != nil {
            lastPrimary = (x, y)
            return
        }

        let settings = trackpadSettings?() ?? .init()
        let sensitivity = settings.cursorSensitivity ?? 900
        let dx = (x - prev.x) * sensitivity
        // GameController y-axis is +up; screen y is +down.
        let dy = -(y - prev.y) * sensitivity
        mouseSender.moveCursor(deltaX: dx, deltaY: dy)
        lastPrimary = (x, y)
    }

    private func handleTouchpadSecondary(controllerID: String, x: Double, y: Double) {
        guard activeController?.id == controllerID else { return }
        guard isEnabled?() == true, trackpadEnabled?() == true else {
            lastSecondary = nil
            return
        }

        let touched = !(x == 0 && y == 0)
        if !touched {
            lastSecondary = nil
            return
        }

        guard let prev = lastSecondary else {
            lastSecondary = (x, y)
            return
        }

        let settings = trackpadSettings?() ?? .init()
        let scrollSensitivity = settings.scrollSensitivity ?? 40
        let natural = settings.naturalScroll ?? true
        // Fingers moving up (y increases) with natural scroll → scroll wheel +y (content up).
        let raw = (y - prev.y) * scrollSensitivity
        let dy = natural ? raw : -raw
        mouseSender.scroll(deltaY: dy)
        lastSecondary = (x, y)
    }

    private func handleTouchpadClick(controllerID: String, pressed: Bool) {
        guard activeController?.id == controllerID else { return }
        guard isEnabled?() == true, trackpadEnabled?() == true else {
            mouseSender.releaseAllButtons()
            return
        }

        if pressed {
            let settings = trackpadSettings?() ?? .init()
            let modifier = (settings.rightClickModifier ?? "l2").lowercased()
            let isRightClick = !modifier.isEmpty && self.pressed.contains(modifier)
            if isRightClick {
                mouseSender.setRightButton(down: true)
            } else {
                mouseSender.setLeftButton(down: true)
            }
        } else {
            mouseSender.releaseAllButtons()
        }
    }

    private func triggerHaptic(name: String) {
        let enabled = hapticsEnabled?() ?? true
        let pattern = hapticPattern?(name)

        let fallback: ControllerHaptics.Spec
        switch name {
        case "error":
            fallback = .init(intensity: 1.0, durationSeconds: 0.10, repeatCount: 2)
        case "connect":
            fallback = .init(intensity: 0.25, durationSeconds: 0.20, repeatCount: 1)
        default:
            fallback = .init(intensity: 0.5, durationSeconds: 0.05, repeatCount: 1)
        }

        haptics.play(controller: activeGCController(), enabled: enabled, pattern: pattern, fallback: fallback)
    }

    private func summarize(_ action: ActionDef?) -> String {
        guard let action else { return "No action" }
        switch action.type.lowercased() {
        case "wispr":
            return "Wispr"
        case "keystroke":
            let mods = (action.modifiers ?? []).map { $0.lowercased() }
            let key = (action.key ?? "").lowercased()
            if !mods.isEmpty, !key.isEmpty {
                return "Keystroke: \(mods.joined(separator: "+"))+\(key)"
            }
            if !key.isEmpty {
                return "Keystroke: \(key)"
            }
            return "Keystroke"
        default:
            return "No action"
        }
    }

    private func pickActiveController() -> ConnectedController? {
        let preferred = preferredController?() ?? "auto"
        if preferred == "auto" {
            return controllers.first
        }

        let lower = preferred.lowercased()
        return controllers.first(where: { controller in
            let haystack = "\(controller.name) \(controller.vendor ?? "")".lowercased()
            if lower == "dualsense" { return haystack.contains("dualsense") }
            if lower == "pro_controller" { return haystack.contains("pro controller") }
            return false
        }) ?? controllers.first
    }
}
