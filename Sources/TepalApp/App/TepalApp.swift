import AppKit
import TepalMac

@main
enum TepalApp {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--diagnose-knock") {
            let sensor = KnockSensorConnection()
            var streamReady = false
            sensor.onStatus = {
                print("KNOCK STATUS: \($0)"); fflush(stdout)
                if $0 == "Listening for a double-knock" { streamReady = true }
            }
            sensor.onKnock = { print("KNOCK RECEIVED"); fflush(stdout) }
            sensor.start()
            if KnockSensorConnection.supportsMotionInCurrentBuild {
                let deadline = Date().addingTimeInterval(25)
                while !streamReady && Date() < deadline {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                }
            }
            sensor.stop()
            exit(streamReady ? 0 : 2)
        }
        let application = NSApplication.shared
        let delegate = TepalApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
