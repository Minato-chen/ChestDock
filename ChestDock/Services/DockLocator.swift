import AppKit
import ApplicationServices

/// Represents which screen edge the bubble is anchored to (`.top` is used when opened from the Menu Bar).
enum DockEdge: String {
    case bottom
    case left
    case right
    case top
}

/// Information about where the target icon sits on the screen so the bubble tail points directly at it.
struct DockAnchorInfo {
    /// Anchor point in AppKit screen coordinates (bottom-left origin) where the bubble tail tip should point.
    var anchorPoint: CGPoint
    /// Which screen edge the bubble tail points toward.
    var edge: DockEdge
    /// The screen containing the icon.
    var screen: NSScreen
}

enum DockLocator {
    private static var lastKnownAnchorPoint: CGPoint?

    /// Checks whether the app currently has Accessibility permission (optional, used for exact Dock icon bounds).
    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Resolves the anchor point under the Menu Bar status item button.
    static func resolveMenuBarAnchor(from button: NSStatusBarButton?) -> DockAnchorInfo {
        if let button = button, let window = button.window {
            let buttonRectInWindow = button.convert(button.bounds, to: nil)
            let screenRect = window.convertToScreen(buttonRectInWindow)
            let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
            let anchor = CGPoint(x: screenRect.midX, y: screenRect.minY - 2)
            return DockAnchorInfo(anchorPoint: anchor, edge: .top, screen: screen)
        }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let anchor = CGPoint(x: mouseLocation.x, y: screen.visibleFrame.maxY - 2)
        return DockAnchorInfo(anchorPoint: anchor, edge: .top, screen: screen)
    }

    /// Resolves the anchor point on the Dock for placing the bubble popover.
    static func resolveDockAnchor() -> DockAnchorInfo {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        let edge = detectDockEdge(on: screen)

        // 1. Try exact Accessibility lookup of the ChestDock icon in com.apple.dock
        if isAccessibilityTrusted(prompt: false),
           let iconRect = findDockIconRectInAppKitCoords() {
            let anchor = anchorPoint(forIconRect: iconRect, edge: edge)
            lastKnownAnchorPoint = anchor
            return DockAnchorInfo(anchorPoint: anchor, edge: edge, screen: screen)
        }

        // 2. Zero-permission fallback: infer from click mouse location & Dock visibleFrame margin
        let anchor = fallbackAnchorPoint(mouseLocation: mouseLocation, screen: screen, edge: edge)
        lastKnownAnchorPoint = anchor
        return DockAnchorInfo(anchorPoint: anchor, edge: edge, screen: screen)
    }

    /// Detects which edge of the screen the Dock resides on by comparing `frame` and `visibleFrame`.
    static func detectDockEdge(on screen: NSScreen) -> DockEdge {
        let full = screen.frame
        let visible = screen.visibleFrame

        let leftMargin = visible.minX - full.minX
        let rightMargin = full.maxX - visible.maxX
        let bottomMargin = visible.minY - full.minY

        if leftMargin > bottomMargin && leftMargin > rightMargin && leftMargin > 10 {
            return .left
        }
        if rightMargin > bottomMargin && rightMargin > leftMargin && rightMargin > 10 {
            return .right
        }
        return .bottom
    }

    private static func anchorPoint(forIconRect rect: CGRect, edge: DockEdge) -> CGPoint {
        switch edge {
        case .bottom:
            return CGPoint(x: rect.midX, y: rect.maxY + 4)
        case .left:
            return CGPoint(x: rect.maxX + 4, y: rect.midY)
        case .right:
            return CGPoint(x: rect.minX - 4, y: rect.midY)
        case .top:
            return CGPoint(x: rect.midX, y: rect.minY - 4)
        }
    }

    private static func fallbackAnchorPoint(mouseLocation: CGPoint, screen: NSScreen, edge: DockEdge) -> CGPoint {
        let full = screen.frame
        let visible = screen.visibleFrame

        switch edge {
        case .bottom:
            let dockTopY = max(visible.minY, full.minY + 68)
            let isMouseNearDock = mouseLocation.y <= dockTopY + 50
            let anchorX: CGFloat
            if isMouseNearDock {
                anchorX = mouseLocation.x
            } else if let last = lastKnownAnchorPoint {
                anchorX = last.x
            } else {
                anchorX = full.midX
            }
            return CGPoint(x: anchorX, y: dockTopY + 4)

        case .left:
            let dockRightX = max(visible.minX, full.minX + 68)
            let isMouseNearDock = mouseLocation.x <= dockRightX + 50
            let anchorY = isMouseNearDock ? mouseLocation.y : (lastKnownAnchorPoint?.y ?? full.midY)
            return CGPoint(x: dockRightX + 4, y: anchorY)

        case .right:
            let dockLeftX = min(visible.maxX, full.maxX - 68)
            let isMouseNearDock = mouseLocation.x >= dockLeftX - 50
            let anchorY = isMouseNearDock ? mouseLocation.y : (lastKnownAnchorPoint?.y ?? full.midY)
            return CGPoint(x: dockLeftX - 4, y: anchorY)

        case .top:
            return CGPoint(x: mouseLocation.x, y: visible.maxY - 2)
        }
    }

    // MARK: - Accessibility Dock Icon Lookup

    private static func findDockIconRectInAppKitCoords() -> CGRect? {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        let appName = ProcessInfo.processInfo.processName
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL

        for child in children {
            var listChildrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &listChildrenRef) == .success,
                  let dockItems = listChildrenRef as? [AXUIElement] else {
                continue
            }

            for item in dockItems {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef)
                let title = titleRef as? String

                var urlRef: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &urlRef)
                let itemURL = (urlRef as? URL)?.standardizedFileURL

                let isMatch = (title == appName) || (itemURL == bundleURL)
                guard isMatch else { continue }

                var posRef: CFTypeRef?
                var sizeRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &posRef) == .success,
                      AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeRef) == .success,
                      let posVal = posRef,
                      let sizeVal = sizeRef else {
                    continue
                }

                var cgPoint = CGPoint.zero
                var cgSize = CGSize.zero
                AXValueGetValue(posVal as! AXValue, .cgPoint, &cgPoint)
                AXValueGetValue(sizeVal as! AXValue, .cgSize, &cgSize)

                let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
                let appKitY = primaryScreenHeight - cgPoint.y - cgSize.height
                return CGRect(x: cgPoint.x, y: appKitY, width: cgSize.width, height: cgSize.height)
            }
        }

        return nil
    }
}
