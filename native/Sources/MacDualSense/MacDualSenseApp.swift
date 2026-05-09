import AppKit
import SwiftUI

@main
struct MacDualSenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var appState = AppState()
    @AppStorage("workspace.has-seen-launch") private var hasSeenWorkspaceLaunch = false

    var body: some Scene {
        MenuBarExtra("mac-dualsense", systemImage: "gamecontroller") {
            MenuView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        workspaceWindow
            .commands {
                MacDualSenseCommands(appState: appState)
            }
    }

    private var workspaceWindow: some Scene {
        WindowGroup("mac-dualsense", id: WorkspaceRootView.windowID) {
            WorkspaceRootView(appState: appState) {
                hasSeenWorkspaceLaunch = true
            }
        }
        .defaultSize(width: 1280, height: 800)
        .defaultLaunchBehavior(hasSeenWorkspaceLaunch ? .suppressed : .automatic)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct MacDualSenseCommands: Commands {
    let appState: AppState

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Open mac-dualsense…") {
                openWorkspace()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        CommandMenu("Controller") {
            Button(appState.isEnabled ? "Pause Input" : "Resume Input") {
                appState.isEnabled.toggle()
            }
            .keyboardShortcut("e", modifiers: [.command, .option])

            Divider()

            Button("Reload Config") {
                appState.configStore.reload()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Open Config in Finder") {
                appState.configStore.openConfigInFinder()
            }

            Button("Reveal Logs") {
                Logger.shared.revealLogFileInFinder()
            }
        }
    }

    private func openWorkspace() {
        NSApp.activate(ignoringOtherApps: true)
        Task {
            try? await openWindow(id: WorkspaceRootView.windowID, sharingBehavior: .required)
        }
    }
}
