import SwiftUI
import AppKit

/// Custom shape that draws an iOS-folder rounded rectangle merged with a smooth pointer tail.
/// Supports `.bottom`, `.left`, `.right` (Dock) and `.top` (Menu Bar), plus `tailProgress` (0.0 when detached).
struct BubbleShape: Shape {
    var edge: DockEdge
    var tailOffset: CGFloat
    var tailProgress: CGFloat = 1.0
    var cornerRadius: CGFloat = 26
    var tailWidth: CGFloat = 24
    var tailHeight: CGFloat = 13

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(tailOffset, tailProgress) }
        set {
            tailOffset = newValue.first
            tailProgress = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let effectiveTailHeight = tailHeight * max(0, min(1, tailProgress))
        let bodyRect: CGRect
        switch edge {
        case .bottom:
            bodyRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: max(0, rect.height - tailHeight)
            )
        case .top:
            bodyRect = CGRect(
                x: rect.minX,
                y: rect.minY + tailHeight,
                width: rect.width,
                height: max(0, rect.height - tailHeight)
            )
        case .left:
            bodyRect = CGRect(
                x: rect.minX + tailHeight,
                y: rect.minY,
                width: max(0, rect.width - tailHeight),
                height: rect.height
            )
        case .right:
            bodyRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: max(0, rect.width - tailHeight),
                height: rect.height
            )
        }

        let r = min(cornerRadius, min(bodyRect.width, bodyRect.height) / 2)
        var path = Path()

        // Start top-left after corner
        path.move(to: CGPoint(x: bodyRect.minX + r, y: bodyRect.minY))

        // Top edge (with tail if opened from Menu Bar `.top` and tailProgress > 0.01)
        if edge == .top && effectiveTailHeight > 0.2 {
            let centerX = clamp(
                bodyRect.midX + tailOffset,
                min: bodyRect.minX + r + tailWidth / 2 + 6,
                max: bodyRect.maxX - r - tailWidth / 2 - 6
            )
            let tipY = bodyRect.minY - effectiveTailHeight
            path.addLine(to: CGPoint(x: centerX - tailWidth / 2, y: bodyRect.minY))
            path.addCurve(
                to: CGPoint(x: centerX, y: tipY),
                control1: CGPoint(x: centerX - tailWidth * 0.22, y: bodyRect.minY),
                control2: CGPoint(x: centerX - 2, y: tipY + 2)
            )
            path.addCurve(
                to: CGPoint(x: centerX + tailWidth / 2, y: bodyRect.minY),
                control1: CGPoint(x: centerX + 2, y: tipY + 2),
                control2: CGPoint(x: centerX + tailWidth * 0.22, y: bodyRect.minY)
            )
        }

        // Top-right corner
        path.addLine(to: CGPoint(x: bodyRect.maxX - r, y: bodyRect.minY))
        path.addArc(
            center: CGPoint(x: bodyRect.maxX - r, y: bodyRect.minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Right edge (with tail if Dock is on the right and tailProgress > 0.01)
        if edge == .right && effectiveTailHeight > 0.2 {
            let centerY = clamp(
                bodyRect.midY - tailOffset,
                min: bodyRect.minY + r + tailWidth / 2 + 6,
                max: bodyRect.maxY - r - tailWidth / 2 - 6
            )
            let tipX = bodyRect.maxX + effectiveTailHeight
            path.addLine(to: CGPoint(x: bodyRect.maxX, y: centerY - tailWidth / 2))
            path.addCurve(
                to: CGPoint(x: tipX, y: centerY),
                control1: CGPoint(x: bodyRect.maxX, y: centerY - tailWidth * 0.22),
                control2: CGPoint(x: tipX - 2, y: centerY - 2)
            )
            path.addCurve(
                to: CGPoint(x: bodyRect.maxX, y: centerY + tailWidth / 2),
                control1: CGPoint(x: tipX - 2, y: centerY + 2),
                control2: CGPoint(x: bodyRect.maxX, y: centerY + tailWidth * 0.22)
            )
        }

        // Bottom-right corner
        path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - r))
        path.addArc(
            center: CGPoint(x: bodyRect.maxX - r, y: bodyRect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge (with tail if Dock is at the bottom and tailProgress > 0.01)
        if edge == .bottom && effectiveTailHeight > 0.2 {
            let centerX = clamp(
                bodyRect.midX + tailOffset,
                min: bodyRect.minX + r + tailWidth / 2 + 6,
                max: bodyRect.maxX - r - tailWidth / 2 - 6
            )
            let tipY = bodyRect.maxY + effectiveTailHeight
            path.addLine(to: CGPoint(x: centerX + tailWidth / 2, y: bodyRect.maxY))
            path.addCurve(
                to: CGPoint(x: centerX, y: tipY),
                control1: CGPoint(x: centerX + tailWidth * 0.22, y: bodyRect.maxY),
                control2: CGPoint(x: centerX + 2, y: tipY - 2)
            )
            path.addCurve(
                to: CGPoint(x: centerX - tailWidth / 2, y: bodyRect.maxY),
                control1: CGPoint(x: centerX - 2, y: tipY - 2),
                control2: CGPoint(x: centerX - tailWidth * 0.22, y: bodyRect.maxY)
            )
        }

        // Bottom-left corner
        path.addLine(to: CGPoint(x: bodyRect.minX + r, y: bodyRect.maxY))
        path.addArc(
            center: CGPoint(x: bodyRect.minX + r, y: bodyRect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Left edge (with tail if Dock is on the left and tailProgress > 0.01)
        if edge == .left && effectiveTailHeight > 0.2 {
            let centerY = clamp(
                bodyRect.midY - tailOffset,
                min: bodyRect.minY + r + tailWidth / 2 + 6,
                max: bodyRect.maxY - r - tailWidth / 2 - 6
            )
            let tipX = bodyRect.minX - effectiveTailHeight
            path.addLine(to: CGPoint(x: bodyRect.minX, y: centerY + tailWidth / 2))
            path.addCurve(
                to: CGPoint(x: tipX, y: centerY),
                control1: CGPoint(x: bodyRect.minX, y: centerY + tailWidth * 0.22),
                control2: CGPoint(x: tipX + 2, y: centerY + 2)
            )
            path.addCurve(
                to: CGPoint(x: bodyRect.minX, y: centerY - tailWidth / 2),
                control1: CGPoint(x: tipX + 2, y: centerY - 2),
                control2: CGPoint(x: bodyRect.minX, y: centerY - tailWidth * 0.22)
            )
        }

        // Top-left corner
        path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + r))
        path.addArc(
            center: CGPoint(x: bodyRect.minX + r, y: bodyRect.minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }

    private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lower), upper)
    }
}

/// Native macOS frosted glass backdrop (`NSVisualEffectView`) for the iOS folder bubble.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}
