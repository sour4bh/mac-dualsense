import Foundation
import Testing
@testable import MacDualSense

private final class RecordingKeyboard: KeyboardOutput {
    var events: [String] = []
    func sendKeystroke(key: String, modifiers: [String]?) -> Bool { events.append(key); return true }
    func setModifier(_ modifier: String, down: Bool) -> Bool { events.append("\(modifier):\(down)"); return true }
    func toggleModifier(_ modifier: String) -> Bool { events.append("toggle:\(modifier)"); return true }
    func releaseAllModifiers() { events.append("release-all") }
}

private final class RecordingMouse: MouseOutput {
    var anyButtonDown = false
    var releases = 0
    func moveCursor(deltaX: Double, deltaY: Double) {}
    func setLeftButton(down: Bool) { anyButtonDown = down }
    func setRightButton(down: Bool) { anyButtonDown = down }
    func scroll(deltaY: Double, deltaX: Double) {}
    func releaseAllButtons() { releases += 1; anyButtonDown = false }
}

@Suite @MainActor
struct InputTests {
    @Test func releaseUsesOriginalHeldAction() {
        let keyboard = RecordingKeyboard()
        let router = InputRouter(keyboard: keyboard)
        router.handle(button: "triangle", pressed: true, action: ActionDef(type: "wispr"), mode: "rcmd_hold", holdMs: 450, enabled: true)
        router.handle(button: "triangle", pressed: false, action: ActionDef(type: "noop"), mode: "lcmd_hold", holdMs: 450, enabled: false)
        #expect(keyboard.events == ["rcmd:true", "rcmd:false"])
    }

    @Test func suppressedAndDisabledPressesDoNotSendInput() {
        let keyboard = RecordingKeyboard()
        let router = InputRouter(keyboard: keyboard)
        router.handle(button: "cross", pressed: true, action: ActionDef(type: "keystroke", key: "return"), mode: "rcmd_hold", holdMs: 450, enabled: false)
        router.handle(button: "cross", pressed: true, action: ActionDef(type: "noop"), mode: "rcmd_hold", holdMs: 450, enabled: true)
        #expect(keyboard.events.isEmpty)
    }

    @Test func sharedModifierRemainsHeldUntilLastRelease() {
        let keyboard = RecordingKeyboard()
        let router = InputRouter(keyboard: keyboard)
        for button in ["triangle", "ps"] {
            router.handle(button: button, pressed: true, action: ActionDef(type: "wispr"), mode: "rcmd_hold", holdMs: 450, enabled: true)
        }
        router.handle(button: "triangle", pressed: false, action: nil, mode: "rcmd_hold", holdMs: 450, enabled: true)
        #expect(keyboard.events.last == "rcmd:true")
        router.handle(button: "ps", pressed: false, action: nil, mode: "rcmd_hold", holdMs: 450, enabled: true)
        #expect(keyboard.events.last == "rcmd:false")
    }

    @Test func pauseCaptureAndProfileChangesReleaseInput() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ConfigStore(configURL: folder.appendingPathComponent("mappings.yaml"), watch: false, automaticallySaves: false)
        let keyboard = RecordingKeyboard()
        let mouse = RecordingMouse()
        let controller = ControllerManager(keyboard: keyboard, mouse: mouse, discover: false)
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(configStore: store, controllerManager: controller, defaults: defaults)
        let baselineReleases = mouse.releases
        state.isEnabled = false
        #expect(mouse.releases == baselineReleases + 1)
        state.workspaceSelection.isLearningButton = true
        #expect(mouse.releases == baselineReleases + 2)
        try store.addProfile(name: "Work")
        store.setActiveProfile("Work")
        #expect(mouse.releases == baselineReleases + 3)
        controller.setActiveController(id: nil)
        #expect(mouse.releases == baselineReleases + 4)
        #expect(keyboard.events.filter { $0 == "release-all" }.count >= 3)
    }

    @Test func disconnectReleasesHeldKeyboardAndMouse() {
        let keyboard = RecordingKeyboard()
        let mouse = RecordingMouse()
        let controller = ControllerManager(keyboard: keyboard, mouse: mouse, discover: false)
        controller.isEnabled = { true }
        controller.canSendInput = { true }
        controller.resolveAction = { _ in ActionDef(type: "wispr") }
        controller.trackpadEnabled = { true }
        controller.updateConnectedControllers([.init(id: "test", name: "DualSense", vendor: nil)])
        controller.handle(controllerID: "test", buttonName: "triangle", pressed: true)
        controller.handle(controllerID: "test", buttonName: "touchpad", pressed: true)
        #expect(keyboard.events.last == "rcmd:true")
        #expect(mouse.anyButtonDown)
        controller.updateConnectedControllers([])
        #expect(keyboard.events.last == "release-all")
        #expect(!mouse.anyButtonDown)
        #expect(controller.pressed.isEmpty)
    }

    @Test func touchpadRoutesAsShortcutAndNeverDispatchesDuringCapture() {
        let keyboard = RecordingKeyboard()
        let mouse = RecordingMouse()
        let controller = ControllerManager(keyboard: keyboard, mouse: mouse, discover: false)
        controller.isEnabled = { true }
        controller.canSendInput = { true }
        controller.resolveAction = { _ in ActionDef(type: "keystroke", key: "return") }
        controller.updateConnectedControllers([.init(id: "test", name: "DualSense", vendor: nil)])
        controller.handle(controllerID: "test", buttonName: "touchpad", pressed: true)
        #expect(keyboard.events == ["return"])
        controller.trackpadEnabled = { true }
        controller.isCapturing = { true }
        controller.handle(controllerID: "test", buttonName: "touchpad", pressed: true)
        #expect(keyboard.events == ["return"])
        #expect(!mouse.anyButtonDown)
        #expect(controller.lastEvent?.button == "touchpad")
        controller.canSendInput = { false }
        controller.isCapturing = { false }
        controller.handle(controllerID: "test", buttonName: "cross", pressed: true)
        #expect(keyboard.events == ["return"])
    }

    @Test func cancelledPulseCannotReleaseANewHold() async throws {
        let keyboard = RecordingKeyboard()
        let router = InputRouter(keyboard: keyboard)
        router.handle(button: "ps", pressed: true, action: ActionDef(type: "wispr"), mode: "rcmd_pulse", holdMs: 50, enabled: true)
        router.releaseAll()
        router.handle(button: "ps", pressed: true, action: ActionDef(type: "wispr"), mode: "rcmd_hold", holdMs: 50, enabled: true)
        try await Task.sleep(for: .milliseconds(120))
        #expect(keyboard.events == ["rcmd:true", "release-all", "rcmd:true"])
    }
}
