import AppKit
import TepalCore
import TepalMac
import Observation
import SwiftUI

@MainActor
@Observable
final class KnockCalendarController {
    private(set) var status = "Off"
    private(set) var recognizedKnockCount = 0
    private(set) var announcementCount = 0
    private(set) var lastAnnouncementAt: Date?
    private let sensor = KnockSensorConnection()
    private let calendar: any CalendarReading
    private var settings = AppSettings.defaults
    private var enabled = false
    private var suspended = false
    private var request: Task<Void, Never>?
    private var requestGeneration: UInt = 0
    private var hideTask: Task<Void, Never>?
    private(set) var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private var onScreen: () -> CGRect = { NSScreen.main?.visibleFrame ?? .zero }
    private var visual: () -> TepalVisualState
    private let showAnnouncement: ((String, String) -> Void)?
    var supportsMotionInCurrentBuild: Bool { KnockSensorConnection.supportsMotionInCurrentBuild }

    init(calendar: any CalendarReading, visual: @escaping () -> TepalVisualState,
         showAnnouncement: ((String, String) -> Void)? = nil) {
        self.calendar = calendar; self.visual = visual
        self.showAnnouncement = showAnnouncement
        sensor.onStatus = { [weak self] message in
            guard let self, self.enabled, !self.suspended else { return }; self.status = message
        }
        sensor.onKnock = { [weak self] in
            guard let self, self.enabled, !self.suspended else { return }
            self.recognizedKnockCount += 1
            self.showNextEvent()
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            })
        }
    }

    isolated deinit {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        sensor.stop(); request?.cancel(); hideTask?.cancel()
        panel?.orderOut(nil)
    }

    func configure(_ newSettings: AppSettings) {
        if settings.enabledCalendarIDs != newSettings.enabledCalendarIDs || settings.confirmedGoogleSourceIDs != newSettings.confirmedGoogleSourceIDs {
            requestGeneration &+= 1; request?.cancel(); request = nil; panel?.orderOut(nil)
        }
        settings = newSettings
        guard enabled != newSettings.doubleKnockEnabled else { return }
        enabled = newSettings.doubleKnockEnabled
        if enabled && !suspended { sensor.start() }
        else {
            sensor.stop()
            requestGeneration &+= 1; request?.cancel(); request = nil; panel?.orderOut(nil)
            status = "Off"
        }
    }
    func stop() {
        sensor.stop(); requestGeneration &+= 1; request?.cancel(); request = nil
        hideTask?.cancel(); panel?.orderOut(nil)
    }
    private func suspend() { suspended = true; stop(); if enabled { status = "Paused while the screen is inactive" } }
    private func resume() { suspended = false; if enabled { sensor.retry() } }
    func retry() { if enabled && !suspended { sensor.retry() } }

    @discardableResult
    func showNextEvent() -> Task<Void, Never>? {
        guard !suspended, request == nil else { return nil }
        // A manual preview uses this same path, without consuming scheduled reminders.
        let selected = settings.enabledCalendarIDs
        let confirmed = settings.confirmedGoogleSourceIDs
        let calendar = calendar
        requestGeneration &+= 1
        let generation = requestGeneration
        request = Task { [weak self] in
            guard let self else { return }
            defer { if self.requestGeneration == generation { self.request = nil } }
            do {
                guard await calendar.authorizationStatus() == .fullAccess else {
                    if !Task.isCancelled { present(title: "Connect your calendar", detail: "Allow calendar access in Settings to see your next event.") }
                    return
                }
                let choices = try await calendar.calendars()
                let allowed = Set(choices.filter { confirmed.contains($0.sourceID) }.map(\.id)).intersection(selected)
                guard !allowed.isEmpty else {
                    if !Task.isCancelled { present(title: "Choose a calendar", detail: "Select a connected calendar in Settings first.") }
                    return
                }
                let now = Date()
                let found = try await calendar.events(from: now, through: now.addingTimeInterval(7 * 86400), calendarIDs: allowed)
                guard !Task.isCancelled else { return }
                if let event = KnockEventSelection.next(in: found, after: Date(), calendarIDs: allowed) {
                    present(title: event.title, detail: event.start.formatted(date: .abbreviated, time: .shortened))
                } else { present(title: "Nothing coming up", detail: "No timed events in your selected calendars in the next 7 days.") }
            } catch {
                if !Task.isCancelled { present(title: "Calendar unavailable", detail: "Try again in a moment, or check your calendar connection.") }
            }
        }
        return request
    }

    private func present(title: String, detail: String) {
        guard !suspended else { return }
        let checkedAt = Date()
        announcementCount += 1
        lastAnnouncementAt = checkedAt
        if let showAnnouncement { showAnnouncement(title, detail); return }
        let view = KnockAnnouncementView(title: title, detail: detail,
            checkedAt: checkedAt, state: visual().replacingPose(.meetingAttentive),
            dismiss: { [weak self] in self?.panel?.orderOut(nil) })
        let panel = self.panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.panel = panel
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.level = .floating; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: view.id(announcementCount))
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.visibleFrame ?? onScreen()
        panel.setFrame(CGRect(x: screen.midX - 210, y: screen.minY + 20, width: 420, height: 158), display: true)
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }
}

private struct KnockAnnouncementView: View {
    let title: String
    let detail: String
    let checkedAt: Date
    let state: TepalVisualState
    let dismiss: () -> Void
    @State private var appeared = false
    var body: some View {
        HStack(spacing: 16) {
            TepalCanvasView(state: state, surface: .preview).frame(width: 82, height: 112)
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR NEXT EVENT").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                Label("Checked at \(checkedAt.formatted(.dateTime.hour().minute().second()))", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Color(nsColor: TepalTheme.palette(for: state.palette).leaf))
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Dismiss next event")
        }
        .padding(20).frame(width: 420, height: 158)
        .background(Color(nsColor: TepalTheme.palette(for: state.palette).habitatBase))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.15)))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .scaleEffect(appeared || state.reducedMotion ? 1 : 0.96)
        .opacity(appeared || state.reducedMotion ? 1 : 0.5)
        .onAppear { withAnimation(.easeOut(duration: 0.22)) { appeared = true } }
    }
}
