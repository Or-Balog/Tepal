import AppKit
import TepalMac
import SwiftUI

enum ControlPanelPresentationAction: Equatable {
    case showAndMakeKey
    case makeKey
}

enum ControlPanelInteractionPolicy {
    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    static let activatesApplication = false

    static func presentationAction(isVisible: Bool) -> ControlPanelPresentationAction {
        isVisible ? .makeKey : .showAndMakeKey
    }
}

final class KeyableControlPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

enum ControlPanelPlacement {
    static func frame(
        size: CGSize,
        home: DockGeometry,
        screens: [ScreenGeometry]
    ) -> CGRect {
        guard let screen = activeScreen(for: home.homePoint, screens: screens) else {
            return CGRect(origin: .zero, size: size)
        }

        let resolvedHome = screen.frame.contains(home.homePoint)
            && home.homePoint.x.isFinite
            && home.homePoint.y.isFinite
            ? home
            : DockHomeLocator.locate(pointer: nil, screens: [screen])
        let visible = screen.visibleFrame
        let size = CGSize(width: size.width, height: min(size.height, visible.height))
        let gap: CGFloat = 14
        let origin: CGPoint
        switch resolvedHome.edge {
        case .bottom:
            origin = CGPoint(
                x: resolvedHome.homePoint.x - size.width / 2,
                y: max(resolvedHome.homePoint.y + gap, visible.minY + gap)
            )
        case .left:
            origin = CGPoint(
                x: resolvedHome.homePoint.x + gap,
                y: resolvedHome.homePoint.y - size.height / 2
            )
        case .right:
            origin = CGPoint(
                x: resolvedHome.homePoint.x - size.width - gap,
                y: resolvedHome.homePoint.y - size.height / 2
            )
        case .unknown:
            origin = CGPoint(
                x: resolvedHome.homePoint.x - size.width / 2,
                y: resolvedHome.homePoint.y - size.height / 2
            )
        }

        return CGRect(
            x: min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width)),
            y: min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height)),
            width: size.width,
            height: size.height
        )
    }

    private static func activeScreen(
        for point: CGPoint,
        screens: [ScreenGeometry]
    ) -> ScreenGeometry? {
        screens.first(where: { $0.frame.contains(point) }) ?? screens.first
    }
}

@MainActor
final class MouseClickMonitorToken: NSObject {
    let rawValue: Any

    init(_ rawValue: Any) {
        self.rawValue = rawValue
    }
}

@MainActor
final class OutsideClickMonitorLifecycle {
    typealias InstallMonitor = (@escaping () -> Void) -> MouseClickMonitorToken?

    private let installLocalMonitor: InstallMonitor
    private let installGlobalMonitor: InstallMonitor
    private let removeMonitor: (MouseClickMonitorToken) -> Void
    private var localMonitor: MouseClickMonitorToken?
    private var globalMonitor: MouseClickMonitorToken?

    init(
        installLocal: @escaping InstallMonitor,
        installGlobal: @escaping InstallMonitor,
        remove: @escaping (MouseClickMonitorToken) -> Void
    ) {
        installLocalMonitor = installLocal
        installGlobalMonitor = installGlobal
        removeMonitor = remove
    }

    func install(onClick: @escaping () -> Void) {
        remove()
        localMonitor = installLocalMonitor(onClick)
        globalMonitor = installGlobalMonitor(onClick)
    }

    func remove() {
        let installedLocal = localMonitor
        let installedGlobal = globalMonitor
        localMonitor = nil
        globalMonitor = nil
        if let installedLocal { removeMonitor(installedLocal) }
        if let installedGlobal { removeMonitor(installedGlobal) }
    }

    isolated deinit {
        if let localMonitor { removeMonitor(localMonitor) }
        if let globalMonitor { removeMonitor(globalMonitor) }
    }
}

@MainActor
final class ControlPanelController: NSObject, NSWindowDelegate {
    static let panelSize = TepalLayout.panelSize

    private let panel: KeyableControlPanel
    private let monitorLifecycle: OutsideClickMonitorLifecycle
    private let screenGeometries: () -> [ScreenGeometry]
    private weak var coordinator: AppCoordinator?
    private var openSettings: (SettingsDestination) -> Void = { _ in }

    var isPresented: Bool { panel.isVisible }

    init(
        screenGeometries: @escaping () -> [ScreenGeometry] = {
            NSScreen.screens.map {
                ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame)
            }
        },
        monitorLifecycle: OutsideClickMonitorLifecycle? = nil
    ) {
        panel = KeyableControlPanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize),
            styleMask: ControlPanelInteractionPolicy.styleMask,
            backing: .buffered,
            defer: false
        )
        self.monitorLifecycle = monitorLifecycle ?? OutsideClickMonitorLifecycle(
            installLocal: { onClick in
                guard let token = NSEvent.addLocalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
                    handler: { event in
                        onClick()
                        return event
                    }
                ) else { return nil }
                return MouseClickMonitorToken(token)
            },
            installGlobal: { onClick in
                guard let token = NSEvent.addGlobalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
                    handler: { _ in onClick() }
                ) else { return nil }
                return MouseClickMonitorToken(token)
            },
            remove: { NSEvent.removeMonitor($0.rawValue) }
        )
        self.screenGeometries = screenGeometries
        super.init()

        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setAccessibilityLabel("Tepal controls")
        panel.setAccessibilityIdentifier("tepal.control-panel")
        panel.onCancel = { [weak self] in self?.close() }
    }

    isolated deinit {
        monitorLifecycle.remove()
    }

    func configure(
        coordinator: AppCoordinator,
        openSettings: @escaping (SettingsDestination) -> Void
    ) {
        self.coordinator = coordinator
        self.openSettings = openSettings
    }

    func routeSettings(_ destination: SettingsDestination) {
        openSettings(destination)
    }

    func toggle(from home: DockGeometry) {
        isPresented ? close() : show(from: home)
    }

    func ensurePresented(from home: DockGeometry) {
        switch ControlPanelInteractionPolicy.presentationAction(isVisible: isPresented) {
        case .showAndMakeKey:
            show(from: home)
        case .makeKey:
            panel.makeKey()
        }
    }

    func show(from home: DockGeometry) {
        guard let coordinator else { return }
        let frame = ControlPanelPlacement.frame(
            size: Self.panelSize, home: home, screens: screenGeometries()
        )
        let content = ControlPanelRootView(coordinator: coordinator) { [weak self] in
            self?.close()
        } onOpenSettings: { [weak self] destination in
            self?.routeSettings(destination)
        }
        panel.contentViewController = NSHostingController(
            rootView: Group {
                if frame.height < Self.panelSize.height {
                    ScrollView(.vertical) { content }
                } else {
                    content
                }
            }
            .frame(width: frame.width, height: frame.height)
        )
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitor()
    }

    func close() {
        monitorLifecycle.remove()
        panel.orderOut(nil)
        panel.contentViewController = nil
    }

    func windowWillClose(_ notification: Notification) {
        monitorLifecycle.remove()
    }

    private func installOutsideClickMonitor() {
        monitorLifecycle.install { [weak self] in
            guard let self else { return }
            if !self.panel.frame.contains(NSEvent.mouseLocation) {
                self.close()
            }
        }
    }
}
