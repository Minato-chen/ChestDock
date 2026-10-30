import SwiftUI
import UniformTypeIdentifiers

struct PagedAppGridView: View {
    @ObservedObject var store: ChestStore
    @State private var draggedItem: DockItem?
    @State private var dragHorizontalOffset: CGFloat = 0

    private var pages: [[DockItem]] {
        store.currentPages
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(store.config.cellWidth), spacing: 8),
            count: store.config.columns
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let pageWidth = geo.size.width
                let activeItems = store.selectedCategory?.items ?? []

                if activeItems.isEmpty {
                    emptyCategoryPlaceholder
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    HStack(spacing: 0) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { _, pageItems in
                            pageGrid(items: pageItems)
                                .frame(width: pageWidth, height: geo.size.height, alignment: .top)
                        }
                    }
                    .offset(x: -CGFloat(store.currentPage) * pageWidth + dragHorizontalOffset)
                    .animation(.spring(response: 0.32, dampingFraction: 0.84), value: store.currentPage)
                    .animation(.interactiveSpring(), value: dragHorizontalOffset)
                }
            }
            .clipped()
            .background(
                TrackpadPagerOverlay(
                    onSwipeLeft: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            store.goToNextPage()
                        }
                    },
                    onSwipeRight: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            store.goToPreviousPage()
                        }
                    }
                )
            )

            // iOS-style Page Indicator Dots
            pageIndicator
                .frame(height: 22)
        }
    }

    @ViewBuilder
    private func pageGrid(items: [DockItem]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            ForEach(items) { item in
                AppIconItemView(item: item, store: store)
                    .onDrag {
                        self.draggedItem = item
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [.text],
                        delegate: GridReorderDropDelegate(
                            targetItem: item,
                            draggedItem: $draggedItem,
                            store: store
                        )
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var emptyCategoryPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("拖拽应用到此添加")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Button("选择应用程序...") {
                store.presentAddItemsPanel()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            if store.pageCount > 1 {
                ForEach(0..<store.pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == store.currentPage ? Color.primary.opacity(0.9) : Color.primary.opacity(0.26))
                        .frame(width: index == store.currentPage ? 7 : 6, height: index == store.currentPage ? 7 : 6)
                        .contentShape(Rectangle().inset(by: -4))
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                store.currentPage = index
                            }
                        }
                }
            } else {
                // Single subtle dot to preserve iOS folder balance
                Circle()
                    .fill(Color.primary.opacity(0.32))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Drag Reorder Delegate

private struct GridReorderDropDelegate: DropDelegate {
    let targetItem: DockItem
    @Binding var draggedItem: DockItem?
    let store: ChestStore

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedItem, dragged.id != targetItem.id else { return }
        withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
            store.reorderItem(draggedItemId: dragged.id, targetItemId: targetItem.id)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }
}

// MARK: - Trackpad / ScrollWheel Horizontal Pager Monitor

private struct TrackpadPagerOverlay: NSViewRepresentable {
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
    }

    final class Coordinator {
        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void
        private var monitor: Any?
        private var accumulatedDeltaX: CGFloat = 0
        private var hasTriggeredInCurrentGesture = false
        private var lastWheelTimestamp: TimeInterval = 0

        init(onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void) {
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
        }

        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func installMonitor(on view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak view] event in
                guard let self = self,
                      let view = view,
                      let window = view.window,
                      event.window == window else {
                    return event
                }

                // Reset gesture state on begin or after a pause
                if event.phase == .began || (event.timestamp - self.lastWheelTimestamp > 0.35) {
                    self.accumulatedDeltaX = 0
                    self.hasTriggeredInCurrentGesture = false
                }
                self.lastWheelTimestamp = event.timestamp

                if event.phase == .ended || event.phase == .cancelled {
                    self.accumulatedDeltaX = 0
                    self.hasTriggeredInCurrentGesture = false
                    return event
                }

                let dx = event.scrollingDeltaX
                let dy = event.scrollingDeltaY
                guard abs(dx) > abs(dy) else { return event }

                self.accumulatedDeltaX += dx
                let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 42 : 4

                if !self.hasTriggeredInCurrentGesture {
                    if self.accumulatedDeltaX < -threshold {
                        self.hasTriggeredInCurrentGesture = true
                        self.onSwipeLeft()
                    } else if self.accumulatedDeltaX > threshold {
                        self.hasTriggeredInCurrentGesture = true
                        self.onSwipeRight()
                    }
                }
                return event
            }
        }
    }
}
