import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ChestStore.shared
        store.refreshDockTile()

        // Observe menu bar icon preference
        store.$config
            .map(\.showMenuBarIcon)
            .removeDuplicates()
            .sink { [weak self] show in
                self?.updateStatusItem(visible: show)
            }
            .store(in: &cancellables)

        // Silent check for updates if enabled
        if store.config.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                UpdateChecker.shared.checkForUpdates(isUserInitiated: false)
            }
        }
    }

    /// Invoked whenever the user clicks the ChestDock icon in the macOS Dock.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        BubblePanelController.shared.toggleFromDockClick()
        return false
    }

    /// Custom right-click menu on the Dock icon.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu(title: "ChestDock")
        let store = ChestStore.shared
        let bubble = BubblePanelController.shared

        let toggleItem = NSMenuItem(
            title: bubble.isVisible ? "收起应用气泡" : "展开应用气泡",
            action: #selector(handleToggleFromDock),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let pinItem = NSMenuItem(
            title: "钉住气泡面板",
            action: #selector(handlePinFromDock),
            keyEquivalent: ""
        )
        pinItem.target = self
        pinItem.state = (bubble.isVisible && bubble.layoutState.isPinned) ? .on : .off
        menu.addItem(pinItem)

        menu.addItem(.separator())

        // Quick access to categories in Dock right-click menu
        for category in store.categories {
            let subMenu = NSMenu(title: category.name)
            if category.items.isEmpty {
                let emptyItem = NSMenuItem(title: "（空分类）", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                subMenu.addItem(emptyItem)
            } else {
                for dockItem in category.items {
                    let appMenuItem = NSMenuItem(
                        title: dockItem.displayName,
                        action: #selector(handleLaunchFromDockMenu(_:)),
                        keyEquivalent: ""
                    )
                    appMenuItem.target = self
                    appMenuItem.representedObject = dockItem
                    let icon = store.icon(for: dockItem).copy() as? NSImage
                    icon?.size = NSSize(width: 18, height: 18)
                    appMenuItem.image = icon
                    subMenu.addItem(appMenuItem)
                }
            }
            let categoryItem = NSMenuItem(title: category.name, action: nil, keyEquivalent: "")
            categoryItem.submenu = subMenu
            menu.addItem(categoryItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "ChestDock 设置...",
            action: #selector(handleOpenSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        return menu
    }

    // MARK: - Status Bar Item (Left-click pops Bubble, Right-click pops Context Menu)

    private func updateStatusItem(visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.image = NSImage(
                    systemSymbolName: "square.grid.2x2.fill",
                    accessibilityDescription: "ChestDock"
                )
                button.target = self
                button.action = #selector(handleStatusBarButtonClick(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                BubblePanelController.shared.registerStatusButton(button)
            }
            self.statusItem = item
        } else {
            if let existing = statusItem {
                if BubblePanelController.shared.isVisible,
                   BubblePanelController.shared.layoutState.triggerSource == .menuBar,
                   !BubblePanelController.shared.layoutState.isPinned {
                    BubblePanelController.shared.hide(forceEvenIfPinned: true)
                }
                NSStatusBar.system.removeStatusItem(existing)
                statusItem = nil
            }
        }
    }

    @objc private func handleStatusBarButtonClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            BubblePanelController.shared.toggleFromMenuBar(button: sender)
            return
        }

        let isRightClick = (event.type == .rightMouseUp) || event.modifierFlags.contains(.control)
        if isRightClick {
            presentStatusBarContextMenu(from: sender)
        } else {
            BubblePanelController.shared.toggleFromMenuBar(button: sender)
        }
    }

    private func presentStatusBarContextMenu(from button: NSStatusBarButton) {
        guard let statusItem = statusItem else { return }
        let bubble = BubblePanelController.shared
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: bubble.isVisible ? "收起气泡面板" : "展开气泡面板",
            action: #selector(handleToggleFromMenuBar),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let pinItem = NSMenuItem(
            title: "钉住气泡面板",
            action: #selector(handlePinFromMenuBar),
            keyEquivalent: ""
        )
        pinItem.target = self
        pinItem.state = (bubble.isVisible && bubble.layoutState.isPinned) ? .on : .off
        menu.addItem(pinItem)

        if bubble.isVisible && bubble.layoutState.isDetachedFromDock {
            let snapItem = NSMenuItem(
                title: "归位面板",
                action: #selector(handleSnapBack),
                keyEquivalent: ""
            )
            snapItem.target = self
            menu.addItem(snapItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "设置...",
            action: #selector(handleOpenSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let hideMenuBarItem = NSMenuItem(
            title: "隐藏菜单栏图标",
            action: #selector(handleHideMenuBarIcon),
            keyEquivalent: ""
        )
        hideMenuBarItem.target = self
        menu.addItem(hideMenuBarItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 ChestDock",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Menu Actions

    @objc private func handleToggleFromDock() {
        if BubblePanelController.shared.isVisible {
            BubblePanelController.shared.hide(forceEvenIfPinned: true)
        } else {
            BubblePanelController.shared.showFromDock()
        }
    }

    @objc private func handlePinFromDock() {
        BubblePanelController.shared.openPinnedOrTogglePin(source: .dock)
    }

    @objc private func handleToggleFromMenuBar() {
        BubblePanelController.shared.toggleFromMenuBar(button: statusItem?.button)
    }

    @objc private func handlePinFromMenuBar() {
        BubblePanelController.shared.openPinnedOrTogglePin(
            source: .menuBar,
            statusButton: statusItem?.button
        )
    }

    @objc private func handleSnapBack() {
        BubblePanelController.shared.snapBackToAnchor()
    }

    @objc private func handleHideMenuBarIcon() {
        ChestStore.shared.config.showMenuBarIcon = false
    }

    @objc private func handleOpenSettings() {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func handleLaunchFromDockMenu(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? DockItem else { return }
        ChestStore.shared.launchItem(item)
    }
}
