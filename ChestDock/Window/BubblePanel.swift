import AppKit

/// A borderless, transparent, non-activating floating panel that hosts the iOS-style folder bubble.
final class BubblePanel: NSPanel {
    var onEscapePressed: (() -> Void)?
    var isPinnedProvider: (() -> Bool)?
    var isCollapsedProvider: (() -> Bool)?
    var onDragEnded: (() -> Void)?

    private var canTrackWindowDrag = false
    private var isDraggingWindow = false
    private var dragStartMouseScreenPoint: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false // Disable system rectangular window shadow to avoid grey border artifacts at squircle corners
        self.isMovableByWindowBackground = false // Controlled via manual drag tracking
        self.hidesOnDeactivate = false
        self.acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func sendEvent(_ event: NSEvent) {
        let isPinned = isPinnedProvider?() ?? false
        let isCollapsed = isCollapsedProvider?() ?? false

        switch event.type {
        case .leftMouseDown:
            isDraggingWindow = false
            if isPinned && (isCollapsed || isDraggableRegion(pointInWindow: event.locationInWindow)) {
                canTrackWindowDrag = true
                dragStartMouseScreenPoint = NSEvent.mouseLocation
                dragStartWindowOrigin = self.frame.origin
            } else {
                canTrackWindowDrag = false
            }
            super.sendEvent(event)

        case .leftMouseDragged:
            if isPinned && canTrackWindowDrag {
                let currentMouse = NSEvent.mouseLocation
                let dx = currentMouse.x - dragStartMouseScreenPoint.x
                let dy = currentMouse.y - dragStartMouseScreenPoint.y
                if isDraggingWindow || hypot(dx, dy) > 3.0 {
                    isDraggingWindow = true
                    self.setFrameOrigin(
                        NSPoint(
                            x: dragStartWindowOrigin.x + dx,
                            y: dragStartWindowOrigin.y + dy
                        )
                    )
                    return
                }
            }
            super.sendEvent(event)

        case .leftMouseUp:
            if isDraggingWindow {
                isDraggingWindow = false
                canTrackWindowDrag = false
                onDragEnded?()
                return
            }
            canTrackWindowDrag = false
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }

    /// Returns true if the mouse-down point is on the top header bar, bottom page-dots bar, or outer margins
    private func isDraggableRegion(pointInWindow pt: NSPoint) -> Bool {
        let w = frame.width
        let h = frame.height

        let isTopBar = pt.y >= h - 60
        let isBottomBar = pt.y <= 40
        let isSideMargin = pt.x <= 22 || pt.x >= w - 22

        return isTopBar || isBottomBar || isSideMargin
    }

    override func cancelOperation(_ sender: Any?) {
        onEscapePressed?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            onEscapePressed?()
            return
        }
        super.keyDown(with: event)
    }
}
