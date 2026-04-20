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

        SwiftUI.Settings {
            SettingsRootView(appState: appState)
                .frame(minWidth: 920, minHeight: 640)
        }
        .defaultSize(width: 980, height: 680)
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
