import AppKit
import TepalCore
import TepalMac
import SwiftUI

struct TepalOnboardingChapter: Equatable {
    let title: String
}

enum TepalOnboardingPresentation {
    static let previewSurface: TepalRenderSurface = .preview

    static let chapters = [
        TepalOnboardingChapter(title: "A quiet place on your Mac"),
        TepalOnboardingChapter(title: "Bring Google Calendar through macOS"),
        TepalOnboardingChapter(title: "Read meetings, never change them"),
        TepalOnboardingChapter(title: "Name your familiar"),
    ]

    static let calendarPermissionExplanation =
        "macOS requires Full Calendar Access to read upcoming titles and times; " +
        "Tepal has no calendar save, edit, or delete path."

    static func previewState(reducedMotion: Bool) -> TepalVisualState {
        TepalVisualState(
            pose: .ready,
            timerProgress: 0,
            palette: .moonFern,
            growth: TepalGrowthProfile(completedFocuses: 0),
            reducedMotion: reducedMotion
        )
    }
}

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @FocusState private var petNameFocused: Bool

    let coordinator: AppCoordinator
    let onComplete: () -> Void

    @State private var page = 0
    @State private var calendarSelection: ConfirmedCalendarSelection
    @State private var petName: String
    @State private var isRequestingAccess = false

    init(coordinator: AppCoordinator, onComplete: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onComplete = onComplete
        _calendarSelection = State(initialValue: ConfirmedCalendarSelection(
            calendarIDs: coordinator.settings.enabledCalendarIDs,
            confirmedSourceIDs: coordinator.settings.confirmedGoogleSourceIDs
        ))
        _petName = State(initialValue: coordinator.settings.petName)
    }

    private var palette: TepalPalette {
        TepalTheme.palette(for: .moonFern)
    }

    var body: some View {
        TepalSettingsShell {
            VStack(spacing: 0) {
                habitatHeader
                    .frame(height: 128)

                VStack(alignment: .leading, spacing: 0) {
                    chapterHeader

                    ScrollView {
                        pageContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                    }

                    Rectangle()
                        .fill(Color(nsColor: palette.divider).opacity(0.72))
                        .frame(height: 1)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            backButton
                            Spacer(minLength: 8)
                            pageActions
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            pageActions
                            backButton
                        }
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, TepalLayout.shelfInset)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .background(Color(nsColor: palette.habitatBase).opacity(0.96))
            }
        }
        .frame(width: TepalLayout.panelSize.width, height: TepalLayout.panelSize.height)
        .clipShape(shellShape)
        .overlay {
            shellShape
                .stroke(Color(nsColor: palette.primaryText).opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .animation(
            effectiveReducedMotion ? nil : .easeInOut(duration: 0.2),
            value: page
        )
        .onChange(of: page) { _, newPage in
            guard newPage == 3 else { return }
            Task { @MainActor in petNameFocused = true }
        }
    }

    private var chapterHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("CHAPTER \(page + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.1)
                Spacer()
                Text("\(page + 1) of \(TepalOnboardingPresentation.chapters.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .accessibilityLabel("Onboarding page \(page + 1) of 4")
            }
            .foregroundStyle(Color(nsColor: palette.secondaryText))

            Text(TepalOnboardingPresentation.chapters[page].title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(nsColor: palette.primaryText))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var habitatHeader: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: palette.habitatAccent),
                        Color(nsColor: palette.habitatBase),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Ellipse()
                    .fill(Color(nsColor: palette.glow).opacity(0.16))
                    .frame(width: size.width * 0.68, height: size.height * 0.92)
                    .blur(radius: 26)
                    .offset(y: -30)

                ForEach(
                    Array(TepalHabitatPresentation.starPoints.enumerated()),
                    id: \.offset
                ) { _, point in
                    Circle()
                        .fill(Color(nsColor: palette.primaryText).opacity(0.36))
                        .frame(width: 2, height: 2)
                        .position(x: size.width * point.x, y: size.height * point.y)
                }

                TepalCanvasView(
                    state: TepalOnboardingPresentation.previewState(
                        reducedMotion: effectiveReducedMotion
                    ),
                    surface: TepalOnboardingPresentation.previewSurface
                )
                .frame(width: 86, height: 86)
                .offset(y: 10)

                Canvas { context, canvasSize in
                    let colors = [palette.groundFar, palette.groundMiddle, palette.groundNear]
                    for (index, path) in TepalHabitatPresentation.groundPaths(in: canvasSize).enumerated() {
                        context.fill(path, with: .color(Color(nsColor: colors[index])))
                    }
                }
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tepal resting in a living terrarium")
        .accessibilityIdentifier("onboarding.tepal-preview")
    }

    private var shellShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TepalLayout.shellRadius, style: .continuous)
    }

    @ViewBuilder
    private var backButton: some View {
        if page > 0 {
            Button("Back") { page -= 1 }
                .buttonStyle(.bordered)
                .tint(Color(nsColor: palette.primaryAction))
                .accessibilityLabel("Go to previous onboarding page")
                .accessibilityIdentifier("onboarding.back")
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case 0:
            VStack(alignment: .leading, spacing: 14) {
                Label("Everything stays on this Mac", systemImage: "lock.shield")
                    .font(.headline)
                Text("Tepal has no account, backend, analytics, or network client. Pomodoro settings, focus history, mood, and rewards stay local and can be cleared in Settings.")
                    .foregroundStyle(Color(nsColor: palette.secondaryText))
                Text("Calendar reminders use events already synced by macOS. Titles, descriptions, locations, attendees, and calendar names stay in memory and never enter focus history. For reminder deduplication and snooze, Tepal stores opaque occurrence identifiers, occurrence-start timestamps, and snooze deadlines locally.")
                    .foregroundStyle(Color(nsColor: palette.secondaryText))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onboarding.local-only")
        case 1:
            VStack(alignment: .leading, spacing: 14) {
                Label("Add Google to macOS first", systemImage: "gearshape.2")
                    .font(.headline)
                Text("Open System Settings › Internet Accounts, add your Google account, and make sure Calendars is enabled. macOS performs the sync; Tepal never signs in to Google directly.")
                    .foregroundStyle(Color(nsColor: palette.secondaryText))
                Button("Open Internet Accounts") {
                    SystemSettingsLink.openInternetAccounts()
                }
                .buttonStyle(.bordered)
                .tint(Color(nsColor: palette.primaryAction))
                .accessibilityLabel("Open Internet Accounts in System Settings")
                .accessibilityIdentifier("onboarding.open-internet-accounts")
            }
        case 2:
            VStack(alignment: .leading, spacing: 14) {
                Label("Calendar permission", systemImage: "calendar.badge.exclamationmark")
                    .font(.headline)
                Text(
                    "Apple does not offer read-only Calendar permission. " +
                    TepalOnboardingPresentation.calendarPermissionExplanation
                )
                    .foregroundStyle(Color(nsColor: palette.secondaryText))
                Text("The permission prompt appears only when you choose Request Full Calendar Access below.")
                    .font(.callout.weight(.medium))

                if coordinator.calendarStatus == .accessDenied {
                    Label("Access was denied. Pomodoro and the creature still work normally.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color(nsColor: palette.secondaryText))
                        .accessibilityIdentifier("onboarding.calendar-denied")
                }
                if case let .unavailable(message) = coordinator.calendarStatus {
                    Text(message)
                        .foregroundStyle(Color(nsColor: palette.secondaryText))
                        .accessibilityIdentifier("onboarding.calendar-error")
                }
            }
        default:
            calendarSelectionPage
        }
    }

    @ViewBuilder
    private var pageActions: some View {
        switch page {
        case 0:
            Button("Continue") { page = 1 }
                .buttonStyle(TepalPrimaryButtonStyle())
                .accessibilityLabel("Continue to Google account setup")
                .accessibilityIdentifier("onboarding.continue-local")
        case 1:
            Button("Google Is Added") { page = 2 }
                .buttonStyle(TepalPrimaryButtonStyle())
                .accessibilityLabel("Continue to Calendar permission explanation")
                .accessibilityIdentifier("onboarding.google-added")
        case 2:
            if OnboardingCalendarAccessPolicy.offersPomodoroOnly(
                for: coordinator.calendarStatus
            ) {
                Button("Continue with Pomodoro Only") {
                    finishPomodoroOnly()
                }
                .buttonStyle(.bordered)
                .tint(Color(nsColor: palette.primaryAction))
                .accessibilityLabel("Finish setup without Calendar access")
                .accessibilityIdentifier("onboarding.pomodoro-only")
            }
            Button(isRequestingAccess ? "Requesting…" : "Request Full Calendar Access") {
                requestAccess()
            }
            .buttonStyle(TepalPrimaryButtonStyle())
            .disabled(isRequestingAccess)
            .accessibilityLabel("Request Full Calendar Access after reading the explanation")
            .accessibilityIdentifier("onboarding.request-calendar-access")
        default:
            Button(calendarSelection.calendarIDs.isEmpty ? "Continue with Pomodoro Only" : "Finish") {
                finishSelection()
            }
                .buttonStyle(TepalPrimaryButtonStyle())
                .accessibilityLabel(
                    calendarSelection.calendarIDs.isEmpty
                        ? "Finish setup without a Google calendar"
                        : "Finish Tepal setup"
                )
                .accessibilityIdentifier("onboarding.finish")
        }
    }

    private var calendarSelectionPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Choose Google calendars", systemImage: "calendar")
                .font(.headline)

            if coordinator.calendarChoices.isEmpty {
                Text("No Google Calendar source is available. Add or re-enable Google in Internet Accounts, then retry. You can still finish with Pomodoro only.")
                    .foregroundStyle(Color(nsColor: palette.secondaryText))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { noGoogleActions }
                    VStack(alignment: .leading, spacing: 8) { noGoogleActions }
                }
            } else {
                Text("macOS identifies these accounts as CalDAV, not by provider. Confirm only a source you know is your Google account; Tepal will read nothing from it until then.")
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: palette.secondaryText))
                    .accessibilityIdentifier("onboarding.source-confirmation-guidance")
                ForEach(groupedCalendars, id: \.sourceID) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(
                            "I confirm \(group.sourceTitle) is my Google account",
                            isOn: sourceBinding(group)
                        )
                        .font(.subheadline.weight(.semibold))
                        .accessibilityLabel("Confirm source \(group.sourceTitle) is a Google account")
                        .accessibilityIdentifier("onboarding.source.\(group.sourceID)")
                        ForEach(group.calendars) { calendar in
                            Toggle(calendar.title, isOn: calendarBinding(calendar))
                                .padding(.leading, 18)
                                .disabled(!calendarSelection.confirmedSourceIDs.contains(calendar.sourceID))
                                .accessibilityLabel("Enable calendar \(calendar.title)")
                                .accessibilityIdentifier("onboarding.calendar.\(calendar.id)")
                        }
                    }
                }
            }

            TextField("Optional pet name", text: $petName)
                .focused($petNameFocused)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Optional pet name")
                .accessibilityIdentifier("onboarding.pet-name")
        }
    }

    @ViewBuilder
    private var noGoogleActions: some View {
        Button("Retry") { coordinator.refreshCalendar() }
            .buttonStyle(.bordered)
            .tint(Color(nsColor: palette.primaryAction))
            .accessibilityLabel("Retry Google Calendar discovery")
            .accessibilityIdentifier("onboarding.retry-calendars")
        Button("Open Internet Accounts") {
            SystemSettingsLink.openInternetAccounts()
        }
        .buttonStyle(.bordered)
        .tint(Color(nsColor: palette.primaryAction))
        .accessibilityLabel("Open Internet Accounts guidance")
        .accessibilityIdentifier("onboarding.no-google-settings")
        Button("Continue with Pomodoro Only") {
            finishPomodoroOnly()
        }
        .buttonStyle(.bordered)
        .tint(Color(nsColor: palette.primaryAction))
        .accessibilityLabel("Finish setup without a Google calendar")
        .accessibilityIdentifier("onboarding.no-google-pomodoro-only")
    }

    private var groupedCalendars: [CalendarGroup] {
        Dictionary(grouping: coordinator.calendarChoices, by: \.sourceID)
            .map { sourceID, calendars in
                CalendarGroup(
                    sourceID: sourceID,
                    sourceTitle: calendars.first?.sourceTitle ?? "Google",
                    calendars: calendars.sorted {
                        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle) == .orderedAscending
            }
    }

    private func sourceBinding(_ group: CalendarGroup) -> Binding<Bool> {
        Binding(
            get: { calendarSelection.confirmedSourceIDs.contains(group.sourceID) },
            set: { confirmed in
                calendarSelection.setSource(
                    group.sourceID,
                    confirmedAsGoogle: confirmed,
                    calendarIDs: Set(group.calendars.map(\.id))
                )
            }
        )
    }

    private func calendarBinding(_ calendar: CalendarDescriptor) -> Binding<Bool> {
        Binding(
            get: { calendarSelection.calendarIDs.contains(calendar.id) },
            set: { enabled in
                calendarSelection.setCalendar(
                    calendar.id,
                    enabled: enabled,
                    sourceID: calendar.sourceID
                )
            }
        )
    }

    private func requestAccess() {
        isRequestingAccess = true
        Task { @MainActor in
            let granted = await coordinator.requestCalendarAccess(afterExplanation: true)
            isRequestingAccess = false
            if granted {
                page = 3
            }
        }
    }

    private func finishSelection() {
        var updated = coordinator.settings
        updated.enabledCalendarIDs = calendarSelection.calendarIDs
        updated.confirmedGoogleSourceIDs = calendarSelection.confirmedSourceIDs
        updated.petName = petName
        updated.onboardingCompleted = true
        coordinator.saveSettings(updated)
        onComplete()
    }

    private func finishPomodoroOnly() {
        calendarSelection = ConfirmedCalendarSelection()
        finishSelection()
    }

    private var effectiveReducedMotion: Bool {
        coordinator.settings.reducedMotionPreference.resolved(
            systemSetting: accessibilityReduceMotion
        )
    }
}

enum OnboardingCalendarAccessPolicy {
    static func offersPomodoroOnly(for status: CalendarStatus) -> Bool {
        switch status {
        case .accessDenied, .unavailable, .disconnected, .noSelection:
            true
        case .notRequested, .refreshing, .ready:
            false
        }
    }
}

private struct CalendarGroup {
    let sourceID: String
    let sourceTitle: String
    let calendars: [CalendarDescriptor]
}

enum SystemSettingsLink {
    static func openInternetAccounts() {
        open("x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")
    }

    static func openCalendarPrivacy() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
    }

    private static func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
