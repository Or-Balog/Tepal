import ServiceManagement
import Testing
@testable import TepalMac

@MainActor
struct LaunchAtLoginControllerTests {
    @Test func registrationChangesOnlyWhenTheExplicitToggleActionRuns() throws {
        // Break caught: constructing or reading the controller silently edits the user's login items.
        let service = TestLaunchAtLoginService(status: .notRegistered)
        let controller = LaunchAtLoginController(service: service)

        #expect(controller.status == .notRegistered)
        #expect(service.registerCount == 0)
        #expect(service.unregisterCount == 0)

        try controller.setEnabled(true)
        #expect(controller.status == .enabled)
        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 0)

        try controller.setEnabled(false)
        #expect(controller.status == .notRegistered)
        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 1)
    }

    @Test func failedRegistrationReportsTheErrorAndKeepsTheActualServiceStatus() {
        // Break caught: a failed enable attempt is reported as enabled even though ServiceManagement rejected it.
        let expected = TestLaunchAtLoginError.registrationRejected
        let service = TestLaunchAtLoginService(
            status: .notRegistered,
            registerError: expected
        )
        let controller = LaunchAtLoginController(service: service)

        #expect(throws: TestLaunchAtLoginError.registrationRejected) {
            try controller.setEnabled(true)
        }
        #expect(controller.status == .notRegistered)
        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 0)
    }
}

@MainActor
private final class TestLaunchAtLoginService: LaunchAtLoginServicing {
    private(set) var status: SMAppService.Status
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private let registerError: (any Error)?
    private let unregisterError: (any Error)?

    init(
        status: SMAppService.Status,
        registerError: (any Error)? = nil,
        unregisterError: (any Error)? = nil
    ) {
        self.status = status
        self.registerError = registerError
        self.unregisterError = unregisterError
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }
}

private enum TestLaunchAtLoginError: Error {
    case registrationRejected
}
