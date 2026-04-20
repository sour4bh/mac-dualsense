import AppKit
import SwiftUI

@main
struct MacDualSenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("mac-dualsense", systemImage: "gamecontroller") {
            MenuView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Window("mac-dualsense Settings", id: "settings") {
            SettingsRootView(appState: appState)
        }
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
