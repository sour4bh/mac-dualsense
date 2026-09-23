import Foundation
import AppKit

@MainActor
final class AppState: ObservableObject {
    private static let isEnabledDefaultsKey = "mac-dualsense.is-enabled"

    @Published var isEnabled: Bool {
        didSet {
            self.controllerManager.releaseInputs()
            defaults.set(isEnabled, forKey: Self.isEnabledDefaultsKey)
        }
    }

    let configStore: ConfigStore
    let controllerManager: ControllerManager
    private var terminationObserver: NSObjectProtocol?
    private let defaults: UserDefaults
    let workspaceSelection: WorkspaceSelection

    isolated deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        controllerManager.releaseInputs()
    }

    static func forLaunch() -> AppState {
        #if DEBUG
        if DemoCapture.outputDirectory != nil { return DemoCapture.makeState() }
        #endif
        return AppState()
    }

    init(configStore: ConfigStore? = nil, controllerManager: ControllerManager? = nil, defaults: UserDefaults = .standard) {
        self.configStore = configStore ?? ConfigStore()
        self.controllerManager = controllerManager ?? ControllerManager()
        self.defaults = defaults
        workspaceSelection = WorkspaceSelection(defaults: defaults)
        isEnabled = defaults.object(forKey: Self.isEnabledDefaultsKey) as? Bool ?? true
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controllerManager.releaseInputs() }
        }
        self.controllerManager.isEnabled = { [weak self] in self?.isEnabled ?? false }
        self.controllerManager.preferredController = { [weak self] in
            self?.configStore.preferredController() ?? "auto"
        }
        self.controllerManager.resolveAction = { [weak self] button in
            guard let self else { return nil }
            return self.configStore.resolve(button: button)
        }
        self.controllerManager.canSendInput = { [weak self] in
            self?.configStore.accessibilityPermissionGranted() ?? false
        }
        self.controllerManager.isCapturing = { [weak self] in
            self?.workspaceSelection.isCapturingInput ?? false
        }
        workspaceSelection.onCaptureChange = { [weak self] in self?.controllerManager.releaseInputs() }
        self.configStore.onRoutingChange = { [weak self] in self?.controllerManager.releaseInputs() }
        self.configStore.onControllerPreferenceChange = { [weak self] in self?.controllerManager.setActiveController(id: nil) }
        self.controllerManager.setActiveController(id: nil)
        self.controllerManager.wisprMode = { [weak self] in
            self?.configStore.wisprSettings().mode ?? "rcmd_hold"
        }
        self.controllerManager.wisprHoldMs = { [weak self] in
            self?.configStore.wisprSettings().holdMs ?? 450
        }
        self.controllerManager.hapticsEnabled = { [weak self] in
            self?.configStore.hapticsEnabled() ?? true
        }
        self.controllerManager.hapticPattern = { [weak self] name in
            self?.configStore.hapticPattern(name)
        }
        self.controllerManager.trackpadEnabled = { [weak self] in
            self?.configStore.currentTrackpadMode() ?? false
        }
        self.controllerManager.trackpadSettings = { [weak self] in
            self?.configStore.trackpadSettings() ?? .init()
        }
    }
}
