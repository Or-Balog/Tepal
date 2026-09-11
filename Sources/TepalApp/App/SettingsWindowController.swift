import AppKit
import TepalMac
import SwiftUI

enum SettingsDestination: String, CaseIterable, Hashable {
    case preferences
    case history

    var tabTitle: String {
        switch self {
        case .preferences: "Settings"
        case .history: "History"
        }
    }
}

enum SettingsWindowPresentationAction: Equatable {
    case create
    case reuse
}

enum SettingsWindowPresentationPolicy {
    static func action(hasOwnedWindow: Bool) -> SettingsWindowPresentationAction {
        hasOwnedWindow ? .reuse : .create
    }
}

struct SettingsWindowPresentationState: Equatable {
    let destination: SettingsDestination
    let windowIdentity: ObjectIdentifier
    let hostingControllerIdentity: ObjectIdentifier
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var ownedWindow: NSWindow?

    var isPresented: Bool { ownedWindow?.isVisible == true }
    var presentationState: SettingsWindowPresentationState? {
        guard let ownedWindow,
              let hostingController = ownedWindow.contentViewController
                as? NSHostingController<SettingsView>
        else {
            return nil
        }
        return SettingsWindowPresentationState(
            destination: hostingController.rootView.initialDestination,
            windowIdentity: ObjectIdentifier(ownedWindow),
            hostingControllerIdentity: ObjectIdentifier(hostingController)
        )
    }

    func show(
        destination: SettingsDestination,
        coordinator: AppCoordinator,
        historyStoreController: HistoryStoreController
    ) {
        switch SettingsWindowPresentationPolicy.action(hasOwnedWindow: ownedWindow != nil) {
        case .create:
            ownedWindow = makeWindow(
                destination: destination
            )
        case .reuse:
            break
        }

        guard let ownedWindow else { return }
        ownedWindow.title = "Tepal \(destination.tabTitle)"
        ownedWindow.contentViewController = NSHostingController(
            rootView: SettingsView(
                initialDestination: destination,
                coordinator: coordinator,
                historyStoreController: historyStoreController
            )
        )
        NSApp.activate(ignoringOtherApps: true)
        ownedWindow.makeKeyAndOrderFront(nil)
    }

    func close() {
        ownedWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === ownedWindow
        else {
            return
        }
        closingWindow.contentViewController = nil
        ownedWindow = nil
    }

    private func makeWindow(
        destination: SettingsDestination
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 820, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tepal \(destination.tabTitle)"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 700, height: 560)
        window.setAccessibilityLabel("Tepal settings and history")
        window.setAccessibilityIdentifier("tepal.settings-window")
        window.center()
        return window
    }
}
