import TepalCore
import TepalMac
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let initialDestination: SettingsDestination
    let coordinator: AppCoordinator
    let historyStoreController: HistoryStoreController

    @State private var destination: SettingsDestination
    @State private var draft: AppSettings
    @State private var reloadToken = UUID()
    @State private var showClearConfirmation = false
    @State private var clearError: String?

    init(
        initialDestination: SettingsDestination = .preferences,
        coordinator: AppCoordinator,
        historyStoreController: HistoryStoreController
    ) {
        self.initialDestination = initialDestination
        self.coordinator = coordinator
        self.historyStoreController = historyStoreController
        _destination = State(initialValue: initialDestination)
        _draft = State(initialValue: coordinator.settings)
    }

    var body: some View {
        TepalSettingsShell(palette: draft.tepalPalette) {
            HStack(spacing: 0) {
                navigationAndPreview
                    .frame(width: 226)

                Rectangle()
                    .fill(Color(nsColor: palette.divider).opacity(0.82))
                    .frame(width: 1)

                destinationContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 560)
        .onAppear {
            coordinator.refreshLaunchAtLoginStatus()
        }
        .onChange(of: draft) { _, value in
            coordinator.saveSettings(value)
        }
        .onChange(of: coordinator.settings) { _, value in
            if value != draft { draft = value }
        }
        .confirmationDialog(
            "Clear all Tepal data from this Mac?",
            isPresented: $showClearConfirmation
        ) {
            Button("Clear All Local Data", role: .destructive) {
                clearLocalData()
            }
            .accessibilityIdentifier("settings.clear-all-confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityLabel("Cancel clearing all local Tepal data")
                .accessibilityIdentifier("settings.clear-all-cancel")
        } message: {
            Text("This removes settings, timer recovery, reminder occurrence keys, calendar selections, completed-focus dates, and unlocked cosmetics. It does not change Calendar events or the macOS Login Item; turn Launch at Login off separately if enabled.")
        }
    }

    private var palette: TepalPalette {
        TepalTheme.palette(for: draft.tepalPalette)
    }

    private var navigationAndPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("TEPAL")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.7)
                    .foregroundStyle(Color(nsColor: palette.leaf))
                Text(destination.tabTitle)
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
            }

            livePreview
                .padding(.top, 22)

            VStack(spacing: 8) {
                destinationButton(.preferences, systemImage: "slider.horizontal.3")
                destinationButton(.history, systemImage: "clock.arrow.circlepath")
            }
            .padding(.top, 22)

            Spacer(minLength: 18)

            Text("Pomodoro, calendar access, and focus history stay on this Mac.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(Color(nsColor: palette.secondaryText))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .background(Color(nsColor: palette.habitatBase).opacity(0.72))
    }

    private var livePreview: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: palette.habitatAccent),
                    Color(nsColor: palette.habitatBase),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            TepalCanvasView(
                state: coordinator.tepalVisualState,
                surface: .preview
            )
            .frame(width: 104, height: 98)
        }
        .frame(height: 148)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(nsColor: palette.divider), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live Tepal preview")
        .accessibilityValue(LivingTerrariumPresentation.personalityLine(for: coordinator.petState))
        .accessibilityIdentifier("settings.tepal-preview")
    }

    private func destinationButton(
        _ item: SettingsDestination,
        systemImage: String
    ) -> some View {
        Button {
            destination = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(item.tabTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(
                Color(nsColor: item == destination ? palette.primaryText : palette.secondaryText)
            )
            .padding(.horizontal, 13)
            .frame(height: 40)
            .background(
                Color(nsColor: palette.habitatAccent)
                    .opacity(item == destination ? 0.96 : 0.38),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        Color(nsColor: item == destination ? palette.primaryAction : palette.divider),
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.tabTitle)
        .accessibilityValue(item == destination ? "Selected" : "Not selected")
        .accessibilityAddTraits(item == destination ? .isSelected : [])
        .accessibilityIdentifier(item == .preferences ? "settings.tab" : "history.tab")
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch destination {
        case .preferences:
            settingsForm
                .accessibilityIdentifier("settings.view")
        case .history:
            HistoryView(
                historyStore: historyStoreController.store,
                petState: coordinator.petState,
                reloadToken: reloadToken,
                focusDuration: draft.focusDuration,
                paletteID: draft.tepalPalette
            )
        }
    }

    private var settingsForm: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                timerSection
                calendarSection
                petSection
                accessibilitySection
                privacySection
            }
            .padding(24)
        }
        .scrollIndicators(.visible)
    }

    private var timerSection: some View {
        TepalSettingsSection(title: "Timer", paletteID: draft.tepalPalette) {
            durationStepper(
                "Focus",
                value: $draft.focusDuration,
                range: 60 ... 7_200,
                identifier: "settings.timer.focus"
            )
            durationStepper(
                "Short break",
                value: $draft.shortBreakDuration,
                range: 60 ... 7_200,
                identifier: "settings.timer.short-break"
            )
            durationStepper(
                "Long break",
                value: $draft.longBreakDuration,
                range: 60 ... 7_200,
                identifier: "settings.timer.long-break"
            )
            Stepper("Long break every \(draft.longBreakEvery) focuses", value: $draft.longBreakEvery, in: 1 ... 12)
                .accessibilityLabel("Long break cadence")
                .accessibilityValue("Every \(draft.longBreakEvery) focus sessions")
                .accessibilityIdentifier("settings.timer.cadence")
            Toggle("Automatically start the next phase", isOn: $draft.autoStartNextPhase)
                .accessibilityLabel("Automatically start the next Pomodoro phase")
                .accessibilityIdentifier("settings.timer.auto-start")
        }
    }

    private var calendarSection: some View {
        TepalSettingsSection(title: "Calendar", paletteID: draft.tepalPalette) {
            LabeledContent("Access", value: calendarStatusTitle)
                .accessibilityLabel("Calendar access status")
                .accessibilityValue(calendarStatusTitle)
                .accessibilityIdentifier("settings.calendar.status")

            if coordinator.calendarChoices.isEmpty {
                Text("No eligible CalDAV account source is currently available. Add Google in Internet Accounts or continue using Pomodoro only.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.calendar.empty")
            } else {
                Text("EventKit identifies these accounts as CalDAV. Confirm only a source you know is Google before selecting calendars.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.calendar.confirmation-guidance")
                ForEach(groupedCalendars, id: \.sourceID) { group in
                    Toggle(
                        "I confirm \(group.sourceTitle) is my Google account",
                        isOn: sourceBinding(group)
                    )
                    .accessibilityLabel("Confirm source \(group.sourceTitle) is a Google account")
                    .accessibilityIdentifier("settings.calendar.source.\(group.sourceID)")
                    ForEach(group.calendars) { calendar in
                        Toggle(calendarDisplayName(calendar), isOn: calendarBinding(calendar))
                            .disabled(!draft.confirmedGoogleSourceIDs.contains(calendar.sourceID))
                            .accessibilityLabel("Enable calendar \(calendar.title) from \(calendar.sourceTitle)")
                            .accessibilityIdentifier("settings.calendar.\(calendar.id)")
                    }
                }
            }

            Stepper(
                "Reminder lead: \(Int(draft.reminderLead / 60)) minutes",
                value: $draft.reminderLead,
                in: 60 ... 3_600,
                step: 60
            )
            .accessibilityLabel("Meeting reminder lead time")
            .accessibilityValue("\(Int(draft.reminderLead / 60)) minutes")
            .accessibilityIdentifier("settings.calendar.lead")

            Toggle("Meeting alerts", isOn: $draft.meetingAlertsEnabled)
                .accessibilityLabel("Enable meeting alerts")
                .accessibilityIdentifier("settings.calendar.alerts")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    calendarActionButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    calendarActionButtons
                }
            }
        }
    }

    @ViewBuilder
    private var calendarActionButtons: some View {
        Button("Request Calendar Access") {
            Task {
                await coordinator.requestCalendarAccess(
                    afterExplanation: coordinator.settings.onboardingCompleted
                )
            }
        }
        .disabled(!coordinator.settings.onboardingCompleted)
        .accessibilityLabel("Request Full Calendar Access")
        .accessibilityIdentifier("settings.calendar.request-access")
        Button("Refresh") { coordinator.refreshCalendar() }
            .accessibilityLabel("Refresh Google calendars")
            .accessibilityIdentifier("settings.calendar.refresh")
    }

    private var groupedCalendars: [SettingsCalendarGroup] {
        Dictionary(grouping: coordinator.calendarChoices, by: \.sourceID)
            .map { sourceID, calendars in
                SettingsCalendarGroup(
                    sourceID: sourceID,
                    sourceTitle: calendars.first?.sourceTitle ?? "CalDAV account",
                    calendars: calendars.sorted {
                        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle) == .orderedAscending
            }
    }

    private var petSection: some View {
        TepalSettingsSection(title: "Pet", paletteID: draft.tepalPalette) {
            TextField("Name", text: $draft.petName)
                .accessibilityLabel("Pet name")
                .accessibilityIdentifier("settings.pet.name")
            Toggle("Double-knock for my next event", isOn: $draft.doubleKnockEnabled)
                .accessibilityIdentifier("settings.pet.double-knock")
                .disabled(!coordinator.knockCalendar.supportsMotionInCurrentBuild && !draft.doubleKnockEnabled)
            Text(coordinator.knockCalendar.supportsMotionInCurrentBuild
                 ? "Two gentle desk taps. Motion stays on this Mac; no keyboard or microphone recording."
                 : "Double-knock is unavailable in this build. You can still preview your next event below.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if draft.doubleKnockEnabled && coordinator.knockCalendar.supportsMotionInCurrentBuild {
                Text(coordinator.knockCalendar.status).font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Double-knocks recognized: \(coordinator.knockCalendar.recognizedKnockCount)")
                    .font(.system(size: 12)).monospacedDigit()
                    .accessibilityIdentifier("settings.pet.knock-count")
                if let checkedAt = coordinator.knockCalendar.lastAnnouncementAt {
                    Text("Last response: \(checkedAt.formatted(.dateTime.hour().minute().second()))")
                        .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack {
                    Button("Retry sensor") { coordinator.knockCalendar.retry() }
                }
            }
            Button("Preview next event") { coordinator.knockCalendar.showNextEvent() }

            Toggle("Ambient excursions", isOn: $draft.ambientExcursionsEnabled)
                .accessibilityLabel("Enable ambient excursions")
                .accessibilityIdentifier("settings.pet.ambient")
            Stepper(
                "Minimum excursion interval: \(Int(draft.minimumAmbientInterval / 60)) minutes",
                value: $draft.minimumAmbientInterval,
                in: 1_800 ... 86_400,
                step: 300
            )
            .accessibilityLabel("Minimum ambient excursion frequency")
            .accessibilityValue("\(Int(draft.minimumAmbientInterval / 60)) minutes")
            .accessibilityIdentifier("settings.pet.ambient-frequency")
            Toggle("Sound", isOn: $draft.soundEnabled)
                .accessibilityLabel("Enable Tepal sound")
                .accessibilityIdentifier("settings.pet.sound")

            Toggle("Launch at login", isOn: launchAtLoginBinding)
                .accessibilityLabel("Launch Tepal at login")
                .accessibilityValue(launchAtLoginAccessibilityValue)
                .accessibilityIdentifier("settings.pet.launch-at-login")
            Text(launchAtLoginStatusText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.pet.launch-at-login-status")
            if let launchAtLoginError = coordinator.launchAtLoginError {
                Text(launchAtLoginError)
                    .foregroundStyle(Color(nsColor: TepalTheme.statusError))
                    .accessibilityLabel("Launch at login error: \(launchAtLoginError)")
                    .accessibilityIdentifier("settings.pet.launch-at-login-error")
            }
        }
    }

    private var accessibilitySection: some View {
        TepalSettingsSection(title: "Accessibility", paletteID: draft.tepalPalette) {
            Picker("Motion", selection: $draft.reducedMotionPreference) {
                Text("Follow System").tag(ReducedMotionPreference.followSystem)
                Text("Always Reduce Motion").tag(ReducedMotionPreference.reduceMotion)
            }
            .accessibilityLabel("Motion preference")
            .accessibilityIdentifier("settings.accessibility.motion")
            Text("Follow System always honors the macOS Reduce Motion setting. The explicit override can additionally reduce motion.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var privacySection: some View {
        TepalSettingsSection(title: "Privacy", paletteID: draft.tepalPalette) {
            Button("Clear All Local Data", role: .destructive) {
                showClearConfirmation = true
            }
            .accessibilityLabel("Clear all local Tepal data")
            .accessibilityIdentifier("settings.privacy.clear-all")
            Button("Open Calendar Privacy Settings") {
                SystemSettingsLink.openCalendarPrivacy()
            }
            .accessibilityLabel("Open Calendar privacy settings in System Settings")
            .accessibilityIdentifier("settings.privacy.open-calendar")
            Text("Titles, descriptions, locations, attendees, and calendar names are never persisted. Reminder deduplication stores only opaque occurrence identifiers, occurrence-start timestamps, and snooze deadlines. Tepal has no network client, analytics, or calendar write path.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if let clearError {
                Text(clearError)
                    .foregroundStyle(Color(nsColor: TepalTheme.statusError))
                    .accessibilityLabel("Clear history error: \(clearError)")
                    .accessibilityIdentifier("settings.privacy.clear-error")
            }
        }
    }

    private func durationStepper(
        _ title: String,
        value: Binding<TimeInterval>,
        range: ClosedRange<TimeInterval>,
        identifier: String
    ) -> some View {
        Stepper(
            "\(title): \(Int(value.wrappedValue / 60)) minutes",
            value: value,
            in: range,
            step: 60
        )
        .accessibilityLabel("\(title) duration")
        .accessibilityValue("\(Int(value.wrappedValue / 60)) minutes")
        .accessibilityIdentifier(identifier)
    }

    private func calendarBinding(_ calendar: CalendarDescriptor) -> Binding<Bool> {
        Binding(
            get: { draft.enabledCalendarIDs.contains(calendar.id) },
            set: { enabled in
                var selection = ConfirmedCalendarSelection(
                    calendarIDs: draft.enabledCalendarIDs,
                    confirmedSourceIDs: draft.confirmedGoogleSourceIDs
                )
                selection.setCalendar(
                    calendar.id,
                    enabled: enabled,
                    sourceID: calendar.sourceID
                )
                draft.enabledCalendarIDs = selection.calendarIDs
                draft.confirmedGoogleSourceIDs = selection.confirmedSourceIDs
            }
        )
    }

    private func sourceBinding(_ group: SettingsCalendarGroup) -> Binding<Bool> {
        Binding(
            get: { draft.confirmedGoogleSourceIDs.contains(group.sourceID) },
            set: { confirmed in
                var selection = ConfirmedCalendarSelection(
                    calendarIDs: draft.enabledCalendarIDs,
                    confirmedSourceIDs: draft.confirmedGoogleSourceIDs
                )
                selection.setSource(
                    group.sourceID,
                    confirmedAsGoogle: confirmed,
                    calendarIDs: Set(group.calendars.map(\.id))
                )
                draft.enabledCalendarIDs = selection.calendarIDs
                draft.confirmedGoogleSourceIDs = selection.confirmedSourceIDs
            }
        )
    }

    private func calendarDisplayName(_ calendar: CalendarDescriptor) -> String {
        "\(calendar.title) — \(calendar.sourceTitle)"
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { coordinator.launchAtLoginStatus == .enabled },
            set: { coordinator.setLaunchAtLoginEnabled($0) }
        )
    }

    private var launchAtLoginAccessibilityValue: String {
        coordinator.launchAtLoginStatus == .enabled ? "Enabled" : "Disabled"
    }

    private var launchAtLoginStatusText: String {
        switch coordinator.launchAtLoginStatus {
        case .enabled:
            "Enabled. Tepal will open automatically when you log in."
        case .notRegistered:
            "Off. Move Tepal.app to /Applications before enabling this for reliable registration."
        case .requiresApproval:
            "macOS approval is required. Allow Tepal in System Settings > General > Login Items."
        case .notFound:
            "Tepal could not be registered at its current location. Move Tepal.app to /Applications and try again."
        @unknown default:
            "The current launch-at-login status is unavailable. Move Tepal.app to /Applications and try again."
        }
    }

    private var calendarStatusTitle: String {
        switch coordinator.calendarStatus {
        case .notRequested: "Not requested"
        case .refreshing: "Refreshing"
        case .disconnected: "No eligible account source"
        case .noSelection: "No confirmed calendar selected"
        case .ready: "Full Access available"
        case .accessDenied: "Denied or revoked"
        case let .unavailable(message): message
        }
    }

    private func clearLocalData() {
        let result = LocalDataClearer.clear(
            coordinator: coordinator,
            historyStoreController: historyStoreController
        )
        draft = coordinator.settings
        reloadToken = UUID()
        switch result {
        case .complete:
            clearError = nil
        case .partialHistoryFailure:
            clearError = "Settings, timer recovery, reminder data, calendar selections, and current runtime state were cleared, but focus history could not be cleared or recreated. Quit and reopen Tepal, then try Clear All Local Data again."
        }
    }
}

private struct SettingsCalendarGroup {
    let sourceID: String
    let sourceTitle: String
    let calendars: [CalendarDescriptor]
}

private struct TepalSettingsSection<Content: View>: View {
    let title: String
    let paletteID: TepalPaletteID
    @ViewBuilder let content: Content

    private var palette: TepalPalette {
        TepalTheme.palette(for: paletteID)
    }

    init(
        title: String,
        paletteID: TepalPaletteID,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.paletteID = paletteID
        self.content = content()
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
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
