import Foundation
import SwiftData

public struct FocusSessionSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let endedAt: Date
    public let duration: TimeInterval?

    public init(id: UUID, endedAt: Date, duration: TimeInterval? = nil) {
        self.id = id
        self.endedAt = endedAt
        self.duration = duration
    }
}

public enum CosmeticReward: String, CaseIterable, Codable, Hashable, Sendable {
    case glow
    case sparkle
    case colorShift
    case morph

    fileprivate var milestone: Int {
        switch self {
        case .glow: 1
        case .sparkle: 4
        case .colorShift: 12
        case .morph: 25
        }
    }
}

public struct RewardSummary: Identifiable, Equatable, Sendable {
    public var id: CosmeticReward { reward }
    public let reward: CosmeticReward
    public let unlockedAt: Date

    public init(reward: CosmeticReward, unlockedAt: Date) {
        self.reward = reward
        self.unlockedAt = unlockedAt
    }
}

public struct FocusHistorySnapshot: Equatable, Sendable {
    public let completedFocusCount: Int
    public let rewardIDs: Set<CosmeticReward>

    public init(completedFocusCount: Int, rewardIDs: Set<CosmeticReward>) {
        self.completedFocusCount = completedFocusCount
        self.rewardIDs = rewardIDs
    }
}

final class FocusSessionRecord: PersistentModel {
    private var backingData: any BackingData<FocusSessionRecord> = FocusSessionRecord.createBackingData()

    var persistentBackingData: any BackingData<FocusSessionRecord> {
        get { backingData }
        set { backingData = newValue }
    }

    static var schemaMetadata: [Schema.PropertyMetadata] {
        [
            .init(
                name: "recordID",
                keypath: \FocusSessionRecord.recordID,
                metadata: Schema.Attribute(.unique)
            ),
            .init(name: "endedAt", keypath: \FocusSessionRecord.endedAt),
            .init(name: "duration", keypath: \FocusSessionRecord.duration),
        ]
    }

    private var _recordID: UUID = UUID()
    var recordID: UUID {
        @storageRestrictions(initializes: _recordID)
        init(initialValue) { _recordID = initialValue }
        get { getValue(forKey: \FocusSessionRecord.recordID) }
        set { setValue(forKey: \FocusSessionRecord.recordID, to: newValue) }
    }

    private var _endedAt: Date = .distantPast
    var endedAt: Date {
        @storageRestrictions(initializes: _endedAt)
        init(initialValue) { _endedAt = initialValue }
        get { getValue(forKey: \FocusSessionRecord.endedAt) }
        set { setValue(forKey: \FocusSessionRecord.endedAt, to: newValue) }
    }

    private var _duration: TimeInterval? = nil
    var duration: TimeInterval? {
        @storageRestrictions(initializes: _duration)
        init(initialValue) { _duration = initialValue }
        get { getValue(forKey: \FocusSessionRecord.duration) }
        set { setValue(forKey: \FocusSessionRecord.duration, to: newValue) }
    }

    init(backingData: any BackingData<FocusSessionRecord>) {
        persistentBackingData = backingData
    }

    init(recordID: UUID = UUID(), endedAt: Date, duration: TimeInterval? = nil) {
        self.recordID = recordID
        self.endedAt = endedAt
        self.duration = duration
    }
}

final class UnlockedRewardRecord: PersistentModel {
    private var backingData: any BackingData<UnlockedRewardRecord> = UnlockedRewardRecord.createBackingData()

    var persistentBackingData: any BackingData<UnlockedRewardRecord> {
        get { backingData }
        set { backingData = newValue }
    }

    static var schemaMetadata: [Schema.PropertyMetadata] {
        [
            .init(
                name: "rewardID",
                keypath: \UnlockedRewardRecord.rewardID,
                metadata: Schema.Attribute(.unique)
            ),
            .init(name: "unlockedAt", keypath: \UnlockedRewardRecord.unlockedAt),
        ]
    }

    private var _rewardID = ""
    var rewardID: String {
        @storageRestrictions(initializes: _rewardID)
        init(initialValue) { _rewardID = initialValue }
        get { getValue(forKey: \UnlockedRewardRecord.rewardID) }
        set { setValue(forKey: \UnlockedRewardRecord.rewardID, to: newValue) }
    }

    private var _unlockedAt: Date = .distantPast
    var unlockedAt: Date {
        @storageRestrictions(initializes: _unlockedAt)
        init(initialValue) { _unlockedAt = initialValue }
        get { getValue(forKey: \UnlockedRewardRecord.unlockedAt) }
        set { setValue(forKey: \UnlockedRewardRecord.unlockedAt, to: newValue) }
    }

    init(backingData: any BackingData<UnlockedRewardRecord>) {
        persistentBackingData = backingData
    }

    init(rewardID: String, unlockedAt: Date) {
        self.rewardID = rewardID
        self.unlockedAt = unlockedAt
    }
}

@MainActor
public final class HistoryStore {
    private let modelContainer: ModelContainer
    private let saveContext: (ModelContext) throws -> Void
    private var context: ModelContext { modelContainer.mainContext }

    public convenience init() throws {
        try self.init(configuration: Self.defaultConfiguration())
    }

    convenience init(storeURL: URL) throws {
        try self.init(configuration: Self.configuration(storeURL: storeURL))
    }

    private convenience init(configuration: ModelConfiguration) throws {
        let container = try ModelContainer(
            for: FocusSessionRecord.self,
            UnlockedRewardRecord.self,
            configurations: configuration
        )
        self.init(modelContainer: container)
    }

    public static func resetDefaultPersistentStore() throws -> HistoryStore {
        try resetPersistentStore(at: defaultConfiguration().url)
    }

    static func resetPersistentStore(
        at storeURL: URL,
        fileManager: FileManager = .default
    ) throws -> HistoryStore {
        guard storeURL.isFileURL,
              !storeURL.lastPathComponent.isEmpty,
              storeURL.path != "/"
        else {
            throw HistoryStoreRecoveryError.invalidStoreURL
        }

        for fileURL in knownPersistentFileURLs(for: storeURL)
            where fileManager.fileExists(atPath: fileURL.path)
        {
            try fileManager.removeItem(at: fileURL)
        }
        return try HistoryStore(storeURL: storeURL)
    }

    static func knownPersistentFileURLs(for storeURL: URL) -> [URL] {
        ["", "-wal", "-shm", "-journal"].map { suffix in
            URL(fileURLWithPath: storeURL.path + suffix, isDirectory: false)
        }
    }

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        saveContext = { try $0.save() }
    }

    init(
        modelContainer: ModelContainer,
        saveContext: @escaping (ModelContext) throws -> Void
    ) {
        self.modelContainer = modelContainer
        self.saveContext = saveContext
    }

    @discardableResult
    public func recordCompletedFocus(endedAt: Date, duration: TimeInterval? = nil) throws -> [RewardSummary] {
        let priorCount = try completedFocusCount()
        let existingIDs = Set(try context.fetch(FetchDescriptor<UnlockedRewardRecord>()).map(\.rewardID))
        let completedCount = priorCount + 1
        var unlocked: [RewardSummary] = []

        context.insert(FocusSessionRecord(endedAt: endedAt, duration: duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }))
        for reward in CosmeticReward.allCases where reward.milestone <= completedCount {
            guard !existingIDs.contains(reward.rawValue) else { continue }
            context.insert(UnlockedRewardRecord(rewardID: reward.rawValue, unlockedAt: endedAt))
            unlocked.append(RewardSummary(reward: reward, unlockedAt: endedAt))
        }

        try saveStagedChanges()
        return unlocked
    }

    public func completedFocusCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<FocusSessionRecord>())
    }

    public func focusHistorySnapshot() throws -> FocusHistorySnapshot {
        FocusHistorySnapshot(
            completedFocusCount: try completedFocusCount(),
            rewardIDs: Set(try unlockedRewards().map(\.reward))
        )
    }

    public func recentSessions(limit: Int) throws -> [FocusSessionSummary] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<FocusSessionRecord>(
            sortBy: [
                SortDescriptor(\FocusSessionRecord.endedAt, order: .reverse),
                SortDescriptor(\FocusSessionRecord.recordID, order: .forward),
            ]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map {
            FocusSessionSummary(id: $0.recordID, endedAt: $0.endedAt, duration: $0.duration)
        }
    }

    public func unlockedRewards() throws -> [RewardSummary] {
        let recordsByID = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<UnlockedRewardRecord>()).map {
                ($0.rewardID, $0)
            }
        )
        return CosmeticReward.allCases.compactMap { reward in
            guard let record = recordsByID[reward.rawValue] else { return nil }
            return RewardSummary(reward: reward, unlockedAt: record.unlockedAt)
        }
    }

    public func clearAll() throws {
        for session in try context.fetch(FetchDescriptor<FocusSessionRecord>()) {
            context.delete(session)
        }
        for reward in try context.fetch(FetchDescriptor<UnlockedRewardRecord>()) {
            context.delete(reward)
        }
        try saveStagedChanges()
    }

    private func saveStagedChanges() throws {
        do {
            try saveContext(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    // Preserve the existing on-disk store name across the Tepal rebrand.
    private static func defaultConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            "DockPetHistory",
            schema: historySchema,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
    }

    private static func configuration(storeURL: URL) -> ModelConfiguration {
        ModelConfiguration(
            "DockPetHistory",
            schema: historySchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
    }

    private static var historySchema: Schema {
        Schema([FocusSessionRecord.self, UnlockedRewardRecord.self])
    }
}

private enum HistoryStoreRecoveryError: Error {
    case invalidStoreURL
}
