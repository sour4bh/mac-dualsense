#if DEBUG
import AppKit
import SwiftUI
import ScreenCaptureKit

@MainActor
enum DemoCapture {
    static var outputDirectory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--capture-demo"), index + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }

    private static var started = false

    static func makeState() -> AppState {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mac-dualsense-demo-\(UUID().uuidString)/mappings.yaml")
        let store = ConfigStore(configURL: file, watch: false, automaticallySaves: false)
        let defaults = UserDefaults(suiteName: "com.sour4bh.mac-dualsense.demo")!
        return AppState(configStore: store, controllerManager: ControllerManager(discover: false), defaults: defaults)
    }

    static func start(appState: AppState) {
        guard !started, let directory = outputDirectory else { return }
        started = true
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try await Task.sleep(for: .seconds(1))
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width >= 1000 }) else { return }
                window.setContentSize(NSSize(width: 1200, height: 780))
                appState.workspaceSelection.editedContext = "default"
                appState.workspaceSelection.section = .controller
                appState.workspaceSelection.inspectorVisible = false
                NSApp.appearance = NSAppearance(named: .aqua)
                window.appearance = NSAppearance(named: .aqua)
                appState.workspaceSelection.previewColorScheme = .light
                try await snapshot(window, to: directory.appendingPathComponent("controller-light.png"))
                appState.workspaceSelection.selectedButton = "cross"
                appState.workspaceSelection.inspectorVisible = true
                try await snapshot(window, to: directory.appendingPathComponent("binding-light.png"))
                NSApp.appearance = NSAppearance(named: .darkAqua)
                window.appearance = NSAppearance(named: .darkAqua)
                appState.workspaceSelection.previewColorScheme = .dark
                try await snapshot(window, to: directory.appendingPathComponent("controller-dark.png"))
                NSApp.appearance = NSAppearance(named: .aqua)
                window.appearance = NSAppearance(named: .aqua)
                appState.workspaceSelection.previewColorScheme = .light
                appState.workspaceSelection.section = .apps
                try await snapshot(window, to: directory.appendingPathComponent("apps-light.png"))
                appState.workspaceSelection.section = .profiles
                try await snapshot(window, to: directory.appendingPathComponent("profiles-light.png"))
                appState.workspaceSelection.section = .keybinds
                window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 1000, height: 640)), display: true)
                try await snapshot(window, to: directory.appendingPathComponent("keybinds-compact.png"))
                appState.workspaceSelection.inspectorVisible = true
                try await snapshot(window, to: directory.appendingPathComponent("inspector-compact.png"))
                appState.workspaceSelection.section = .controller
                try await snapshot(window, to: directory.appendingPathComponent("controller-compact.png"))
                try "Captured actual app views using an isolated configuration; no controller connected.\n".write(to: directory.appendingPathComponent("capture.txt"), atomically: true, encoding: .utf8)
                try? FileManager.default.removeItem(at: appState.configStore.configFileURL.deletingLastPathComponent())
                NSApp.terminate(nil)
            } catch {
                Logger.shared.error("Demo capture failed: \(error)")
                NSApp.terminate(nil)
            }
        }
    }

    private static func snapshot(_ window: NSWindow, to url: URL) async throws {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .seconds(1.2))
        Logger.shared.info("Capture \(url.lastPathComponent) frame=\(window.frame) minimum=\(window.minSize) contentMinimum=\(window.contentMinSize) fitting=\(window.contentView?.fittingSize ?? .zero)")
        let content = try await SCShareableContent.currentProcess
        guard let ownWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { throw CaptureError.noView }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * 2)
        configuration.height = Int(window.frame.height * 2)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: ownWindow), configuration: configuration
        )
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CaptureError.noBitmap }
        try png.write(to: url)
    }

    private enum CaptureError: Error { case noView, noBitmap }
}
#endif
