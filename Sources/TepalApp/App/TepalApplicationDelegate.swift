import AppKit
import TepalCore
import TepalMac

enum TepalApplicationCommand {
    case primary
    case showSettings
}

@MainActor
struct TepalApplicationCommandRouter {
    let performPrimary: () -> Void
    let showSettings: (SettingsDestination) -> Void

    func perform(_ command: TepalApplicationCommand) {
        switch command {
        case .primary:
            performPrimary()
        case .showSettings:
            openSettings(.preferences)
        }
    }

    func openSettings(_ destination: SettingsDestination) {
        showSettings(destination)
    }
}

enum DockMenuPresentation {
    static func primaryTitle(for pomodoro: PomodoroSnapshot) -> String {
        switch pomodoro.phase {
        case .idle:
            "Start Focus"
        case .focus, .shortBreak, .longBreak:
            pomodoro.isPaused ? "Resume \(phaseName(pomodoro.phase))" : "Pause \(phaseName(pomodoro.phase))"
        }
    }

    static func ambientTitle(enabled: Bool) -> String {
        enabled ? "Pause Ambient Excursions" : "Resume Ambient Excursions"
    }

    private static func phaseName(_ phase: PomodoroPhase) -> String {
        switch phase {
        case .idle, .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }
}

@MainActor
struct TepalApplicationWiring {
    let rendererFactory: DockTileSemanticRendererFactory
    let soundPlayer: any LocalSoundPlaying

    init(
        rendererFactory: DockTileSemanticRendererFactory = .production,
        soundPlayer: any LocalSoundPlaying = AppKitLocalSoundPlayer()
    ) {
        self.rendererFactory = rendererFactory
        self.soundPlayer = soundPlayer
    }

    func makeTileInstallation(frame: NSRect) -> DockTileRendererInstallation {
        DockTileRendererInstallation(
            frame: frame,
            rendererFactory: rendererFactory
        )
    }

    func makeSoundPlayer() -> any LocalSoundPlaying {
        soundPlayer
    }
}

@MainActor
final class TepalApplicationDelegate: NSObject, NSApplicationDelegate {
    let tileInstallation: DockTileRendererInstallation
    let soundPlayer: any LocalSoundPlaying
    private let excursionController = ExcursionPanelController()
    private let controlPanelController = ControlPanelController()
    private let settingsWindowController = SettingsWindowController()
    private let settingsStore = SettingsStore()
    private var historyStoreController: HistoryStoreController?
    private var commandRouter: TepalApplicationCommandRouter?

    private(set) var coordinator: AppCoordinator?

    static func makeControlPanelSettingsCallback(
        hideControlPanel: @escaping () -> Void,
        commandRouter: TepalApplicationCommandRouter
    ) -> (SettingsDestination) -> Void {
        { destination in
            hideControlPanel()
            commandRouter.openSettings(destination)
        }
    }

    init(wiring: TepalApplicationWiring = TepalApplicationWiring()) {
        tileInstallation = wiring.makeTileInstallation(
            frame: NSRect(x: 0, y: 0, width: 128, height: 128)
        )
        soundPlayer = wiring.makeSoundPlayer()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Put the motion sensor's reporting interval back if a previous run ended
        // abruptly while double-knock was listening.
        SensorReportIntervalGuard.restorePendingChange()
        NSApp.dockTile.contentView = tileInstallation.contentView
        let historyStoreController = HistoryStoreController()
        let controlPanelController = controlPanelController
        let coordinator = AppCoordinator(
            settingsStore: settingsStore,
            historyStore: historyStoreController,
            soundPlayer: soundPlayer,
            tileView: tileInstallation.semanticRenderer,
            excursionController: excursionController,
            toggleControlPanel: { [weak controlPanelController] home in
                controlPanelController?.toggle(from: home)
            },
            ensureControlPanelPresented: { [weak controlPanelController] home in
                controlPanelController?.ensurePresented(from: home)
            }
        )
        self.historyStoreController = historyStoreController
        self.coordinator = coordinator
        let commandRouter = TepalApplicationCommandRouter(
            performPrimary: { [weak coordinator] in coordinator?.performDockPrimaryAction() },
            showSettings: { [weak self] destination in
                self?.showOwnedSettings(destination)
            }
        )
        self.commandRouter = commandRouter
        controlPanelController.configure(
            coordinator: coordinator,
            openSettings: Self.makeControlPanelSettingsCallback(
                hideControlPanel: { [weak controlPanelController] in
                    controlPanelController?.close()
                },
                commandRouter: commandRouter
            )
        )
        coordinator.start()
        coordinator.activateControlPanel()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        coordinator?.activateControlPanel()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.terminate()
        controlPanelController.close()
        settingsWindowController.close()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let coordinator else { return nil }
        let menu = NSMenu(title: "Tepal")

        let primary = NSMenuItem(
            title: DockMenuPresentation.primaryTitle(for: coordinator.pomodoro),
            action: #selector(primaryDockAction),
            keyEquivalent: ""
        )
        primary.target = self
        menu.addItem(primary)

        let skip = NSMenuItem(
            title: "Skip Phase",
            action: #selector(skipPhase),
            keyEquivalent: ""
        )
        skip.target = self
        skip.isEnabled = coordinator.pomodoro.phase != .idle
        menu.addItem(skip)

        let ambient = NSMenuItem(
            title: DockMenuPresentation.ambientTitle(
                enabled: coordinator.settings.ambientExcursionsEnabled
            ),
            action: #selector(toggleAmbientExcursions),
            keyEquivalent: ""
        )
        ambient.target = self
        menu.addItem(ambient)

        menu.addItem(.separator())
        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit Tepal",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func primaryDockAction() {
        commandRouter?.perform(.primary)
    }

    @objc private func skipPhase() {
        coordinator?.skipPhase()
    }

    @objc private func toggleAmbientExcursions() {
        guard let coordinator else { return }
        coordinator.setAmbientExcursionsEnabled(
            !coordinator.settings.ambientExcursionsEnabled
        )
    }

    @objc private func showSettings() {
        commandRouter?.perform(.showSettings)
    }

    private func showOwnedSettings(_ destination: SettingsDestination) {
        guard let coordinator, let historyStoreController else { return }
        controlPanelController.close()
        settingsWindowController.show(
            destination: destination,
            coordinator: coordinator,
            historyStoreController: historyStoreController
        )
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}
