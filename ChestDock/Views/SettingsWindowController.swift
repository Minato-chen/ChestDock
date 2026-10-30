import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func showSettings() {
        // Hide the floating bubble first so it doesn't cover the Settings window
        BubblePanelController.shared.hide()

        if let existing = window {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = SettingsView(store: ChestStore.shared)
        let hostingController = NSHostingController(rootView: contentView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "ChestDock 设置"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 680, height: 480))
        newWindow.minSize = NSSize(width: 620, height: 440)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }
}
