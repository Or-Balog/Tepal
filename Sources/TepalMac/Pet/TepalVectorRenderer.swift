import AppKit
import CoreGraphics
import TepalCore

public enum TepalRenderSurface: Equatable, Sendable {
    case dock, habitat, preview, excursion

    public var showsTimerProgress: Bool { self == .dock }
}

public enum TepalDockProgressPresentation: Equatable, Sendable {
    case halo
    case activeTimer(progress: Double)

    // TepalVisualState encodes timer activity through its semantic timer poses.
    // Non-timer poses must not turn a retained numeric progress value into a Dock ring.
    public static func make(for state: TepalVisualState) -> TepalDockProgressPresentation {
        switch state.pose {
        case .preparingFocus, .keepingWatch, .pausedCurious, .resting:
            .activeTimer(progress: min(1, max(0, state.timerProgress)))
        case .ready, .meetingAttentive, .completionBloom, .walking, .staticFallback:
            .halo
        }
    }
}

@MainActor
public enum TepalVectorRenderer {
    public static func draw(
        state: TepalVisualState,
        surface: TepalRenderSurface,
        illustrated: Bool = false,
        frameIndex: Int,
        signatureMotionProgress: Double = 1,
        in context: CGContext,
        bounds: CGRect
    ) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let callerPath = context.path?.copy()
        let palette = TepalTheme.palette(for: state.palette)
        let renderBounds = surface == .habitat ? bounds : aspectFitSquare(in: bounds)
        let motionProgress = state.reducedMotion
            ? 1
            : min(1, max(0, signatureMotionProgress))
        let paths = TepalGeometry.paths(
            in: animatedBounds(
                for: state,
                frameIndex: frameIndex,
                signatureMotionProgress: motionProgress,
                bounds: renderBounds
            ),
            pose: state.pose,
            growth: state.growth.tier,
            motion: TepalMotionPolicy.frame(
                for: state.pose,
                frameIndex: frameIndex,
                reducedMotion: state.reducedMotion
            )
        )
        let scale = renderBounds.width
        let center = CGPoint(x: renderBounds.midX, y: renderBounds.midY)
        let progressRadius = scale * (illustrated ? 0.48 : 0.415)

        context.beginPath()
        context.saveGState()
        context.clip(to: renderBounds)
        context.setLineCap(.round)

        if surface.showsTimerProgress {
            switch TepalDockProgressPresentation.make(for: state) {
            case .halo:
                drawHalo(
                    in: context,
                    center: center,
                    radius: scale * 0.38,
                    color: palette.glow.cgColor
                )
            case let .activeTimer(progress):
                drawProgressTrack(
                    in: context,
                    center: center,
                    radius: progressRadius,
                    lineWidth: scale * 0.035,
                    color: palette.habitatAccent.cgColor
                )
                drawProgressArc(
                    progress: progress,
                    in: context,
                    center: center,
                    radius: progressRadius,
                    lineWidth: scale * 0.035,
                    color: palette.primaryAction.cgColor
                )
            }
        }

        if illustrated {
            let imageRatio = CGFloat(TepalIconArtwork.image.width) / CGFloat(TepalIconArtwork.image.height)
            let fps = TepalDockMotion.framesPerSecond(for: state)
            let time = fps > 0 ? Double(frameIndex % 7200) / fps : 0
            let breath = fps > 0 ? sin(time * .pi / 2.4) : 0
            let resting = state.pose == .resting
            let height = renderBounds.height * (resting ? 0.78 : 0.94) * (1 + breath * 0.018)
            let width = renderBounds.height * 0.94 * imageRatio * (resting ? 1.2 : 1.1) * (1 - breath * 0.012)
            let artworkBounds = CGRect(x: renderBounds.midX - width / 2,
                y: renderBounds.minY + renderBounds.height * 0.025, width: width, height: height)
            if fps > 0 && (state.pose == .ready || state.pose == .pausedCurious || state.pose == .walking) {
                let angle = sin(time * .pi / 5) * 0.025
                context.translateBy(x: artworkBounds.midX, y: artworkBounds.minY)
                context.rotate(by: angle)
                context.translateBy(x: -artworkBounds.midX, y: -artworkBounds.minY)
            }
            context.interpolationQuality = .high
            let image = TepalIconArtwork.image
            context.draw(image, in: artworkBounds)
            if state.palette != .moonFern {
                context.saveGState()
                context.clip(to: artworkBounds, mask: image)
                context.setBlendMode(.multiply)
                context.setFillColor(palette.bodyTop.cgColor)
                context.fill(artworkBounds)
                context.restoreGState()
            }
        } else {
        fillBodyGradient(paths.body, palette: palette, in: context)
        drawLowerRightBodyShade(paths.body, in: context, color: palette.bodyShade)
        fill(paths.leftLeaf, color: palette.leaf.cgColor, in: context)
        fill(paths.rightLeaf, color: palette.leaf.cgColor, in: context)
        for mark in paths.growthMarks {
            fill(mark, color: palette.pollen.cgColor, in: context)
        }
        fill(paths.leftEye, color: palette.eye.cgColor, in: context)
        fill(paths.rightEye, color: palette.eye.cgColor, in: context)
        }

        context.restoreGState()
        context.beginPath()
        if let callerPath {
            context.addPath(callerPath)
        }
    }

    // Temporary compatibility overload: Dock and excursion callers migrate to explicit surfaces in Tasks 5–6.
    public static func draw(
        state: TepalVisualState,
        frameIndex: Int,
        signatureMotionProgress: Double = 1,
        in context: CGContext,
        bounds: CGRect
    ) {
        draw(
            state: state,
            surface: .dock,
            frameIndex: frameIndex,
            signatureMotionProgress: signatureMotionProgress,
            in: context,
            bounds: bounds
        )
    }

    private static func aspectFitSquare(in bounds: CGRect) -> CGRect {
        let side = min(bounds.width, bounds.height)
        return CGRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
    }

    private static func animatedBounds(
        for state: TepalVisualState,
        frameIndex: Int,
        signatureMotionProgress: Double,
        bounds: CGRect
    ) -> CGRect {
        guard !state.reducedMotion else { return bounds }
        let phase = ((frameIndex % 4) + 4) % 4
        let offsets: [CGFloat] = [0, 1, 0, -1]
        let signatureLift: CGFloat = state.pose == .preparingFocus
            ? bounds.height * 0.018 * CGFloat(1 - signatureMotionProgress)
            : 0
        let vertical = state.pose == .walking
            ? offsets[phase] * bounds.height * 0.008 + signatureLift
            : signatureLift
        let horizontal = state.pose == .walking ? offsets[(phase + 1) % 4] * bounds.width * 0.008 : 0
        return bounds.offsetBy(dx: horizontal, dy: vertical)
    }

    private static func drawProgressTrack(
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        color: CGColor
    ) {
        context.beginPath()
        context.setStrokeColor(color.copy(alpha: 0.72) ?? color)
        context.setLineWidth(lineWidth)
        context.addEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        context.strokePath()
    }

    private static func drawHalo(
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        color: CGColor
    ) {
        guard let innerGlow = color.copy(alpha: 0.16),
              let outerGlow = color.copy(alpha: 0)
        else { return }
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [innerGlow, outerGlow] as CFArray,
            locations: [0, 1]
        ) else { return }

        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: radius * 0.42,
            endCenter: center,
            endRadius: radius,
            options: []
        )
    }

    private static func drawProgressArc(
        progress: Double,
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        color: CGColor
    ) {
        context.beginPath()
        let boundedProgress = min(1, max(0, progress))
        guard boundedProgress > 0 else { return }
        let start = CGFloat.pi / 2
        let end = start - CGFloat(boundedProgress) * 2 * .pi
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.addArc(
            center: center,
            radius: radius,
            startAngle: start,
            endAngle: end,
            clockwise: true
        )
        context.strokePath()
    }

    private static func fillBodyGradient(
        _ body: CGPath,
        palette: TepalPalette,
        in context: CGContext,
    ) {
        let bounds = body.boundingBoxOfPath
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [palette.bodyTop.cgColor, palette.bodyBottom.cgColor] as CFArray,
            locations: [0, 1]
        ) else { return }

        context.saveGState()
        context.beginPath()
        context.addPath(body)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.midX, y: bounds.maxY),
            end: CGPoint(x: bounds.midX, y: bounds.minY),
            options: []
        )
        context.restoreGState()
    }

    private static func drawLowerRightBodyShade(
        _ body: CGPath,
        in context: CGContext,
        color: NSColor
    ) {
        let bounds = body.boundingBoxOfPath
        context.saveGState()
        context.beginPath()
        context.addPath(body)
        context.clip()
        context.setFillColor(color.withAlphaComponent(0.30).cgColor)
        context.fillEllipse(in: CGRect(
            x: bounds.midX - bounds.width * 0.06,
            y: bounds.minY - bounds.height * 0.12,
            width: bounds.width * 0.72,
            height: bounds.height * 0.68
        ))
        context.restoreGState()
    }

    private static func fill(_ path: CGPath, color: CGColor, in context: CGContext) {
        context.setFillColor(color)
        context.beginPath()
        context.addPath(path)
        context.fillPath()
    }
}
