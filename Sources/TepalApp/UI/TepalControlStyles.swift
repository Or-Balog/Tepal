import TepalCore
import TepalMac
import SwiftUI

struct TepalPrimaryButtonStyle: ButtonStyle {
    let palette: TepalPaletteID

    init(palette: TepalPaletteID = .moonFern) {
        self.palette = palette
    }

    func makeBody(configuration: Configuration) -> some View {
        let theme = TepalTheme.palette(for: palette)
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(nsColor: theme.habitatBase))
            .frame(maxWidth: .infinity, minHeight: TepalLayout.primaryControlHeight)
            .background(
                Color(nsColor: theme.primaryAction)
                    .opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct TepalCompactButtonStyle: ButtonStyle {
    let palette: TepalPaletteID

    init(palette: TepalPaletteID = .moonFern) {
        self.palette = palette
    }

    func makeBody(configuration: Configuration) -> some View {
        let theme = TepalTheme.palette(for: palette)
        configuration.label
            .foregroundStyle(Color(nsColor: theme.primaryText))
            .frame(
                width: TepalLayout.compactControlWidth,
                height: TepalLayout.primaryControlHeight
            )
            .background(
                Color(nsColor: theme.habitatAccent)
                    .opacity(configuration.isPressed ? 0.70 : 1),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color(nsColor: theme.divider), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
