import AppKit
import SwiftUI

/// Every color the app draws with, named by the job it does rather than the
/// hue, so a color scheme is just a different set of answers. The schemes
/// themselves live in `ColorSchemes.swift`.
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

/// Which `Palette` the app is wearing. Stored by raw value, so renaming a
/// case strands whoever had it picked back on Harvest.
public enum ColorTheme: String, CaseIterable, Sendable {
    case harvest
    case kattsafe

    public var palette: Palette {
        switch self {
        case .harvest: return .harvest
        case .kattsafe: return .kattsafe
        }
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
