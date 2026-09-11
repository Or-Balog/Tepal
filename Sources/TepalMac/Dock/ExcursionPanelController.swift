import AppKit
import TepalCore

@MainActor
public protocol ExcursionPresenting: AnyObject {
    var isPresented: Bool { get }

    func showProbe(
        from geometry: DockGeometry,
        appearance: TepalVisualState,
        onDismiss: @escaping () -> Void
    )
    func showMeetings(
        titles: [String],
        start: Date,
        from home: DockGeometry,
        appearance: TepalVisualState,
        onDismiss: @escaping () -> Void,
        onSnooze: @escaping () -> Void
    )
    func showMeetingsWithoutSnooze(
        titles: [String],
        start: Date,
        from home: DockGeometry,
        appearance: TepalVisualState,
        onDismiss: @escaping () -> Void
    )
    func hide()
}

struct ExcursionPresentationPlan {
    let startFrame: NSRect
    let destinationFrame: NSRect
    let usesFade: Bool

    static func make(
        at geometry: DockGeometry,
        size: NSSize,
        creatureOnRight: Bool,
        reducedMotion: Bool,
        visibleFrame: NSRect?
    ) -> ExcursionPresentationPlan {
        let creatureCenterOffset = creatureOnRight ? size.width - 48 : 48
        let dockFrame = NSRect(
            x: geometry.homePoint.x - creatureCenterOffset,
            y: geometry.homePoint.y - 48,
            width: size.width,
            height: size.height
        )
        let displacement: CGPoint
        switch geometry.edge {
        case .bottom:
            displacement = CGPoint(x: 0, y: 60)
        case .left:
            displacement = CGPoint(x: 60, y: 0)
        case .right:
            displacement = CGPoint(x: -60, y: 0)
        case .unknown:
            displacement = .zero
        }
        let translatedFrame = dockFrame.offsetBy(
            dx: reducedMotion ? 0 : displacement.x,
            dy: reducedMotion ? 0 : displacement.y
        )
        let destinationFrame = clamp(translatedFrame, to: visibleFrame)
        return ExcursionPresentationPlan(
            startFrame: reducedMotion ? destinationFrame : dockFrame,
            destinationFrame: destinationFrame,
            usesFade: reducedMotion
        )
    }

    private static func clamp(_ frame: NSRect, to visibleFrame: NSRect?) -> NSRect {
        guard let visibleFrame else { return frame }
        return NSRect(
            x: min(max(frame.minX, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - frame.width)),
            y: min(max(frame.minY, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - frame.height)),
            width: frame.width,
            height: frame.height
        )
    }
}

@MainActor
public final class ExcursionPanelController: ExcursionPresenting {
    private let panel: NSPanel
    private var autoDismissTimer: Timer?
    private var meetingView: MeetingPresentationView?
    private var currentMeetingTitles: [String] = []
    private var onDismiss: (() -> Void)?
    private var onSnooze: (() -> Void)?

    public var isPresented: Bool {
        panel.isVisible
    }

    var presentedMeetingTitles: [String] {
        currentMeetingTitles
    }

    public init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    public func showProbe(
        from geometry: DockGeometry,
        appearance: TepalVisualState,
        onDismiss: @escaping () -> Void
    ) {
        dismissCurrent(notify: false)

        let creature = TepalTileView(
            frame: NSRect(x: 0, y: 0, width: 96, height: 96),
            displayDestination: .viewOnly,
            renderSurface: .excursion
        )
        creature.render(appearance.replacingPose(.walking))
        panel.contentView = creature
        panel.hasShadow = false

        let plan = ExcursionPresentationPlan.make(
            at: geometry,
            size: NSSize(width: 96, height: 96),
            creatureOnRight: false,
            reducedMotion: appearance.reducedMotion,
            visibleFrame: visibleFrame(near: geometry.homePoint)
        )

        self.onDismiss = onDismiss
        present(
            from: plan.startFrame,
            to: plan.destinationFrame,
            reducedMotion: plan.usesFade
        )
        scheduleAutoDismiss(after: 2)
    }

    public func showMeetings(
        titles: [String],
        start: Date,
        from home: DockGeometry,
        appearance: TepalVisualState,
        onDismiss: @escaping () -> Void,
        onSnooze: @escaping () -> Void
    ) {
        showMeetings(
            titles: titles,
            start: start,
            from: home,
            appearance: appearance,
            onDismiss: onDismiss,
            optionalSnooze: onSnooze
        )
    }

    public func showMeetingsWithoutSnooze(
        titles: [String],
        start: Date,
        from home: DockGeometry,
        appearance: TepalVisualState,
        onDismiss: @escaping () -> Void
    ) {
        showMeetings(
            titles: titles,
            start: start,
            from: home,
            appearance: appearance,
            onDismiss: onDismiss,
            optionalSnooze: nil
        )
    }

    public func hide() {
        dismissCurrent(notify: false)
    }

    private func showMeetings(
        titles: [String],
        start: Date,
        from home: DockGeometry,
        appearance: TepalVisualState,
        onDismiss: @escaping () -> Void,
        optionalSnooze: (() -> Void)?
    ) {
        dismissCurrent(notify: false)

        let normalizedTitles = titles.isEmpty ? ["Untitled event"] : titles

        let content = MeetingPresentationView(
            titles: normalizedTitles,
            start: start,
            appearance: appearance,
            creatureOnRight: home.edge == .right,
            target: self,
            dismissAction: #selector(dismissButtonPressed),
            snoozeAction: optionalSnooze == nil ? nil : #selector(snoozeButtonPressed)
        )
        meetingView = content
        currentMeetingTitles = normalizedTitles
        panel.contentView = content
        panel.hasShadow = true

        let size = NSSize(width: 376, height: 148)
        let plan = ExcursionPresentationPlan.make(
            at: home,
            size: size,
            creatureOnRight: home.edge == .right,
            reducedMotion: appearance.reducedMotion,
            visibleFrame: visibleFrame(near: home.homePoint)
        )

        self.onDismiss = onDismiss
        onSnooze = optionalSnooze
        present(
            from: plan.startFrame,
            to: plan.destinationFrame,
            reducedMotion: plan.usesFade
        )
        scheduleAutoDismiss(after: 8)
    }

    private func present(from startFrame: NSRect, to destinationFrame: NSRect, reducedMotion: Bool) {
        panel.setFrame(reducedMotion ? destinationFrame : startFrame, display: true)
        panel.alphaValue = reducedMotion ? 0 : 1
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reducedMotion ? 0.2 : 0.35
            if reducedMotion {
                panel.animator().alphaValue = 1
            } else {
                panel.animator().setFrame(destinationFrame, display: true)
            }
        }
    }

    private func scheduleAutoDismiss(after interval: TimeInterval) {
        autoDismissTimer?.invalidate()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissCurrent(notify: true)
            }
        }
    }

    @objc private func dismissButtonPressed() {
        dismissCurrent(notify: true)
    }

    @objc private func snoozeButtonPressed() {
        let handler = onSnooze
        dismissCurrent(notify: false)
        handler?()
    }

    private func dismissCurrent(notify: Bool) {
        let dismissal = onDismiss
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        meetingView?.stopCountdown()
        meetingView = nil
        currentMeetingTitles = []
        panel.contentView = nil
        onDismiss = nil
        onSnooze = nil
        panel.orderOut(nil)
        panel.alphaValue = 1

        if notify {
            dismissal?()
        }
    }

    private func visibleFrame(near point: CGPoint) -> NSRect? {
        NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
    }
}

@MainActor
final class MeetingPresentationView: NSView {
    private let countdownLabel = NSTextField(labelWithString: "")
    private let start: Date
    private var countdownTimer: Timer?

    init(
        titles: [String],
        start: Date,
        appearance: TepalVisualState,
        creatureOnRight: Bool,
        target: AnyObject,
        dismissAction: Selector,
        snoozeAction: Selector?
    ) {
        self.start = start
        super.init(frame: NSRect(x: 0, y: 0, width: 376, height: 148))

        let creature = TepalTileView(
            frame: NSRect(x: 0, y: 0, width: 88, height: 88),
            displayDestination: .viewOnly,
            renderSurface: .excursion
        )
        creature.translatesAutoresizingMaskIntoConstraints = false
        creature.render(appearance.replacingPose(.meetingAttentive))

        let deepMoss = TepalTheme.palette(for: .moonFern)
        let bubble = NSVisualEffectView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.material = .hudWindow
        bubble.blendingMode = .withinWindow
        bubble.state = .active
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 16
        bubble.layer?.backgroundColor = deepMoss.habitatBase.withAlphaComponent(0.92).cgColor
        bubble.layer?.borderColor = deepMoss.habitatAccent.cgColor
        bubble.layer?.borderWidth = 1
        bubble.setAccessibilityIdentifier("meeting.bubble")

        let botanicalSignal = MeetingBotanicalSignalView(color: deepMoss.meetingCoral)
        botanicalSignal.translatesAutoresizingMaskIntoConstraints = false
        botanicalSignal.setAccessibilityLabel("Meeting botanical signal")
        botanicalSignal.setAccessibilityIdentifier("meeting.signal")

        let meetingLabel = NSTextField(labelWithString: (0...120).contains(start.timeIntervalSinceNow) ? "TIME TO PREPARE" : "MEETING")
        meetingLabel.font = .systemFont(ofSize: 12, weight: .bold)
        meetingLabel.textColor = deepMoss.primaryText
        meetingLabel.setAccessibilityIdentifier("meeting.context")

        let contextRow = NSStackView(views: [botanicalSignal, meetingLabel])
        contextRow.orientation = .horizontal
        contextRow.alignment = .centerY
        contextRow.spacing = 5

        let titleScroll = MeetingTitleListScrollView(titles: titles)
        titleScroll.translatesAutoresizingMaskIntoConstraints = false
        titleScroll.titleTextColor = deepMoss.primaryText

        let dateLabel = NSTextField(labelWithString: Self.timeFormatter.string(from: start))
        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = deepMoss.primaryText.withAlphaComponent(0.82)
        dateLabel.setAccessibilityLabel("Meeting start time")
        dateLabel.setAccessibilityIdentifier("meeting.start-time")

        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        countdownLabel.textColor = deepMoss.primaryText
        countdownLabel.setAccessibilityLabel("Time until meeting")
        countdownLabel.setAccessibilityIdentifier("meeting.countdown")

        let metadataRow = NSStackView(views: [dateLabel, countdownLabel])
        metadataRow.orientation = .horizontal
        metadataRow.alignment = .centerY
        metadataRow.distribution = .fillEqually
        metadataRow.spacing = 8

        let dismissButton = NSButton(title: "Dismiss", target: target, action: dismissAction)
        dismissButton.bezelStyle = .rounded
        dismissButton.bezelColor = deepMoss.meetingCoral
        dismissButton.contentTintColor = deepMoss.habitatBase
        dismissButton.setAccessibilityLabel("Dismiss meeting reminder")
        dismissButton.setAccessibilityIdentifier("meeting.dismiss")

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.addArrangedSubview(dismissButton)
        if let snoozeAction {
            let snoozeButton = NSButton(title: "Snooze 5 min", target: target, action: snoozeAction)
            snoozeButton.bezelStyle = .rounded
            snoozeButton.contentTintColor = deepMoss.primaryText
            snoozeButton.setAccessibilityLabel("Snooze meeting reminder for five minutes")
            snoozeButton.setAccessibilityIdentifier("meeting.snooze")
            buttonRow.addArrangedSubview(snoozeButton)
        }

        let textStack = NSStackView(views: [contextRow, titleScroll, metadataRow, buttonRow])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        bubble.addSubview(textStack)

        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        if creatureOnRight {
            row.addArrangedSubview(bubble)
            row.addArrangedSubview(creature)
        } else {
            row.addArrangedSubview(creature)
            row.addArrangedSubview(bubble)
        }
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            creature.widthAnchor.constraint(equalToConstant: 88),
            creature.heightAnchor.constraint(equalToConstant: 88),
            bubble.heightAnchor.constraint(equalToConstant: 132),
            textStack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
            botanicalSignal.widthAnchor.constraint(equalToConstant: 16),
            botanicalSignal.heightAnchor.constraint(equalToConstant: 16),
            titleScroll.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            titleScroll.heightAnchor.constraint(equalToConstant: 34),
            metadataRow.widthAnchor.constraint(equalTo: textStack.widthAnchor),
        ])
        for button in buttonRow.arrangedSubviews.compactMap({ $0 as? NSButton }) {
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }

        updateCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCountdown()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func updateCountdown() {
        let remaining = max(0, Int(start.timeIntervalSinceNow.rounded(.up)))
        countdownLabel.stringValue = String(format: "Starts in %d:%02d", remaining / 60, remaining % 60)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

@MainActor
private final class MeetingBotanicalSignalView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 5, y: 6, width: 7, height: 8)).fill()

        let leftLeaf = NSBezierPath()
        leftLeaf.move(to: CGPoint(x: 7, y: 7))
        leftLeaf.curve(
            to: CGPoint(x: 2, y: 10),
            controlPoint1: CGPoint(x: 5, y: 11),
            controlPoint2: CGPoint(x: 2, y: 12)
        )
        leftLeaf.curve(
            to: CGPoint(x: 7, y: 7),
            controlPoint1: CGPoint(x: 3, y: 8),
            controlPoint2: CGPoint(x: 5, y: 7)
        )
        leftLeaf.fill()

        let rightLeaf = NSBezierPath()
        rightLeaf.move(to: CGPoint(x: 10, y: 7))
        rightLeaf.curve(
            to: CGPoint(x: 15, y: 10),
            controlPoint1: CGPoint(x: 12, y: 11),
            controlPoint2: CGPoint(x: 15, y: 12)
        )
        rightLeaf.curve(
            to: CGPoint(x: 10, y: 7),
            controlPoint1: CGPoint(x: 14, y: 8),
            controlPoint2: CGPoint(x: 12, y: 7)
        )
        rightLeaf.fill()
    }
}

@MainActor
final class MeetingTitleListScrollView: NSScrollView {
    private let titleLabel: NSTextField

    init(titles: [String]) {
        titleLabel = NSTextField(
            wrappingLabelWithString: titles.map { "• \($0)" }.joined(separator: "\n")
        )
        super.init(frame: .zero)

        drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = true
        autohidesScrollers = true

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0
        titleLabel.setAccessibilityLabel(titles.count == 1 ? "Meeting title" : "Meeting titles")
        titleLabel.setAccessibilityValue(titles.joined(separator: ", "))
        titleLabel.setAccessibilityIdentifier("meeting.title")
        documentView = titleLabel
    }

    var titleTextColor: NSColor? {
        get { titleLabel.textColor }
        set { titleLabel.textColor = newValue }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func layout() {
        super.layout()
        let width = contentSize.width
        guard width > 0 else { return }
        let measurementBounds = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: .greatestFiniteMagnitude
        )
        let measuredHeight = titleLabel.cell?.cellSize(forBounds: measurementBounds).height ?? 0
        titleLabel.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: max(contentSize.height, measuredHeight)
        )
    }
}
