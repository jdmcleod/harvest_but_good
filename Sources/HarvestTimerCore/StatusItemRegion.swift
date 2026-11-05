import CoreGraphics

/// Which half of the menu bar item a click landed on: the play/pause glyph at
/// the leading edge, or the running total that opens the window.
public enum StatusItemRegion: Equatable {
    case timer
    case window

    public static let glyphSize: CGFloat = 16
    public static let glyphLeading: CGFloat = 8
    public static let glyphTrailing: CGFloat = 3
    public static let glyphWidth = glyphLeading + glyphSize + glyphTrailing

    public init(x: CGFloat) {
        self = x < Self.glyphWidth ? .timer : .window
    }
}
