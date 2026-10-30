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

            AboutSettingsTab()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 480)
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

                Text("开启后可在屏幕右上角菜单栏单机直接呼出应用网格，右键呼出控制菜单。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("更新维护") {
                Toggle("自动检查新版本", isOn: $store.config.autoCheckUpdates)

                Text("ChestDock 启动后会在后台静默检查 GitHub Releases 是否有新版本。")
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

// MARK: - Tab 2: Categories & Apps Management

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
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
            .padding(.trailing, 8)

            // Right Column: Items in Selected Category
            VStack(alignment: .leading, spacing: 8) {
                if let category = activeCategory {
                    HStack {
                        Text("「\(category.name)」中的项目")
                            .font(.headline)
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

                    List {
                        ForEach(category.items) { item in
                            HStack(spacing: 10) {
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

                                Text(item.type.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.primary.opacity(0.06))
                                    )

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
            .frame(minWidth: 360)
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
        let created = store.addCategory(name: name.isEmpty ? "新分类" : name)
        newCategoryName = ""
        selectedCategoryId = created.id
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
                store.renameCategory(id: category.id, newName: nameText)
            }
    }
}

// MARK: - Tab 3: Grid & Appearance

private struct LayoutAppearanceTab: View {
    @ObservedObject var store: ChestStore

    var body: some View {
        Form {
            Section("气泡网格行列自定义") {
                HStack {
                    Text("网格行数 (Rows): \(store.config.rows) 行")
                        .frame(width: 170, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { Double(store.config.rows) },
                            set: { store.config.rows = Int($0.rounded()) }
                        ),
                        in: 2...6,
                        step: 1
                    )
                }

                HStack {
                    Text("网格列数 (Columns): \(store.config.columns) 列")
                        .frame(width: 170, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { Double(store.config.columns) },
                            set: { store.config.columns = Int($0.rounded()) }
                        ),
                        in: 3...8,
                        step: 1
                    )
                }

                HStack {
                    Text("图标尺寸: \(Int(store.config.iconSize)) pt")
                        .frame(width: 170, alignment: .leading)
                    Slider(
                        value: $store.config.iconSize,
                        in: 44...80,
                        step: 2
                    )
                }

                Text("当前单页容量：\(store.config.rows) × \(store.config.columns) = \(store.config.pageSize) 个图标，超出自动横向翻页。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tab 4: Shortcuts Settings

private struct ShortcutsSettingsTab: View {
    @ObservedObject var store: ChestStore

    var body: some View {
        Form {
            Section("悬浮面板控制快捷键") {
                HStack {
                    Text("钉住 / 取消钉住面板:")
                        .frame(width: 180, alignment: .leading)
                    Spacer()
                    Picker("", selection: $store.config.togglePinShortcut.key) {
                        Text("P 键").tag("p")
                        Text("D 键").tag("d")
                        Text("K 键").tag("k")
                    }
                    .frame(width: 110)
                    Text("修饰键：⌘ Command")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("收起为悬浮球 / 展开:")
                        .frame(width: 180, alignment: .leading)
                    Spacer()
                    Picker("", selection: $store.config.toggleCollapseShortcut.key) {
                        Text("M 键").tag("m")
                        Text("H 键").tag("h")
                        Text("- (减号)").tag("-")
                    }
                    .frame(width: 110)
                    Text("修饰键：⌘ Command")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("默认导航快捷键速查") {
                VStack(alignment: .leading, spacing: 8) {
                    shortcutRow(key: "Esc", desc: "立即收起关闭气泡")
                    shortcutRow(key: "← / →", desc: "在分类内左右翻页")
                    shortcutRow(key: "⌘ + ← / →", desc: "快速切换前一个/后一个分类")
                    shortcutRow(key: "Tab / ⇧Tab", desc: "正向/逆向循环切换分类")
                    shortcutRow(key: "⌘ + 点击应用", desc: "启动应用并保持气泡展开（连开模式）")
                    shortcutRow(key: "双击顶部胶囊横条", desc: "钉住状态下快速收起为悬浮球")
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

// MARK: - Tab 6: About & Updates

private struct AboutSettingsTab: View {
    @ObservedObject var updater = UpdateChecker.shared

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // App Icon preview
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
