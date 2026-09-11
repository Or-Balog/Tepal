import TepalCore
import TepalMac
import Observation
import SwiftUI

enum HistoryPresentation {
    static func mood(totalCompleted: Int, petState: PetState) -> String {
        switch petState {
        case .idle: "Calm"
        case .focus: "Focused"
        case .rest: "Rested"
        case .meetingAlert: "Attentive"
        case .reward: "Proud"
        case .excursion: "Curious"
        }
    }

    static func rewardName(_ reward: CosmeticReward) -> String {
        switch reward {
        case .glow: "Soft Glow"
        case .sparkle: "Sparkle"
        case .colorShift: "Color Shift"
        case .morph: "Tiny Morph"
        }
    }

    static func gardenRows(
        sessions: [FocusSessionSummary],
        focusDuration: TimeInterval
    ) -> [HistoryGardenRowState] {
        return sessions.map {
            HistoryGardenRowState(
                id: $0.id,
                endedAt: $0.endedAt,
                durationText: $0.duration.map { "\(max(1, Int(($0 / 60).rounded()))) min" } ?? "Duration not recorded"
            )
        }
    }
}

struct HistoryGardenRowState: Identifiable, Equatable {
    let id: UUID
    let endedAt: Date
    let durationText: String
}

struct HistoryViewSnapshot: Equatable {
    let sessions: [FocusSessionSummary]
    let rewards: [RewardSummary]
    let totalCompleted: Int
}

@MainActor
@Observable
final class HistoryViewModel {
    typealias Load = (HistoryStore) throws -> HistoryViewSnapshot

    private let load: Load

    private(set) var sessions: [FocusSessionSummary] = []
    private(set) var rewards: [RewardSummary] = []
    private(set) var totalCompleted = 0
    private(set) var errorMessage: String?

    init() {
        load = { historyStore in
            HistoryViewSnapshot(
                sessions: try historyStore.recentSessions(limit: 100),
                rewards: try historyStore.unlockedRewards(),
                totalCompleted: try historyStore.completedFocusCount()
            )
        }
    }

    init(load: @escaping Load) {
        self.load = load
    }

    func reload(historyStore: HistoryStore?) {
        guard let historyStore else {
            clear(message: "Focus history is unavailable in this session.")
            return
        }

        do {
            let snapshot = try load(historyStore)
            sessions = snapshot.sessions
            rewards = snapshot.rewards
            totalCompleted = snapshot.totalCompleted
            errorMessage = nil
        } catch {
            clear(message: "Focus history could not be loaded.")
        }
    }

    private func clear(message: String) {
        sessions = []
        rewards = []
        totalCompleted = 0
        errorMessage = message
    }
}

struct HistoryView: View {
    let historyStore: HistoryStore?
    let petState: PetState
    let reloadToken: UUID
    let focusDuration: TimeInterval
    let paletteID: TepalPaletteID

    @State private var model: HistoryViewModel

    init(
        historyStore: HistoryStore?,
        petState: PetState,
        reloadToken: UUID,
        focusDuration: TimeInterval = 1_500,
        paletteID: TepalPaletteID = .moonFern
    ) {
        self.historyStore = historyStore
        self.petState = petState
        self.reloadToken = reloadToken
        self.focusDuration = focusDuration
        self.paletteID = paletteID
        _model = State(initialValue: HistoryViewModel())
    }

    private var sessions: [FocusSessionSummary] { model.sessions }
    private var rewards: [RewardSummary] { model.rewards }
    private var totalCompleted: Int { model.totalCompleted }
    private var errorMessage: String? { model.errorMessage }

    private var palette: TepalPalette {
        TepalTheme.palette(for: paletteID)
    }

    private var gardenRows: [HistoryGardenRowState] {
        HistoryPresentation.gardenRows(
            sessions: sessions,
            focusDuration: focusDuration
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("GARDEN RECORD")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Color(nsColor: palette.leaf))
                    Text("Focus history")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                    Text("A quiet record of the focus sessions that helped Tepal grow.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color(nsColor: palette.secondaryText))
                }
                .padding(.bottom, 2)

                TepalHistorySection(title: "Summary", paletteID: paletteID) {
                    HStack(spacing: 12) {
                        historyMetric(
                            title: "Completed focuses",
                            value: "\(totalCompleted)",
                            identifier: "history.total"
                        )
                        historyMetric(
                            title: "Current mood",
                            value: HistoryPresentation.mood(
                                totalCompleted: totalCompleted,
                                petState: petState
                            ),
                            identifier: "history.mood"
                        )
                    }
                }

                TepalHistorySection(title: "Unlocked growth", paletteID: paletteID) {
                    if rewards.isEmpty {
                        gardenEmptyState(
                            systemImage: "sparkles",
                            text: "Complete a focus session to unlock the first gentle cosmetic.",
                            identifier: "history.rewards-empty"
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(rewards.enumerated()), id: \.element.id) { index, reward in
                                if index > 0 { botanicalDivider }
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Image(systemName: "leaf.fill")
                                        .foregroundStyle(Color(nsColor: palette.leaf))
                                        .accessibilityHidden(true)
                                    Text(HistoryPresentation.rewardName(reward.reward))
                                    Spacer(minLength: 12)
                                    Text(reward.unlockedAt.formatted(date: .abbreviated, time: .omitted))
                                        .foregroundStyle(Color(nsColor: palette.secondaryText))
                                }
                                .padding(.vertical, 10)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(
                                    "\(HistoryPresentation.rewardName(reward.reward)) unlocked \(reward.unlockedAt.formatted(date: .long, time: .omitted))"
                                )
                                .accessibilityIdentifier("history.reward.\(reward.reward.rawValue)")
                            }
                        }
                    }
                }

                TepalHistorySection(title: "Completed focus dates", paletteID: paletteID) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("New sessions keep their original focus duration. Older sessions may have no recorded duration.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Color(nsColor: palette.secondaryText))
                            .fixedSize(horizontal: false, vertical: true)
                        if gardenRows.isEmpty {
                            gardenEmptyState(
                                systemImage: "leaf",
                                text: "No completed focus sessions yet.",
                                identifier: "history.sessions-empty"
                            )
                        } else {
                            ForEach(Array(gardenRows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 { botanicalDivider }
                                gardenRow(row)
                            }
                        }
                    }
                }

                if let errorMessage {
                    TepalHistorySection(title: "History status", paletteID: paletteID) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color(nsColor: TepalTheme.statusError))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("History error: \(errorMessage)")
                            .accessibilityIdentifier("history.error")
                    }
                }
            }
            .padding(24)
        }
        .scrollIndicators(.visible)
        .task(id: reloadToken) { reload() }
        .accessibilityIdentifier("history.view")
    }

    private func historyMetric(
        title: String,
        value: String,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(nsColor: palette.primaryText))
            Text(title)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color(nsColor: palette.secondaryText))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: palette.habitatAccent).opacity(0.58),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title == "Current mood" ? "Current positive pet mood" : title)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }

    private func gardenRow(_ row: HistoryGardenRowState) -> some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: palette.habitatAccent))
                Image(systemName: "leaf.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: palette.leaf))
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.endedAt.formatted(date: .long, time: .omitted))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(row.endedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Color(nsColor: palette.secondaryText))
            }
            Spacer(minLength: 12)
            Text(row.durationText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(nsColor: palette.leaf))
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Focus completed \(row.endedAt.formatted(date: .long, time: .shortened)), duration \(row.durationText)"
        )
        .accessibilityIdentifier("history.session.\(row.id.uuidString)")
    }

    private func gardenEmptyState(
        systemImage: String,
        text: String,
        identifier: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .foregroundStyle(Color(nsColor: palette.leaf))
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(Color(nsColor: palette.secondaryText))
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var botanicalDivider: some View {
        Rectangle()
            .fill(Color(nsColor: palette.divider).opacity(0.72))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    @MainActor
    private func reload() {
        model.reload(historyStore: historyStore)
    }
}

private struct TepalHistorySection<Content: View>: View {
    let title: String
    let paletteID: TepalPaletteID
    let content: Content

    init(
        title: String,
        paletteID: TepalPaletteID,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.paletteID = paletteID
        self.content = content()
    }

    private var palette: TepalPalette {
        TepalTheme.palette(for: paletteID)
    }

    var body: some View {
        Section {
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(nsColor: palette.habitatBase).opacity(0.68),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(nsColor: palette.divider).opacity(0.92), lineWidth: 1)
                }
        } header: {
            HStack(spacing: 9) {
                Capsule()
                    .fill(Color(nsColor: palette.leaf))
                    .frame(width: 22, height: 3)
                    .accessibilityHidden(true)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.25)
                    .foregroundStyle(Color(nsColor: palette.secondaryText))
                    .accessibilityAddTraits(.isHeader)
                Rectangle()
                    .fill(Color(nsColor: palette.divider).opacity(0.72))
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 2)
        }
    }
}
