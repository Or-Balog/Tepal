import CoreGraphics
import TepalCore

public struct TepalPaths {
    public let body: CGPath
    public let leftLeaf: CGPath
    public let rightLeaf: CGPath
    public let leftEye: CGPath
    public let rightEye: CGPath
    public let growthMarks: [CGPath]

    public init(
        body: CGPath,
        leftLeaf: CGPath,
        rightLeaf: CGPath,
        leftEye: CGPath,
        rightEye: CGPath,
        growthMarks: [CGPath]
    ) {
        self.body = body
        self.leftLeaf = leftLeaf
        self.rightLeaf = rightLeaf
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.growthMarks = growthMarks
    }
}

public enum TepalGeometry {
    public static func paths(
        in bounds: CGRect,
        pose: TepalPose,
        growth: TepalGrowthTier,
        motion: TepalMotionFrame = .settled
    ) -> TepalPaths {
        let adjustment = adjustment(for: pose)
        let sway = CGFloat(motion.leafSway)
        let body = bodyPath(adjustment: adjustment)
        let leftLeaf = leafPath(
            base: CGPoint(x: 0.39 + adjustment.x, y: 0.63 + adjustment.y),
            tip: CGPoint(
                x: 0.24 + adjustment.x - adjustment.leafSpread + 0.012 * max(0, sway),
                y: 0.86 + adjustment.y
            ),
            width: 0.085
        )
        let rightLeaf = leafPath(
            base: CGPoint(x: 0.59 + adjustment.x, y: 0.635 + adjustment.y),
            tip: CGPoint(
                x: 0.74 + adjustment.x + adjustment.leafSpread + 0.012 * min(0, sway),
                y: 0.87 + adjustment.y
            ),
            width: 0.09
        )
        let eyeY = 0.49 + adjustment.y - adjustment.eyeDrop
        let eyeHeight = 0.065 * CGFloat(max(0.08, min(1, motion.eyeOpen)))
        let centeredEyeY = eyeY + (0.065 - eyeHeight) / 2
        let leftEye = ellipse(CGRect(
            x: 0.405 + adjustment.x,
            y: centeredEyeY,
            width: 0.045,
            height: eyeHeight
        ))
        let rightEye = ellipse(CGRect(
            x: 0.555 + adjustment.x,
            y: centeredEyeY,
            width: 0.045,
            height: eyeHeight
        ))
        let growthMarks = growthMarkRects.prefix(markCount(for: growth)).map { rect in
            ellipse(rect.offsetBy(dx: adjustment.x, dy: adjustment.y))
        }
        let settledLeftLeaf = leafPath(
            base: CGPoint(x: 0.39 + adjustment.x, y: 0.63 + adjustment.y),
            tip: CGPoint(x: 0.24 + adjustment.x - adjustment.leafSpread, y: 0.86 + adjustment.y),
            width: 0.085
        )
        let settledRightLeaf = leafPath(
            base: CGPoint(x: 0.59 + adjustment.x, y: 0.635 + adjustment.y),
            tip: CGPoint(x: 0.74 + adjustment.x + adjustment.leafSpread, y: 0.87 + adjustment.y),
            width: 0.09
        )
        let characterBounds = [body, settledLeftLeaf, settledRightLeaf].reduce(CGRect.null) { bounds, path in
            bounds.union(path.boundingBoxOfPath)
        }
        let mappedBounds = bounds.insetBy(dx: 0.0001, dy: 0.0001)

        return TepalPaths(
            body: map(body, from: characterBounds, into: mappedBounds),
            leftLeaf: map(leftLeaf, from: characterBounds, into: mappedBounds),
            rightLeaf: map(rightLeaf, from: characterBounds, into: mappedBounds),
            leftEye: map(leftEye, from: characterBounds, into: mappedBounds),
            rightEye: map(rightEye, from: characterBounds, into: mappedBounds),
            growthMarks: growthMarks.map { map($0, from: characterBounds, into: mappedBounds) }
        )
    }

    private struct PoseAdjustment {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let leafSpread: CGFloat
        let eyeDrop: CGFloat
    }

    private static func adjustment(for pose: TepalPose) -> PoseAdjustment {
        switch pose {
        case .preparingFocus:
            PoseAdjustment(x: 0, y: -0.01, width: 0.01, height: -0.01, leafSpread: -0.01, eyeDrop: 0)
        case .keepingWatch:
            PoseAdjustment(x: 0, y: 0, width: 0, height: 0.01, leafSpread: 0, eyeDrop: 0)
        case .pausedCurious:
            PoseAdjustment(x: 0.015, y: 0, width: 0, height: 0, leafSpread: 0.015, eyeDrop: -0.01)
        case .resting:
            PoseAdjustment(x: 0, y: -0.07, width: 0.05, height: -0.07, leafSpread: -0.025, eyeDrop: 0.025)
        case .meetingAttentive:
            PoseAdjustment(x: 0, y: 0.015, width: -0.01, height: 0.02, leafSpread: 0.025, eyeDrop: -0.01)
        case .completionBloom:
            PoseAdjustment(x: 0, y: 0.02, width: 0.015, height: 0.02, leafSpread: 0.04, eyeDrop: 0)
        case .walking:
            PoseAdjustment(x: 0.025, y: -0.015, width: 0, height: 0, leafSpread: 0.01, eyeDrop: 0)
        case .ready, .staticFallback:
            PoseAdjustment(x: 0, y: 0, width: 0, height: 0, leafSpread: 0, eyeDrop: 0)
        }
    }

    private static func bodyPath(adjustment: PoseAdjustment) -> CGPath {
        // The body carries a deliberate 55/45 left/right weight around its visual center.
        let left = 0.235 + adjustment.x - adjustment.width
        let right = 0.725 + adjustment.x + adjustment.width
        let bottom = 0.18 + adjustment.y
        let top = 0.71 + adjustment.y + adjustment.height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.485 + adjustment.x, y: bottom))
        path.addCurve(
            to: CGPoint(x: left, y: 0.44 + adjustment.y),
            control1: CGPoint(x: 0.34 + adjustment.x, y: bottom - 0.01),
            control2: CGPoint(x: left - 0.02, y: 0.29 + adjustment.y)
        )
        path.addCurve(
            to: CGPoint(x: 0.44 + adjustment.x, y: top),
            control1: CGPoint(x: left - 0.005, y: 0.61 + adjustment.y),
            control2: CGPoint(x: 0.33 + adjustment.x, y: top + 0.02)
        )
        path.addCurve(
            to: CGPoint(x: 0.66 + adjustment.x, y: 0.66 + adjustment.y + adjustment.height),
            control1: CGPoint(x: 0.53 + adjustment.x, y: top + 0.015),
            control2: CGPoint(x: 0.62 + adjustment.x, y: 0.72 + adjustment.y + adjustment.height)
        )
        path.addCurve(
            to: CGPoint(x: right, y: 0.42 + adjustment.y),
            control1: CGPoint(x: 0.72 + adjustment.x, y: 0.62 + adjustment.y),
            control2: CGPoint(x: right + 0.025, y: 0.52 + adjustment.y)
        )
        path.addCurve(
            to: CGPoint(x: 0.485 + adjustment.x, y: bottom),
            control1: CGPoint(x: right + 0.015, y: 0.28 + adjustment.y),
            control2: CGPoint(x: 0.63 + adjustment.x, y: bottom - 0.01)
        )
        path.closeSubpath()
        return path
    }

    private static func leafPath(base: CGPoint, tip: CGPoint, width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: base)
        path.addCurve(
            to: tip,
            control1: CGPoint(x: base.x - width * 0.85, y: base.y + 0.08),
            control2: CGPoint(x: tip.x - width * 0.45, y: tip.y - 0.02)
        )
        path.addCurve(
            to: base,
            control1: CGPoint(x: tip.x + width * 0.50, y: tip.y - 0.05),
            control2: CGPoint(x: base.x + width * 0.70, y: base.y + 0.03)
        )
        path.closeSubpath()
        return path
    }

    private static let growthMarkRects = [
        CGRect(x: 0.474, y: 0.615, width: 0.052, height: 0.035),
        CGRect(x: 0.375, y: 0.355, width: 0.040, height: 0.040),
        CGRect(x: 0.590, y: 0.320, width: 0.045, height: 0.045),
        CGRect(x: 0.480, y: 0.260, width: 0.040, height: 0.050),
    ]

    private static func markCount(for growth: TepalGrowthTier) -> Int {
        switch growth {
        case .seedling: 0
        case .glowing: 1
        case .sprouted: 2
        case .flourishing: 3
        case .mature: 4
        }
    }

    private static func ellipse(_ rect: CGRect) -> CGPath {
        CGPath(ellipseIn: rect, transform: nil)
    }

    private static func map(_ path: CGPath, from sourceBounds: CGRect, into bounds: CGRect) -> CGPath {
        guard sourceBounds.width > 0, sourceBounds.height > 0 else { return path }
        var transform = CGAffineTransform(
            a: bounds.width / sourceBounds.width,
            b: 0,
            c: 0,
            d: bounds.height / sourceBounds.height,
            tx: bounds.minX - sourceBounds.minX * bounds.width / sourceBounds.width,
            ty: bounds.minY - sourceBounds.minY * bounds.height / sourceBounds.height
        )
        return path.copy(using: &transform) ?? path
    }
}
