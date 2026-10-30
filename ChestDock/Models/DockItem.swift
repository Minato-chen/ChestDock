import Foundation
import AppKit

/// Represents the type of item stored inside a ChestDock category.
/// Phase 1 focuses on `.application`, while `.folder` and `.file` are built-in and can be toggled in Settings.
enum DockItemType: String, Codable, CaseIterable, Identifiable {
    case application
    case folder
    case file

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .application: return "应用程序"
        case .folder: return "文件夹"
        case .file: return "文件"
        }
    }
}

/// A single item inside a category grid.
struct DockItem: Identifiable, Codable, Hashable {
    var id: UUID
    var type: DockItemType
    var path: String
    var customName: String?
    var bookmarkData: Data?

    init(
        id: UUID = UUID(),
        type: DockItemType = .application,
        path: String,
        customName: String? = nil,
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.type = type
        self.path = path
        self.customName = customName
        self.bookmarkData = bookmarkData
    }

    var url: URL {
        if let bookmarkData = bookmarkData {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return resolved
            }
        }
        return URL(fileURLWithPath: path)
    }

    var displayName: String {
        if let custom = customName, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        let targetURL = url
        let localizedName = FileManager.default.displayName(atPath: targetURL.path)
        if localizedName.hasSuffix(".app") {
            return String(localizedName.dropLast(4))
        }
        return localizedName
    }

    var bundleIdentifier: String? {
        guard type == .application else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Creates a `DockItem` from a local file URL if allowed by current settings.
    static func from(url: URL, allowFoldersAndFiles: Bool) -> DockItem? {
        let standardizedURL = url.standardizedFileURL
        let path = standardizedURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return nil
        }

        let isPackage = NSWorkspace.shared.isFilePackage(atPath: path)
        let isApp = path.lowercased().hasSuffix(".app")

        let detectedType: DockItemType
        if isApp {
            detectedType = .application
        } else if isDirectory.boolValue && !isPackage {
            guard allowFoldersAndFiles else { return nil }
            detectedType = .folder
        } else {
            guard allowFoldersAndFiles else { return nil }
            detectedType = .file
        }

        let bookmark = try? standardizedURL.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        return DockItem(
            type: detectedType,
            path: path,
            bookmarkData: bookmark
        )
    }
}
