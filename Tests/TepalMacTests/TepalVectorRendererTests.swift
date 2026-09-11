import AppKit
import CoreGraphics
import TepalCore
import Testing
import ImageIO
@testable import TepalMac

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

@MainActor
struct TepalVectorRendererTests {
    @Test func onlyTheDockSurfaceDrawsTimerProgress() {
        #expect(TepalRenderSurface.dock.showsTimerProgress)
        #expect(!TepalRenderSurface.habitat.showsTimerProgress)
        #expect(!TepalRenderSurface.preview.showsTimerProgress)
        #expect(!TepalRenderSurface.excursion.showsTimerProgress)
    }

    @Test(arguments: [
        TepalRenderSurface.habitat,
        .preview,
        .excursion,
    ])
    func nonDockSurfacesDoNotRenderTimerProgress(surface: TepalRenderSurface) {
        let emptyTimer = makeState(pose: .keepingWatch, completedFocuses: 0, timerProgress: 0)
        let fullTimer = makeState(pose: .keepingWatch, completedFocuses: 0, timerProgress: 1)

        #expect(
            renderPixels(state: emptyTimer, surface: surface, frameIndex: 0)
            == renderPixels(state: fullTimer, surface: surface, frameIndex: 0)
        )
    }

    @Test func nonDockSurfacesLeaveTheDockTrackPixelsTransparent() {
        let state = makeState(pose: .ready, completedFocuses: 0, timerProgress: 0)
        let dockPixels = renderPixels(state: state, surface: .dock, frameIndex: 0)
        let habitatPixels = renderPixels(state: state, surface: .habitat, frameIndex: 0)
        let dockOnlyPixels = pixelIndicesOpaque(in: dockPixels).filter {
            habitatPixels[$0 + 3] == 0
        }

        #expect(!dockOnlyPixels.isEmpty)
        for surface in [TepalRenderSurface.habitat, .preview, .excursion] {
            let pixels = renderPixels(state: state, surface: surface, frameIndex: 0)
            for index in dockOnlyPixels {
                #expect(pixels[index + 3] == 0)
            }
        }
    }

    @Test func dockProgressPresentationReservesTracksForTimerPoses() {
        // Break caught: idle, fallback, or alert poses inherit a full countdown track from an unrelated numeric progress value.
        let ready = makeState(pose: .ready, completedFocuses: 0, timerProgress: 0)
        let fallback = makeState(pose: .staticFallback, completedFocuses: 0, timerProgress: 0)
        let active = makeState(pose: .keepingWatch, completedFocuses: 0, timerProgress: 0.5)

        #expect(TepalDockProgressPresentation.make(for: ready) == .halo)
        #expect(TepalDockProgressPresentation.make(for: fallback) == .halo)
        #expect(TepalDockProgressPresentation.make(for: active) == .activeTimer(progress: 0.5))
    }

    @Test(arguments: [
        (TepalPose.ready, TepalDockProgressPresentation.halo),
        (.preparingFocus, .activeTimer(progress: 0.5)),
        (.keepingWatch, .activeTimer(progress: 0.5)),
        (.pausedCurious, .activeTimer(progress: 0.5)),
        (.resting, .activeTimer(progress: 0.5)),
        (.meetingAttentive, .halo),
        (.completionBloom, .halo),
        (.walking, .halo),
        (.staticFallback, .halo),
    ])
    func dockProgressPresentationClassifiesEveryCanonicalPoseWithRetainedProgress(
        pose: TepalPose,
        expected: TepalDockProgressPresentation
    ) {
        // Break caught: a dormant Tepal pose inherits an active Dock track from retained timer progress.
        let state = makeState(pose: pose, completedFocuses: 0, timerProgress: 0.5)

        #expect(TepalDockProgressPresentation.make(for: state) == expected)
    }

    @Test func activeDockProgressChangesOnlyExternalArcPixelsForTheSamePose() {
        // Break caught: changing timer progress mutates the creature or fails to draw the active countdown arc.
        let emptyProgress = makeState(pose: .keepingWatch, completedFocuses: 0, timerProgress: 0)
        let halfProgress = makeState(pose: .keepingWatch, completedFocuses: 0, timerProgress: 0.5)
        let emptyPixels = renderPixels(state: emptyProgress, surface: .dock, frameIndex: 0)
        let halfPixels = renderPixels(state: halfProgress, surface: .dock, frameIndex: 0)
        let changedPixels = changedPixelIndices(between: emptyPixels, and: halfPixels)

        #expect(!changedPixels.isEmpty)
        for index in changedPixels {
            #expect(isInActiveProgressBand(pixelIndex: index, width: 128, height: 128))
        }
        #expect(alpha(atX: 0, y: 0, in: emptyPixels) == 0)
        #expect(alpha(atX: 0, y: 0, in: halfPixels) == 0)
    }

    @Test func idleAndStaticDockFramesUseGlowHalosWithoutFullProgressTracks() {
        // Break caught: a dormant Dock tile renders the active Deep Moss countdown track instead of a restrained palette glow.
        let states = [
            makeState(pose: .ready, completedFocuses: 0, timerProgress: 0),
            makeState(pose: .staticFallback, completedFocuses: 0, timerProgress: 0),
        ]

        for state in states {
            let pixels = renderPixels(state: state, surface: .dock, frameIndex: 0)
            let ringFreePixels = renderPixels(state: state, surface: .preview, frameIndex: 0)
            let dockDecoration = changedPixelIndices(between: pixels, and: ringFreePixels)
            let haloPixels = dockDecoration.filter {
                isInHaloBand(pixelIndex: $0, width: 128, height: 128)
            }
            let trackPixels = dockDecoration.filter {
                isInActiveTrackCore(pixelIndex: $0, width: 128, height: 128)
            }

            #expect(!haloPixels.isEmpty)
            #expect(trackPixels.isEmpty)
            #expect(alpha(atX: 0, y: 0, in: pixels) == 0)
        }
    }

    @Test func habitatRendererUsesTheCanonicalNinetyTwoByEightySixCharacterBox() {
        let pixels = renderPixels(
            state: makeState(pose: .ready, completedFocuses: 0),
            surface: .habitat,
            frameIndex: 0,
            width: 92,
            height: 86
        )
        let visibleBounds = visiblePixelBounds(in: pixels, width: 92, height: 86)

        #expect(visibleBounds == CGRect(x: 0, y: 0, width: 92, height: 86))
    }

    @Test func everyPaletteIdentifierResolvesToADistinctPalette() {
        // Break caught: two selectable palette identifiers render the same creature body.
        let bodyColors = TepalPaletteID.allCases.map {
            packedRGB(TepalTheme.palette(for: $0).body)
        }

        #expect(Set(bodyColors).count == TepalPaletteID.allCases.count)
    }

    @Test func moonFernUsesLivingTerrariumTokens() {
        // Break caught: the default creature drifts from Living Terrarium's green semantic tokens.
        let palette = TepalTheme.palette(for: .moonFern)
        #expect(packedRGB(palette.bodyTop) == 0xC8F5A4)
        #expect(packedRGB(palette.bodyBottom) == 0x58B899)
        #expect(packedRGB(palette.bodyShade) == 0x1A7566)
        #expect(packedRGB(palette.leaf) == 0xDDFFAF)
        #expect(packedRGB(palette.eye) == 0xF8FFF3)
        #expect(packedRGB(palette.glow) == 0x8AEFB3)
        #expect(packedRGB(palette.habitatBase) == 0x111916)
        #expect(packedRGB(palette.habitatAccent) == 0x1E382F)
    }

    @Test func livingTerrariumMetricsAreExact() {
        // Break caught: a surface cannot reproduce the approved fixed Living Terrarium composition.
        #expect(TepalLayout.panelSize == CGSize(width: 360, height: 640))
        #expect(TepalLayout.habitatHeight == 350)
        #expect(TepalLayout.shelfHeight == 290)
        #expect(TepalLayout.shellRadius == 30)
        #expect(TepalLayout.shelfInset == 24)
        #expect(TepalLayout.timerPointSize == 60)
        #expect(TepalLayout.characterSize == CGSize(width: 92, height: 86))
    }

    @Test func leafEarsIntersectTheBodyAndEyesRemainInsideIt() {
        // Break caught: the canonical silhouette regresses into detached ears or eyes outside the body.
        let paths = TepalGeometry.paths(
            in: CGRect(origin: .zero, size: TepalLayout.characterSize),
            pose: .ready,
            growth: .seedling
        )

        #expect(paths.body.boundingBoxOfPath.intersects(paths.leftLeaf.boundingBoxOfPath))
        #expect(paths.body.boundingBoxOfPath.intersects(paths.rightLeaf.boundingBoxOfPath))
        #expect(paths.body.contains(paths.leftEye.boundingBoxOfPath.center))
        #expect(paths.body.contains(paths.rightEye.boundingBoxOfPath.center))
    }

    @Test(arguments: TepalPose.allCases)
    func leafEarBasesRemainInsideBodyForEveryPose(pose: TepalPose) {
        // Break caught: a pose separates an ear at its actual attachment point despite overlapping bounds.
        let paths = TepalGeometry.paths(
            in: CGRect(origin: .zero, size: TepalLayout.characterSize),
            pose: pose,
            growth: .seedling
        )

        #expect(paths.body.contains(firstPathPoint(in: paths.leftLeaf)!))
        #expect(paths.body.contains(firstPathPoint(in: paths.rightLeaf)!))
    }

    @Test func canonicalReadyCharacterFillsTheApprovedVisualBox() {
        // Break caught: geometry fits inside the 92×86 canvas but renders the character materially smaller.
        let paths = TepalGeometry.paths(
            in: CGRect(origin: .zero, size: TepalLayout.characterSize),
            pose: .ready,
            growth: .seedling
        )
        let visibleBounds = [paths.body, paths.leftLeaf, paths.rightLeaf].reduce(CGRect.null) {
            $0.union($1.boundingBoxOfPath)
        }

        #expect(abs(visibleBounds.minX) < 0.001)
        #expect(abs(visibleBounds.minY) < 0.001)
        #expect(abs(visibleBounds.width - TepalLayout.characterSize.width) < 0.001)
        #expect(abs(visibleBounds.height - TepalLayout.characterSize.height) < 0.001)
    }

    @Test func everyPaletteMaintainsApprovedTextAndFocusContrast() {
        // Break caught: a curated palette makes normal text or the keyboard-focus boundary illegible.
        for id in TepalPaletteID.allCases {
            let palette = TepalTheme.palette(for: id)
            #expect(contrastRatio(palette.primaryText, palette.habitatBase) >= 4.5)
            #expect(contrastRatio(palette.primaryText, palette.habitatAccent) >= 4.5)
            #expect(contrastRatio(palette.primaryAction, palette.habitatBase) >= 3.0)
            #expect(contrastRatio(palette.primaryAction, palette.habitatAccent) >= 3.0)
        }
    }

    @Test func everyMoreControlUsesItsProductionBoundaryTokenAtNonTextContrast() {
        // Break caught: the compact More control renders as a bare ellipsis because its actual
        // production boundary token disappears into the habitat-accent button background.
        for id in TepalPaletteID.allCases {
            let palette = TepalTheme.palette(for: id)
            #expect(contrastRatio(palette.moreControlBorder, palette.habitatAccent) >= 3.0)
        }
    }

    @Test func everyPaletteSeparatesTheThreeFernGroundBands() {
        // Break caught: the approved shallow layers collapse into one indistinguishable dark mound.
        for id in TepalPaletteID.allCases {
            let palette = TepalTheme.palette(for: id)
            #expect(contrastRatio(palette.groundFar, palette.groundMiddle) >= 1.30)
            #expect(contrastRatio(palette.groundMiddle, palette.groundNear) >= 1.30)
        }
    }

    @Test func everyProductionPersonalityCaptionPairMaintainsTextContrastOverBodyEndpoints() {
        // Break caught: the small caption is drawn directly on variable body colors and becomes unreadable.
        for id in TepalPaletteID.allCases {
            let palette = TepalTheme.palette(for: id)
            for bodyEndpoint in [palette.bodyTop, palette.bodyBottom] {
                let actualBackground = composite(
                    palette.personalityCaptionBackground,
                    over: bodyEndpoint
                )
                #expect(contrastRatio(
                    palette.personalityCaptionForeground,
                    actualBackground
                ) >= 4.5)
            }
        }
    }

    @Test func geometryStaysInsideRequestedBoundsForEveryPoseAndGrowthTier() {
        // Break caught: a pose or earned growth decoration clips outside a rendering surface.
        let bounds = CGRect(x: 17, y: 29, width: 173, height: 91)

        for pose in TepalPose.allCases {
            for growth in TepalGrowthTier.allCases {
                let paths = TepalGeometry.paths(in: bounds, pose: pose, growth: growth)
                let allPaths = [
                    paths.body, paths.leftLeaf, paths.rightLeaf,
                    paths.leftEye, paths.rightEye,
                ] + paths.growthMarks

                for path in allPaths {
                    #expect(!path.isEmpty)
                    #expect(bounds.contains(path.boundingBoxOfPath))
                }
            }
        }
    }

    @Test(arguments: [
        (TepalGrowthTier.seedling, 0),
        (.glowing, 1),
        (.sprouted, 2),
        (.flourishing, 3),
        (.mature, 4),
    ])
    func growthTierControlsVisibleGrowthMarkCount(tier: TepalGrowthTier, expectedCount: Int) {
        // Break caught: a milestone no longer adds exactly one persistent growth detail.
        let paths = TepalGeometry.paths(
            in: CGRect(x: 0, y: 0, width: 100, height: 100),
            pose: .ready,
            growth: tier
        )

        #expect(paths.growthMarks.count == expectedCount)
    }

    @Test func bitmapRenderPaintsTheCreatureCenterAndPreservesTransparentCorners() {
        // Break caught: the shared renderer produces a blank tile or paints an opaque square background.
        let pixels = renderPixels(surface: .dock, frameIndex: 0)

        #expect(alpha(atX: 64, y: 64, in: pixels) > 0)
        #expect(alpha(atX: 0, y: 0, in: pixels) == 0)
        #expect(alpha(atX: 127, y: 0, in: pixels) == 0)
        #expect(alpha(atX: 0, y: 127, in: pixels) == 0)
        #expect(alpha(atX: 127, y: 127, in: pixels) == 0)
    }

    @Test func repeatedBitmapRenderIsDeterministic() {
        // Break caught: decorative randomness makes identical state and frame inputs produce different pixels.
        #expect(
            renderPixels(surface: .dock, frameIndex: 7)
                == renderPixels(surface: .dock, frameIndex: 7)
        )
    }

    @Test func normalRendererFramesPresentLeafSwayAndRareBlinkWhileReducedMotionSettles() {
        // Break caught: normal habitat rendering remains pinned to frame zero, or Reduced Motion
        // keeps consuming decorative blink/sway frames after interruption.
        let normal = makeState(pose: .ready, completedFocuses: 0, reducedMotion: false)
        let reduced = makeState(pose: .ready, completedFocuses: 0, reducedMotion: true)

        #expect(renderPixels(state: normal, surface: .habitat, frameIndex: 0)
            != renderPixels(state: normal, surface: .habitat, frameIndex: 1))
        #expect(renderPixels(state: normal, surface: .habitat, frameIndex: 30)
            != renderPixels(state: normal, surface: .habitat, frameIndex: 31))
        #expect(renderPixels(state: reduced, surface: .habitat, frameIndex: 0)
            == renderPixels(state: reduced, surface: .habitat, frameIndex: 31))
    }

    @Test func motionFrameChangesLeafEarAndEyeGeometryWithoutMovingTheWholeCharacter() {
        let bounds = CGRect(origin: .zero, size: TepalLayout.characterSize)
        let settled = TepalGeometry.paths(
            in: bounds,
            pose: .ready,
            growth: .seedling,
            motion: .settled
        )
        let expressive = TepalGeometry.paths(
            in: bounds,
            pose: .ready,
            growth: .seedling,
            motion: TepalMotionFrame(eyeOpen: 0.12, leafSway: 1)
        )

        #expect(expressive.leftEye.boundingBoxOfPath.height < settled.leftEye.boundingBoxOfPath.height)
        #expect(expressive.leftLeaf.boundingBoxOfPath != settled.leftLeaf.boundingBoxOfPath)
        #expect(expressive.body.boundingBoxOfPath == settled.body.boundingBoxOfPath)
        #expect(bounds.contains(expressive.leftLeaf.boundingBoxOfPath))
        #expect(bounds.contains(expressive.rightLeaf.boundingBoxOfPath))
        #expect(bounds.contains(expressive.leftEye.boundingBoxOfPath))
        #expect(bounds.contains(expressive.rightEye.boundingBoxOfPath))
    }

    @Test func nonSquareRendersAspectFitEveryPoseAndGrowthTier() {
        // Break caught: rectangular surfaces stretch or crowd the creature outside its circular render region.
        let sizes = [(width: 192, height: 96), (width: 96, height: 192)]
        let milestones = [0, 1, 4, 12, 25]

        for size in sizes {
            let fittedSide = min(size.width, size.height)
            let fittedBounds = CGRect(
                x: (size.width - fittedSide) / 2,
                y: (size.height - fittedSide) / 2,
                width: fittedSide,
                height: fittedSide
            )
            for pose in TepalPose.allCases {
                for completedFocuses in milestones {
                    let state = makeState(pose: pose, completedFocuses: completedFocuses)
                    let pixels = renderPixels(
                        state: state,
                        surface: .dock,
                        frameIndex: 0,
                        width: size.width,
                        height: size.height
                    )

                    let escapedPixelCount = nontransparentPixelCount(
                        outside: fittedBounds,
                        in: pixels,
                        width: size.width,
                        height: size.height
                    )
                    #expect(escapedPixelCount == 0)
                }
            }
        }
    }

    @Test func rendererPreservesAndDoesNotPaintTheCallersCurrentPath() {
        // Break caught: renderer stroke operations consume and paint geometry already pending in the shared context.
        let width = 64
        let height = 64
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let state = makeState(pose: .keepingWatch, completedFocuses: 0)
        let seededPath = CGPath(rect: CGRect(x: 0, y: 52, width: 12, height: 12), transform: nil)

        pixels.withUnsafeMutableBytes { storage in
            let context = CGContext(
                data: storage.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.addPath(seededPath)

            TepalVectorRenderer.draw(
                state: state,
                surface: .dock,
                frameIndex: 0,
                in: context,
                bounds: CGRect(x: 0, y: 0, width: width, height: height)
            )

            #expect(context.path?.boundingBoxOfPath == seededPath.boundingBoxOfPath)
        }

        let unseededPixels = renderPixels(
            state: state,
            surface: .dock,
            frameIndex: 0,
            width: width,
            height: height
        )
        let matchesUnseededRender = pixels == unseededPixels
        #expect(matchesUnseededRender)
    }

    @Test func illustratedDockPreservesProgressAndTransparentEdges() throws {
        let ready = makeState(pose: .keepingWatch, completedFocuses: 4, timerProgress: 0)
        let half = makeState(pose: .keepingWatch, completedFocuses: 4, timerProgress: 0.5)
        let empty = renderPixels(state: ready, surface: .dock, frameIndex: 0, illustrated: true)
        let filled = renderPixels(state: half, surface: .dock, frameIndex: 0, illustrated: true)
        #expect(empty != filled)
        #expect(alpha(atX: 64, y: 64, in: empty) > 0)
        #expect(alpha(atX: 0, y: 0, in: empty) == 0)
        for index in stride(from: 0, to: empty.count, by: 4) where Array(empty[index..<index+4]) != Array(filled[index..<index+4]) {
            let point = pixelPoint(for: index, width: 128, height: 128)
            let radius = hypot(point.x - 64, point.y - 64)
            #expect(radius > 128 * 0.45 && radius < 128 * 0.51)
        }
        let moving = makeState(pose: .ready, completedFocuses: 4, reducedMotion: false)
        let initial = renderPixels(state: moving, surface: .dock, frameIndex: 0, illustrated: true)
        let breathing = renderPixels(state: moving, surface: .dock, frameIndex: 18, illustrated: true)
        let didMove = initial != breathing
        #expect(didMove)
        let reducedLater = renderPixels(state: ready, surface: .dock, frameIndex: 18, illustrated: true)
        let stayedStill = empty == reducedLater
        #expect(stayedStill)
        let vector = renderPixels(state: ready, surface: .dock, frameIndex: 0)
        #expect(empty != vector)
        if let directory = ProcessInfo.processInfo.environment["TEPAL_ICON_CAPTURE_DIR"] {
            let data = Data(filled)
            let provider = try #require(CGDataProvider(data: data as CFData))
            let image = try #require(CGImage(width: 128, height: 128, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 512, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("dock-focus.png"))
            let animationURL = URL(fileURLWithPath: directory).appendingPathComponent("living-dock.gif")
            let destination = try #require(CGImageDestinationCreateWithURL(animationURL as CFURL, "com.compuserve.gif" as CFString, 120, nil))
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for frame in 0..<120 {
                let bytes = renderPixels(state: moving, surface: .dock, frameIndex: frame, illustrated: true)
                let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
                let image = try #require(CGImage(width: 128, height: 128, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: 512, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
                CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 12.0]] as CFDictionary)
            }
            #expect(CGImageDestinationFinalize(destination))
        }
    }

    private func renderPixels(
        state: TepalVisualState? = nil,
        surface: TepalRenderSurface,
        frameIndex: Int,
        width: Int = 128,
        height: Int = 128,
        illustrated: Bool = false
    ) -> [UInt8] {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let state = state ?? makeState(pose: .keepingWatch, completedFocuses: 12)

        pixels.withUnsafeMutableBytes { storage in
            let context = CGContext(
                data: storage.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            TepalVectorRenderer.draw(
                state: state,
                surface: surface,
                illustrated: illustrated,
                frameIndex: frameIndex,
                in: context,
                bounds: CGRect(x: 0, y: 0, width: width, height: height)
            )
        }

        return pixels
    }

    private func alpha(atX x: Int, y: Int, in pixels: [UInt8]) -> UInt8 {
        alpha(atX: x, y: y, width: 128, in: pixels)
    }

    private func alpha(atX x: Int, y: Int, width: Int, in pixels: [UInt8]) -> UInt8 {
        pixels[((y * width) + x) * 4 + 3]
    }

    private func makeState(
        pose: TepalPose,
        completedFocuses: Int,
        timerProgress: Double = 0.5,
        reducedMotion: Bool = true
    ) -> TepalVisualState {
        TepalPresentationPolicy.make(
            petState: .focus,
            isTimerPaused: false,
            timerProgress: timerProgress,
            palette: .moonFern,
            completedFocuses: completedFocuses,
            reducedMotion: reducedMotion
        ).replacingPose(pose)
    }

    private func nontransparentPixelCount(
        outside bounds: CGRect,
        in pixels: [UInt8],
        width: Int,
        height: Int
    ) -> Int {
        var count = 0
        for y in 0..<height {
            for x in 0..<width where !bounds.contains(CGPoint(x: x, y: y)) {
                if alpha(atX: x, y: y, width: width, in: pixels) != 0 {
                    count += 1
                }
            }
        }
        return count
    }

    private func pixelIndicesOpaque(in pixels: [UInt8]) -> [Int] {
        stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0 + 3] > 0 }
    }

    private func changedPixelIndices(between lhs: [UInt8], and rhs: [UInt8]) -> [Int] {
        stride(from: 0, to: lhs.count, by: 4).filter { index in
            lhs[index..<(index + 4)] != rhs[index..<(index + 4)]
        }
    }

    private func isInHaloBand(
        pixelIndex: Int,
        width: Int,
        height: Int
    ) -> Bool {
        let point = pixelPoint(for: pixelIndex, width: width, height: height)
        let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        let radius = hypot(point.x - center.x, point.y - center.y)
        return radius >= CGFloat(width) * 0.28 && radius <= CGFloat(width) * 0.37
    }

    private func isInActiveProgressBand(pixelIndex: Int, width: Int, height: Int) -> Bool {
        let point = pixelPoint(for: pixelIndex, width: width, height: height)
        let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        let radius = hypot(point.x - center.x, point.y - center.y)
        return radius >= CGFloat(width) * 0.37 && radius <= CGFloat(width) * 0.46
    }

    private func isInActiveTrackCore(pixelIndex: Int, width: Int, height: Int) -> Bool {
        let point = pixelPoint(for: pixelIndex, width: width, height: height)
        let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        let radius = hypot(point.x - center.x, point.y - center.y)
        return radius >= CGFloat(width) * 0.40 && radius <= CGFloat(width) * 0.43
    }

    private func pixelPoint(for pixelIndex: Int, width: Int, height: Int) -> CGPoint {
        let offset = pixelIndex / 4
        return CGPoint(x: offset % width, y: min(height - 1, offset / width))
    }

    private func visiblePixelBounds(in pixels: [UInt8], width: Int, height: Int) -> CGRect {
        var visible = CGRect.null
        for y in 0..<height {
            for x in 0..<width where alpha(atX: x, y: y, width: width, in: pixels) > 0 {
                visible = visible.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return visible
    }

    private func packedRGB(_ color: NSColor) -> UInt32 {
        let red = UInt32((color.redComponent * 255).rounded())
        let green = UInt32((color.greenComponent * 255).rounded())
        let blue = UInt32((color.blueComponent * 255).rounded())
        return (red << 16) | (green << 8) | blue
    }

    private func firstPathPoint(in path: CGPath) -> CGPoint? {
        var firstPoint: CGPoint?
        path.applyWithBlock { element in
            guard firstPoint == nil, element.pointee.type == .moveToPoint else { return }
            firstPoint = element.pointee.points[0]
        }
        return firstPoint
    }

    private func contrastRatio(_ foreground: NSColor, _ background: NSColor) -> Double {
        let lighter = max(relativeLuminance(foreground), relativeLuminance(background))
        let darker = min(relativeLuminance(foreground), relativeLuminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func composite(_ foreground: NSColor, over background: NSColor) -> NSColor {
        let foreground = foreground.usingColorSpace(.sRGB)!
        let background = background.usingColorSpace(.sRGB)!
        let alpha = foreground.alphaComponent
        return NSColor(
            srgbRed: foreground.redComponent * alpha + background.redComponent * (1 - alpha),
            green: foreground.greenComponent * alpha + background.greenComponent * (1 - alpha),
            blue: foreground.blueComponent * alpha + background.blueComponent * (1 - alpha),
            alpha: 1
        )
    }

    private func relativeLuminance(_ color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB)!
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { channel in
            channel <= 0.04045
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
}
