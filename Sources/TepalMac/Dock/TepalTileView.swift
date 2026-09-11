import AppKit
import TepalCore

public enum DockTileAnimationOwner: Equatable, Sendable {
    case legacyProbe
    case semanticRenderer
}

public enum DockTileDisplayDestination: Equatable, Sendable {
    case applicationDockTile
    case viewOnly
}

public enum TepalDockMotion {
    public static func framesPerSecond(for state: TepalVisualState) -> Double {
        guard !state.reducedMotion else { return 0 }
        switch state.pose {
        case .staticFallback, .meetingAttentive: return 0
        case .keepingWatch, .resting, .preparingFocus: return 6
        default: return 12
        }
    }
}

@MainActor
public final class TepalTileView: NSView {
    public let displayDestination: DockTileDisplayDestination
    public private(set) var renderedSurface = TepalRenderSurface.dock
    public private(set) var renderedVisualState = TepalVisualState(
        pose: .staticFallback,
        timerProgress: 0,
        palette: .moonFern,
        growth: TepalGrowthProfile(completedFocuses: 0),
        reducedMotion: true
    )
    private var frameIndex = 0
    private var animationTimer: Timer?
    private(set) var animationInterval: TimeInterval?
    private let requestDockDisplay: @MainActor () -> Void
    public private(set) var animationOwner: DockTileAnimationOwner = .legacyProbe

    public var isAnimating: Bool {
        animationTimer != nil
    }

    public var acceptsLegacyProbeRedraws: Bool {
        animationOwner == .legacyProbe
    }

    public override init(frame frameRect: NSRect) {
        displayDestination = .applicationDockTile
        requestDockDisplay = { NSApp?.dockTile.display() }
        super.init(frame: frameRect)
    }

    public init(
        frame frameRect: NSRect,
        displayDestination: DockTileDisplayDestination,
        renderSurface: TepalRenderSurface
    ) {
        self.displayDestination = displayDestination
        renderedSurface = displayDestination == .applicationDockTile ? .dock : renderSurface
        requestDockDisplay = { NSApp?.dockTile.display() }
        super.init(frame: frameRect)
    }

    public convenience init?(validatedDockFrame frameRect: NSRect) {
        guard frameRect.width.isFinite,
              frameRect.height.isFinite,
              frameRect.width > 0,
              frameRect.height > 0
        else {
            return nil
        }
        self.init(
            frame: frameRect,
            displayDestination: .applicationDockTile,
            renderSurface: .dock
        )
    }

    init(
        frame frameRect: NSRect,
        displayDestination: DockTileDisplayDestination,
        renderSurface: TepalRenderSurface,
        requestDockDisplay: @escaping @MainActor () -> Void
    ) {
        self.displayDestination = displayDestination
        renderedSurface = displayDestination == .applicationDockTile ? .dock : renderSurface
        self.requestDockDisplay = requestDockDisplay
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    isolated deinit {
        animationTimer?.invalidate()
    }

    public func render(_ visualState: TepalVisualState) {
        let poseChanged = renderedVisualState.pose != visualState.pose
        renderedVisualState = visualState
        animationOwner = .semanticRenderer

        if poseChanged || visualState.reducedMotion {
            frameIndex = 0
        }

        configureAnimationTimer()
        requestDisplay()
    }

    // Retained for the Dock ownership probe while callers transition to semantic rendering.
    public func setFrame(index: Int) {
        guard acceptsLegacyProbeRedraws else { return }
        frameIndex = max(index, 0)
        requestDisplay()
    }

    public func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationInterval = nil
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let graphics = NSGraphicsContext.current?.cgContext else { return }
        TepalVectorRenderer.draw(
            state: renderedVisualState,
            surface: renderedSurface,
            illustrated: true,
            frameIndex: frameIndex,
            in: graphics,
            bounds: bounds
        )
    }

    private func configureAnimationTimer() {
        let framesPerSecond = TepalDockMotion.framesPerSecond(for: renderedVisualState)
        guard framesPerSecond > 0 else {
            stopAnimation()
            return
        }

        let interval = 1 / framesPerSecond
        guard animationInterval != interval || animationTimer == nil else { return }

        animationTimer?.invalidate()
        animationInterval = interval
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advanceAnimation()
            }
        }
    }

    private func advanceAnimation() {
        frameIndex += 1
        requestDisplay()
    }

    private func requestDisplay() {
        needsDisplay = true
        if displayDestination == .applicationDockTile {
            requestDockDisplay()
        }
    }
}

@MainActor
public final class StaticTepalIconView: NSView {
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let graphics = NSGraphicsContext.current?.cgContext else { return }
        TepalVectorRenderer.draw(
            state: TepalVisualState(
                pose: .staticFallback,
                timerProgress: 0,
                palette: .moonFern,
                growth: TepalGrowthProfile(completedFocuses: 0),
                reducedMotion: true
            ),
            surface: .dock,
            illustrated: true,
            frameIndex: 0,
            in: graphics,
            bounds: bounds
        )
    }
}

@MainActor
public struct DockTileSemanticRendererFactory {
    private let makeRenderer: @MainActor (NSRect) -> TepalTileView?

    public init(makeRenderer: @escaping @MainActor (NSRect) -> TepalTileView?) {
        self.makeRenderer = makeRenderer
    }

    public func makeRenderer(frame: NSRect) -> TepalTileView? {
        makeRenderer(frame)
    }

    public static var production: DockTileSemanticRendererFactory {
        DockTileSemanticRendererFactory { frame in
            TepalTileView(
                validatedDockFrame: frame
            )
        }
    }
}

@MainActor
public final class DockTileRendererInstallation {
    public let semanticRenderer: TepalTileView?
    public let contentView: NSView

    public init(
        frame: NSRect,
        rendererFactory: DockTileSemanticRendererFactory = .production
    ) {
        let renderer = rendererFactory.makeRenderer(frame: frame)
        semanticRenderer = renderer
        contentView = renderer ?? StaticTepalIconView(frame: frame)
    }

    convenience init(
        frame: NSRect,
        makeSemanticRenderer: @escaping @MainActor @Sendable (NSRect) -> TepalTileView?
    ) {
        self.init(
            frame: frame,
            rendererFactory: DockTileSemanticRendererFactory(
                makeRenderer: makeSemanticRenderer
            )
        )
    }
}
