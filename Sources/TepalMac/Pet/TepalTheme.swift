import AppKit
import CoreGraphics
import TepalCore

@MainActor
public struct TepalPalette {
    public let bodyTop: NSColor
    public let bodyBottom: NSColor
    public let bodyShade: NSColor
    public let leaf: NSColor
    public let eye: NSColor
    public let glow: NSColor
    public let habitatBase: NSColor
    public let habitatAccent: NSColor
    public let habitatShadow: NSColor
    public let primaryText: NSColor
    public let secondaryText: NSColor
    public let primaryAction: NSColor
    public let divider: NSColor
    public let groundNear: NSColor
    public let groundMiddle: NSColor
    public let groundFar: NSColor
    public let pollen: NSColor
    public let meetingCoral: NSColor

    // Temporary compatibility token for existing surfaces. Task 4 migrates palette cards to gradients.
    public var body: NSColor { bodyBottom }

    /// The visible boundary of the compact More control. This intentionally uses the
    /// palette's non-text action color instead of the low-emphasis shelf divider.
    public var moreControlBorder: NSColor { primaryAction }

    /// The body-local caption uses an opaque semantic pair so its contrast does not
    /// depend on which endpoint of the creature gradient is directly beneath it.
    public var personalityCaptionForeground: NSColor { primaryText }
    public var personalityCaptionBackground: NSColor { habitatShadow }

    fileprivate init(
        bodyTop: UInt32,
        bodyBottom: UInt32,
        bodyShade: UInt32,
        leaf: UInt32,
        eye: UInt32,
        glow: UInt32,
        habitatBase: UInt32,
        habitatAccent: UInt32,
        habitatShadow: UInt32,
        primaryText: UInt32,
        secondaryText: UInt32,
        primaryAction: UInt32,
        divider: UInt32,
        groundNear: UInt32,
        groundMiddle: UInt32,
        groundFar: UInt32,
        pollen: UInt32,
        meetingCoral: UInt32
    ) {
        self.bodyTop = NSColor(hex: bodyTop)
        self.bodyBottom = NSColor(hex: bodyBottom)
        self.bodyShade = NSColor(hex: bodyShade)
        self.leaf = NSColor(hex: leaf)
        self.eye = NSColor(hex: eye)
        self.glow = NSColor(hex: glow)
        self.habitatBase = NSColor(hex: habitatBase)
        self.habitatAccent = NSColor(hex: habitatAccent)
        self.habitatShadow = NSColor(hex: habitatShadow)
        self.primaryText = NSColor(hex: primaryText)
        self.secondaryText = NSColor(hex: secondaryText)
        self.primaryAction = NSColor(hex: primaryAction)
        self.divider = NSColor(hex: divider)
        self.groundNear = NSColor(hex: groundNear)
        self.groundMiddle = NSColor(hex: groundMiddle)
        self.groundFar = NSColor(hex: groundFar)
        self.pollen = NSColor(hex: pollen)
        self.meetingCoral = NSColor(hex: meetingCoral)
    }
}

@MainActor
public enum TepalLayout {
    public static let panelSize = CGSize(width: 360, height: 640)
    public static let habitatHeight: CGFloat = 350
    public static let shelfHeight: CGFloat = 290
    public static let shellRadius: CGFloat = 30
    public static let shelfInset: CGFloat = 24
    public static let timerPointSize: CGFloat = 60
    public static let characterSize = CGSize(width: 92, height: 86)
    public static let primaryControlHeight: CGFloat = 46
    public static let compactControlWidth: CGFloat = 46
}

@MainActor
public enum TepalTheme {
    public static let statusError = NSColor.systemRed

    public static func palette(for id: TepalPaletteID) -> TepalPalette {
        switch id {
        case .moonFern:
            TepalPalette(
                bodyTop: 0xC8F5A4,
                bodyBottom: 0x58B899,
                bodyShade: 0x1A7566,
                leaf: 0xDDFFAF,
                eye: 0xF8FFF3,
                glow: 0x8AEFB3,
                habitatBase: 0x111916,
                habitatAccent: 0x1E382F,
                habitatShadow: 0x08110C,
                primaryText: 0xEAF4E6,
                secondaryText: 0xB8C9B8,
                primaryAction: 0x8AEFB3,
                divider: 0x365043,
                groundNear: 0x72A968,
                groundMiddle: 0x4E8C63,
                groundFar: 0x315A47,
                pollen: 0xF2D889,
                meetingCoral: 0xF08B75
            )
        case .twilightPlum:
            TepalPalette(
                bodyTop: 0xA28BC2,
                bodyBottom: 0x76558C,
                bodyShade: 0x49325C,
                leaf: 0xA28BC2,
                eye: 0xF5EDFA,
                glow: 0xD5BAFF,
                habitatBase: 0x18131E,
                habitatAccent: 0x382743,
                habitatShadow: 0x0D0A10,
                primaryText: 0xF5EDFA,
                secondaryText: 0xC9BDD0,
                primaryAction: 0xD5BAFF,
                divider: 0x4B3A58,
                groundNear: 0xA28BC2,
                groundMiddle: 0x76558C,
                groundFar: 0x4B3560,
                pollen: 0xF2D889,
                meetingCoral: 0xF08B75
            )
        case .dewdrop:
            TepalPalette(
                bodyTop: 0x71C9BE,
                bodyBottom: 0x367B7C,
                bodyShade: 0x1B5D5C,
                leaf: 0x71C9BE,
                eye: 0xE6F7F4,
                glow: 0xAFE9DC,
                habitatBase: 0x0E1B1C,
                habitatAccent: 0x1B3C3D,
                habitatShadow: 0x071011,
                primaryText: 0xE6F7F4,
                secondaryText: 0xB8D3CF,
                primaryAction: 0xAFE9DC,
                divider: 0x285253,
                groundNear: 0x71C9BE,
                groundMiddle: 0x367B7C,
                groundFar: 0x265758,
                pollen: 0xF2D889,
                meetingCoral: 0xF08B75
            )
        case .pollenGold:
            TepalPalette(
                bodyTop: 0xC9A84E,
                bodyBottom: 0x8A6323,
                bodyShade: 0x604514,
                leaf: 0xC9A84E,
                eye: 0xFFF6DE,
                glow: 0xF2D889,
                habitatBase: 0x1D180D,
                habitatAccent: 0x493818,
                habitatShadow: 0x100C05,
                primaryText: 0xFFF6DE,
                secondaryText: 0xDBCBAA,
                primaryAction: 0xF2D889,
                divider: 0x5A4825,
                groundNear: 0xC9A84E,
                groundMiddle: 0x8A6323,
                groundFar: 0x604514,
                pollen: 0xF2D889,
                meetingCoral: 0xF08B75
            )
        case .emberMoss:
            TepalPalette(
                bodyTop: 0xB97555,
                bodyBottom: 0x854F3D,
                bodyShade: 0x5A2E24,
                leaf: 0xB97555,
                eye: 0xFBEDE7,
                glow: 0xF2B38F,
                habitatBase: 0x1D1411,
                habitatAccent: 0x47271D,
                habitatShadow: 0x100A08,
                primaryText: 0xFBEDE7,
                secondaryText: 0xD9BDB2,
                primaryAction: 0xF2B38F,
                divider: 0x59372C,
                groundNear: 0xB97555,
                groundMiddle: 0x854F3D,
                groundFar: 0x5A2E24,
                pollen: 0xF2D889,
                meetingCoral: 0xF08B75
            )
        case .frostBloom:
            TepalPalette(
                bodyTop: 0x9CBBD6,
                bodyBottom: 0x5B7194,
                bodyShade: 0x3B5175,
                leaf: 0x9CBBD6,
                eye: 0xEEF7FC,
                glow: 0xCBE7F5,
                habitatBase: 0x111923,
                habitatAccent: 0x24374B,
                habitatShadow: 0x09101A,
                primaryText: 0xEEF7FC,
                secondaryText: 0xBDCEDA,
                primaryAction: 0xCBE7F5,
                divider: 0x354B61,
                groundNear: 0x9CBBD6,
                groundMiddle: 0x5B7194,
                groundFar: 0x3B5175,
                pollen: 0xF2D889,
                meetingCoral: 0xF08B75
            )
        }
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        precondition(hex <= 0xFF_FF_FF, "Tepal colors must use six hexadecimal digits")
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
