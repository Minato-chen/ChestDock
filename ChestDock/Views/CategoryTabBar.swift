import SwiftUI

struct CategoryTabBar: View {
    @ObservedObject var store: ChestStore
    @ObservedObject var layoutState: BubbleLayoutState
    @Namespace private var tabNamespace

    @State private var editingCategoryId: UUID?
    @State private var editingName: String = ""
    @State private var isHoveringBar: Bool = false
    @State private var isHoveringCapsule: Bool = false
    @State private var isHoveringPin: Bool = false
    @State private var isHoveringCollapse: Bool = false
    @FocusState private var isRenameFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.categories) { category in
                            categoryPill(for: category)
                                .id(category.id)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 6)
                    .padding(.vertical, 6)
                }
                .onChange(of: store.selectedCategoryId) { _, newId in
                    if let newId = newId {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            proxy.scrollTo(newId, anchor: .center)
                        }
                    }
                }
            }

            // iOS-style Control Pill Capsule in top-right
            controlPill
                .padding(.trailing, 14)
        }
        .frame(height: 42)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isHoveringBar = hovering
            }
        }
        .contextMenu {
            Button(layoutState.isPinned ? "取消钉住 (⌘P)" : "钉住气泡面板 (⌘P)") {
                BubblePanelController.shared.togglePin()
            }
            if layoutState.isPinned {
                Button("收起为悬浮球 (⌘M)") {
                    BubblePanelController.shared.setCollapsed(true)
                }
            }
            if layoutState.isDetachedFromDock {
                Button("归位面板") {
                    BubblePanelController.shared.snapBackToAnchor()
                }
            }
            Divider()
            Button("新建分类") {
                createNewCategoryAndEdit()
            }
            Button("添加应用到当前分类...") {
                store.presentAddItemsPanel()
            }
            Divider()
            Button("设置...") {
                SettingsWindowController.shared.showSettings()
            }
        }
    }

    /// Modern iOS-styled dark/translucent pill hosting the Pin button and Collapse button side-by-side
    private var controlPill: some View {
        let isPinned = layoutState.isPinned
        let isPillVisible = isPinned || isHoveringBar || isHoveringCapsule

        return HStack(spacing: 4) {
            // 1. Pin Button
            Button {
                BubblePanelController.shared.togglePin()
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11.5, weight: .semibold))
                    .rotationEffect(.degrees(isPinned ? 0 : 45))
                    .foregroundStyle(isPinned ? Color.accentColor : Color.primary.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(
                                isPinned
                                    ? Color.accentColor.opacity(0.18)
                                    : (isHoveringPin ? Color.primary.opacity(0.12) : Color.clear)
                            )
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(isHoveringPin ? 1.08 : 1.0)
            .onHover { isHoveringPin = $0 }
            .help(isPinned ? "已钉住（可拖动面板，点击取消钉住 ⌘P）" : "钉住面板（常驻不收起 ⌘P）")

            // 2. Collapse Button (As referenced in user image: arrow.down.right.and.arrow.up.left)
            if isPinned {
                Button {
                    BubblePanelController.shared.toggleCollapse()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(isHoveringCollapse ? Color.primary.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .scaleEffect(isHoveringCollapse ? 1.08 : 1.0)
                .onHover { isHoveringCollapse = $0 }
                .help("缩小为悬浮球 (⌘M)")
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
            }
        }
        .padding(.horizontal, isPinned ? 5 : 2)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.45))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8)
                )
        )
        .opacity(isPillVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isPinned)
        .animation(.easeInOut(duration: 0.16), value: isPillVisible)
        .onHover { isHoveringCapsule = $0 }
    }

    @ViewBuilder
    private func categoryPill(for category: AppCategory) -> some View {
        let isSelected = (store.selectedCategory?.id == category.id)
        let isEditing = (editingCategoryId == category.id)

        ZStack {
            if isSelected {
                Capsule()
                    .fill(Color.primary.opacity(0.16))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8)
                    )
                    .matchedGeometryEffect(id: "ActiveCategoryPill", in: tabNamespace)
            }

            if isEditing {
                TextField("分类名称", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 54, maxWidth: 110)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .focused($isRenameFocused)
                    .onSubmit {
                        commitRename(for: category.id)
                    }
                    .onChange(of: isRenameFocused) { _, focused in
                        if !focused {
                            commitRename(for: category.id)
                        }
                    }
            } else {
                Text(category.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
            }
        }
        .contentShape(Capsule())
        .onTapGesture(count: 2) {
            beginRename(category)
        }
        .onTapGesture(count: 1) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                store.selectCategory(category.id)
            }
        }
        .contextMenu {
            Button(layoutState.isPinned ? "取消钉住 (⌘P)" : "钉住气泡面板 (⌘P)") {
                BubblePanelController.shared.togglePin()
            }
            if layoutState.isPinned {
                Button("收起为悬浮球 (⌘M)") {
                    BubblePanelController.shared.setCollapsed(true)
                }
            }
            if layoutState.isDetachedFromDock {
                Button("归位面板") {
                    BubblePanelController.shared.snapBackToAnchor()
                }
            }
            Divider()
            Button("添加应用到此分类...") {
                store.selectCategory(category.id)
                store.presentAddItemsPanel(for: category.id)
            }
            Divider()
            Button("重命名「\(category.name)」") {
                beginRename(category)
            }
            Button("新建分类") {
                createNewCategoryAndEdit()
            }
            if store.categories.count > 1 {
                Button("删除「\(category.name)」", role: .destructive) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.deleteCategory(id: category.id)
                    }
                }
            }
            Divider()
            Button("设置...") {
                SettingsWindowController.shared.showSettings()
            }
        }
    }

    private func beginRename(_ category: AppCategory) {
        store.selectCategory(category.id)
        editingName = category.name
        editingCategoryId = category.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isRenameFocused = true
        }
    }

    private func commitRename(for categoryId: UUID) {
        guard editingCategoryId == categoryId else { return }
        store.renameCategory(id: categoryId, newName: editingName)
        editingCategoryId = nil
    }

    private func createNewCategoryAndEdit() {
        let created = store.addCategory(name: "新分类")
        beginRename(created)
    }
}
