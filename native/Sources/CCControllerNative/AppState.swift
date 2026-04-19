import Foundation

@MainActor
final class AppState: ObservableObject {
    private static let isEnabledDefaultsKey = "cc-controller.is-enabled"

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.isEnabledDefaultsKey)
        }
    }

    let configStore = ConfigStore()
    let controllerManager = ControllerManager()

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.isEnabledDefaultsKey) as? Bool ?? true
        controllerManager.isEnabled = { [weak self] in self?.isEnabled ?? false }
        controllerManager.preferredController = { [weak self] in
            self?.configStore.preferredController() ?? "auto"
        }
        controllerManager.resolveAction = { [weak self] button in
            guard let self else { return nil }
            return self.configStore.resolve(button: button)
        }
        controllerManager.accessibilityPrompt = { [weak self] in
            self?.configStore.ensureAccessibilityPermission()
        }
        controllerManager.wisprMode = { [weak self] in
            self?.configStore.wisprSettings().mode ?? "rcmd_hold"
        }
        controllerManager.wisprHoldMs = { [weak self] in
            self?.configStore.wisprSettings().holdMs ?? 450
        }
        controllerManager.hapticsEnabled = { [weak self] in
            self?.configStore.hapticsEnabled() ?? true
        }
        controllerManager.hapticPattern = { [weak self] name in
            self?.configStore.hapticPattern(name)
        }
    }
}
