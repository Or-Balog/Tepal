import CoreGraphics

public enum DockEdge: Equatable, Sendable {
    case bottom
    case left
    case right
    case unknown
}

public struct ScreenGeometry: Equatable, Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public struct DockGeometry: Equatable, Sendable {
    public let edge: DockEdge
    public let homePoint: CGPoint
    public let usedPointer: Bool

    public init(edge: DockEdge, homePoint: CGPoint, usedPointer: Bool) {
        self.edge = edge
        self.homePoint = homePoint
        self.usedPointer = usedPointer
    }
}

public enum DockHomeLocator {
    public static func locate(pointer: CGPoint?, screens: [ScreenGeometry]) -> DockGeometry {
        guard let screen = screen(containing: pointer, from: screens) else {
            return DockGeometry(edge: .unknown, homePoint: .zero, usedPointer: false)
        }

        let edge = dockEdge(for: screen)
        if let pointer {
            let clampedPointer = clamp(pointer, to: screen.frame)
            if isNearDockEdge(clampedPointer, edge: edge, frame: screen.frame) {
                return DockGeometry(edge: edge, homePoint: clampedPointer, usedPointer: true)
            }
        }

        return DockGeometry(edge: edge, homePoint: fallbackPoint(for: edge, in: screen.frame), usedPointer: false)
    }

    private static func screen(containing pointer: CGPoint?, from screens: [ScreenGeometry]) -> ScreenGeometry? {
        if let pointer, let pointerScreen = screens.first(where: { $0.frame.contains(pointer) }) {
            return pointerScreen
        }
        return screens.first
    }

    private static func dockEdge(for screen: ScreenGeometry) -> DockEdge {
        let bottomInset = max(0, screen.visibleFrame.minY - screen.frame.minY)
        let leftInset = max(0, screen.visibleFrame.minX - screen.frame.minX)
        let rightInset = max(0, screen.frame.maxX - screen.visibleFrame.maxX)

        let largestInset = max(bottomInset, leftInset, rightInset)
        guard largestInset > 0 else { return .unknown }
        if bottomInset == largestInset { return .bottom }
        if leftInset == largestInset { return .left }
        return .right
    }

    private static func clamp(_ point: CGPoint, to frame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, frame.minX), frame.maxX),
            y: min(max(point.y, frame.minY), frame.maxY)
        )
    }

    private static func isNearDockEdge(_ point: CGPoint, edge: DockEdge, frame: CGRect) -> Bool {
        switch edge {
        case .bottom:
            point.y - frame.minY <= 120
        case .left:
            point.x - frame.minX <= 120
        case .right:
            frame.maxX - point.x <= 120
        case .unknown:
            false
        }
    }

    private static func fallbackPoint(for edge: DockEdge, in frame: CGRect) -> CGPoint {
        switch edge {
        case .bottom:
            CGPoint(x: frame.midX, y: frame.minY + 12)
        case .left:
            CGPoint(x: frame.minX + 12, y: frame.midY)
        case .right:
            CGPoint(x: frame.maxX - 12, y: frame.midY)
        case .unknown:
            CGPoint(x: frame.midX, y: frame.midY)
        }
    }
}
