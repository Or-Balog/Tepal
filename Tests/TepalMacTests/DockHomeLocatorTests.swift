import CoreGraphics
import Testing
@testable import TepalMac

struct DockHomeLocatorTests {
    @Test func selectsBottomEdgeFromBottomVisibleFrameInset() {
        let geometry = DockHomeLocator.locate(pointer: nil, screens: [
            screen(frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                   visibleFrame: CGRect(x: 0, y: 74, width: 1_440, height: 826))
        ])

        #expect(geometry.edge == .bottom)
    }

    @Test func selectsLeftEdgeFromLeftVisibleFrameInset() {
        let geometry = DockHomeLocator.locate(pointer: nil, screens: [
            screen(frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                   visibleFrame: CGRect(x: 68, y: 0, width: 1_372, height: 900))
        ])

        #expect(geometry.edge == .left)
    }

    @Test func selectsRightEdgeFromRightVisibleFrameInset() {
        let geometry = DockHomeLocator.locate(pointer: nil, screens: [
            screen(frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                   visibleFrame: CGRect(x: 0, y: 0, width: 1_366, height: 900))
        ])

        #expect(geometry.edge == .right)
    }

    @Test func usesPointerWithin120PointsOfSelectedDockEdge() {
        let geometry = DockHomeLocator.locate(pointer: CGPoint(x: 420, y: 90), screens: [
            screen(frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                   visibleFrame: CGRect(x: 0, y: 74, width: 1_440, height: 826))
        ])

        #expect(geometry.homePoint == CGPoint(x: 420, y: 90))
        #expect(geometry.usedPointer)
    }

    @Test func usesCenterInsetFromDockEdgeWhenPointerIsDistant() {
        let geometry = DockHomeLocator.locate(pointer: CGPoint(x: 400, y: 300), screens: [
            screen(frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                   visibleFrame: CGRect(x: 0, y: 74, width: 1_440, height: 826))
        ])

        #expect(geometry.homePoint == CGPoint(x: 720, y: 12))
        #expect(!geometry.usedPointer)
    }

    @Test func returnsUnknownZeroGeometryWithoutScreens() {
        let geometry = DockHomeLocator.locate(pointer: CGPoint(x: 1, y: 1), screens: [])

        #expect(geometry.edge == .unknown)
        #expect(geometry.homePoint == .zero)
        #expect(!geometry.usedPointer)
    }

    private func screen(frame: CGRect, visibleFrame: CGRect) -> ScreenGeometry {
        ScreenGeometry(frame: frame, visibleFrame: visibleFrame)
    }
}
