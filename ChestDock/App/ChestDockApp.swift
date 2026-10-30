import SwiftUI

@main
struct ChestDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: ChestStore.shared)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    SettingsWindowController.shared.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
