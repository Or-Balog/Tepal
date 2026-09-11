import Foundation
import Testing
@testable import TepalCore
@testable import TepalMac

struct SettingsStoreTests {
    @Test func reducedMotionPreferenceNeverOverridesTheSystemTowardMoreMotion() {
        // Break caught: the explicit preference re-enables hop translation while macOS Reduce Motion is enabled.
        #expect(ReducedMotionPreference.followSystem.resolved(systemSetting: false) == false)
        #expect(ReducedMotionPreference.followSystem.resolved(systemSetting: true))
        #expect(ReducedMotionPreference.reduceMotion.resolved(systemSetting: false))
        #expect(ReducedMotionPreference.reduceMotion.resolved(systemSetting: true))
    }

    @Test func emptyDefaultsUseTheDocumentedApplicationSettings() {
        // Break caught: first launch reads zeroed or stale preferences instead of the product defaults.
        withDefaults { defaults in
            let store = SettingsStore(userDefaults: defaults)

            #expect(store.settings == .defaults)
            #expect(store.loadRecovery() == nil)
            #expect(store.loadReminderState() == ReminderState())
        }
    }

    @Test func settingsRoundTripThroughASecondStore() {
        // Break caught: changing a preference updates memory but is missing after relaunch.
        withDefaults { defaults in
            var expected = AppSettings.defaults
            expected.focusDuration = 1_800
            expected.shortBreakDuration = 420
            expected.longBreakDuration = 1_200
            expected.longBreakEvery = 3
            expected.autoStartNextPhase = true
            expected.reminderLead = 900
            expected.soundEnabled = true
            expected.ambientExcursionsEnabled = false
            expected.minimumAmbientInterval = 2_400

            let writer = SettingsStore(userDefaults: defaults)
            writer.settings = expected

            let reader = SettingsStore(userDefaults: defaults)
            #expect(reader.settings == expected)
        }
    }

    @Test func tepalPaletteRoundTripsThroughASecondStore() {
        withDefaults { defaults in
            var expected = AppSettings.defaults
            expected.tepalPalette = .twilightPlum

            let writer = SettingsStore(userDefaults: defaults)
            writer.settings = expected

            let reader = SettingsStore(userDefaults: defaults)
            #expect(reader.settings.tepalPalette == .twilightPlum)
        }
    }

    @Test func preRenamePaletteAndPreferencesRemainReadable() {
        withDefaults { defaults in
            let json = #"{"version":1,"value":{"focusDuration":2100,"moonmossPalette":"twilightPlum","doubleKnockEnabled":true,"onboardingCompleted":true}}"#
            defaults.set(Data(json.utf8), forKey: "dockpet.v1.settings")
            let settings = SettingsStore(userDefaults: defaults).settings
            #expect(settings.tepalPalette == .twilightPlum)
            #expect(settings.focusDuration == 2100)
            #expect(settings.doubleKnockEnabled)
            #expect(settings.onboardingCompleted)
        }
    }

    @Test func unknownTepalPaletteFallsBackWithoutDiscardingOtherSettings() {
        withDefaults { defaults in
            let json = #"{"version":1,"value":{"focusDuration":1800,"moonmossPalette":"unknown-future-palette"}}"#
            defaults.set(Data(json.utf8), forKey: "dockpet.v1.settings")

            let settings = SettingsStore(userDefaults: defaults).settings

            #expect(settings.tepalPalette == .moonFern)
            #expect(settings.focusDuration == 1_800)
        }
    }

    @Test func interfacePreferencesRoundTripWithoutCalendarContent() throws {
        // Break caught: onboarding, pet, accessibility, or selected Google identifiers disappear after relaunch.
        try withDefaults { defaults in
            var expected = AppSettings.defaults
            expected.enabledCalendarIDs = ["google-work", "google-personal"]
            expected.confirmedGoogleSourceIDs = ["google-source"]
            expected.petName = "Pip"
            expected.reducedMotionPreference = .reduceMotion
            expected.launchAtLoginEnabled = true
            expected.onboardingCompleted = true

            let writer = SettingsStore(userDefaults: defaults)
            writer.settings = expected
            let reader = SettingsStore(userDefaults: defaults)

            #expect(reader.settings == expected)
            let storedData = try #require(defaults.data(forKey: "dockpet.v1.settings"))
            let storedText = try #require(String(data: storedData, encoding: .utf8))
            #expect(!storedText.contains("eventTitle"))
            #expect(!storedText.contains("calendarTitle"))
        }
    }

    @Test func legacySettingsDecodeWithSafeInterfaceDefaults() throws {
        // Break caught: adding Task 7 fields makes every valid pre-UI settings record decode as corrupt and get deleted.
        try withDefaults { defaults in
            var legacy = LegacyAppSettings.fixture
            legacy.focusDuration = 1_800
            legacy.soundEnabled = true
            defaults.set(
                try JSONEncoder().encode(FixtureVersionedRecord(version: 1, value: legacy)),
                forKey: "dockpet.v1.settings"
            )

            let settings = SettingsStore(userDefaults: defaults).settings

            #expect(settings.focusDuration == 1_800)
            #expect(settings.soundEnabled)
            #expect(settings.enabledCalendarIDs.isEmpty)
            #expect(settings.confirmedGoogleSourceIDs.isEmpty)
            #expect(settings.petName.isEmpty)
            #expect(settings.reducedMotionPreference == .followSystem)
            #expect(!settings.launchAtLoginEnabled)
            #expect(!settings.onboardingCompleted)
            #expect(defaults.data(forKey: "dockpet.v1.settings") != nil)
        }
    }

    @Test func interfaceIdentifiersAndPetNameAreNormalizedBeforePersistence() {
        // Break caught: blank identifiers or unbounded whitespace-only names become durable selection/UI state.
        withDefaults { defaults in
            var invalid = AppSettings.defaults
            invalid.enabledCalendarIDs = ["", "  ", " work "]
            invalid.confirmedGoogleSourceIDs = [" source ", "\n"]
            invalid.petName = "  Pip  "

            let store = SettingsStore(userDefaults: defaults)
            store.settings = invalid

            #expect(store.settings.enabledCalendarIDs == ["work"])
            #expect(store.settings.confirmedGoogleSourceIDs == ["source"])
            #expect(store.settings.petName == "Pip")
        }
    }

    @Test func legacyAutoClassifiedSourcesDoNotBecomeGoogleConfirmations() {
        // Break caught: a source accepted by the old title heuristic remains trusted after upgrade without the user's confirmation.
        withDefaults { defaults in
            let legacyJSON = """
            {"version":1,"value":{"enabledCalendarIDs":["work"],"enabledCalendarSourceIDs":["misleading-source"]}}
            """
            defaults.set(Data(legacyJSON.utf8), forKey: "dockpet.v1.settings")

            let settings = SettingsStore(userDefaults: defaults).settings

            #expect(settings.confirmedGoogleSourceIDs.isEmpty)
            #expect(settings.enabledCalendarIDs.isEmpty)
        }
    }

    @Test func decodedSettingsAreClampedBeforeTheyReachTheTimerEngine() throws {
        // Break caught: malformed persisted durations or a zero cadence can crash or destabilize the timer engine.
        try withDefaults { defaults in
            var persisted = AppSettings.defaults
            persisted.focusDuration = 0
            persisted.shortBreakDuration = 59
            persisted.longBreakDuration = 7_201
            persisted.longBreakEvery = 0
            persisted.reminderLead = 3_601
            persisted.minimumAmbientInterval = 1
            let record = FixtureVersionedRecord(version: 1, value: persisted)
            defaults.set(try JSONEncoder().encode(record), forKey: "dockpet.v1.settings")

            let settings = SettingsStore(userDefaults: defaults).settings

            #expect(settings.focusDuration == 60)
            #expect(settings.shortBreakDuration == 60)
            #expect(settings.longBreakDuration == 7_200)
            #expect(settings.longBreakEvery == 1)
            #expect(settings.reminderLead == 3_600)
            #expect(settings.minimumAmbientInterval == 1_800)
        }
    }

    @Test func assignedSettingsAreClampedBeforeSaving() {
        // Break caught: invalid values are normalized only after relaunch and can reach a live engine immediately.
        withDefaults { defaults in
            var invalid = AppSettings.defaults
            invalid.focusDuration = 10_000
            invalid.shortBreakDuration = -1
            invalid.longBreakDuration = 0
            invalid.longBreakEvery = -4
            invalid.reminderLead = 0
            invalid.minimumAmbientInterval = 600

            let writer = SettingsStore(userDefaults: defaults)
            writer.settings = invalid
            let saved = SettingsStore(userDefaults: defaults).settings

            #expect(writer.settings.focusDuration == 7_200)
            #expect(writer.settings.shortBreakDuration == 60)
            #expect(writer.settings.longBreakDuration == 60)
            #expect(writer.settings.longBreakEvery == 1)
            #expect(writer.settings.reminderLead == 60)
            #expect(writer.settings.minimumAmbientInterval == 1_800)
            #expect(saved == writer.settings)
        }
    }

    @Test func finiteAmbientIntervalAboveOneWeekRoundTripsUnchanged() {
        // Break caught: normalization adds an undocumented upper bound to an otherwise valid ambient interval.
        withDefaults { defaults in
            var expected = AppSettings.defaults
            expected.minimumAmbientInterval = 700_000

            let writer = SettingsStore(userDefaults: defaults)
            writer.settings = expected
            let persisted = SettingsStore(userDefaults: defaults).settings

            #expect(writer.settings.minimumAmbientInterval == 700_000)
            #expect(persisted.minimumAmbientInterval == 700_000)
        }
    }

    @Test func changingSettingsPublishesOnlyTheSettingsStoreChangeSignal() {
        // Break caught: the coordinator cannot refresh calendar and ambient schedules when persisted settings change.
        withDefaults { defaults in
            let store = SettingsStore(userDefaults: defaults)
            let capture = NotificationCapture()
            let token = NotificationCenter.default.addObserver(
                forName: SettingsStore.settingsDidChangeNotification,
                object: store,
                queue: nil
            ) { notification in
                capture.record(notification)
            }
            defer { NotificationCenter.default.removeObserver(token) }

            var changed = AppSettings.defaults
            changed.calendarRefreshInterval = 1_200
            store.settings = changed
            store.saveRecovery(nil)

            #expect(capture.count == 1)
            #expect(capture.lastObject === store)
        }
    }

    @Test func nonfiniteDurationFieldsNormalizeWithoutErasingThePreviousRecord() {
        // Break caught: JSON encoding failure publishes invalid memory state and deletes the last valid settings record.
        withDefaults { defaults in
            let store = SettingsStore(userDefaults: defaults)
            var previous = AppSettings.defaults
            previous.soundEnabled = true
            store.settings = previous
            #expect(defaults.data(forKey: "dockpet.v1.settings") != nil)

            var nonfinite = AppSettings.defaults
            nonfinite.focusDuration = .infinity
            nonfinite.shortBreakDuration = -.infinity
            nonfinite.longBreakDuration = .nan
            nonfinite.reminderLead = .infinity
            nonfinite.snoozeDuration = .infinity
            nonfinite.calendarLookahead = .nan
            nonfinite.calendarRefreshInterval = -.infinity
            nonfinite.minimumAmbientInterval = .infinity
            store.settings = nonfinite

            let persisted = SettingsStore(userDefaults: defaults).settings
            #expect(store.settings == .defaults)
            #expect(persisted == .defaults)
            #expect(defaults.data(forKey: "dockpet.v1.settings") != nil)
            #expect([
                persisted.focusDuration,
                persisted.shortBreakDuration,
                persisted.longBreakDuration,
                persisted.reminderLead,
                persisted.snoozeDuration,
                persisted.calendarLookahead,
                persisted.calendarRefreshInterval,
                persisted.minimumAmbientInterval,
            ].allSatisfy { $0.isFinite })
        }
    }

    @Test func validPomodoroRecoveryRoundTripsExactly() {
        // Break caught: relaunch discards a valid paused timer or changes its remaining time.
        withDefaults { defaults in
            let expected = PomodoroSnapshot(
                phase: .shortBreak,
                remaining: .seconds(240),
                targetEnd: nil,
                completedFocusCount: 2,
                isPaused: true
            )
            let writer = SettingsStore(userDefaults: defaults)
            writer.saveRecovery(expected)

            let reader = SettingsStore(userDefaults: defaults)
            #expect(reader.loadRecovery() == expected)
        }
    }

    @Test func corruptRecoveryIsRemovedWithoutDeletingValidSettings() {
        // Break caught: one damaged recovery blob either survives repeated launches or wipes unrelated preferences.
        withDefaults { defaults in
            var expectedSettings = AppSettings.defaults
            expectedSettings.soundEnabled = true
            let writer = SettingsStore(userDefaults: defaults)
            writer.settings = expectedSettings
            defaults.set(Data("not-json".utf8), forKey: "dockpet.v1.recovery")

            let reader = SettingsStore(userDefaults: defaults)

            #expect(reader.loadRecovery() == nil)
            #expect(defaults.object(forKey: "dockpet.v1.recovery") == nil)
            #expect(reader.settings == expectedSettings)
            #expect(defaults.object(forKey: "dockpet.v1.settings") != nil)
        }
    }

    @Test func reminderStateRoundTripsWithoutEventContent() throws {
        // Break caught: reminder deduplication is lost on relaunch or persistence expands into calendar-content storage.
        try withDefaults { defaults in
            let key = ReminderOccurrenceKey(
                eventID: "opaque-occurrence-42",
                start: Date(timeIntervalSinceReferenceDate: 20_000)
            )
            let expected = ReminderState(
                shown: [key],
                snoozedUntil: [key: Date(timeIntervalSinceReferenceDate: 20_300)],
                snoozeUsed: [key]
            )
            let writer = SettingsStore(userDefaults: defaults)
            writer.saveReminderState(expected)

            let reader = SettingsStore(userDefaults: defaults)
            #expect(reader.loadReminderState() == expected)

            let storedData = try #require(defaults.data(forKey: "dockpet.v1.reminderState"))
            let storedText = try #require(String(data: storedData, encoding: .utf8))
            #expect(!storedText.contains("eventTitle"))
            #expect(!storedText.contains("calendarTitle"))
            #expect(!storedText.contains("CalendarEventSummary"))
        }
    }

    @Test func clearAllRemovesOnlyTepalRecordsAndRestoresDefaults() {
        // Break caught: privacy clearing leaves local app records behind or removes another defaults owner's value.
        withDefaults { defaults in
            let store = SettingsStore(userDefaults: defaults)
            var custom = AppSettings.defaults
            custom.soundEnabled = true
            custom.tepalPalette = .twilightPlum
            store.settings = custom
            store.saveRecovery(PomodoroSnapshot(
                phase: .focus,
                remaining: .seconds(1_000),
                targetEnd: Date(timeIntervalSinceReferenceDate: 50_000),
                completedFocusCount: 3,
                isPaused: false
            ))
            store.saveReminderState(ReminderState(shown: [
                ReminderOccurrenceKey(
                    eventID: "opaque-occurrence-7",
                    start: Date(timeIntervalSinceReferenceDate: 40_000)
                )
            ]))
            defaults.set("keep-me", forKey: "unrelated.owner.value")

            store.clearAll()

            #expect(store.settings == .defaults)
            #expect(store.settings.tepalPalette == .moonFern)
            #expect(store.loadRecovery() == nil)
            #expect(store.loadReminderState() == ReminderState())
            #expect(defaults.object(forKey: "dockpet.v1.settings") == nil)
            #expect(defaults.object(forKey: "dockpet.v1.recovery") == nil)
            #expect(defaults.object(forKey: "dockpet.v1.reminderState") == nil)
            #expect(defaults.string(forKey: "unrelated.owner.value") == "keep-me")
        }
    }
}

private final class NotificationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var notifications: [Notification] = []

    var count: Int {
        lock.withLock { notifications.count }
    }

    var lastObject: AnyObject? {
        lock.withLock { notifications.last?.object as AnyObject? }
    }

    func record(_ notification: Notification) {
        lock.withLock { notifications.append(notification) }
    }
}

private struct FixtureVersionedRecord<Value: Codable>: Codable {
    let version: Int
    let value: Value
}

private struct LegacyAppSettings: Codable {
    var focusDuration: TimeInterval
    var shortBreakDuration: TimeInterval
    var longBreakDuration: TimeInterval
    var longBreakEvery: Int
    var autoStartNextPhase: Bool
    var reminderLead: TimeInterval
    var snoozeDuration: TimeInterval
    var calendarLookahead: TimeInterval
    var calendarRefreshInterval: TimeInterval
    var soundEnabled: Bool
    var ambientExcursionsEnabled: Bool
    var meetingAlertsEnabled: Bool
    var minimumAmbientInterval: TimeInterval

    static let fixture = LegacyAppSettings(
        focusDuration: 1_500,
        shortBreakDuration: 300,
        longBreakDuration: 900,
        longBreakEvery: 4,
        autoStartNextPhase: false,
        reminderLead: 600,
        snoozeDuration: 300,
        calendarLookahead: 172_800,
        calendarRefreshInterval: 900,
        soundEnabled: false,
        ambientExcursionsEnabled: true,
        meetingAlertsEnabled: true,
        minimumAmbientInterval: 1_800
    )
}

private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "Tepal.SettingsStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}
