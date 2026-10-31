import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: ChestStore

    var body: some View {
        TabView {
            GeneralSettingsTab(store: store)
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }

            CategoriesManagementTab(store: store)
                .tabItem {
                    Label("分类与应用", systemImage: "square.grid.2x2")
                }

            LayoutAppearanceTab(store: store)
                .tabItem {
                    Label("网格与外观", systemImage: "slider.horizontal.3")
                }

            ShortcutsSettingsTab(store: store)
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }

            ExtensionsAndPermissionsTab(store: store)
                .tabItem {
                    Label("扩展与权限", systemImage: "lock.shield")
                }

            AboutSettingsTab(store: store)
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 500)
    }
}

// MARK: - Tab 1: General Settings

private struct GeneralSettingsTab: View {
    @ObservedObject var store: ChestStore
    @State private var launchAtLogin: Bool = AutoLaunchManager.shared.isEnabled

    var body: some View {
        Form {
            Section("系统启动") {
                Toggle("开机自动启动 ChestDock", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        AutoLaunchManager.shared.setEnabled(newValue)
                        store.config.launchAtLogin = newValue
                    }

                Text("启用后，Mac 开机登录时 ChestDock 会在后台静默待命，随时可通过 Dock 或顶部菜单栏点击唤醒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("快捷入口") {
                Toggle("在顶部菜单栏显示 ChestDock 快捷图标", isOn: $store.config.showMenuBarIcon)

                Text("开启后可在屏幕右上角菜单栏单击直接呼出应用网格，右键呼出控制菜单。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = AutoLaunchManager.shared.isEnabled
        }
    }
}

// MARK: - Tab 2: Categories & Apps Management (With Drag-to-move & Reorder)

private struct CategoriesManagementTab: View {
    @ObservedObject var store: ChestStore
    @State private var selectedCategoryId: UUID?
    @State private var newCategoryName: String = ""
    @State private var isDropTargeted: Bool = false

    private var activeCategory: AppCategory? {
        if let id = selectedCategoryId, let match = store.categories.first(where: { $0.id == id }) {
            return match
        }
        return store.categories.first
    }

    var body: some View {
        HSplitView {
            // Left Column: Categories List
            VStack(alignment: .leading, spacing: 8) {
                Text("顶部分类")
                    .font(.headline)
                    .padding(.horizontal, 4)

                List(selection: $selectedCategoryId) {
                    ForEach(store.categories) { category in
                        HStack {
                            CategoryNameRow(category: category, store: store)
                            Spacer()
                            Text("\(category.items.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                        .tag(category.id)
                        // Drop an App item onto this category in Settings
                        .onDrop(of: [.text, .fileURL], isTargeted: nil) { providers in
                            handleDropOnCategoryRow(providers: providers, targetCategory: category)
                        }
                    }
                    .onMove { indices, newOffset in
                        store.moveCategory(from: indices, to: newOffset)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))

                HStack(spacing: 6) {
                    TextField("新分类名称...", text: $newCategoryName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addNewCategory()
                        }

                    Button {
                        addNewCategory()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .help("新建分类")

                    Button {
                        if let active = activeCategory, store.categories.count > 1 {
                            store.deleteCategory(id: active.id)
                            selectedCategoryId = store.categories.first?.id
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.categories.count <= 1 || activeCategory == nil)
                    .help("删除选中分类")
                }
            }
            .frame(minWidth: 200, idealWidth: 230, maxWidth: 270)
            .padding(.trailing, 8)

            // Right Column: Items in Selected Category (Supports Reordering & Moving)
            VStack(alignment: .leading, spacing: 8) {
                if let category = activeCategory {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .center, spacing: 4) {
                            Text("「\(category.name)」")
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("(\(category.items.count))")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Spacer()

                            Button {
                                store.presentAddItemsPanel(for: category.id)
                            } label: {
                                Label(
                                    store.config.allowFoldersAndFiles ? "添加项目..." : "添加应用...",
                                    systemImage: "plus.circle.fill"
                                )
                            }
                        }

                        Text("可拖拽调整顺序或拖至左侧分类")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    List {
                        ForEach(category.items) { item in
                            HStack(spacing: 10) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                                    .padding(.trailing, 2)

                                Image(nsImage: store.icon(for: item))
                                    .resizable()
                                    .frame(width: 28, height: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(item.url.path)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()

                                // Move to category menu button
                                if store.categories.count > 1 {
                                    Menu {
                                        ForEach(store.categories.filter { $0.id != category.id }) { targetCat in
                                            Button(targetCat.name) {
                                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                                    store.moveItem(item.id, from: category.id, to: targetCat.id)
                                                }
                                            }
                                        }
                                    } label: {
                                        Label("移动到", systemImage: "arrow.right.circle")
                                            .font(.caption)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .fixedSize()
                                }

                                Button(role: .destructive) {
                                    store.removeItem(item.id, from: category.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("移除")
                            }
                            .padding(.vertical, 2)
                            .contextMenu {
                                if store.categories.count > 1 {
                                    Menu("移动到分类") {
                                        ForEach(store.categories.filter { $0.id != category.id }) { targetCat in
                                            Button(targetCat.name) {
                                                store.moveItem(item.id, from: category.id, to: targetCat.id)
                                            }
                                        }
                                    }
                                }
                                Divider()
                                Button("从分类中移除", role: .destructive) {
                                    store.removeItem(item.id, from: category.id)
                                }
                            }
                        }
                        .onMove { sourceIndices, destination in
                            store.moveItems(fromOffsets: sourceIndices, toOffset: destination, in: category.id)
                        }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                    .overlay {
                        if category.items.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.down.app")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.secondary)
                                Text("拖拽 .app 应用到此列表，或点击右上角「添加应用...」")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                        handleDrop(providers: providers, into: category.id)
                    }
                }
            }
            .frame(minWidth: 380)
            .padding(.leading, 8)
        }
        .onAppear {
            if selectedCategoryId == nil {
                selectedCategoryId = store.selectedCategory?.id ?? store.categories.first?.id
            }
        }
    }

    private func addNewCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = String(name.prefix(12))
        let created = store.addCategory(name: trimmedName.isEmpty ? "新分类" : trimmedName)
        newCategoryName = ""
        selectedCategoryId = created.id
    }

    private func handleDropOnCategoryRow(providers: [NSItemProvider], targetCategory: AppCategory) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
                    let uuidString: String?
                    if let str = data as? String {
                        uuidString = str
                    } else if let d = data as? Data, let s = String(data: d, encoding: .utf8) {
                        uuidString = s
                    } else {
                        uuidString = nil
                    }
                    if let uuidString = uuidString, let itemId = UUID(uuidString: uuidString) {
                        Task { @MainActor in
                            if let cur = activeCategory?.id, cur != targetCategory.id {
                                store.moveItem(itemId, from: cur, to: targetCategory.id)
                            }
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func handleDrop(providers: [NSItemProvider], into categoryId: UUID) -> Bool {
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
            store.addItems(from: urls, to: categoryId)
        }
        return true
    }
}

private struct CategoryNameRow: View {
    let category: AppCategory
    @ObservedObject var store: ChestStore
    @State private var nameText: String = ""

    var body: some View {
        TextField("分类名称", text: $nameText)
            .textFieldStyle(.plain)
            .onAppear {
                nameText = category.name
            }
            .onChange(of: category.name) { _, newValue in
                nameText = newValue
            }
            .onSubmit {
                let trimmed = String(nameText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
                if !trimmed.isEmpty {
                    store.renameCategory(id: category.id, newName: trimmed)
                }
            }
    }
}

// MARK: - Tab 3: Grid & Appearance (Stepper & TextField)

private struct LayoutAppearanceTab: View {
    @ObservedObject var store: ChestStore

    @State private var rowsText: String = ""
    @State private var columnsText: String = ""
    @State private var iconSizeText: String = ""

    var body: some View {
        Form {
            Section("气泡网格行列自定义 (1~5 行，1~9 列)") {
                HStack(spacing: 12) {
                    Text("网格行数 (Rows):")
                        .frame(width: 140, alignment: .leading)

                    TextField("行数", text: $rowsText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 58)
                        .multilineTextAlignment(.center)
                        .onSubmit { commitRows() }

                    Stepper("", value: $store.config.rows, in: 1...5)
                        .labelsHidden()
                        .onChange(of: store.config.rows) { _, newVal in
                            rowsText = "\(newVal)"
                        }

                    Text("行 (范围 1 ~ 5)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Text("网格列数 (Columns):")
                        .frame(width: 140, alignment: .leading)

                    TextField("列数", text: $columnsText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 58)
                        .multilineTextAlignment(.center)
                        .onSubmit { commitColumns() }

                    Stepper("", value: $store.config.columns, in: 1...9)
                        .labelsHidden()
                        .onChange(of: store.config.columns) { _, newVal in
                            columnsText = "\(newVal)"
                        }

                    Text("列 (范围 1 ~ 9)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Text("图标尺寸 (Icon Size):")
                        .frame(width: 140, alignment: .leading)

                    TextField("尺寸", text: $iconSizeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 58)
                        .multilineTextAlignment(.center)
                        .onSubmit { commitIconSize() }

                    Stepper(
                        "",
                        value: Binding(
                            get: { Int(store.config.iconSize) },
                            set: { store.config.iconSize = Double($0) }
                        ),
                        in: 36...96,
                        step: 4
                    )
                    .labelsHidden()
                    .onChange(of: store.config.iconSize) { _, newVal in
                        iconSizeText = "\(Int(newVal))"
                    }

                    Text("pt (范围 36 ~ 96)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("当前单页容量：\(store.config.rows) × \(store.config.columns) = \(store.config.pageSize) 个图标，超出自动横向翻页。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onAppear {
                rowsText = "\(store.config.rows)"
                columnsText = "\(store.config.columns)"
                iconSizeText = "\(Int(store.config.iconSize))"
            }

            Section("Dock 图标与状态显示") {
                Picker("Dock 文件夹缩略图样式:", selection: $store.config.dockPreviewGrid) {
                    ForEach(DockTilePreviewGrid.allCases) { grid in
                        Text(grid.title).tag(grid)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Dock 缩略图跟随当前选中的分类变化", isOn: $store.config.syncDockIconWithActiveCategory)
                Toggle("在气泡内显示正在运行的应用指示圆点 (•)", isOn: $store.config.showRunningIndicator)
            }

            Section("边缘悬浮与吸附交互") {
                Toggle("允许钉住时缩小为边缘悬浮小图标", isOn: $store.config.enableFloatingTrigger)
                if store.config.enableFloatingTrigger {
                    Toggle("拖动悬浮图标松手后自动吸附至左/右屏幕边缘", isOn: $store.config.autoSnapToEdge)
                    Text("开启后支持在钉住时将面板收纳至屏幕两侧边缘，多显示器中缝自动居中跨屏显示，且避开系统 Dock 与菜单栏。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("默认关闭。钉住面板仅保持常驻展开，不显示缩小按钮，减少桌面视觉干扰。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func commitRows() {
        if let val = Int(rowsText) {
            let clamped = max(1, min(5, val))
            store.config.rows = clamped
            rowsText = "\(clamped)"
        } else {
            rowsText = "\(store.config.rows)"
        }
    }

    private func commitColumns() {
        if let val = Int(columnsText) {
            let clamped = max(1, min(9, val))
            store.config.columns = clamped
            columnsText = "\(clamped)"
        } else {
            columnsText = "\(store.config.columns)"
        }
    }

    private func commitIconSize() {
        if let val = Double(iconSizeText) {
            let clamped = max(36, min(96, val))
            store.config.iconSize = clamped
            iconSizeText = "\(Int(clamped))"
        } else {
            iconSizeText = "\(Int(store.config.iconSize))"
        }
    }
}

// MARK: - Tab 4: Shortcuts Settings (With separate enable/disable switches)

private struct ShortcutsSettingsTab: View {
    @ObservedObject var store: ChestStore

    var body: some View {
        Form {
            Section("悬浮面板控制快捷键 (分别启用/禁用)") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("启用「钉住 / 取消钉住」快捷键", isOn: $store.config.togglePinShortcut.isEnabled)
                        .font(.system(size: 13, weight: .medium))

                    if store.config.togglePinShortcut.isEnabled {
                        HStack {
                            Text("快捷触发按键:")
                                .frame(width: 120, alignment: .leading)
                            Picker("", selection: $store.config.togglePinShortcut.key) {
                                Text("P 键").tag("p")
                                Text("D 键").tag("d")
                                Text("K 键").tag("k")
                            }
                            .frame(width: 110)
                            Text("组合修饰键：⌘ Command")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 20)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("启用「缩小为悬浮图标 / 展开」快捷键", isOn: $store.config.toggleCollapseShortcut.isEnabled)
                        .font(.system(size: 13, weight: .medium))

                    if store.config.toggleCollapseShortcut.isEnabled {
                        HStack {
                            Text("快捷触发按键:")
                                .frame(width: 120, alignment: .leading)
                            Picker("", selection: $store.config.toggleCollapseShortcut.key) {
                                Text("M 键").tag("m")
                                Text("H 键").tag("h")
                                Text("- (减号)").tag("-")
                            }
                            .frame(width: 110)
                            Text("组合修饰键：⌘ Command")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 20)
                    }
                }
            }

            Section("默认导航操作速查") {
                VStack(alignment: .leading, spacing: 8) {
                    shortcutRow(key: "Esc", desc: "立即收起并关闭气泡")
                    shortcutRow(key: "← / →", desc: "在分类内左右翻页")
                    shortcutRow(key: "⌘ + ← / →", desc: "快速切换前一个/后一个分类")
                    shortcutRow(key: "Tab / ⇧Tab", desc: "正向/逆向循环切换分类")
                    shortcutRow(key: "⌘ + 点击应用", desc: "启动应用并保持气泡展开（连开模式）")
                    shortcutRow(key: "双击顶部胶囊横条", desc: "钉住状态下快速收起为悬浮图标")
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(key: String, desc: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.08))
                )
                .frame(width: 130, alignment: .leading)

            Text(desc)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Tab 5: Extensions & Permissions

private struct ExtensionsAndPermissionsTab: View {
    @ObservedObject var store: ChestStore
    @State private var isAXTrusted: Bool = DockLocator.isAccessibilityTrusted(prompt: false)

    var body: some View {
        Form {
            Section("内容类型扩展（暂未实现）") {
                Toggle("允许添加常用文件夹与普通文件", isOn: $store.config.allowFoldersAndFiles)
                    .disabled(true)
                Text("此项仅为底层架构预留占位，当前版本仅支持 .app 应用程序。未来版本将支持直接拖入常用文件夹与文档作为快捷方式。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dock 图标精确定位 (可选)") {
                HStack {
                    Image(systemName: isAXTrusted ? "checkmark.seal.fill" : "info.circle.fill")
                        .foregroundStyle(isAXTrusted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isAXTrusted ? "已开启辅助功能精确定位" : "当前使用免权限鼠标智能定位")
                            .font(.system(size: 13, weight: .medium))
                        Text("免权限模式下已支持点击 Dock 图标自动对齐气泡小尾巴；开启辅助功能权限后可直接读取 Dock 图标精确坐标。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !isAXTrusted {
                        Button("请求辅助功能权限") {
                            _ = DockLocator.isAccessibilityTrusted(prompt: true)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                isAXTrusted = DockLocator.isAccessibilityTrusted(prompt: false)
                            }
                        }
                    } else {
                        Button("刷新状态") {
                            isAXTrusted = DockLocator.isAccessibilityTrusted(prompt: false)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            isAXTrusted = DockLocator.isAccessibilityTrusted(prompt: false)
        }
    }
}

// MARK: - Tab 6: About & Updates (Now hosting Automatic Update Check switch)

private struct AboutSettingsTab: View {
    @ObservedObject var store: ChestStore
    @ObservedObject var updater = UpdateChecker.shared

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let img = NSImage(named: "AppIcon") {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .shadow(radius: 6)
            } else {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 4) {
                Text("ChestDock")
                    .font(.system(size: 22, weight: .bold))
                Text("版本 \(updater.currentVersion) (Build 1)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("专为 macOS 设计的轻量级 iOS 风格 Dock 应用抽屉")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(updater.repoWebURL)
                } label: {
                    Label("GitHub 仓库", systemImage: "link")
                }

                Button {
                    updater.checkForUpdates(isUserInitiated: true)
                } label: {
                    if updater.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(updater.isChecking)
            }
            .padding(.top, 4)

            // Auto check update toggle moved into About tab
            Toggle("启动时在后台自动检查新版本", isOn: $store.config.autoCheckUpdates)
                .font(.system(size: 12.5))
                .padding(.top, 4)

            if let msg = updater.checkMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(updater.hasUpdate ? Color.accentColor : Color.secondary)
            }

            Spacer()

            Text("© 2026 Minato-chen. Released under the MIT License.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
