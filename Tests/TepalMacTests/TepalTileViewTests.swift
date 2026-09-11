import AppKit
import TepalCore
import Testing
@testable import TepalMac

@MainActor
struct TepalTileViewTests {
    @Test func dockTileUsesTheExplicitDockSurface() {
        // Break caught: the Dock view falls back to a renderer default and can silently lose its progress arc.
        let tile = TepalTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))

        tile.render(TepalPresentationPolicy.make(
            petState: .focus,
            isTimerPaused: false,
            timerProgress: 0.5,
            palette: .moonFern,
            completedFocuses: 0,
            reducedMotion: true
        ))

        #expect(tile.renderedSurface == .dock)
    }

    @Test func viewOnlyTileCanUseTheExcursionSurfaceWithoutChangingDockDefaults() {
        // Break caught: an excursion must duplicate the Dock tile renderer to remove timer progress from its character.
        let tile = TepalTileView(
            frame: NSRect(x: 0, y: 0, width: 96, height: 96),
            displayDestination: .viewOnly,
            renderSurface: .excursion
        )

        #expect(tile.renderedSurface == .excursion)
    }

    @Test func renderingTepalStateRetainsTheSuppliedVisualStateAndRespectsReducedMotion() {
        // Break caught: the Dock tile discards Tepal palette/growth data or schedules animation despite Reduced Motion.
        let tile = TepalTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        let visual = TepalPresentationPolicy.make(
            petState: .focus,
            isTimerPaused: false,
            timerProgress: 0.25,
            palette: .frostBloom,
            completedFocuses: 25,
            reducedMotion: true
        )

        tile.render(visual)

        #expect(tile.renderedVisualState == visual)
        #expect(!tile.isAnimating)
    }

    @Test func keepingWatchInstallsAGentleBreathingTimer() {
        // Break caught: focus animation no longer follows the shared Tepal motion policy.
        let tile = TepalTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        let visual = TepalPresentationPolicy.make(
            petState: .focus,
            isTimerPaused: false,
            timerProgress: 0.25,
            palette: .moonFern,
            completedFocuses: 0,
            reducedMotion: false
        )

        tile.render(visual)

        #expect(tile.renderedVisualState.pose == .keepingWatch)
        #expect(tile.isAnimating)
        #expect(tile.animationInterval == 1.0 / 6.0)
    }

    @Test func meetingPoseRemainsStatic() {
        // Break caught: the semantically static meeting pose keeps a Dock animation timer alive.
        let tile = TepalTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        let visual = TepalPresentationPolicy.make(
            petState: .meetingAlert,
            isTimerPaused: false,
            timerProgress: 0,
            palette: .moonFern,
            completedFocuses: 0,
            reducedMotion: false
        )

        tile.render(visual)

        #expect(tile.renderedVisualState.pose == .meetingAttentive)
        #expect(!tile.isAnimating)
    }

    @Test func semanticRenderingTakesOwnershipAndRejectsLegacyProbeRedraws() {
        // Break caught: the legacy Dock probe remains a redraw owner after semantic rendering begins.
        let tile = TepalTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))

        #expect(tile.animationOwner == .legacyProbe)

        tile.render(TepalPresentationPolicy.make(
            petState: .meetingAlert,
            isTimerPaused: false,
            timerProgress: 0.5,
            palette: .moonFern,
            completedFocuses: 0,
            reducedMotion: false
        ))

        #expect(tile.animationOwner == .semanticRenderer)
        #expect(!tile.acceptsLegacyProbeRedraws)
    }

    @Test func viewOnlyRendererUsesItsExplicitSurfaceWithoutRequestingAnApplicationDockRedraw() {
        // Break caught: a test-injected view-only renderer silently falls back to Dock surface treatment or wakes the application's Dock tile.
        var dockDisplayRequests = 0
        let tile = TepalTileView(
            frame: NSRect(x: 0, y: 0, width: 96, height: 96),
            displayDestination: .viewOnly,
            renderSurface: .excursion,
            requestDockDisplay: { dockDisplayRequests += 1 }
        )

        tile.render(TepalPresentationPolicy.make(
            petState: .excursion,
            isTimerPaused: false,
            timerProgress: 0,
            palette: .moonFern,
            completedFocuses: 0,
            reducedMotion: true
        ))

        #expect(tile.renderedSurface == .excursion)
        #expect(dockDisplayRequests == 0)
    }

    @Test func applicationDockRendererOwnsDockDisplayRequests() {
        // Break caught: separating excursion rendering also disconnects the real Dock renderer from NSDockTile display.
        var dockDisplayRequests = 0
        let tile = TepalTileView(
            frame: NSRect(x: 0, y: 0, width: 128, height: 128),
            displayDestination: .applicationDockTile,
            renderSurface: .dock,
            requestDockDisplay: { dockDisplayRequests += 1 }
        )

        tile.render(TepalPresentationPolicy.make(
            petState: .focus,
            isTimerPaused: false,
            timerProgress: 0.25,
            palette: .moonFern,
            completedFocuses: 0,
            reducedMotion: true
        ))

        #expect(dockDisplayRequests == 1)
    }

    @Test func stopAnimationInvalidatesAnActiveSemanticTimer() {
        // Break caught: app termination leaves the Dock animation timer running after lifecycle cleanup.
        let tile = TepalTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        tile.render(TepalPresentationPolicy.make(
            petState: .idle,
            isTimerPaused: false,
            timerProgress: 0,
            palette: .moonFern,
            completedFocuses: 0,
            reducedMotion: false
        ))
        #expect(tile.isAnimating)

        tile.stopAnimation()

        #expect(!tile.isAnimating)
    }

    @Test func rendererInstallationUsesAStaticProgrammaticFallback() {
        // Break caught: failure to initialize the semantic pixel renderer leaves the Dock tile blank or aborts app startup.
        let installation = DockTileRendererInstallation(
            frame: NSRect(x: 0, y: 0, width: 128, height: 128),
            makeSemanticRenderer: { _ in nil }
        )

        #expect(installation.semanticRenderer == nil)
        #expect(installation.contentView is StaticTepalIconView)
    }

    @Test func productionRendererValidationFallsBackForAnUnusableRenderFrame() {
        // Break caught: the public production installation constructs an unusable semantic renderer unconditionally, so its fallback is unreachable.
        let installation = DockTileRendererInstallation(
            frame: NSRect(x: 0, y: 0, width: 0, height: 128)
        )

        #expect(installation.semanticRenderer == nil)
        #expect(installation.contentView is StaticTepalIconView)
    }
}
