import AppKit
import SwiftUI

/// Every color the app draws with, named by the job it does rather than the
/// hue, so a color scheme is just a different set of answers.
public struct Palette: Sendable {
    /// The strip across the top of the window, and the window behind it.
    public let header: NSColor
    /// Buttons, the running timer, the goal bar, the selected picker row.
    public let accent: Color
    /// The start-timer button.
    public let start: Color
    /// An entry picked in the list.
    public let selection: Color
    public let success: Color
    public let warning: Color
    public let danger: Color
    public let favorite: Color
    /// Pills, cards and the break total bubble.
    public let outline: AnyShapeStyle
    /// Search fields and the picker lists under them.
    public let fieldOutline: AnyShapeStyle
    /// The dashed edge of a break on the timeline.
    public let breakOutline: Color
    /// The empty part of the goal bar.
    public let track: Color
    /// A play button on an entry that isn't running.
    public let idleControl: Color
    /// The ring around a picked timeline block or color swatch.
    public let emphasis: Color
    /// One per project, repeating once they run out, so the same project
    /// reads the same in the list, the chips, and the timeline.
    public let projectColors: [Color]

    public static let harvest = Palette(
        header: NSColor(hex: 0xF36C00),
        accent: Color(hex: 0xF36C00),
        start: Color(hex: 0x3E8542),
        selection: .accentColor,
        success: .green,
        warning: .yellow,
        danger: .red,
        favorite: .yellow,
        outline: AnyShapeStyle(.quaternary),
        fieldOutline: AnyShapeStyle(.separator),
        breakOutline: Color.secondary.opacity(0.35),
        track: Color.primary.opacity(0.08),
        idleControl: .secondary,
        emphasis: .primary,
        projectColors: [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown]
    )

    public var headerColor: Color { Color(nsColor: header) }

    public func forProject(_ projectId: Int64) -> Color {
        projectColors[Int(projectId % Int64(projectColors.count))]
    }

    public func forFavorite(_ favorite: Favorite) -> Color {
        guard let index = favorite.colorIndex, projectColors.indices.contains(index) else {
            return forProject(favorite.projectId)
        }
        return projectColors[index]
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.harvest
}

public extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension NSColor {
    /// Opacity is dropped: every stored color is a solid one.
    var hex: UInt32 {
        guard let rgb = usingColorSpace(.sRGB) else { return 0 }
        func channel(_ value: CGFloat) -> UInt32 {
            UInt32((min(max(value, 0), 1) * 255).rounded())
        }
        return channel(rgb.redComponent) << 16
            | channel(rgb.greenComponent) << 8
            | channel(rgb.blueComponent)
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: opacity))
    }
}
