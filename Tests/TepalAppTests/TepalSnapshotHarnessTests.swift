import AppKit
import TepalCore
import TepalMac
import SwiftUI
import Testing
@testable import TepalApp

struct TepalSnapshotHarnessTests {
    @MainActor
    @Test func canonicalTerrariumCaptureIsExactly360By640() throws {
        // Break caught: a native capture silently drifts from the approved fixed panel dimensions.
        let view = LivingTerrariumView(
            state: .canonicalReady,
            actions: .noOp
        )
        let png = try TepalSnapshotHarness.capture(
            view,
            size: TepalLayout.panelSize,
            fileName: "native-ready.png"
        )
        let bitmap = try #require(NSBitmapImageRep(data: png))
        #expect(bitmap.pixelsWide == 360)
        #expect(bitmap.pixelsHigh == 640)
    }

    @MainActor
    @Test func canonicalCaptureUsesTheProductionKeyableTransparentPanelHost() {
        // Break caught: the snapshot silently renders a bare hosting view instead of the real panel host.
        let panel = TepalSnapshotHarness.makePanel(
            LivingTerrariumView(state: .canonicalReady, actions: .noOp),
            size: TepalLayout.panelSize
        )

        #expect(panel is KeyableControlPanel)
        #expect(panel.canBecomeKey)
        #expect(panel.styleMask == ControlPanelInteractionPolicy.styleMask)
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor.alphaComponent == 0)
        #expect(panel.contentViewController != nil)
        #expect(panel.contentView?.layer?.contentsScale == 1)
    }

    @MainActor
    @Test func canonicalCaptureIsDeterministicNonblankAndContainsProductionLandmarks() throws {
        let view = LivingTerrariumView(state: .canonicalReady, actions: .noOp)
        let first = try TepalSnapshotHarness.capture(
            view,
            size: TepalLayout.panelSize,
            fileName: "native-ready.png"
        )
        let second = try TepalSnapshotHarness.capture(
            view,
            size: TepalLayout.panelSize,
            fileName: "native-ready.png"
        )
        let bitmap = try #require(NSBitmapImageRep(data: first))
        let pixels = TepalSnapshotPixels(bitmap: bitmap)
        let palette = TepalTheme.palette(for: .moonFern)

        #expect(first == second)
        #expect(pixels.nontransparentCount > 140_000)
        #expect(pixels.distinctOpaqueRGBCount > 64)
        #expect(pixels.count(near: palette.primaryAction, inTopDown: CGRect(x: 24, y: 440, width: 260, height: 65)) > 500)
    }

    @MainActor
    @Test func ritualStatesRenderWithoutLosingTheNativeControls() throws {
        for (name, pose, phase, seconds, paused) in [
            ("focus", TepalPose.keepingWatch, PomodoroPhase.focus, 1122, false),
            ("paused", .pausedCurious, .focus, 1122, true),
            ("completion", .completionBloom, .shortBreak, 300, false),
            ("rest", .resting, .shortBreak, 240, false),
            ("meeting", .meetingAttentive, .idle, 1500, false)
        ] {
            let state = LivingTerrariumState(
                visualState: TepalVisualState(pose: pose, timerProgress: 0.3, palette: .moonFern,
                    growth: TepalGrowthProfile(completedFocuses: 4), reducedMotion: true),
                phase: phase, remaining: .seconds(seconds), isPaused: paused,
                personalityLine: name == "completion" ? "Something new took root." : "Keeping watch.",
                nextEventLine: "Next · Design review · Tomorrow at 10:00",
                calendarAccessibilityValue: "Design review tomorrow at 10:00", pendingUnlock: nil)
            let png = try TepalSnapshotHarness.capture(LivingTerrariumView(state: state, actions: .noOp),
                size: TepalLayout.panelSize, fileName: "native-\(name).png")
            let bitmap = try #require(NSBitmapImageRep(data: png))
            #expect(TepalSnapshotPixels(bitmap: bitmap).nontransparentCount > 200_000)
        }
    }

}

private extension LivingTerrariumState {
    static let canonicalReady = LivingTerrariumState(
        visualState: TepalVisualState(
            pose: .ready,
            timerProgress: 0,
            palette: .moonFern,
            growth: TepalGrowthProfile(completedFocuses: 4),
            reducedMotion: true
        ),
        phase: .idle,
        remaining: .seconds(1_500),
        isPaused: false,
        personalityLine: "The glade is quiet.",
        nextEventLine: "Next · Design review in 42m",
        calendarAccessibilityValue: "Design review in 42 minutes",
        pendingUnlock: nil
    )
}

private extension LivingTerrariumActions {
    @MainActor
    static let noOp = LivingTerrariumActions(
        primary: {},
        skip: {},
        selectPalette: { _ in },
        dismissUnlock: {},
        openSettings: {},
        openHistory: {}
    )
}

enum TepalSnapshotError: Error {
    case bitmapCreation
    case pngEncoding
}

@MainActor
enum TepalSnapshotHarness {
    static func makePanel<V: View>(_ view: V, size: CGSize) -> NSPanel {
        let bounds = CGRect(origin: .zero, size: size)
        let panel = KeyableControlPanel(
            contentRect: bounds,
            styleMask: ControlPanelInteractionPolicy.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingController(
            rootView: view.frame(width: size.width, height: size.height)
        )
        host.view.frame = bounds
        host.view.wantsLayer = true
        host.view.layer?.contentsScale = 1
        host.view.layer?.rasterizationScale = 1
        panel.contentViewController = host
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.contentsScale = 1
        panel.contentView?.layer?.rasterizationScale = 1
        panel.setContentSize(size)
        return panel
    }

    static func capture<V: View>(
        _ view: V,
        size: CGSize,
        fileName: String
    ) throws -> Data {
        let bounds = CGRect(origin: .zero, size: size)
        let panel = makePanel(view, size: size)
        guard let host = panel.contentView else {
            throw TepalSnapshotError.bitmapCreation
        }
        host.frame = bounds
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: Int(size.width) * 4,
            bitsPerPixel: 32
        ) else {
            throw TepalSnapshotError.bitmapCreation
        }
        bitmap.size = size
        host.cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw TepalSnapshotError.pngEncoding
        }
        if let directory = ProcessInfo.processInfo.environment["TEPAL_CAPTURE_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try png.write(to: url.appendingPathComponent(fileName), options: .atomic)
        }
        return png
    }
}

@MainActor
private struct TepalSnapshotPixels {
    let bitmap: NSBitmapImageRep

    var nontransparentCount: Int {
        countPixels { $0.alphaComponent > 0.03 }
    }

    var distinctOpaqueRGBCount: Int {
        var colors = Set<UInt32>()
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.95
                else { continue }
                let red = UInt32((color.redComponent * 255).rounded())
                let green = UInt32((color.greenComponent * 255).rounded())
                let blue = UInt32((color.blueComponent * 255).rounded())
                colors.insert(red << 16 | green << 8 | blue)
            }
        }
        return colors.count
    }

    func count(near target: NSColor, inTopDown rect: CGRect, tolerance: CGFloat = 0.10) -> Int {
        guard let target = target.usingColorSpace(.deviceRGB) else { return 0 }
        let xRange = max(0, Int(rect.minX))..<min(bitmap.pixelsWide, Int(rect.maxX))
        let topYRange = max(0, Int(rect.minY))..<min(bitmap.pixelsHigh, Int(rect.maxY))
        var count = 0
        for topY in topYRange {
            // NSBitmapImageRep decoded from the PNG uses the image's top-down row order.
            let y = topY
            for x in xRange {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if abs(color.redComponent - target.redComponent) <= tolerance,
                   abs(color.greenComponent - target.greenComponent) <= tolerance,
                   abs(color.blueComponent - target.blueComponent) <= tolerance,
                   color.alphaComponent > 0.5 {
                    count += 1
                }
            }
        }
        return count
    }

    func bounds(
        near target: NSColor,
        inTopDown rect: CGRect,
        tolerance: CGFloat
    ) -> CGRect? {
        guard let target = target.usingColorSpace(.deviceRGB) else { return nil }
        let xRange = max(0, Int(rect.minX))..<min(bitmap.pixelsWide, Int(rect.maxX))
        let yRange = max(0, Int(rect.minY))..<min(bitmap.pixelsHigh, Int(rect.maxY))
        var bounds = CGRect.null
        for y in yRange {
            for x in xRange {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      abs(color.redComponent - target.redComponent) <= tolerance,
                      abs(color.greenComponent - target.greenComponent) <= tolerance,
                      abs(color.blueComponent - target.blueComponent) <= tolerance,
                      color.alphaComponent > 0.5
                else { continue }
                bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return bounds.isNull ? nil : bounds
    }

    private func countPixels(where predicate: (NSColor) -> Bool) -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y), predicate(color) {
                    count += 1
                }
            }
        }
        return count
    }
}
