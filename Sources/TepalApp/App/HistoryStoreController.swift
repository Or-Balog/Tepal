import TepalMac
import Foundation

enum HistoryStoreClearResult: Equatable {
    case cleared
    case recovered
    case failed
}

@MainActor
final class HistoryStoreController: FocusHistoryRecording {
    private let recoverStore: () throws -> HistoryStore

    private(set) var store: HistoryStore?

    init(
        makeStore: () throws -> HistoryStore = { try HistoryStore() },
        recoverStore: @escaping () throws -> HistoryStore = {
            try HistoryStore.resetDefaultPersistentStore()
        }
    ) {
        store = try? makeStore()
        self.recoverStore = recoverStore
    }

    func recordCompletedFocus(endedAt: Date, duration: TimeInterval? = nil) throws -> [RewardSummary] {
        guard let store else { throw HistoryStoreControllerError.unavailable }
        return try store.recordCompletedFocus(endedAt: endedAt, duration: duration)
    }

    func completedFocusCount() throws -> Int {
        guard let store else { throw HistoryStoreControllerError.unavailable }
        return try store.completedFocusCount()
    }

    func focusHistorySnapshot() throws -> FocusHistorySnapshot {
        guard let store else { throw HistoryStoreControllerError.unavailable }
        return try store.focusHistorySnapshot()
    }

    func clearAllOrRecover() -> HistoryStoreClearResult {
        if let store {
            do {
                try store.clearAll()
                return .cleared
            } catch {
                self.store = nil
            }
        }

        do {
            store = try recoverStore()
            return .recovered
        } catch {
            store = nil
            return .failed
        }
    }
}

enum LocalDataClearResult: Equatable {
    case complete(historyRecovered: Bool)
    case partialHistoryFailure
}

@MainActor
enum LocalDataClearer {
    static func clear(
        coordinator: AppCoordinator,
        historyStoreController: HistoryStoreController
    ) -> LocalDataClearResult {
        coordinator.clearAllLocalData()

        switch historyStoreController.clearAllOrRecover() {
        case .cleared:
            return .complete(historyRecovered: false)
        case .recovered:
            return .complete(historyRecovered: true)
        case .failed:
            return .partialHistoryFailure
        }
    }
}

private enum HistoryStoreControllerError: Error {
    case unavailable
}
