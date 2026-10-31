import AppKit
import SwiftUI
import Combine

enum BubbleTriggerSource {
    case dock
    case menuBar
}

@MainActor
final class BubbleLayoutState: ObservableObject {
    @Published var dockEdge: DockEdge = .bottom
    /// Horizontal (for bottom/top) or vertical (for left/right) offset of the tail tip from the bubble center.
    @Published var tailOffsetFromCenter: CGFloat = 0
    @Published var isPresented: Bool = false
    /// Whether the bubble is currently pinned (stays open on outside click / app launch & can be dragged).
    @Published var isPinned: Bool = false
    /// Whether the pinned bubble has been dragged away from its anchor (retracts the tail into a pure rounded rect).
    @Published var isDetachedFromDock: Bool = false
    /// Whether the pinned bubble is currently collapsed into a floating pill/ball.
    @Published var isCollapsed: Bool = false
    /// Where the bubble was last opened from.
    @Published var triggerSource: BubbleTriggerSource = .dock
}

@MainActor
final class BubblePanelController {
    static let shared = BubblePanelController()

    let layoutState = BubbleLayoutState()
    private var panel: BubblePanel?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var windowMoveObserver: NSObjectProtocol?
    private var lastOutsideDismissTime: TimeInterval = 0
    private var lastOutsideDismissSource: BubbleTriggerSource?
    private var lastAnchorInfo: DockAnchorInfo?
    private weak var lastStatusButton: NSStatusBarButton?
    private var anchoredOrigin: CGPoint?
    private var isProgrammaticFrameChange = false
    private var visibilityGeneration: Int = 0

    // Constant size for the floating bubble pill when collapsed (macOS native menu bar button size)
    static let collapsedSize = CGSize(width: 38, height: 38)

    private init() {
        let store = ChestStore.shared
        store.onItemLaunched = { [weak self] in
            guard let self = self else { return }
            if !self.layoutState.isPinned {
                self.hide()
            }
        }
        store.onConfigChanged = { [weak self] in
            self?.resizeIfVisible()
        }
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func registerStatusButton(_ button: NSStatusBarButton?) {
        self.lastStatusButton = button
    }

    // MARK: - Pinning & Detaching & Collapsing

    func togglePin() {
        setPinned(!layoutState.isPinned)
    }

    func setPinned(_ pinned: Bool) {
        layoutState.isPinned = pinned
        if !pinned {
            layoutState.isCollapsed = false
        }

        if !pinned && layoutState.isDetachedFromDock {
            snapBackToAnchor()
        } else if !pinned {
            resizeIfVisible()
        }
    }

    func toggleCollapse() {
        setCollapsed(!layoutState.isCollapsed)
    }

    func setCollapsed(_ collapsed: Bool) {
        guard layoutState.isPinned else { return }
        guard let panel = panel, panel.isVisible else { return }

        layoutState.isCollapsed = collapsed

        let targetSize: CGSize
        if collapsed {
            targetSize = Self.collapsedSize
        } else {
            let anchorInfo = lastAnchorInfo ?? (layoutState.triggerSource == .menuBar ? DockLocator.resolveMenuBarAnchor(from: lastStatusButton) : DockLocator.resolveDockAnchor())
            targetSize = computePanelSize(for: ChestStore.shared.config, edge: anchorInfo.edge)
        }

        // Keep top-right corner stationary
        let currentFrame = panel.frame
        let newX = currentFrame.maxX - targetSize.width
        let newY = currentFrame.maxY - targetSize.height
        let targetFrame = NSRect(x: newX, y: newY, width: targetSize.width, height: targetSize.height)

        isProgrammaticFrameChange = true
        panel.setFrame(targetFrame, display: true, animate: true)
        isProgrammaticFrameChange = false
    }

    /// Invoked from the right-click menu ("钉住气泡面板"):
    func openPinnedOrTogglePin(source: BubbleTriggerSource, statusButton: NSStatusBarButton? = nil) {
        if !isVisible {
            switch source {
            case .menuBar:
                showFromMenuBar(button: statusButton, forcePinned: true)
            case .dock:
                showFromDock(forcePinned: true)
            }
        } else {
            togglePin()
        }
    }

    func snapBackToAnchor() {
        guard let panel = panel else { return }
        let anchorInfo: DockAnchorInfo
        switch layoutState.triggerSource {
        case .dock:
            anchorInfo = DockLocator.resolveDockAnchor()
        case .menuBar:
            anchorInfo = DockLocator.resolveMenuBarAnchor(from: lastStatusButton)
        }
        lastAnchorInfo = anchorInfo
        layoutState.dockEdge = anchorInfo.edge

        let bubbleSize: CGSize
        if layoutState.isCollapsed {
            bubbleSize = Self.collapsedSize
        } else {
            bubbleSize = computePanelSize(for: ChestStore.shared.config, edge: anchorInfo.edge)
        }

        let (frame, tailOffset) = computeFrameAndTailOffset(
            bubbleSize: bubbleSize,
            anchorInfo: anchorInfo
        )
        anchoredOrigin = frame.origin

        layoutState.tailOffsetFromCenter = tailOffset
        layoutState.isDetachedFromDock = false

        isProgrammaticFrameChange = true
        panel.setFrame(frame, display: true, animate: true)
        isProgrammaticFrameChange = false
    }

    // MARK: - Show / Hide / Toggle (Dock & Menu Bar)

    func toggleFromDockClick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastOutsideDismissTime < 0.3 && lastOutsideDismissSource == .dock {
            return
        }

        if isVisible {
            if layoutState.triggerSource == .menuBar {
                showFromDock()
            } else {
                hide(forceEvenIfPinned: true)
            }
        } else {
            showFromDock()
        }
    }

    func toggleFromMenuBar(button: NSStatusBarButton?) {
        if let button = button {
            lastStatusButton = button
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastOutsideDismissTime < 0.3 && lastOutsideDismissSource == .menuBar {
            return
        }

        if isVisible {
            if layoutState.triggerSource == .dock {
                showFromMenuBar(button: button)
            } else {
                hide(forceEvenIfPinned: true)
            }
        } else {
            showFromMenuBar(button: button)
        }
    }

    func showFromDock(forcePinned: Bool = false) {
        layoutState.triggerSource = .dock
        layoutState.isDetachedFromDock = false
        layoutState.isCollapsed = false
        let anchorInfo = DockLocator.resolveDockAnchor()
        present(with: anchorInfo, forcePinned: forcePinned)
    }

    func showFromMenuBar(button: NSStatusBarButton?, forcePinned: Bool = false) {
        layoutState.triggerSource = .menuBar
        layoutState.isDetachedFromDock = false
        layoutState.isCollapsed = false
        if let button = button {
            lastStatusButton = button
        }
        let anchorInfo = DockLocator.resolveMenuBarAnchor(from: button ?? lastStatusButton)
        present(with: anchorInfo, forcePinned: forcePinned)
    }

    func show() {
        showFromDock()
    }

    private func present(with anchorInfo: DockAnchorInfo, forcePinned: Bool) {
        visibilityGeneration += 1
        let store = ChestStore.shared
        lastAnchorInfo = anchorInfo
        layoutState.dockEdge = anchorInfo.edge

        if forcePinned {
            layoutState.isPinned = true
        }

        let bubbleSize: CGSize
        if layoutState.isCollapsed {
            bubbleSize = Self.collapsedSize
        } else {
            bubbleSize = computePanelSize(for: store.config, edge: anchorInfo.edge)
        }

        let (frame, tailOffset) = computeFrameAndTailOffset(
            bubbleSize: bubbleSize,
            anchorInfo: anchorInfo
        )
        layoutState.tailOffsetFromCenter = tailOffset

        if panel == nil {
            createPanel(initialFrame: frame)
        }

        guard let panel = panel else { return }

        isProgrammaticFrameChange = true
        if !layoutState.isDetachedFromDock {
            anchoredOrigin = frame.origin
            panel.setFrame(frame, display: true)
        } else {
            let currentOrigin = panel.frame.origin
            panel.setFrame(NSRect(origin: currentOrigin, size: bubbleSize), display: true)
        }
        isProgrammaticFrameChange = false

        let wasVisible = panel.isVisible && layoutState.isPresented
        layoutState.isPresented = true
        panel.makeKeyAndOrderFront(nil)

        if !wasVisible {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1.0
            }
        } else {
            panel.animator().alphaValue = 1.0
            panel.alphaValue = 1.0
        }

        startEventMonitors()
    }

    func hide(fromOutsideClick: Bool = false, forceEvenIfPinned: Bool = false) {
        guard let panel = panel, panel.isVisible else { return }
        if layoutState.isPinned && !forceEvenIfPinned {
            return
        }
        if fromOutsideClick {
            lastOutsideDismissTime = ProcessInfo.processInfo.systemUptime
            lastOutsideDismissSource = layoutState.triggerSource
        }
        visibilityGeneration += 1
        let hideGeneration = visibilityGeneration
        stopEventMonitors()
        layoutState.isPresented = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      self.visibilityGeneration == hideGeneration,
                      !self.layoutState.isPresented else {
                    return
                }
                panel.orderOut(nil)
            }
        })
    }

    func resizeIfVisible() {
        guard let panel = panel, panel.isVisible else { return }
        let anchorInfo = lastAnchorInfo ?? DockLocator.resolveDockAnchor()

        let bubbleSize: CGSize
        if layoutState.isCollapsed {
            bubbleSize = Self.collapsedSize
        } else {
            bubbleSize = computePanelSize(for: ChestStore.shared.config, edge: anchorInfo.edge)
        }

        let targetFrame: NSRect
        if layoutState.isDetachedFromDock {
            let oldFrame = panel.frame
            let newX = oldFrame.midX - bubbleSize.width / 2
            let newY = oldFrame.midY - bubbleSize.height / 2
            targetFrame = NSRect(x: newX, y: newY, width: bubbleSize.width, height: bubbleSize.height)
        } else {
            let (frame, tailOffset) = computeFrameAndTailOffset(
                bubbleSize: bubbleSize,
                anchorInfo: anchorInfo
            )
            anchoredOrigin = frame.origin
            layoutState.tailOffsetFromCenter = tailOffset
            targetFrame = frame
        }

        isProgrammaticFrameChange = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isProgrammaticFrameChange = false
            }
        })
    }

    // MARK: - Panel Setup & Geometry

    private func createPanel(initialFrame: NSRect) {
        let newPanel = BubblePanel(contentRect: initialFrame)
        newPanel.onEscapePressed = { [weak self] in
            self?.hide(forceEvenIfPinned: true)
        }
        newPanel.isPinnedProvider = { [weak self] in
            self?.layoutState.isPinned ?? false
        }
        newPanel.isCollapsedProvider = { [weak self] in
            self?.layoutState.isCollapsed ?? false
        }

        let rootView = BubbleContentView(
            store: ChestStore.shared,
            layoutState: layoutState
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: initialFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        newPanel.contentView = hostingView

        windowMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: newPanel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePanelDidMove()
            }
        }

        self.panel = newPanel
    }

    private func handlePanelDidMove() {
        guard !isProgrammaticFrameChange,
              layoutState.isPinned,
              let panel = panel,
              let anchored = anchoredOrigin else {
            return
        }

        let current = panel.frame.origin
        let distance = hypot(current.x - anchored.x, current.y - anchored.y)
        let shouldDetach = distance > 14

        if layoutState.isDetachedFromDock != shouldDetach {
            layoutState.isDetachedFromDock = shouldDetach
        }
    }

    private func computePanelSize(for config: GridConfig, edge: DockEdge) -> CGSize {
        let tailLength: CGFloat = 14
        let base = config.bubbleSize(tailHeight: 0)
        switch edge {
        case .bottom, .top:
            return CGSize(width: base.width, height: base.height + tailLength)
        case .left, .right:
            return CGSize(width: base.width + tailLength, height: base.height)
        }
    }

    private func computeFrameAndTailOffset(
        bubbleSize: CGSize,
        anchorInfo: DockAnchorInfo
    ) -> (NSRect, CGFloat) {
        let screenFrame = anchorInfo.screen.visibleFrame
        let fullFrame = anchorInfo.screen.frame
        let anchor = anchorInfo.anchorPoint
        let margin: CGFloat = 14
        let maxTailOffset = (bubbleSize.width / 2) - 36

        switch anchorInfo.edge {
        case .bottom:
            let idealX = anchor.x - bubbleSize.width / 2
            let minX = fullFrame.minX + margin
            let maxX = fullFrame.maxX - bubbleSize.width - margin
            let clampedX = min(max(idealX, minX), maxX)
            let y = max(screenFrame.minY + 6, anchor.y)

            let bubbleCenterX = clampedX + bubbleSize.width / 2
            let rawOffset = anchor.x - bubbleCenterX
            let tailOffset = min(max(rawOffset, -maxTailOffset), maxTailOffset)
            return (NSRect(x: clampedX, y: y, width: bubbleSize.width, height: bubbleSize.height), tailOffset)

        case .top:
            let idealX = anchor.x - bubbleSize.width / 2
            let minX = fullFrame.minX + margin
            let maxX = fullFrame.maxX - bubbleSize.width - margin
            let clampedX = min(max(idealX, minX), maxX)
            let y = min(screenFrame.maxY - bubbleSize.height - 4, anchor.y - bubbleSize.height)

            let bubbleCenterX = clampedX + bubbleSize.width / 2
            let rawOffset = anchor.x - bubbleCenterX
            let tailOffset = min(max(rawOffset, -maxTailOffset), maxTailOffset)
            return (NSRect(x: clampedX, y: y, width: bubbleSize.width, height: bubbleSize.height), tailOffset)

        case .left:
            let x = max(screenFrame.minX + 6, anchor.x)
            let idealY = anchor.y - bubbleSize.height / 2
            let minY = fullFrame.minY + margin
            let maxY = fullFrame.maxY - bubbleSize.height - margin
            let clampedY = min(max(idealY, minY), maxY)

            let bubbleCenterY = clampedY + bubbleSize.height / 2
            let maxVertOffset = (bubbleSize.height / 2) - 36
            let rawOffset = anchor.y - bubbleCenterY
            let tailOffset = min(max(rawOffset, -maxVertOffset), maxVertOffset)
            return (NSRect(x: x, y: clampedY, width: bubbleSize.width, height: bubbleSize.height), tailOffset)

        case .right:
            let x = min(screenFrame.maxX - bubbleSize.width - 6, anchor.x - bubbleSize.width)
            let idealY = anchor.y - bubbleSize.height / 2
            let minY = fullFrame.minY + margin
            let maxY = fullFrame.maxY - bubbleSize.height - margin
            let clampedY = min(max(idealY, minY), maxY)

            let bubbleCenterY = clampedY + bubbleSize.height / 2
            let maxVertOffset = (bubbleSize.height / 2) - 36
            let rawOffset = anchor.y - bubbleCenterY
            let tailOffset = min(max(rawOffset, -maxVertOffset), maxVertOffset)
            return (NSRect(x: x, y: clampedY, width: bubbleSize.width, height: bubbleSize.height), tailOffset)
        }
    }

    // MARK: - Event Monitors

    private func startEventMonitors() {
        stopEventMonitors()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self,
                      let panel = self.panel,
                      panel.isVisible,
                      !self.layoutState.isPinned else { return }
                let mouseLoc = NSEvent.mouseLocation
                if let button = self.lastStatusButton,
                   let btnWindow = button.window,
                   btnWindow.frame.insetBy(dx: -4, dy: -4).contains(mouseLoc) {
                    return
                }
                if !panel.frame.contains(mouseLoc) {
                    self.hide(fromOutsideClick: true)
                }
            }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self = self,
                  let panel = self.panel,
                  panel.isVisible,
                  !self.layoutState.isPinned else { return event }

            let mouseLoc = NSEvent.mouseLocation
            // If click occurs in an App window (like Settings) outside the bubble panel, dismiss bubble
            if event.window != panel && !panel.frame.contains(mouseLoc) {
                // Ignore click directly on menu bar button
                if let button = self.lastStatusButton,
                   let btnWindow = button.window,
                   btnWindow.frame.insetBy(dx: -4, dy: -4).contains(mouseLoc) {
                    return event
                }
                self.hide(fromOutsideClick: true)
            }
            return event
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }

            let store = ChestStore.shared
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let cmd = event.modifierFlags.contains(.command)
            let opt = event.modifierFlags.contains(.option)
            let ctrl = event.modifierFlags.contains(.control)
            let shift = event.modifierFlags.contains(.shift)

            func matchesShortcut(_ sc: KeyShortcut) -> Bool {
                guard sc.isEnabled else { return false }
                guard sc.key.lowercased() == key else { return false }
                let reqCmd = sc.modifiers.contains("command")
                let reqOpt = sc.modifiers.contains("option")
                let reqCtrl = sc.modifiers.contains("control")
                let reqShift = sc.modifiers.contains("shift")
                return cmd == reqCmd && opt == reqOpt && ctrl == reqCtrl && shift == reqShift
            }

            if matchesShortcut(store.config.togglePinShortcut) {
                self.togglePin()
                return nil
            }

            if self.layoutState.isPinned && matchesShortcut(store.config.toggleCollapseShortcut) {
                self.toggleCollapse()
                return nil
            }

            if let firstResponder = self.panel?.firstResponder,
               firstResponder is NSTextView || firstResponder is NSTextField {
                if event.keyCode == 53 { // Escape
                    self.panel?.makeFirstResponder(nil)
                    return nil
                }
                return event
            }

            switch event.keyCode {
            case 53: // Escape
                self.hide(forceEvenIfPinned: true)
                return nil
            case 123: // Left Arrow
                if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
                    ChestStore.shared.selectPreviousCategory()
                } else {
                    ChestStore.shared.goToPreviousPage()
                }
                return nil
            case 124: // Right Arrow
                if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
                    ChestStore.shared.selectNextCategory()
                } else {
                    ChestStore.shared.goToNextPage()
                }
                return nil
            case 48: // Tab
                if event.modifierFlags.contains(.shift) {
                    ChestStore.shared.selectPreviousCategory()
                } else {
                    ChestStore.shared.selectNextCategory()
                }
                return nil
            default:
                return event
            }
        }
    }

    private func stopEventMonitors() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
}
