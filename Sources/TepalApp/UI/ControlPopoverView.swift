import SwiftUI

struct ControlPanelRootView: View {
    let coordinator: AppCoordinator
    let onCompleteOrDismiss: () -> Void
    let onOpenSettings: (SettingsDestination) -> Void

    var body: some View {
        Group {
            if coordinator.settings.onboardingCompleted {
                ControlPopoverView(
                    coordinator: coordinator,
                    onDismiss: onCompleteOrDismiss,
                    onOpenSettings: onOpenSettings
                )
            } else {
                OnboardingView(
                    coordinator: coordinator,
                    onComplete: onCompleteOrDismiss
                )
            }
        }
    }
}

struct ControlPopoverView: View {
    let coordinator: AppCoordinator
    let onDismiss: () -> Void
    let onOpenSettings: (SettingsDestination) -> Void

    var body: some View {
        LivingTerrariumContainer(
            coordinator: coordinator,
            onDismiss: onDismiss,
            onOpenSettings: onOpenSettings
        )
    }
}
