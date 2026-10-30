import Foundation

/// A top-level category tab in the bubble (e.g. "常用", "效率", "开发").
struct AppCategory: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var iconSystemName: String?
    var items: [DockItem]

    init(
        id: UUID = UUID(),
        name: String,
        iconSystemName: String? = nil,
        items: [DockItem] = []
    ) {
        self.id = id
        self.name = name
        self.iconSystemName = iconSystemName
        self.items = items
    }

    /// Splits the category's items into pages of size `pageSize`.
    func pages(pageSize: Int) -> [[DockItem]] {
        let validPageSize = max(1, pageSize)
        guard !items.isEmpty else { return [[]] }
        return stride(from: 0, to: items.count, by: validPageSize).map { startIndex in
            let endIndex = min(startIndex + validPageSize, items.count)
            return Array(items[startIndex..<endIndex])
        }
    }
}
