import TepalCore
@testable import TepalMac
import Foundation
import AppKit
import SwiftUI
import SwiftData
import Testing
@testable import TepalApp

@MainActor
struct TepalSurfacePresentationTests {
    private static let semanticEndpointDistanceThreshold = 30
    private static let minimumSemanticEndpointSamples = 100

    @Test(arguments: [0, 1, 4, 12, 25])
    func habitatGrowthIsDeterministic(completedFocuses: Int) {
        let growth = TepalGrowthProfile(completedFocuses: completedFocuses)

        #expect(
            TepalHabitatPresentation.decorations(for: growth)
            == TepalHabitatPresentation.decorations(for: growth)
        )
    }

    @Test func canonicalHabitatUsesThreeGroundLayersAndSparseStars() {
        #expect(TepalHabitatPresentation.groundLayerCount == 3)
        #expect(TepalHabitatPresentation.starPoints.count == 5)
    }

    @Test func canonicalHabitatAtmosphereIsSubtleAndFadesInsideTheHabitat() {
        // Break caught: a large opaque ellipse replaces the approved restrained radial atmosphere.
        let atmosphere = TepalHabitatPresentation.atmosphere

        #expect(atmosphere.maximumOpacity <= 0.12)
        #expect(atmosphere.endRadiusFraction <= 0.50)
        #expect(atmosphere.endsTransparent)
    }

    @Test func habitatGroundLayersAreDistinctShallowRollingContours() {
        let size = CGSize(width: 360, height: 220)
        let layers = TepalHabitatPresentation.groundLayers
        let bounds = TepalHabitatPresentation.groundPaths(in: size).map(\.boundingRect)

        #expect(layers.count == 3)
        #expect(layers.map(\.crestX) == [0.26, 0.68, 0.42])
        #expect(layers.map(\.crestY) == [0.88, 0.92, 0.96])
        #expect(zip(bounds.map(\.minY), [193.6, 202.4, 211.2]).allSatisfy {
            abs($0.0 - $0.1) < 0.001
        })
        #expect(bounds.allSatisfy { $0.maxY == size.height && $0.height <= 27 })
    }

    @Test func habitatCanvasUsesTheHabitatRenderSurface() {
        #expect(TepalHabitatPresentation.characterSurface == .habitat)
    }

    @Test func swiftUICanvasPlacesTepalLeafTipsAboveTheirAttachmentPoints() {
        let palette = TepalTheme.palette(for: .moonFern)
        let pixels = renderSwiftUICanvasPixels()
        let topTipArea = leafColorCount(
            in: CGRect(x: 12, y: 4, width: 24, height: 24),
            palette: palette,
            pixels: pixels
        )
        let lowerMirrorArea = leafColorCount(
            in: CGRect(x: 12, y: 58, width: 24, height: 24),
            palette: palette,
            pixels: pixels
        )

        #expect(topTipArea > lowerMirrorArea)
    }

    @Test func swiftUICanvasKeepsBodyGradientAndShadeInTheirSemanticVisualQuadrants() {
        let palette = TepalTheme.palette(for: .twilightPlum)
        let pixels = renderSwiftUICanvasPixels(palette: .twilightPlum)
        let topSamples = semanticColorSamples(
            near: color(from: palette.bodyTop),
            pixels: pixels
        )
        let bottomSamples = semanticColorSamples(
            near: color(from: palette.bodyBottom),
            pixels: pixels
        )
        let shadeContrast = rightSideShadeContrast(in: pixels)

        #expect(topSamples.count >= Self.minimumSemanticEndpointSamples)
        #expect(bottomSamples.count >= Self.minimumSemanticEndpointSamples)
        #expect(topSamples.centroid < bottomSamples.centroid)
        #expect(shadeContrast.lower > shadeContrast.upper * 2)
    }

    @Test func tepalButtonStylesAreAvailableForSemanticPaletteControls() {
        _ = TepalPrimaryButtonStyle(palette: .moonFern)
        _ = TepalCompactButtonStyle(palette: .moonFern)
    }

    @Test func settingsShellAcceptsArbitraryNativeContent() {
        // Break caught: the shared botanical shell becomes coupled to onboarding or Settings state.
        _ = TepalSettingsShell {
            Text("Native settings content")
        }
    }

    @Test func recordedHistoryIgnoresCurrentTimerPreference() {
        // Break caught: a timer preference retroactively changes a stored session's duration.
        let session = FocusSessionSummary(id: UUID(), endedAt: .distantPast, duration: 1500)
        let rows = HistoryPresentation.gardenRows(sessions: [session], focusDuration: 3000)
        #expect(rows.first?.durationText == "25 min")
    }

    @Test func legacyHistoryDoesNotInventDurationFromCurrentSettings() {
        // Break caught: garden decoration replaces the scannable completion date or omits the session duration.
        let endedAt = Date(timeIntervalSinceReferenceDate: 123_456)
        let session = FocusSessionSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
            endedAt: endedAt
        )

        let rows = HistoryPresentation.gardenRows(
            sessions: [session],
            focusDuration: 1_500
        )

        #expect(rows.map(\.endedAt) == [endedAt])
        #expect(rows.map(\.durationText) == ["Duration not recorded"])
    }

    @Test func historyReloadUnavailableClearsPreviouslyLoadedState() throws {
        // Break caught: losing the store leaves stale sessions, rewards, or totals visible behind the unavailable message.
        let store = try makeTask8HistoryStore()
        let endedAt = Date(timeIntervalSinceReferenceDate: 88_000)
        let snapshot = HistoryViewSnapshot(
            sessions: [FocusSessionSummary(id: UUID(), endedAt: endedAt)],
            rewards: [RewardSummary(reward: .glow, unlockedAt: endedAt)],
            totalCompleted: 7
        )
        let model = HistoryViewModel(load: { _ in snapshot })

        model.reload(historyStore: store)
        model.reload(historyStore: nil)

        #expect(model.sessions.isEmpty)
        #expect(model.rewards.isEmpty)
        #expect(model.totalCompleted == 0)
        #expect(model.errorMessage == "Focus history is unavailable in this session.")
    }

    @Test func historyReloadFailureClearsPreviouslyLoadedState() throws {
        // Break caught: a persistence read failure leaves stale garden data visible or reuses the unavailable-store copy.
        let store = try makeTask8HistoryStore()
        let endedAt = Date(timeIntervalSinceReferenceDate: 99_000)
        let snapshot = HistoryViewSnapshot(
            sessions: [FocusSessionSummary(id: UUID(), endedAt: endedAt)],
            rewards: [RewardSummary(reward: .sparkle, unlockedAt: endedAt)],
            totalCompleted: 12
        )
        var shouldThrow = false
        let model = HistoryViewModel(load: { _ in
            if shouldThrow { throw Task8HistoryTestError.forcedReadFailure }
            return snapshot
        })

        model.reload(historyStore: store)
        shouldThrow = true
        model.reload(historyStore: store)

        #expect(model.sessions.isEmpty)
        #expect(model.rewards.isEmpty)
        #expect(model.totalCompleted == 0)
        #expect(model.errorMessage == "Focus history could not be loaded.")
    }

    @Test func onboardingPreviewUsesFirstRunMoonFernWithoutATimerRing() {
        // Break caught: onboarding inherits live timer/palette state or renders the Dock progress treatment.
        let preview = TepalOnboardingPresentation.previewState(reducedMotion: true)

        #expect(TepalOnboardingPresentation.previewSurface == .preview)
        #expect(!TepalOnboardingPresentation.previewSurface.showsTimerProgress)
        #expect(preview.pose == .ready)
        #expect(preview.timerProgress == 0)
        #expect(preview.palette == .moonFern)
        #expect(preview.growth == TepalGrowthProfile(completedFocuses: 0))
        #expect(preview.reducedMotion)
    }

    @Test func flagshipSurfaceUsesTheExactFixedHabitatAndShelfSplit() {
        // Break caught: the full-bleed panel gains an inset card, scrolls, or changes the approved fixed composition.
        #expect(TepalLayout.panelSize == CGSize(width: 360, height: 640))
        #expect(TepalLayout.habitatHeight == 350)
        #expect(TepalLayout.shelfHeight == 290)
        #expect(TepalLayout.habitatHeight + TepalLayout.shelfHeight == TepalLayout.panelSize.height)
        #expect(TepalLayout.shellRadius == 30)
        #expect(TepalLayout.shelfInset == 24)
        #expect(TepalLayout.timerPointSize == 60)
        #expect(TepalLayout.primaryControlHeight == 46)
        #expect(TepalLayout.compactControlWidth == 46)
    }

    private func renderSwiftUICanvasPixels(palette: TepalPaletteID = .moonFern) -> [UInt8] {
        let state = TepalPresentationPolicy.make(
            petState: .idle,
            isTimerPaused: false,
            timerProgress: 0,
            palette: palette,
            completedFocuses: 0,
            reducedMotion: true
        )
        let renderer = ImageRenderer(
            content: TepalCanvasView(state: state, surface: .habitat)
                .frame(width: 92, height: 86)
        )
        renderer.scale = 1
        guard let image = renderer.cgImage else {
            Issue.record("SwiftUI Canvas image rendering unexpectedly failed")
            return []
        }
        var pixels = [UInt8](repeating: 0, count: 92 * 86 * 4)
        guard let data = image.dataProvider?.data,
              let source = CFDataGetBytePtr(data)
        else {
            Issue.record("SwiftUI Canvas pixels unexpectedly unavailable")
            return []
        }
        for y in 0..<86 {
            for x in 0..<92 {
                let sourceIndex = y * image.bytesPerRow + x * 4
                let destinationIndex = (y * 92 + x) * 4
                pixels[destinationIndex] = source[sourceIndex + 2]
                pixels[destinationIndex + 1] = source[sourceIndex + 1]
                pixels[destinationIndex + 2] = source[sourceIndex]
                pixels[destinationIndex + 3] = source[sourceIndex + 3]
            }
        }
        return pixels
    }

    private func leafColorCount(in rect: CGRect, palette: TepalPalette, pixels: [UInt8]) -> Int {
        let leaf = color(from: palette.leaf)
        let bodyTop = color(from: palette.bodyTop)
        let bodyBottom = color(from: palette.bodyBottom)
        return (Int(rect.minY)..<Int(rect.maxY)).reduce(into: 0) { count, y in
            count += (Int(rect.minX)..<Int(rect.maxX)).reduce(into: 0) { count, x in
                let index = ((y * 92) + x) * 4
                guard pixels[index + 3] > 0 else { return }
                let pixel = (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
                if colorDistance(pixel, leaf) < colorDistance(pixel, bodyTop),
                   colorDistance(pixel, leaf) < colorDistance(pixel, bodyBottom) {
                    count += 1
                }
            }
        }
    }

    private func color(from color: NSColor) -> (red: Int, green: Int, blue: Int) {
        (
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }

    private func colorDistance(
        _ lhs: (red: Int, green: Int, blue: Int),
        _ rhs: (red: Int, green: Int, blue: Int)
    ) -> Int {
        abs(lhs.red - rhs.red) + abs(lhs.green - rhs.green) + abs(lhs.blue - rhs.blue)
    }

    private func semanticColorSamples(
        near semanticColor: (red: Int, green: Int, blue: Int),
        pixels: [UInt8]
    ) -> (count: Int, centroid: Double) {
        let paths = TepalGeometry.paths(
            in: CGRect(x: 0, y: 0, width: 92, height: 86),
            pose: .staticFallback,
            growth: .seedling
        )
        var totalY = 0
        var count = 0
        for y in 0..<86 {
            for x in 0..<92 {
                let index = ((y * 92) + x) * 4
                let canonicalPoint = CGPoint(x: x, y: 86 - y)
                guard pixels[index + 3] > 0,
                      paths.body.contains(canonicalPoint),
                      !paths.leftLeaf.contains(canonicalPoint),
                      !paths.rightLeaf.contains(canonicalPoint),
                      !paths.leftEye.contains(canonicalPoint),
                      !paths.rightEye.contains(canonicalPoint)
                else { continue }
                let pixel = (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
                if colorDistance(pixel, semanticColor) <= Self.semanticEndpointDistanceThreshold {
                    totalY += y
                    count += 1
                }
            }
        }
        return (count, count > 0 ? Double(totalY) / Double(count) : .infinity)
    }

    private func rightSideShadeContrast(in pixels: [UInt8]) -> (upper: Int, lower: Int) {
        let body = TepalGeometry.paths(
            in: CGRect(x: 0, y: 0, width: 92, height: 86),
            pose: .staticFallback,
            growth: .seedling
        ).body
        let bounds = body.boundingBoxOfPath
        let bodyTop = 86 - bounds.maxY
        let bodyBottom = 86 - bounds.minY
        let bodyMidpoint = (bodyTop + bodyBottom) / 2
        let leftX = Int((bounds.minX + bounds.width * 0.40).rounded())
        let rightX = Int((bounds.minX + bounds.width * 0.66).rounded())
        var upper = 0
        var lower = 0

        for visualY in Int(bodyTop)...Int(bodyBottom) {
            let storageY = visualY
            guard visualY >= Int(bodyTop), visualY <= Int(bodyBottom) else { continue }
            guard body.contains(CGPoint(x: leftX, y: 86 - visualY)),
                  body.contains(CGPoint(x: rightX, y: 86 - visualY))
            else { continue }
            let leftIndex = ((storageY * 92) + leftX) * 4
            let rightIndex = ((storageY * 92) + rightX) * 4
            guard pixels[leftIndex + 3] == 255, pixels[rightIndex + 3] == 255 else { continue }
            let contrast = max(0, luminance(of: pixels, at: leftIndex) - luminance(of: pixels, at: rightIndex))
            if Double(visualY) < bodyMidpoint {
                upper += contrast
            } else {
                lower += contrast
            }
        }
        return (upper, lower)
    }

    private func luminance(of pixels: [UInt8], at index: Int) -> Int {
        Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])
    }

}

@MainActor
private func makeTask8HistoryStore() throws -> HistoryStore {
    let schema = Schema([FocusSessionRecord.self, UnlockedRewardRecord.self])
    let configuration = ModelConfiguration(
        "TepalTask8History-\(UUID().uuidString)",
        schema: schema,
        isStoredInMemoryOnly: true,
        groupContainer: .none,
        cloudKitDatabase: .none
    )
    let container = try ModelContainer(
        for: FocusSessionRecord.self,
        UnlockedRewardRecord.self,
        configurations: configuration
    )
    return HistoryStore(modelContainer: container)
}

private enum Task8HistoryTestError: Error {
    case forcedReadFailure
}
