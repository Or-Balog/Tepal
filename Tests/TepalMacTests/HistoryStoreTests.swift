import Foundation
import SwiftData
import Testing
@testable import TepalMac

@MainActor
struct HistoryStoreTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TEPAL_LEGACY_FIXTURE"] != nil))
    func legacyMigrationFixture() throws {
        guard let path = ProcessInfo.processInfo.environment["TEPAL_LEGACY_FIXTURE"] else { return }
        let store = try HistoryStore(storeURL: URL(fileURLWithPath: path))
        #expect(try store.completedFocusCount() == 1)
        #expect(try store.recentSessions(limit: 1).first?.duration == nil)
        #expect(try store.recentSessions(limit: 1).first?.endedAt == Date(timeIntervalSinceReferenceDate: 12345))
    }

    @Test func durationPersistsIndependentlyForEachSession() throws {
        // Break caught: durations disappear on reload or one setting is assigned to all sessions.
        let container = try makeContainer()
        let writer = HistoryStore(modelContainer: container)
        try writer.recordCompletedFocus(endedAt: Date(timeIntervalSinceReferenceDate: 1), duration: 1500)
        try writer.recordCompletedFocus(endedAt: Date(timeIntervalSinceReferenceDate: 2), duration: 3000)
        let reader = HistoryStore(modelContainer: container)
        #expect(try reader.recentSessions(limit: 10).map(\.duration) == [3000, 1500])
    }

    @Test func completedFocusSessionsPersistAcrossStoreInstances() throws {
        // Break caught: completion updates only an in-memory counter and disappears when the store is recreated.
        let container = try makeContainer()
        let writer = HistoryStore(modelContainer: container)
        try writer.recordCompletedFocus(endedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        try writer.recordCompletedFocus(endedAt: Date(timeIntervalSinceReferenceDate: 2_000))

        let reader = HistoryStore(modelContainer: container)

        #expect(try reader.completedFocusCount() == 2)
        #expect(try reader.recentSessions(limit: 10).map(\.endedAt) == [
            Date(timeIntervalSinceReferenceDate: 2_000),
            Date(timeIntervalSinceReferenceDate: 1_000),
        ])
    }

    @Test func historySnapshotCarriesSessionCountAndPersistedRewardIdentifiers() throws {
        // Break caught: the coordinator receives only a count and cannot recover growth from compatible reward records.
        let container = try makeContainer()
        let store = HistoryStore(modelContainer: container)
        for count in 1...4 {
            try store.recordCompletedFocus(
                endedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(count))
            )
        }

        let snapshot = try store.focusHistorySnapshot()

        #expect(snapshot.completedFocusCount == 4)
        #expect(snapshot.rewardIDs == [.glow, .sparkle])
    }

    @Test func rewardsUnlockOnceAtTheFourDocumentedMilestones() throws {
        // Break caught: rewards unlock at an off-by-one count, duplicate, or depend on nondeterministic state.
        let container = try makeContainer()
        let store = HistoryStore(modelContainer: container)
        var newlyUnlocked: [CosmeticReward] = []

        for count in 1...25 {
            newlyUnlocked += try store.recordCompletedFocus(
                endedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(count))
            ).map(\.reward)
        }

        #expect(newlyUnlocked == [.glow, .sparkle, .colorShift, .morph])
        #expect(try store.unlockedRewards().map(\.reward) == [
            .glow,
            .sparkle,
            .colorShift,
            .morph,
        ])

        _ = try store.recordCompletedFocus(endedAt: Date(timeIntervalSinceReferenceDate: 26))
        #expect(try store.unlockedRewards().map(\.reward) == [
            .glow,
            .sparkle,
            .colorShift,
            .morph,
        ])
    }

    @Test func recentSessionsAreNewestFirstAndHonorTheLimit() throws {
        // Break caught: history ordering follows insertion order or ignores the UI's bounded fetch limit.
        let container = try makeContainer()
        let store = HistoryStore(modelContainer: container)
        try store.recordCompletedFocus(endedAt: Date(timeIntervalSinceReferenceDate: 300))
        try store.recordCompletedFocus(endedAt: Date(timeIntervalSinceReferenceDate: 100))
        try store.recordCompletedFocus(endedAt: Date(timeIntervalSinceReferenceDate: 200))

        let sessions = try store.recentSessions(limit: 2)

        #expect(sessions.map(\.endedAt) == [
            Date(timeIntervalSinceReferenceDate: 300),
            Date(timeIntervalSinceReferenceDate: 200),
        ])
    }

    @Test func nonpositiveSessionLimitReturnsNoRows() throws {
        // Break caught: an invalid UI limit reaches SwiftData as an unsafe fetch limit or returns unbounded history.
        let container = try makeContainer()
        let store = HistoryStore(modelContainer: container)
        try store.recordCompletedFocus(endedAt: Date(timeIntervalSinceReferenceDate: 100))

        #expect(try store.recentSessions(limit: 0).isEmpty)
        #expect(try store.recentSessions(limit: -1).isEmpty)
    }

    @Test func failedAtomicSaveRollsBackSessionAndRewardBeforeRetry() throws {
        // Break caught: a failed reward save commits its session, so retry duplicates progress and shifts the unlock date.
        let container = try makeContainer()
        let failedDate = Date(timeIntervalSinceReferenceDate: 700)
        let retryDate = Date(timeIntervalSinceReferenceDate: 800)
        let failingStore = HistoryStore(modelContainer: container, saveContext: { _ in
            throw ForcedSaveFailure()
        })

        #expect(throws: ForcedSaveFailure.self) {
            try failingStore.recordCompletedFocus(endedAt: failedDate)
        }

        let store = HistoryStore(modelContainer: container)
        #expect(try store.completedFocusCount() == 0)
        #expect(try store.recentSessions(limit: 10).isEmpty)
        #expect(try store.unlockedRewards().isEmpty)

        let unlocked = try store.recordCompletedFocus(endedAt: retryDate)
        #expect(try store.completedFocusCount() == 1)
        #expect(try store.recentSessions(limit: 10).map(\.endedAt) == [retryDate])
        #expect(unlocked == [RewardSummary(reward: .glow, unlockedAt: retryDate)])
        #expect(try store.unlockedRewards() == unlocked)
    }

    @Test func clearAllDeletesSessionsAndRewardsFromPersistentStorage() throws {
        // Break caught: privacy clearing hides rows from one store while SwiftData records remain queryable.
        let container = try makeContainer()
        let writer = HistoryStore(modelContainer: container)
        for count in 1...4 {
            try writer.recordCompletedFocus(
                endedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(count))
            )
        }

        try writer.clearAll()
        let reader = HistoryStore(modelContainer: container)

        #expect(try reader.completedFocusCount() == 0)
        #expect(try reader.recentSessions(limit: 10).isEmpty)
        #expect(try reader.unlockedRewards().isEmpty)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<FocusSessionRecord>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<UnlockedRewardRecord>()) == 0)
    }

    @Test func controlledPersistentResetRecreatesHistoryWithoutDeletingSiblingFiles() throws {
        // Break caught: recovery either has no corruption escape hatch or deletes a broad Application Support path.
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("TepalHistoryReset-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        let storeURL = directory.appendingPathComponent("TepalHistory.store")
        let siblingURL = directory.appendingPathComponent("keep-me.txt")
        try Data("unrelated".utf8).write(to: siblingURL)
        defer {
            for url in HistoryStore.knownPersistentFileURLs(for: storeURL) {
                try? fileManager.removeItem(at: url)
            }
            try? fileManager.removeItem(at: siblingURL)
            try? fileManager.removeItem(at: directory)
        }

        var store: HistoryStore? = try HistoryStore(storeURL: storeURL)
        try store?.recordCompletedFocus(endedAt: Date(timeIntervalSinceReferenceDate: 5_000))
        #expect(try store?.completedFocusCount() == 1)
        store = nil

        for sidecar in HistoryStore.knownPersistentFileURLs(for: storeURL).dropFirst() {
            try Data("stale".utf8).write(to: sidecar)
        }

        let recovered = try HistoryStore.resetPersistentStore(at: storeURL)

        #expect(try recovered.completedFocusCount() == 0)
        #expect(try String(contentsOf: siblingURL, encoding: .utf8) == "unrelated")
    }
}

private struct ForcedSaveFailure: Error {}

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([FocusSessionRecord.self, UnlockedRewardRecord.self])
    let configuration = ModelConfiguration(
        "TepalHistoryTests-\(UUID().uuidString)",
        schema: schema,
        isStoredInMemoryOnly: true,
        groupContainer: .none,
        cloudKitDatabase: .none
    )
    return try ModelContainer(
        for: FocusSessionRecord.self,
        UnlockedRewardRecord.self,
        configurations: configuration
    )
}
