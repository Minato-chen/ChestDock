import SwiftUI
import UniformTypeIdentifiers

struct BubbleContentView: View {
    @ObservedObject var store: ChestStore
    @ObservedObject var layoutState: BubbleLayoutState
    @State private var isDroppingFiles: Bool = false
    @State private var isHoveringCollapsed: Bool = false

    private let tailHeight: CGFloat = 13

    var body: some View {
        if layoutState.isCollapsed {
            collapsedFloatingView
        } else {
            expandedBubbleView
        }
    }

    // MARK: - Native macOS Styled Collapsed Floating Icon

    private var collapsedFloatingView: some View {
        Button {
            BubblePanelController.shared.setCollapsed(false)
        } label: {
            ZStack {
                // Frosted background with smooth squircle
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(isHoveringCollapsed ? 0.12 : 0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(isHoveringCollapsed ? 0.45 : 0.25),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(isHoveringCollapsed ? 0.28 : 0.18),
                        radius: isHoveringCollapsed ? 8 : 5,
                        x: 0,
                        y: 2
                    )

                // Native macOS menu-bar style icon
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(isHoveringCollapsed ? 1.0 : 0.85))
            }
            .frame(
                width: BubblePanelController.collapsedSize.width,
                height: BubblePanelController.collapsedSize.height
            )
        }
        .buttonStyle(.plain)
        .onHover { isHoveringCollapsed = $0 }
        .help("点击展开面板")
        .contextMenu {
            Button("展开面板") {
                BubblePanelController.shared.setCollapsed(false)
            }
            Button("取消钉住并关闭") {
                BubblePanelController.shared.setPinned(false)
                BubblePanelController.shared.hide(forceEvenIfPinned: true)
            }
            Divider()
            Button("设置...") {
                SettingsWindowController.shared.showSettings()
            }
        }
    }

    // MARK: - Expanded Bubble View

    private var expandedBubbleView: some View {
        let bubbleShape = BubbleShape(
            edge: layoutState.dockEdge,
            tailOffset: layoutState.tailOffsetFromCenter,
            tailProgress: layoutState.isDetachedFromDock ? 0.0 : 1.0,
            cornerRadius: 26,
            tailWidth: 24,
            tailHeight: tailHeight
        )

        return ZStack {
            // Frosted Glass Material clipped to BubbleShape
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color.white.opacity(0.06))
                .clipShape(bubbleShape)

            // Main Content padded away from the tail edge
            VStack(spacing: 2) {
                if layoutState.isPinned && store.config.enableFloatingTrigger {
                    Capsule()
                        .fill(Color.primary.opacity(0.24))
                        .frame(width: 36, height: 4)
                        .padding(.top, 6)
                        .contentShape(Rectangle().inset(by: -6))
                        .onTapGesture(count: 2) {
                            BubblePanelController.shared.toggleCollapse()
                        }
                        .help("双击收起面板 (⌘M)")
                        .transition(.opacity.combined(with: .scale))
                }

                CategoryTabBar(store: store, layoutState: layoutState)
                    .padding(.top, layoutState.isPinned ? 2 : 8)

                Divider()
                    .opacity(0.35)
                    .padding(.horizontal, 18)

                PagedAppGridView(store: store)
                    .padding(.bottom, 8)
            }
            .padding(contentInsets(for: layoutState.dockEdge))

            // Specular highlight border around the bubble + tail
            bubbleShape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDroppingFiles ? 0.85 : (layoutState.isPinned ? 0.56 : 0.42)),
                            Color.white.opacity(isDroppingFiles ? 0.65 : (layoutState.isPinned ? 0.28 : 0.16))
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: isDroppingFiles ? 2.2 : 1.1
                )
        }
        .contentShape(bubbleShape)
        .onDrop(of: [.fileURL], isTargeted: $isDroppingFiles) { providers in
            handleDropIntoBubble(providers: providers)
        }
        .contextMenu {
            Button(layoutState.isPinned ? "取消钉住 (⌘P)" : "钉住气泡面板 (⌘P)") {
                BubblePanelController.shared.togglePin()
            }
            if layoutState.isPinned {
                Button("收起面板 (⌘M)") {
                    BubblePanelController.shared.setCollapsed(true)
                }
            }
            if layoutState.isDetachedFromDock {
                Button("归位面板") {
                    BubblePanelController.shared.snapBackToAnchor()
                }
            }
            Divider()
            Button("添加应用到当前分类...") {
                store.presentAddItemsPanel()
            }
            Button("新建分类") {
                store.addCategory(name: "新分类")
            }
            Divider()
            Button("设置...") {
                SettingsWindowController.shared.showSettings()
            }
        }
    }

    private func contentInsets(for edge: DockEdge) -> EdgeInsets {
        switch edge {
        case .bottom:
            return EdgeInsets(top: 0, leading: 0, bottom: tailHeight, trailing: 0)
        case .top:
            return EdgeInsets(top: tailHeight, leading: 0, bottom: 0, trailing: 0)
        case .left:
            return EdgeInsets(top: 0, leading: tailHeight, bottom: 0, trailing: 0)
        case .right:
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: tailHeight)
        }
    }

    private func handleDropIntoBubble(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    defer { group.leave() }
                    if let data = data as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    store.addItems(from: urls)
                }
            }
        }
        return true
    }
}
