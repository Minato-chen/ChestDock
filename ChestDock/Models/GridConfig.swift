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
    var version: Int = 1
    var rows: Int = 3
    var columns: Int = 4
    var iconSize: Double = 60.0
    var showRunningIndicator: Bool = true
    var showMenuBarIcon: Bool = true
    var dockPreviewGrid: DockTilePreviewGrid = .twoByTwo
    var syncDockIconWithActiveCategory: Bool = false
    /// Phase 2 extension switch: allow folders & files to be added alongside .app bundles
    var allowFoldersAndFiles: Bool = false

    // General & Auto-launch settings
    var launchAtLogin: Bool = false
    var autoCheckUpdates: Bool = true

    // Customizable shortcuts (with independent enabled switches, disabled by default)
    var togglePinShortcut: KeyShortcut = KeyShortcut(isEnabled: false, key: "p", modifiers: ["command"])
    var toggleCollapseShortcut: KeyShortcut = KeyShortcut(isEnabled: false, key: "m", modifiers: ["command"])

    // Floating Trigger & Edge Snapping
    var enableFloatingTrigger: Bool = false
    var autoSnapToEdge: Bool = true

    enum CodingKeys: String, CodingKey {
        case version, rows, columns, iconSize, showRunningIndicator, showMenuBarIcon
        case dockPreviewGrid, syncDockIconWithActiveCategory, allowFoldersAndFiles
        case launchAtLogin, autoCheckUpdates, togglePinShortcut, toggleCollapseShortcut
        case enableFloatingTrigger, autoSnapToEdge
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = (try? container.decode(Int.self, forKey: .version)) ?? 1
        self.rows = (try? container.decode(Int.self, forKey: .rows)) ?? 3
        self.columns = (try? container.decode(Int.self, forKey: .columns)) ?? 4
        self.iconSize = (try? container.decode(Double.self, forKey: .iconSize)) ?? 60.0
        self.showRunningIndicator = (try? container.decode(Bool.self, forKey: .showRunningIndicator)) ?? true
        self.showMenuBarIcon = (try? container.decode(Bool.self, forKey: .showMenuBarIcon)) ?? true
        self.dockPreviewGrid = (try? container.decode(DockTilePreviewGrid.self, forKey: .dockPreviewGrid)) ?? .twoByTwo
        self.syncDockIconWithActiveCategory = (try? container.decode(Bool.self, forKey: .syncDockIconWithActiveCategory)) ?? false
        self.allowFoldersAndFiles = (try? container.decode(Bool.self, forKey: .allowFoldersAndFiles)) ?? false
        self.launchAtLogin = (try? container.decode(Bool.self, forKey: .launchAtLogin)) ?? false
        self.autoCheckUpdates = (try? container.decode(Bool.self, forKey: .autoCheckUpdates)) ?? true
        self.togglePinShortcut = (try? container.decode(KeyShortcut.self, forKey: .togglePinShortcut)) ?? KeyShortcut(isEnabled: false, key: "p", modifiers: ["command"])
        self.toggleCollapseShortcut = (try? container.decode(KeyShortcut.self, forKey: .toggleCollapseShortcut)) ?? KeyShortcut(isEnabled: false, key: "m", modifiers: ["command"])
        self.enableFloatingTrigger = (try? container.decode(Bool.self, forKey: .enableFloatingTrigger)) ?? false
        self.autoSnapToEdge = (try? container.decode(Bool.self, forKey: .autoSnapToEdge)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(rows, forKey: .rows)
        try container.encode(columns, forKey: .columns)
        try container.encode(iconSize, forKey: .iconSize)
        try container.encode(showRunningIndicator, forKey: .showRunningIndicator)
        try container.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
        try container.encode(dockPreviewGrid, forKey: .dockPreviewGrid)
        try container.encode(syncDockIconWithActiveCategory, forKey: .syncDockIconWithActiveCategory)
        try container.encode(allowFoldersAndFiles, forKey: .allowFoldersAndFiles)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(autoCheckUpdates, forKey: .autoCheckUpdates)
        try container.encode(togglePinShortcut, forKey: .togglePinShortcut)
        try container.encode(toggleCollapseShortcut, forKey: .toggleCollapseShortcut)
        try container.encode(enableFloatingTrigger, forKey: .enableFloatingTrigger)
        try container.encode(autoSnapToEdge, forKey: .autoSnapToEdge)
    }

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
