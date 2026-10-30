import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class ChestStore: ObservableObject {
    static let shared = ChestStore()

    @Published var categories: [AppCategory] = [] {
        didSet {
            ensureValidSelection()
            saveState()
            refreshDockTile()
        }
    }

    @Published var selectedCategoryId: UUID? {
        didSet {
            if oldValue != selectedCategoryId {
                currentPage = 0
                if config.syncDockIconWithActiveCategory {
                    refreshDockTile()
                }
            }
        }
    }

    @Published var currentPage: Int = 0

    @Published var config: GridConfig = GridConfig() {
        didSet {
            clampCurrentPage()
            saveState()
            refreshDockTile()
            onConfigChanged?()
        }
    }

    @Published private(set) var runningBundleIDs: Set<String> = []
    @Published private(set) var runningAppPaths: Set<String> = []

    /// Callback invoked when user launches an item so the bubble immediately dismisses.
    var onItemLaunched: (() -> Void)?
    /// Callback invoked when grid config changes so the bubble window resizes smoothly.
    var onConfigChanged: (() -> Void)?

    private var workspaceObservers: [NSObjectProtocol] = []
    private var iconCache: [String: NSImage] = [:]
    private var isLoading = false

    private struct PersistedData: Codable {
        var categories: [AppCategory]
        var config: GridConfig
        var selectedCategoryId: UUID?
    }

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("ChestDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("state.json")
    }

    private init() {
        loadState()
        setupRunningAppsObserver()
        refreshRunningApps()
        refreshDockTile()
    }

    // MARK: - Computed Properties

    var selectedCategory: AppCategory? {
        if let id = selectedCategoryId, let match = categories.first(where: { $0.id == id }) {
            return match
        }
        return categories.first
    }

    var selectedCategoryIndex: Int? {
        guard let id = selectedCategory?.id else { return nil }
        return categories.firstIndex(where: { $0.id == id })
    }

    var currentPages: [[DockItem]] {
        guard let category = selectedCategory else { return [[]] }
        return category.pages(pageSize: config.pageSize)
    }

    var pageCount: Int {
        max(1, currentPages.count)
    }

    // MARK: - Selection & Pagination

    func selectCategory(_ id: UUID) {
        guard selectedCategoryId != id else { return }
        selectedCategoryId = id
        currentPage = 0
    }

    func selectNextCategory() {
        guard !categories.isEmpty else { return }
        let idx = selectedCategoryIndex ?? 0
        let nextIdx = (idx + 1) % categories.count
        selectedCategoryId = categories[nextIdx].id
    }

    func selectPreviousCategory() {
        guard !categories.isEmpty else { return }
        let idx = selectedCategoryIndex ?? 0
        let prevIdx = (idx - 1 + categories.count) % categories.count
        selectedCategoryId = categories[prevIdx].id
    }

    func goToNextPage() {
        if currentPage < pageCount - 1 {
            currentPage += 1
        }
    }

    func goToPreviousPage() {
        if currentPage > 0 {
            currentPage -= 1
        }
    }

    private func ensureValidSelection() {
        if categories.isEmpty {
            return
        }
        if let selectedCategoryId = selectedCategoryId,
           categories.contains(where: { $0.id == selectedCategoryId }) {
            clampCurrentPage()
            return
        }
        selectedCategoryId = categories.first?.id
        currentPage = 0
    }

    private func clampCurrentPage() {
        let maxPage = max(0, pageCount - 1)
        if currentPage > maxPage {
            currentPage = maxPage
        }
    }

    // MARK: - Category Operations

    @discardableResult
    func addCategory(name: String, iconSystemName: String? = nil) -> AppCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "新分类" : trimmed
        let newCategory = AppCategory(name: finalName, iconSystemName: iconSystemName, items: [])
        categories.append(newCategory)
        selectedCategoryId = newCategory.id
        return newCategory
    }

    func renameCategory(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[idx].name = trimmed
    }

    func deleteCategory(id: UUID) {
        guard categories.count > 1 else { return }
        categories.removeAll { $0.id == id }
        ensureValidSelection()
    }

    func moveCategory(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Item Operations

    func addItems(from urls: [URL], to categoryId: UUID? = nil) {
        let targetId = categoryId ?? selectedCategory?.id
        guard let targetId = targetId,
              let catIdx = categories.firstIndex(where: { $0.id == targetId }) else { return }

        var addedCount = 0
        for url in urls {
            guard let item = DockItem.from(url: url, allowFoldersAndFiles: config.allowFoldersAndFiles) else {
                continue
            }
            // Avoid duplicates in the same category
            let alreadyExists = categories[catIdx].items.contains {
                $0.url.standardizedFileURL.path == item.url.standardizedFileURL.path
            }
            if !alreadyExists {
                categories[catIdx].items.append(item)
                addedCount += 1
            }
        }

        if addedCount > 0 {
            let totalPages = categories[catIdx].pages(pageSize: config.pageSize).count
            currentPage = max(0, totalPages - 1)
        }
    }

    func removeItem(_ itemId: UUID, from categoryId: UUID? = nil) {
        let targetId = categoryId ?? selectedCategory?.id
        guard let targetId = targetId,
              let catIdx = categories.firstIndex(where: { $0.id == targetId }) else { return }
        categories[catIdx].items.removeAll { $0.id == itemId }
        clampCurrentPage()
    }

    func moveItem(_ itemId: UUID, from sourceCategoryId: UUID, to targetCategoryId: UUID) {
        guard sourceCategoryId != targetCategoryId,
              let srcIdx = categories.firstIndex(where: { $0.id == sourceCategoryId }),
              let dstIdx = categories.firstIndex(where: { $0.id == targetCategoryId }),
              let itemIdx = categories[srcIdx].items.firstIndex(where: { $0.id == itemId }) else {
            return
        }
        let item = categories[srcIdx].items.remove(at: itemIdx)
        if !categories[dstIdx].items.contains(where: { $0.path == item.path }) {
            categories[dstIdx].items.append(item)
        }
        clampCurrentPage()
    }

    func reorderItem(draggedItemId: UUID, targetItemId: UUID, in categoryId: UUID? = nil) {
        guard draggedItemId != targetItemId else { return }
        let targetCatId = categoryId ?? selectedCategory?.id
        guard let targetCatId = targetCatId,
              let catIdx = categories.firstIndex(where: { $0.id == targetCatId }),
              let fromIndex = categories[catIdx].items.firstIndex(where: { $0.id == draggedItemId }),
              let toIndex = categories[catIdx].items.firstIndex(where: { $0.id == targetItemId }) else {
            return
        }
        var updatedItems = categories[catIdx].items
        let moved = updatedItems.remove(at: fromIndex)
        updatedItems.insert(moved, at: toIndex)
        categories[catIdx].items = updatedItems
    }

    // MARK: - Interactive Open Panel for Adding Apps

    func presentAddItemsPanel(for categoryId: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = config.allowFoldersAndFiles
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        if config.allowFoldersAndFiles {
            panel.title = "添加应用、文件夹或文件"
            panel.prompt = "添加"
            panel.allowedContentTypes = [.application, .folder, .item]
        } else {
            panel.title = "选择要添加的应用程序"
            panel.prompt = "添加应用"
            panel.allowedContentTypes = [.applicationBundle, .application]
        }

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            addItems(from: panel.urls, to: categoryId)
        }
    }

    // MARK: - Launching & Actions

    func launchItem(_ item: DockItem, forceKeepBubbleOpen: Bool = false) {
        let targetURL = item.url
        let flags = NSEvent.modifierFlags
        let shouldKeepOpen = forceKeepBubbleOpen || flags.contains(.command) || flags.contains(.option)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.open(targetURL, configuration: configuration) { [weak self] _, error in
            if let error = error {
                NSLog("Failed to open \(targetURL.path): \(error.localizedDescription)")
            }
            if !shouldKeepOpen {
                Task { @MainActor in
                    self?.onItemLaunched?()
                }
            }
        }
        // Immediately notify to dismiss bubble unless modifier key is held
        if !shouldKeepOpen {
            onItemLaunched?()
        }
    }

    func openFiles(_ fileURLs: [URL], withApp item: DockItem) {
        guard item.type == .application else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            fileURLs,
            withApplicationAt: item.url,
            configuration: configuration
        ) { _, _ in }
        onItemLaunched?()
    }

    func revealInFinder(_ item: DockItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
        onItemLaunched?()
    }

    func quitRunningApp(_ item: DockItem) {
        guard item.type == .application else { return }
        let path = item.url.standardizedFileURL.path
        let bundleId = item.bundleIdentifier
        for runningApp in NSWorkspace.shared.runningApplications {
            if let bundleId = bundleId, runningApp.bundleIdentifier == bundleId {
                runningApp.terminate()
            } else if runningApp.bundleURL?.standardizedFileURL.path == path {
                runningApp.terminate()
            }
        }
    }

    func isItemRunning(_ item: DockItem) -> Bool {
        guard item.type == .application else { return false }
        if let bundleId = item.bundleIdentifier, runningBundleIDs.contains(bundleId) {
            return true
        }
        return runningAppPaths.contains(item.url.standardizedFileURL.path)
    }

    // MARK: - Icon Cache

    func icon(for item: DockItem) -> NSImage {
        let key = item.url.path
        if let cached = iconCache[key] {
            return cached
        }
        let img = NSWorkspace.shared.icon(forFile: key)
        img.size = NSSize(width: 128, height: 128)
        iconCache[key] = img
        return img
    }

    // MARK: - Running Apps Tracking

    private func setupRunningAppsObserver() {
        let center = NSWorkspace.shared.notificationCenter
        let launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRunningApps()
            }
        }
        let terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRunningApps()
            }
        }
        workspaceObservers = [launchObserver, terminateObserver]
    }

    private func refreshRunningApps() {
        var bundleIDs = Set<String>()
        var paths = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier {
                bundleIDs.insert(id)
            }
            if let url = app.bundleURL?.standardizedFileURL {
                paths.insert(url.path)
            }
        }
        runningBundleIDs = bundleIDs
        runningAppPaths = paths
    }

    // MARK: - Dock Tile Rendering

    func refreshDockTile() {
        guard !isLoading else { return }
        let previewCategory: AppCategory?
        if config.syncDockIconWithActiveCategory {
            previewCategory = selectedCategory ?? categories.first
        } else {
            previewCategory = categories.first
        }
        let items = previewCategory?.items ?? []
        let icons = items.prefix(config.dockPreviewGrid.maxIcons).map { icon(for: $0) }
        DockTileRenderer.updateDockTile(
            with: icons,
            grid: config.dockPreviewGrid
        )
    }

    // MARK: - Persistence & Default Data

    private func loadState() {
        isLoading = true
        defer { isLoading = false }

        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode(PersistedData.self, from: data),
           !decoded.categories.isEmpty {
            self.categories = decoded.categories
            self.config = decoded.config
            self.selectedCategoryId = decoded.selectedCategoryId ?? decoded.categories.first?.id
            return
        }

        // Populate starter categories with real macOS applications
        self.categories = Self.createDefaultCategories()
        self.selectedCategoryId = self.categories.first?.id
        saveState()
    }

    private func saveState() {
        guard !isLoading else { return }
        let payload = PersistedData(
            categories: categories,
            config: config,
            selectedCategoryId: selectedCategoryId
        )
        if let encoded = try? JSONEncoder().encode(payload) {
            try? encoded.write(to: storageURL, options: .atomic)
        }
    }

    private static func createDefaultCategories() -> [AppCategory] {
        func findApps(_ candidatePaths: [String]) -> [DockItem] {
            var results: [DockItem] = []
            for path in candidatePaths {
                if FileManager.default.fileExists(atPath: path) {
                    let url = URL(fileURLWithPath: path)
                    if let item = DockItem.from(url: url, allowFoldersAndFiles: false) {
                        results.append(item)
                    }
                }
            }
            return results
        }

        let commonCandidates = [
            "/Applications/Safari.app",
            "/System/Cryptexes/App/System/Applications/Safari.app",
            "/System/Applications/Mail.app",
            "/System/Applications/Calendar.app",
            "/System/Applications/Notes.app",
            "/System/Applications/Reminders.app",
            "/System/Applications/Messages.app",
            "/System/Applications/Music.app",
            "/System/Applications/Photos.app",
            "/System/Applications/Maps.app",
            "/System/Applications/Weather.app",
            "/System/Applications/Calculator.app",
            "/System/Applications/Clock.app",
            "/System/Applications/System Settings.app"
        ]

        let devAndToolsCandidates = [
            "/Applications/Xcode.app",
            "/Applications/Visual Studio Code.app",
            "/Applications/Cursor.app",
            "/Applications/iTerm.app",
            "/System/Applications/Utilities/Terminal.app",
            "/System/Applications/Utilities/Activity Monitor.app",
            "/System/Applications/Utilities/Console.app",
            "/System/Applications/Utilities/Screenshot.app",
            "/System/Applications/Utilities/Disk Utility.app",
            "/System/Applications/Utilities/Keychain Access.app"
        ]

        let creativeCandidates = [
            "/Applications/Figma.app",
            "/System/Applications/Preview.app",
            "/System/Applications/QuickTime Player.app",
            "/System/Applications/Freeform.app",
            "/System/Applications/Books.app",
            "/System/Applications/Podcasts.app",
            "/System/Applications/Font Book.app"
        ]

        // Deduplicate Safari path
        var seenNames = Set<String>()
        let commonItems = findApps(commonCandidates).filter { item in
            seenNames.insert(item.displayName).inserted
        }
        let devItems = findApps(devAndToolsCandidates)
        let creativeItems = findApps(creativeCandidates)

        return [
            AppCategory(name: "常用", items: commonItems),
            AppCategory(name: "开发与工具", items: devItems),
            AppCategory(name: "创作与媒体", items: creativeItems)
        ]
    }
}
