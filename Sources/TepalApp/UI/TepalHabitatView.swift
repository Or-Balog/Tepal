import AppKit
import TepalCore
import TepalMac
import SwiftUI

struct TepalHabitatDecoration: Equatable {
    enum Kind: Equatable {
        case sprout, pollen
    }

    let kind: Kind
    let x: Double
    let y: Double
}

struct TepalHabitatGroundLayer: Equatable {
    let crestX: Double
    let crestY: Double
    let leadingY: Double
    let trailingY: Double
}

struct TepalHabitatAtmosphere: Equatable {
    let maximumOpacity: Double
    let endRadiusFraction: Double
    let endsTransparent: Bool
}

enum TepalHabitatPresentation {
    static let characterSurface: TepalRenderSurface = .habitat
    static let atmosphere = TepalHabitatAtmosphere(
        maximumOpacity: 0.12,
        endRadiusFraction: 0.48,
        endsTransparent: true
    )
    static let groundLayerCount = 3
    static let groundLayers = [
        TepalHabitatGroundLayer(crestX: 0.26, crestY: 0.88, leadingY: 0.94, trailingY: 0.92),
        TepalHabitatGroundLayer(crestX: 0.68, crestY: 0.92, leadingY: 0.97, trailingY: 0.96),
        TepalHabitatGroundLayer(crestX: 0.42, crestY: 0.96, leadingY: 0.99, trailingY: 0.985),
    ]
    static let starPoints: [(x: Double, y: Double)] = [
        (0.18, 0.18), (0.36, 0.11), (0.57, 0.20), (0.73, 0.13), (0.86, 0.24),
    ]

    static func decorations(for growth: TepalGrowthProfile) -> [TepalHabitatDecoration] {
        let all = [
            TepalHabitatDecoration(kind: .sprout, x: 0.18, y: 0.84),
            TepalHabitatDecoration(kind: .sprout, x: 0.78, y: 0.88),
            TepalHabitatDecoration(kind: .pollen, x: 0.31, y: 0.35),
            TepalHabitatDecoration(kind: .pollen, x: 0.71, y: 0.29),
        ]
        return Array(all.prefix(growth.tier.habitatDecorationCount))
    }

    static func groundPaths(in size: CGSize) -> [Path] {
        groundLayers.map { groundPath(for: $0, in: size) }
    }

    static func groundPath(for layer: TepalHabitatGroundLayer, in size: CGSize) -> Path {
        let crest = CGPoint(
            x: size.width * layer.crestX,
            y: size.height * layer.crestY
        )
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        path.addQuadCurve(
            to: crest,
            control: CGPoint(x: crest.x * 0.44, y: size.height * layer.leadingY)
        )
        path.addQuadCurve(
            to: CGPoint(x: size.width, y: size.height),
            control: CGPoint(
                x: crest.x + (size.width - crest.x) * 0.54,
                y: size.height * layer.trailingY
            )
        )
        path.closeSubpath()
        return path
    }
}

@MainActor
private enum TepalArtwork {
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Tepal_TepalApp.bundle"),
           let packaged = Bundle(url: url) { return packaged }
        return .module
    }()
    static let glade = load("glade")
    static let creature = load("creature")
    private static func load(_ name: String) -> NSImage {
        guard let url = bundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing bundled Tepal artwork: \(name)")
        }
        return image
    }
}

struct TepalHabitatView: View {
    let state: TepalVisualState

    private var palette: TepalPalette { TepalTheme.palette(for: state.palette) }
    private var isResting: Bool { state.pose == .resting }
    private var isBlooming: Bool { state.pose == .completionBloom }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Image(nsImage: TepalArtwork.glade)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .saturation(state.pose == .keepingWatch ? 0.65 : 0.9)
                    .brightness(state.pose == .keepingWatch ? -0.06 : 0)
                Color(nsColor: palette.habitatAccent)
                    .opacity(state.palette == .moonFern ? 0 : 0.22)
                    .blendMode(.color)

                Ellipse()
                    .fill(.black.opacity(0.38))
                    .frame(width: 108, height: 16)
                    .blur(radius: 8)
                    .position(x: size.width * 0.5, y: size.height * 0.665)

                Image(nsImage: TepalArtwork.creature)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 174, height: 174)
                    .colorMultiply(Color(nsColor: state.palette == .moonFern ? .white : palette.bodyTop))
                    .scaleEffect(x: isResting ? 1.08 : 1, y: isResting ? 0.82 : 1, anchor: .bottom)
                    .rotationEffect(.degrees(state.pose == .pausedCurious ? -7 : 0), anchor: .bottom)
                    .shadow(color: Color(nsColor: palette.glow).opacity(0.18), radius: 16)
                    .position(x: size.width * 0.5, y: size.height * 0.43 - (isBlooming ? 12 : 0))
                    .animation(state.reducedMotion ? nil : .easeInOut(duration: 0.65), value: state.pose)

                ForEach(Array(TepalHabitatPresentation.decorations(for: state.growth).enumerated()), id: \.offset) { _, decoration in
                    Circle()
                        .fill(Color(nsColor: palette.pollen).opacity(0.7))
                        .frame(width: 3, height: 3)
                        .shadow(color: Color(nsColor: palette.pollen), radius: 4)
                        .position(x: size.width * decoration.x, y: size.height * decoration.y)
                }

                if isBlooming || state.pose == .meetingAttentive {
                    Image(systemName: "camera.macro")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(Color(nsColor: isBlooming ? palette.pollen : palette.meetingCoral))
                        .shadow(color: Color(nsColor: palette.pollen).opacity(0.4), radius: 8)
                        .position(x: size.width * (isBlooming ? 0.5 : 0.74), y: size.height * 0.69)
                }

                LinearGradient(colors: [.clear, Color(nsColor: palette.habitatBase)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 75)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(height: TepalLayout.habitatHeight)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tepal habitat")
    }
}

private extension TepalGrowthTier {
    var habitatDecorationCount: Int {
        switch self {
        case .seedling: 0
        case .glowing: 1
        case .sprouted: 2
        case .flourishing: 3
        case .mature: 4
        }
    }
}
