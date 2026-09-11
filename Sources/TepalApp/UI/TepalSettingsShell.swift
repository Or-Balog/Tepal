import TepalCore
import TepalMac
import SwiftUI

struct TepalSettingsShell<Content: View>: View {
    let palette: TepalPaletteID
    private let content: Content

    init(
        palette: TepalPaletteID = .moonFern,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.content = content()
    }

    private var theme: TepalPalette {
        TepalTheme.palette(for: palette)
    }

    var body: some View {
        content
            .foregroundStyle(Color(nsColor: theme.primaryText))
            .tint(Color(nsColor: theme.primaryAction))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(
                    colors: [
                        Color(nsColor: theme.habitatAccent),
                        Color(nsColor: theme.habitatBase),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .environment(\.colorScheme, .dark)
    }
}
