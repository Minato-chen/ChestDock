import AppKit

/// Renders either the minimalist static ChestDock icon or an iOS-folder style rounded squircle icon
/// containing a 2x2 or 3x3 grid of app icons directly onto the macOS Dock tile (`NSApp.dockTile`).
enum DockTileRenderer {
    @MainActor
    static func updateDockTile(with icons: [NSImage], grid: DockTilePreviewGrid) {
        let size = NSSize(width: 256, height: 256)
        let renderedImage: NSImage
        if grid == .staticAppIcon {
            renderedImage = renderStaticAppIcon(size: size)
        } else {
            renderedImage = renderFolderIcon(size: size, icons: icons, grid: grid)
        }

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = renderedImage
        imageView.imageScaling = .scaleProportionallyUpOrDown

        NSApp.applicationIconImage = renderedImage
        NSApp.dockTile.contentView = imageView
        NSApp.dockTile.display()
    }

    /// Renders the minimalist ChestDock app icon directly using CoreGraphics so it is 100% immune to LaunchServices icon cache.
    static func renderStaticAppIcon(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            return image
        }

        let scale = size.width / 1024.0
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)

        // 1. Outer macOS Squircle (824x824 centered in 1024x1024)
        let baseRect = NSRect(x: 100, y: 100, width: 824, height: 824)
        let baseRadius: CGFloat = 185.0
        let basePath = NSBezierPath(roundedRect: baseRect, xRadius: baseRadius, yRadius: baseRadius)

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -22 * scale),
            blur: 42 * scale,
            color: NSColor(calibratedRed: 0.05, green: 0.12, blue: 0.28, alpha: 0.38).cgColor
        )
        NSColor.black.setFill()
        basePath.fill()
        ctx.restoreGState()

        ctx.saveGState()
        basePath.addClip()

        let bgGradient = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.92, alpha: 1.0), 0.0),
            (NSColor(calibratedRed: 0.30, green: 0.66, blue: 0.98, alpha: 1.0), 1.0)
        )
        bgGradient?.draw(in: baseRect, angle: 90)

        // 2. Minimalist White Bubble with Tail in the Center
        let bubbleRect = NSRect(x: 242, y: 274, width: 540, height: 510)
        let bubbleRadius: CGFloat = 122
        let tailWidth: CGFloat = 88
        let tailHeight: CGFloat = 48
        let midX = bubbleRect.midX
        let bottomY = bubbleRect.minY

        let bubblePath = NSBezierPath()
        bubblePath.move(to: NSPoint(x: midX + tailWidth / 2, y: bottomY))
        bubblePath.line(to: NSPoint(x: bubbleRect.maxX - bubbleRadius, y: bottomY))
        bubblePath.appendArc(
            withCenter: NSPoint(x: bubbleRect.maxX - bubbleRadius, y: bottomY + bubbleRadius),
            radius: bubbleRadius,
            startAngle: 270,
            endAngle: 360
        )
        bubblePath.line(to: NSPoint(x: bubbleRect.maxX, y: bubbleRect.maxY - bubbleRadius))
        bubblePath.appendArc(
            withCenter: NSPoint(x: bubbleRect.maxX - bubbleRadius, y: bubbleRect.maxY - bubbleRadius),
            radius: bubbleRadius,
            startAngle: 0,
            endAngle: 90
        )
        bubblePath.line(to: NSPoint(x: bubbleRect.minX + bubbleRadius, y: bubbleRect.maxY))
        bubblePath.appendArc(
            withCenter: NSPoint(x: bubbleRect.minX + bubbleRadius, y: bubbleRect.maxY - bubbleRadius),
            radius: bubbleRadius,
            startAngle: 90,
            endAngle: 180
        )
        bubblePath.line(to: NSPoint(x: bubbleRect.minX, y: bottomY + bubbleRadius))
        bubblePath.appendArc(
            withCenter: NSPoint(x: bubbleRect.minX + bubbleRadius, y: bottomY + bubbleRadius),
            radius: bubbleRadius,
            startAngle: 180,
            endAngle: 270
        )
        bubblePath.line(to: NSPoint(x: midX - tailWidth / 2, y: bottomY))

        bubblePath.curve(
            to: NSPoint(x: midX, y: bottomY - tailHeight),
            controlPoint1: NSPoint(x: midX - tailWidth * 0.24, y: bottomY),
            controlPoint2: NSPoint(x: midX - 10, y: bottomY - tailHeight + 4)
        )
        bubblePath.curve(
            to: NSPoint(x: midX + tailWidth / 2, y: bottomY),
            controlPoint1: NSPoint(x: midX + 10, y: bottomY - tailHeight + 4),
            controlPoint2: NSPoint(x: midX + tailWidth * 0.24, y: bottomY)
        )
        bubblePath.close()

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -14 * scale),
            blur: 28 * scale,
            color: NSColor(calibratedRed: 0.04, green: 0.14, blue: 0.38, alpha: 0.28).cgColor
        )
        let bubbleGrad = NSGradient(
            starting: NSColor(calibratedWhite: 1.0, alpha: 0.96),
            ending: NSColor(calibratedRed: 0.90, green: 0.95, blue: 1.0, alpha: 0.92)
        )
        bubbleGrad?.draw(in: bubblePath, angle: -90)
        ctx.restoreGState()

        // 3. Clean 2x2 Rounded Squares inside the Bubble
        let squareSide: CGFloat = 152
        let gap: CGFloat = 44
        let gridTotal = squareSide * 2 + gap
        let startX = bubbleRect.midX - gridTotal / 2
        let startY = bubbleRect.midY - gridTotal / 2

        let colors: [(NSColor, NSColor)] = [
            (NSColor(calibratedRed: 0.22, green: 0.64, blue: 1.0, alpha: 1.0),
             NSColor(calibratedRed: 0.12, green: 0.44, blue: 0.94, alpha: 1.0)),
            (NSColor(calibratedRed: 0.20, green: 0.84, blue: 0.86, alpha: 1.0),
             NSColor(calibratedRed: 0.10, green: 0.64, blue: 0.78, alpha: 1.0)),
            (NSColor(calibratedRed: 0.44, green: 0.48, blue: 0.98, alpha: 1.0),
             NSColor(calibratedRed: 0.30, green: 0.32, blue: 0.88, alpha: 1.0)),
            (NSColor(calibratedRed: 1.0, green: 0.66, blue: 0.24, alpha: 1.0),
             NSColor(calibratedRed: 0.96, green: 0.44, blue: 0.16, alpha: 1.0))
        ]

        for index in 0..<4 {
            let row = index / 2
            let col = index % 2
            let x = startX + CGFloat(col) * (squareSide + gap)
            let y = startY + CGFloat(1 - row) * (squareSide + gap)
            let rect = NSRect(x: x, y: y, width: squareSide, height: squareSide)
            let path = NSBezierPath(roundedRect: rect, xRadius: 38, yRadius: 38)
            let (topColor, bottomColor) = colors[index]
            NSGradient(starting: topColor, ending: bottomColor)?.draw(in: path, angle: -90)
        }

        ctx.restoreGState()

        let borderRect = baseRect.insetBy(dx: 2.5, dy: 2.5)
        let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: baseRadius - 2, yRadius: baseRadius - 2)
        NSColor.white.withAlphaComponent(0.32).setStroke()
        borderPath.lineWidth = 5.0
        borderPath.stroke()

        ctx.restoreGState()
        return image
    }

    static func renderFolderIcon(size: NSSize, icons: [NSImage], grid: DockTilePreviewGrid) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            return image
        }

        let padding: CGFloat = size.width * 0.09
        let folderRect = NSRect(
            x: padding,
            y: padding,
            width: size.width - padding * 2,
            height: size.height - padding * 2
        )
        let cornerRadius = folderRect.width * 0.23

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -6),
            blur: 14,
            color: NSColor.black.withAlphaComponent(0.32).cgColor
        )

        let squirclePath = NSBezierPath(roundedRect: folderRect, xRadius: cornerRadius, yRadius: cornerRadius)

        let topColor = NSColor(calibratedRed: 0.92, green: 0.95, blue: 1.0, alpha: 0.88)
        let bottomColor = NSColor(calibratedRed: 0.76, green: 0.82, blue: 0.94, alpha: 0.85)
        if let gradient = NSGradient(starting: topColor, ending: bottomColor) {
            gradient.draw(in: squirclePath, angle: -90)
        } else {
            topColor.setFill()
            squirclePath.fill()
        }
        ctx.restoreGState()

        ctx.saveGState()
        let borderPath = NSBezierPath(
            roundedRect: folderRect.insetBy(dx: 1.5, dy: 1.5),
            xRadius: cornerRadius - 1,
            yRadius: cornerRadius - 1
        )
        borderPath.lineWidth = 2.5
        NSColor.white.withAlphaComponent(0.55).setStroke()
        borderPath.stroke()
        ctx.restoreGState()

        let gridCount = max(2, grid.rawValue)
        let innerPadding = folderRect.width * (gridCount == 2 ? 0.15 : 0.13)
        let gridArea = folderRect.insetBy(dx: innerPadding, dy: innerPadding)
        let spacing = folderRect.width * (gridCount == 2 ? 0.08 : 0.055)
        let totalSpacing = spacing * CGFloat(gridCount - 1)
        let cellSize = (gridArea.width - totalSpacing) / CGFloat(gridCount)

        for index in 0..<min(icons.count, grid.maxIcons) {
            let row = index / gridCount
            let col = index % gridCount

            let cellX = gridArea.minX + CGFloat(col) * (cellSize + spacing)
            let cellY = gridArea.maxY - CGFloat(row + 1) * cellSize - CGFloat(row) * spacing
            let cellRect = NSRect(x: cellX, y: cellY, width: cellSize, height: cellSize)

            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -1.5),
                blur: 3.0,
                color: NSColor.black.withAlphaComponent(0.22).cgColor
            )
            icons[index].draw(
                in: cellRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: false,
                hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
            )
            ctx.restoreGState()
        }

        if icons.isEmpty {
            for index in 0..<4 {
                let row = index / 2
                let col = index % 2
                let emptyInset = folderRect.width * 0.18
                let area = folderRect.insetBy(dx: emptyInset, dy: emptyInset)
                let gap = folderRect.width * 0.08
                let side = (area.width - gap) / 2
                let x = area.minX + CGFloat(col) * (side + gap)
                let y = area.maxY - CGFloat(row + 1) * side - CGFloat(row) * gap
                let rect = NSRect(x: x, y: y, width: side, height: side)
                let placeholder = NSBezierPath(roundedRect: rect, xRadius: side * 0.24, yRadius: side * 0.24)
                NSColor.white.withAlphaComponent(0.45).setFill()
                placeholder.fill()
            }
        }

        return image
    }
}
