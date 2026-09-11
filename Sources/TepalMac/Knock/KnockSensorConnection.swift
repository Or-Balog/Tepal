import Foundation
import Security
import TepalCore

/// App-owned bridge: acquisition runs independently of windows on a dedicated
/// run-loop thread; only status and recognized gestures reach the main actor.
@MainActor
public final class KnockSensorConnection {
    private var worker: MotionSensorWorker?
    private var generation: UInt = 0
    public var onKnock: () -> Void = {}
    public var onStatus: (String) -> Void = { _ in }
    public init() {}

    isolated deinit { stop() }

    public static var supportsMotionInCurrentBuild: Bool {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any] else { return false }
        let entitlements = information[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        return (entitlements?["com.apple.security.app-sandbox"] as? Bool) != true
    }

    public func start() {
        guard worker == nil else { return }
        guard Self.supportsMotionInCurrentBuild else {
            onStatus("Double-knock is unavailable in this sandboxed build. Preview next event still works.")
            return
        }
        generation &+= 1
        let current = generation
        let worker = MotionSensorWorker { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.generation == current, self.worker != nil else { return }
                switch event {
                case .status(let message): self.onStatus(message)
                case .knock: self.onKnock()
                }
            }
        }
        self.worker = worker
        worker.start()
    }

    public func stop() {
        generation &+= 1
        let old = worker; worker = nil
        old?.stop()
    }
    public func retry() { stop(); start() }
}
