import AppKit
import SwiftUI

@main
struct CCControllerNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("CC Controller", systemImage: "gamecontroller") {
            MenuView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Preferences", id: "preferences") {
            PreferencesView(appState: appState)
                .frame(minWidth: 700, minHeight: 700)
        }
        .defaultSize(width: 800, height: 800)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
