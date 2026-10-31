import Foundation
import CoreGraphics

enum DockTilePreviewGrid: Int, Codable, CaseIterable, Identifiable {
    case staticAppIcon = 0
    case twoByTwo = 2
    case threeByThree = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .staticAppIcon: return "默认应用图标"
        case .twoByTwo: return "2 × 2 (四宫格动态预览)"
        case .threeByThree: return "3 × 3 (九宫格动态预览)"
        }
    }

    var maxIcons: Int {
        rawValue * rawValue
    }
}

/// Represents a configurable shortcut key with modifiers
struct KeyShortcut: Codable, Equatable {
    var isEnabled: Bool = true
    var key: String // e.g. "p", "m", " "
    var modifiers: [String] // e.g. ["command"], ["shift", "command"]

    var displayString: String {
        guard isEnabled else { return "已禁用" }
        var str = ""
        if modifiers.contains("control") { str += "⌃" }
        if modifiers.contains("option") { str += "⌥" }
        if modifiers.contains("shift") { str += "⇧" }
        if modifiers.contains("command") { str += "⌘" }
        str += key.uppercased()
        return str
    }
}

struct GridConfig: Codable, Equatable {
    var rows: Int = 3
    var columns: Int = 4
    var iconSize: Double = 60.0
    var showRunningIndicator: Bool = true
    var showMenuBarIcon: Bool = true
    var dockPreviewGrid: DockTilePreviewGrid = .staticAppIcon
    var syncDockIconWithActiveCategory: Bool = false
    /// Phase 2 extension switch: allow folders & files to be added alongside .app bundles
    var allowFoldersAndFiles: Bool = false

    // General & Auto-launch settings
    var launchAtLogin: Bool = false
    var autoCheckUpdates: Bool = true

    // Customizable shortcuts (with independent enabled switches)
    var togglePinShortcut: KeyShortcut = KeyShortcut(isEnabled: true, key: "p", modifiers: ["command"])
    var toggleCollapseShortcut: KeyShortcut = KeyShortcut(isEnabled: true, key: "m", modifiers: ["command"])

    var pageSize: Int {
        max(1, rows * columns)
    }

    /// Computes the ideal cell width & height based on `iconSize`
    var cellWidth: CGFloat {
        CGFloat(iconSize) + 32
    }

    var cellHeight: CGFloat {
        CGFloat(iconSize) + 38
    }

    /// Computes the total bubble window size including top category bar, grid, page indicator, and tail.
    func bubbleSize(tailHeight: CGFloat = 14) -> CGSize {
        let horizontalPadding: CGFloat = 36
        let topBarHeight: CGFloat = 48
        let pageControlHeight: CGFloat = 28
        let verticalPadding: CGFloat = 24

        let gridWidth = CGFloat(columns) * cellWidth + CGFloat(max(0, columns - 1)) * 8
        let gridHeight = CGFloat(rows) * cellHeight + CGFloat(max(0, rows - 1)) * 8

        let width = max(320, gridWidth + horizontalPadding)
        let height = topBarHeight + gridHeight + pageControlHeight + verticalPadding + tailHeight
        return CGSize(width: width, height: height)
    }
}
