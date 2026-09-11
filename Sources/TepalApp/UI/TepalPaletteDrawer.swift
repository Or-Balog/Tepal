import AppKit
import TepalCore
import TepalMac
import SwiftUI

struct TepalPaletteCardState: Identifiable, Equatable {
    let id: TepalPaletteID
    let name: String
    let isSelected: Bool
    let isLocked: Bool
    let unlockRequirement: Int?
    let accessibilityValue: String
}

enum TepalPalettePresentation {
    static func cards(
        profile: TepalGrowthProfile,
        selected: TepalPaletteID
    ) -> [TepalPaletteCardState] {
        TepalPaletteID.allCases.map { palette in
            let requirement = unlockRequirement(for: palette)
            let isLocked = !profile.availablePalettes.contains(palette)
            let isSelected = !isLocked && selected == palette
            let accessibilityValue: String
            if isSelected {
                accessibilityValue = "Selected"
            } else if isLocked, let requirement {
                accessibilityValue = "Locked. Unlock at \(requirement) completed focuses"
            } else {
                accessibilityValue = "Available"
            }

            return TepalPaletteCardState(
                id: palette,
                name: name(for: palette),
                isSelected: isSelected,
                isLocked: isLocked,
                unlockRequirement: requirement,
                accessibilityValue: accessibilityValue
            )
        }
    }

    static func selectionIntent(for card: TepalPaletteCardState) -> TepalPaletteID? {
        card.isLocked ? nil : card.id
    }

    static func unlockLine(for palette: TepalPaletteID) -> String {
        switch palette {
        case .moonFern: "Tepal has settled into the glade."
        case .twilightPlum: "Twilight has deepened around the glade."
        case .dewdrop: "A clear new color gathers on the moss."
        case .pollenGold: "A warm color found its way into the glade."
        case .emberMoss: "A quiet ember now glows among the moss."
        case .frostBloom: "A cool bloom has opened in the glade."
        }
    }

    static func name(for palette: TepalPaletteID) -> String {
        switch palette {
        case .moonFern: "Moon Fern"
        case .twilightPlum: "Twilight Plum"
        case .dewdrop: "Dewdrop"
        case .pollenGold: "Pollen Gold"
        case .emberMoss: "Ember Moss"
        case .frostBloom: "Frost Bloom"
        }
    }

    private static func unlockRequirement(for palette: TepalPaletteID) -> Int? {
        switch palette {
        case .moonFern, .twilightPlum, .dewdrop: nil
        case .pollenGold: 4
        case .emberMoss: 12
        case .frostBloom: 25
        }
    }
}

enum TepalPaletteDrawerPresentation {
    static func previewState(for visualState: TepalVisualState) -> TepalVisualState {
        visualState
    }

    static func growthLine(for profile: TepalGrowthProfile) -> String {
        guard let milestone = profile.nextMilestone else {
            return "Every palette is in bloom."
        }
        let remaining = max(0, milestone - profile.completedFocuses)
        let focusLabel = remaining == 1 ? "focus" : "focuses"
        return "\(remaining) \(focusLabel) until Leaf \(leafNumber(for: nextTier(after: profile.tier)))"
    }

    private static func nextTier(after tier: TepalGrowthTier) -> TepalGrowthTier {
        switch tier {
        case .seedling: .glowing
        case .glowing: .sprouted
        case .sprouted: .flourishing
        case .flourishing: .mature
        case .mature: .mature
        }
    }

    private static func leafNumber(for tier: TepalGrowthTier) -> String {
        switch tier {
        case .seedling: "01"
        case .glowing: "02"
        case .sprouted: "03"
        case .flourishing: "04"
        case .mature: "05"
        }
    }
}

enum TepalPalettePreviewStatus: Equatable {
    case ready
    case unavailable

    var message: String? {
        switch self {
        case .ready: nil
        case .unavailable: "Preview unavailable. Your current palette is unchanged."
        }
    }
}

struct TepalUnlockPresentationState: Equatable {
    let palette: TepalPaletteID
    let selectedPalette: TepalPaletteID
    let line: String
}

enum TepalUnlockPresentation {
    static func make(
        unlocked: TepalPaletteID,
        selected: TepalPaletteID
    ) -> TepalUnlockPresentationState {
        TepalUnlockPresentationState(
            palette: unlocked,
            selectedPalette: selected,
            line: TepalPalettePresentation.unlockLine(for: unlocked)
        )
    }
}

struct TepalPaletteDrawer: View {
    @Environment(\.dismiss) private var dismiss

    let visualState: TepalVisualState
    let previewStatus: TepalPalettePreviewStatus
    let onSelect: (TepalPaletteID) -> Void

    init(
        visualState: TepalVisualState,
        previewStatus: TepalPalettePreviewStatus = .ready,
        onSelect: @escaping (TepalPaletteID) -> Void
    ) {
        self.visualState = visualState
        self.previewStatus = previewStatus
        self.onSelect = onSelect
    }

    private var cards: [TepalPaletteCardState] {
        TepalPalettePresentation.cards(
            profile: visualState.growth,
            selected: visualState.palette
        )
    }

    private var palette: TepalPalette {
        TepalTheme.palette(for: visualState.palette)
    }

    private var previewState: TepalVisualState {
        TepalPaletteDrawerPresentation.previewState(for: visualState)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            drawerHeader

            growthSummary

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(cards) { card in
                    TepalPaletteCard(card: card, onSelect: onSelect)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 330)
        .background(Color(nsColor: palette.habitatBase))
        .foregroundStyle(Color(nsColor: palette.primaryText))
        .environment(\.colorScheme, .dark)
    }

    private var drawerHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            preview
            VStack(alignment: .leading, spacing: 3) {
                Text("Palettes & Growth")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("\(LivingTerrariumPresentation.leafLabel(for: visualState.growth.tier)) · \(LivingTerrariumPresentation.growthTitle(for: visualState.growth.tier))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(nsColor: palette.secondaryText))
                Text("Choose a color for Tepal")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color(nsColor: palette.primaryText).opacity(0.72))
            }
            Spacer(minLength: 0)
            Button(action: dismiss.callAsFunction) {
                Text("Done")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TepalCompactTextButtonStyle(palette: visualState.palette))
            .accessibilityLabel("Close palettes and growth")
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: palette.habitatAccent),
                            Color(nsColor: palette.habitatBase),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            if previewStatus == .ready {
                TepalCanvasView(state: previewState, surface: .preview)
                    .padding(6)
            } else {
                TepalCanvasView(
                    state: previewState.replacingPose(.staticFallback),
                    surface: .preview
                )
                .padding(6)
            }
        }
        .frame(width: 76, height: 68)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: palette.divider), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tepal preview")
        .accessibilityValue(
            "\(TepalPalettePresentation.name(for: previewState.palette)) palette, \(LivingTerrariumPresentation.growthTitle(for: previewState.growth.tier)) growth"
        )
    }

    private var growthSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<TepalGrowthTier.allCases.count, id: \.self) { index in
                    Capsule()
                        .fill(
                            Color(nsColor: index <= growthTierIndex ? palette.leaf : palette.divider)
                                .opacity(index <= growthTierIndex ? 0.88 : 0.72)
                        )
                        .frame(height: 5)
                }
            }
            Text(TepalPaletteDrawerPresentation.growthLine(for: visualState.growth))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color(nsColor: palette.secondaryText))
            if let message = previewStatus.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(nsColor: palette.primaryText))
                    .accessibilityIdentifier("palette.preview-status")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tepal growth")
        .accessibilityValue(TepalPaletteDrawerPresentation.growthLine(for: visualState.growth))
    }

    private var growthTierIndex: Int {
        TepalGrowthTier.allCases.firstIndex(of: visualState.growth.tier) ?? 0
    }
}

struct TepalUnlockReveal: NSViewRepresentable {
    let state: TepalUnlockPresentationState
    let onViewPalette: () -> Void
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> TepalUnlockRevealView {
        TepalUnlockRevealView(
            state: state,
            onViewPalette: onViewPalette,
            onDismiss: onDismiss
        )
    }

    func updateNSView(_ reveal: TepalUnlockRevealView, context: Context) {
        reveal.update(
            state: state,
            onViewPalette: onViewPalette,
            onDismiss: onDismiss
        )
    }
}

@MainActor
final class TepalUnlockRevealView: NSVisualEffectView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let lineLabel = NSTextField(wrappingLabelWithString: "")
    private let viewPaletteButton = TepalAccessibleButton(title: "VIEW PALETTE", target: nil, action: nil)
    private let dismissButton = TepalAccessibleButton(title: "Dismiss", target: nil, action: nil)
    private var onViewPalette: () -> Void = {}
    private var onDismiss: () -> Void = {}

    init(
        state: TepalUnlockPresentationState,
        onViewPalette: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        self.state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        setAccessibilityElement(false)
        setAccessibilityIdentifier("terrarium.unlock-reveal")

        configureSubviews()
        update(state: state, onViewPalette: onViewPalette, onDismiss: onDismiss)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        state: TepalUnlockPresentationState,
        onViewPalette: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onViewPalette = onViewPalette
        self.onDismiss = onDismiss

        let palette = TepalTheme.palette(for: state.palette)
        let name = TepalPalettePresentation.name(for: state.palette)
        titleLabel.stringValue = "\(name) unlocked"
        lineLabel.stringValue = state.line
        titleLabel.textColor = palette.primaryText
        lineLabel.textColor = palette.primaryText.withAlphaComponent(0.76)
        layer?.backgroundColor = palette.habitatAccent.cgColor
        layer?.borderColor = palette.primaryAction.withAlphaComponent(0.65).cgColor
        viewPaletteButton.contentTintColor = palette.primaryAction
        dismissButton.contentTintColor = palette.primaryText
        viewPaletteButton.setAccessibilityLabel("View the unlocked \(name) palette")
        viewPaletteButton.setAccessibilityValue("Opens the palette library without selecting this palette")
        dismissButton.setAccessibilityLabel("Dismiss \(name) unlock")
        dismissButton.setAccessibilityValue("Keeps Tepal's current palette")
    }

    private func configureSubviews() {
        [titleLabel, lineLabel].forEach {
            $0.setAccessibilityElement(false)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        lineLabel.font = .systemFont(ofSize: 12)
        lineLabel.maximumNumberOfLines = 2
        lineLabel.lineBreakMode = .byTruncatingTail

        configure(button: viewPaletteButton, action: #selector(viewPalettePressed))
        configure(button: dismissButton, action: #selector(dismissPressed))
        viewPaletteButton.setAccessibilityIdentifier("terrarium.unlock.view-palette")
        dismissButton.setAccessibilityIdentifier("terrarium.unlock.dismiss")

        let copyStack = NSStackView(views: [titleLabel, lineLabel])
        copyStack.orientation = .vertical
        copyStack.alignment = .leading
        copyStack.spacing = 2
        copyStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView(views: [viewPaletteButton, dismissButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 6
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(copyStack)
        addSubview(buttonStack)
        NSLayoutConstraint.activate([
            copyStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            copyStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            copyStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: copyStack.trailingAnchor, constant: 8),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func configure(button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.bezelStyle = .recessed
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setAccessibilityElement(true)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    @objc private func viewPalettePressed() {
        onViewPalette()
    }

    @objc private func dismissPressed() {
        onDismiss()
    }
}

@MainActor
private final class TepalAccessibleButton: NSButton {
    override func accessibilityPerformPress() -> Bool {
        performClick(nil)
        return true
    }
}

private struct TepalPaletteCard: View {
    @FocusState private var isFocused: Bool

    let card: TepalPaletteCardState
    let onSelect: (TepalPaletteID) -> Void

    private var palette: TepalPalette {
        TepalTheme.palette(for: card.id)
    }

    private var statusLabel: String {
        if card.isSelected { return "Selected" }
        if card.isLocked, let requirement = card.unlockRequirement {
            return "Locked · \(requirement) focuses"
        }
        return "Available"
    }

    var body: some View {
        Button {
            if let intent = TepalPalettePresentation.selectionIntent(for: card) {
                onSelect(intent)
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                palettePreview
                Text(card.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Label(statusLabel, systemImage: card.isLocked ? "lock.fill" : card.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
            .padding(10)
            .background(Color(nsColor: palette.habitatAccent), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        Color(nsColor: isFocused || card.isSelected ? palette.primaryAction : palette.habitatBase),
                        lineWidth: isFocused || card.isSelected ? 2 : 1
                    )
            }
            .opacity(card.isLocked ? 0.72 : 1)
        }
        .buttonStyle(.plain)
        .disabled(card.isLocked)
        .focusable(!card.isLocked)
        .focused($isFocused)
        .frame(minHeight: 44)
        .accessibilityLabel("\(card.name) palette")
        .accessibilityValue(card.accessibilityValue)
        .accessibilityHint(card.isLocked ? "This palette is not available yet." : "Select this palette for Tepal.")
        .accessibilityIdentifier("palette.\(card.id.rawValue)")
    }

    private var palettePreview: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
            spacing: 2
        ) {
            ForEach(Array(semanticColors.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(nsColor: color))
                    .frame(height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var semanticColors: [NSColor] {
        [
            palette.bodyTop,
            palette.bodyBottom,
            palette.leaf,
            palette.glow,
        ]
    }
}

private struct TepalCompactTextButtonStyle: ButtonStyle {
    let palette: TepalPaletteID

    func makeBody(configuration: Configuration) -> some View {
        let theme = TepalTheme.palette(for: palette)
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(nsColor: theme.primaryText))
            .background(
                Color(nsColor: theme.habitatBase).opacity(configuration.isPressed ? 0.76 : 0.50),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: theme.divider), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
