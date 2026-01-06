import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var isEnabled: Bool = false

    let configStore = ConfigStore()
    let controllerManager = ControllerManager()

    init() {
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
    }
}
