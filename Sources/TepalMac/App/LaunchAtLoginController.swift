import ServiceManagement

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
private final class MainAppLaunchAtLoginService: LaunchAtLoginServicing {
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
public final class LaunchAtLoginController {
    private let service: any LaunchAtLoginServicing

    public var status: SMAppService.Status {
        service.status
    }

    public init() {
        service = MainAppLaunchAtLoginService()
    }

    init(service: any LaunchAtLoginServicing) {
        self.service = service
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
