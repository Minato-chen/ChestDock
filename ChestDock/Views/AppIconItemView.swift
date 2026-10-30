import SwiftUI
import UniformTypeIdentifiers

struct AppIconItemView: View {
    let item: DockItem
    @ObservedObject var store: ChestStore

    @State private var isHovering: Bool = false
    @State private var isDropTarget: Bool = false

    private var iconSize: CGFloat {
        CGFloat(store.config.iconSize)
    }

    private var isRunning: Bool {
        store.config.showRunningIndicator && store.isItemRunning(item)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                Image(nsImage: store.icon(for: item))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .shadow(
                        color: .black.opacity(isHovering ? 0.34 : 0.2),
                        radius: isHovering ? 8 : 4,
                        x: 0,
                        y: isHovering ? 4 : 2
                    )
                    .scaleEffect(isDropTarget ? 1.14 : (isHovering ? 1.07 : 1.0))
                    .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovering)
                    .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isDropTarget)
            }
            .frame(width: iconSize + 8, height: iconSize + 4)

            Text(item.displayName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: store.config.cellWidth - 6)
                .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 0.5)

            Circle()
                .fill(Color.primary.opacity(isRunning ? 0.85 : 0.0))
                .frame(width: 4.5, height: 4.5)
                .shadow(color: .white.opacity(isRunning ? 0.5 : 0), radius: 2)
        }
        .frame(width: store.config.cellWidth, height: store.config.cellHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(isHovering || isDropTarget ? 0.08 : 0.0))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            store.launchItem(item)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            handleDroppedFiles(providers: providers)
        }
        .contextMenu {
            Button("打开「\(item.displayName)」") {
                store.launchItem(item)
            }
            Button("打开并保持面板展开 (⌘ + 点击)") {
                store.launchItem(item, forceKeepBubbleOpen: true)
            }
            Button("在 Finder 中显示") {
                store.revealInFinder(item)
            }
            if store.isItemRunning(item) {
                Button("退出「\(item.displayName)」") {
                    store.quitRunningApp(item)
                }
            }

            if store.categories.count > 1, let currentCatId = store.selectedCategory?.id {
                Menu("移动到其他分类") {
                    ForEach(store.categories.filter { $0.id != currentCatId }) { targetCat in
                        Button(targetCat.name) {
                            store.moveItem(item.id, from: currentCatId, to: targetCat.id)
                        }
                    }
                }
            }

            Divider()

            Button("从分类中移除", role: .destructive) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    store.removeItem(item.id)
                }
            }
        }
    }

    private func handleDroppedFiles(providers: [NSItemProvider]) -> Bool {
        guard item.type == .application else { return false }
        var collectedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    defer { group.leave() }
                    if let data = data as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        collectedURLs.append(url)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            guard !collectedURLs.isEmpty else { return }
            // If all dropped items are .app bundles, add them to the category instead
            let allApps = collectedURLs.allSatisfy { $0.path.lowercased().hasSuffix(".app") }
            if allApps {
                store.addItems(from: collectedURLs)
            } else {
                store.openFiles(collectedURLs, withApp: item)
            }
        }
        return true
    }
}
