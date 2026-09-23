import AppKit
import SwiftUI

@main
struct MacDualSenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var appState = AppState.forLaunch()
    @AppStorage("workspace.has-seen-launch") private var hasSeenWorkspaceLaunch = false

    var body: some Scene {
        workspaceWindow
            .commands { MacDualSenseCommands(appState: appState) }

        SwiftUI.Settings { SettingsView(store: appState.configStore) }

        MenuBarExtra {
            MenuView(appState: appState)
        } label: {
            MenuBarLabel(showWorkspace: shouldShowWorkspace)
        }
        .menuBarExtraStyle(.window)
    }

    private var shouldShowWorkspace: Bool {
        #if DEBUG
        if DemoCapture.outputDirectory != nil { return true }
        #endif
        return !hasSeenWorkspaceLaunch
    }

    private var workspaceWindow: some Scene {
        WindowGroup("mac-dualsense", id: WorkspaceRootView.windowID) {
            WorkspaceRootView(appState: appState) {
                hasSeenWorkspaceLaunch = true
            }
        }
        .defaultSize(width: 1200, height: 780)
        .defaultLaunchBehavior(shouldShowWorkspace ? .automatic : .suppressed)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let firstLaunch = !UserDefaults.standard.bool(forKey: "workspace.has-seen-launch")
        #if DEBUG
        let opensWorkspace = firstLaunch || DemoCapture.outputDirectory != nil
        #else
        let opensWorkspace = firstLaunch
        #endif
        NSApp.setActivationPolicy(opensWorkspace ? .regular : .accessory)
        if opensWorkspace { NSApp.activate(ignoringOtherApps: true) }
    }
}

private struct MacDualSenseCommands: Commands {
    let appState: AppState

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Open mac-dualsense…") { openWorkspace() }
                .keyboardShortcut("o", modifiers: [.command])
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
        openWindow(id: WorkspaceRootView.windowID)
    }
}

private struct MenuBarLabel: View {
    let showWorkspace: Bool
    @Environment(\.openWindow) private var openWindow
    @State private var opened = false

    var body: some View {
        Image(systemName: "gamecontroller")
            .accessibilityLabel("mac-dualsense")
            .onAppear {
                guard showWorkspace, !opened else { return }
                opened = true
                openWindow(id: WorkspaceRootView.windowID)
            }
    }
}
