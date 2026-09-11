import TepalCore
import TepalMac
import SwiftUI

enum TepalSignatureMotion {
    static let focusPreparationDuration: TimeInterval = 0.650
    static let completionBloomDuration: TimeInterval = 1.400
    static let completionRiseDuration = completionBloomDuration * 0.6
    static let completionSettleDuration = completionBloomDuration * 0.4
}

enum TepalCanvasCadence {
    static func frameInterval(for state: TepalVisualState) -> TimeInterval? {
        let framesPerSecond = TepalMotionPolicy.framesPerSecond(
            for: state.pose,
            reducedMotion: state.reducedMotion
        )
        guard framesPerSecond > 0 else { return nil }
        return 1 / framesPerSecond
    }

    static func frameIndex(
        at timeIntervalSinceReferenceDate: TimeInterval,
        for state: TepalVisualState
    ) -> Int {
        guard let frameInterval = frameInterval(for: state) else { return 0 }
        return Int(floor(max(0, timeIntervalSinceReferenceDate) / frameInterval))
    }
}

struct TepalCanvasView: View {
    let state: TepalVisualState
    let surface: TepalRenderSurface

    init(state: TepalVisualState, surface: TepalRenderSurface = .habitat) {
        self.state = state
        self.surface = surface
    }

    var body: some View {
        Color.clear
            .keyframeAnimator(
                initialValue: TepalCanvasMotionValues.settled,
                trigger: TepalCanvasMotionTrigger(state: state)
            ) { _, motion in
                TepalCadencedDrawingCanvas(
                    state: motion.renderedState(from: state),
                    surface: surface,
                    signatureMotionProgress: motion.progress
                )
                .scaleEffect(CGFloat(motion.scale))
                .offset(y: CGFloat(motion.verticalOffset))
            } keyframes: { _ in
                KeyframeTrack(\.progress) {
                    if state.reducedMotion {
                        MoveKeyframe(1)
                    } else {
                        switch state.pose {
                        case .keepingWatch:
                            MoveKeyframe(0)
                            CubicKeyframe(1, duration: TepalSignatureMotion.focusPreparationDuration)
                        case .completionBloom:
                            MoveKeyframe(0)
                            CubicKeyframe(0.78, duration: TepalSignatureMotion.completionRiseDuration)
                            CubicKeyframe(1, duration: TepalSignatureMotion.completionSettleDuration)
                        default:
                            MoveKeyframe(1)
                        }
                    }
                }
                KeyframeTrack(\.scale) {
                    if state.reducedMotion {
                        MoveKeyframe(1)
                    } else {
                        switch state.pose {
                        case .keepingWatch:
                            MoveKeyframe(0.96)
                            CubicKeyframe(1, duration: TepalSignatureMotion.focusPreparationDuration)
                        case .completionBloom:
                            MoveKeyframe(0.94)
                            CubicKeyframe(1.07, duration: TepalSignatureMotion.completionRiseDuration)
                            CubicKeyframe(1, duration: TepalSignatureMotion.completionSettleDuration)
                        default:
                            MoveKeyframe(1)
                        }
                    }
                }
                KeyframeTrack(\.verticalOffset) {
                    if state.reducedMotion {
                        MoveKeyframe(0)
                    } else {
                        switch state.pose {
                        case .keepingWatch:
                            MoveKeyframe(3)
                            CubicKeyframe(0, duration: TepalSignatureMotion.focusPreparationDuration)
                        case .completionBloom:
                            MoveKeyframe(4)
                            CubicKeyframe(-2, duration: TepalSignatureMotion.completionRiseDuration)
                            CubicKeyframe(0, duration: TepalSignatureMotion.completionSettleDuration)
                        default:
                            MoveKeyframe(0)
                        }
                    }
                }
            }
        .accessibilityHidden(true)
    }
}

private struct TepalCadencedDrawingCanvas: View {
    let state: TepalVisualState
    let surface: TepalRenderSurface
    let signatureMotionProgress: Double

    @ViewBuilder
    var body: some View {
        if let interval = TepalCanvasCadence.frameInterval(for: state) {
            TimelineView(.periodic(from: .now, by: interval)) { timeline in
                TepalDrawingCanvas(
                    state: state,
                    surface: surface,
                    frameIndex: TepalCanvasCadence.frameIndex(
                        at: timeline.date.timeIntervalSinceReferenceDate,
                        for: state
                    ),
                    signatureMotionProgress: signatureMotionProgress
                )
            }
        } else {
            TepalDrawingCanvas(
                state: state,
                surface: surface,
                frameIndex: 0,
                signatureMotionProgress: signatureMotionProgress
            )
        }
    }
}

private struct TepalDrawingCanvas: View {
    let state: TepalVisualState
    let surface: TepalRenderSurface
    let frameIndex: Int
    let signatureMotionProgress: Double

    var body: some View {
        Canvas { context, size in
            context.withCGContext { graphics in
                graphics.saveGState()
                graphics.translateBy(x: 0, y: size.height)
                graphics.scaleBy(x: 1, y: -1)
                TepalVectorRenderer.draw(
                    state: state,
                    surface: surface,
                    illustrated: surface == .preview,
                    frameIndex: frameIndex,
                    signatureMotionProgress: signatureMotionProgress,
                    in: graphics,
                    bounds: CGRect(origin: .zero, size: size)
                )
                graphics.restoreGState()
            }
        }
    }
}

private struct TepalCanvasMotionTrigger: Equatable {
    let pose: TepalPose
    let reducedMotion: Bool

    init(state: TepalVisualState) {
        pose = state.pose
        reducedMotion = state.reducedMotion
    }
}

private struct TepalCanvasMotionValues {
    var progress: Double
    var scale: Double
    var verticalOffset: Double

    static let settled = TepalCanvasMotionValues(
        progress: 1,
        scale: 1,
        verticalOffset: 0
    )

    func renderedState(from state: TepalVisualState) -> TepalVisualState {
        guard !state.reducedMotion,
              state.pose == .keepingWatch,
              progress < 1
        else { return state }
        return state.replacingPose(.preparingFocus)
    }
}
