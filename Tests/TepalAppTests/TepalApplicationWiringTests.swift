import AppKit
import TepalCore
import Foundation
import Testing
@testable import TepalApp
import TepalMac

@MainActor
struct TepalApplicationWiringTests {
    @Test func appDelegateWiringKeepsTheStaticFallbackWhenSemanticConstructionFails() {
        // Break caught: the delegate bypasses the failable renderer factory, making production fallback unreachable during app launch.
        let wiring = TepalApplicationWiring(
            rendererFactory: DockTileSemanticRendererFactory { _ in nil }
        )

        let delegate = TepalApplicationDelegate(wiring: wiring)

        #expect(delegate.tileInstallation.semanticRenderer == nil)
        #expect(delegate.tileInstallation.contentView is StaticTepalIconView)
    }

    @Test func appDelegateWiringInjectsTheProductionCoordinatorSoundService() {
        // Break caught: production constructs a coordinator without the local AppKit sound service, leaving the Sound toggle inert.
        let soundPlayer = WiringSoundRecorder()
        let wiring = TepalApplicationWiring(
            soundPlayer: soundPlayer
        )

        let delegate = TepalApplicationDelegate(wiring: wiring)
        delegate.soundPlayer.play(.focusCompleted)

        #expect(soundPlayer.cues == [.focusCompleted])
    }

    @Test func delegateControlPanelCallbackHidesPanelThenForwardsExactDestination() {
        // Break caught: the callback actually installed by the delegate collapses History into Settings, bypasses its router, or routes before hiding the panel.
        var events: [SettingsCallbackEvent] = []
        let router = TepalApplicationCommandRouter(
            performPrimary: {},
            showSettings: { events.append(.routed($0)) }
        )
        let callback = TepalApplicationDelegate.makeControlPanelSettingsCallback(
            hideControlPanel: { events.append(.hidden) },
            commandRouter: router
        )

        callback(.preferences)
        callback(.history)

        #expect(events == [
            .hidden, .routed(.preferences),
            .hidden, .routed(.history),
        ])
    }

    @Test func dockSettingsCommandRoutesPreferencesAndNotHistory() {
        // Break caught: the Dock Settings command maps to History or loses its fixed Preferences destination.
        var destinations: [SettingsDestination] = []
        let router = TepalApplicationCommandRouter(
            performPrimary: {},
            showSettings: { destinations.append($0) }
        )

        router.perform(.showSettings)

        #expect(destinations == [.preferences])
    }

    @Test func wiredDockRendererReceivesTheExactCoordinatorVisualState() throws {
        // Break caught: application wiring gives the Dock a legacy seedling render instead of the coordinator's palette and growth state.
        let suiteName = "Tepal.TepalApplicationWiringTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = SettingsStore(userDefaults: defaults)
        var settings = AppSettings.defaults
        settings.tepalPalette = .emberMoss
        settingsStore.settings = settings
        let wiring = TepalApplicationWiring()
        let tile = try #require(wiring.makeTileInstallation(
            frame: NSRect(x: 0, y: 0, width: 128, height: 128)
        ).semanticRenderer)
        let coordinator = AppCoordinator(
            settingsStore: settingsStore,
            historyStore: WiringHistoryRecorder(completedFocuses: 12),
            tileView: tile,
            excursionController: ExcursionPanelController(),
            reducedMotion: { true },
            processArguments: []
        )
        defer { coordinator.terminate() }

        #expect(tile.renderedVisualState == coordinator.tepalVisualState)
        #expect(tile.renderedVisualState.palette == .emberMoss)
        #expect(tile.renderedVisualState.growth.completedFocuses == 12)
    }
}

private enum SettingsCallbackEvent: Equatable {
    case hidden
    case routed(SettingsDestination)
}

@MainActor
private final class WiringSoundRecorder: LocalSoundPlaying {
    private(set) var cues: [LocalSoundCue] = []

    func play(_ cue: LocalSoundCue) {
        cues.append(cue)
    }
}

@MainActor
private final class WiringHistoryRecorder: FocusHistoryRecording {
    private let completedFocuses: Int

    init(completedFocuses: Int) {
        self.completedFocuses = completedFocuses
    }

    func recordCompletedFocus(endedAt: Date, duration: TimeInterval?) throws -> [RewardSummary] {
        []
    }

    func focusHistorySnapshot() throws -> FocusHistorySnapshot {
        FocusHistorySnapshot(completedFocusCount: completedFocuses, rewardIDs: [])
    }
}
