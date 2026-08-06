import AppKit
import SwiftUI

public extension Color {
    static let harvest = Color(red: 243 / 255, green: 108 / 255, blue: 0)
}

public extension NSColor {
    static let harvest = NSColor(red: 243 / 255, green: 108 / 255, blue: 0, alpha: 1)
}

public func formattedHours(_ hours: Double) -> String {
    let totalMinutes = Int((hours * 60).rounded())
    return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
}
