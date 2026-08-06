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

public func parseHours(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    let value: Double
    if let colon = trimmed.firstIndex(of: ":") {
        guard let hours = Int(trimmed[..<colon]),
              let minutes = Int(trimmed[trimmed.index(after: colon)...]),
              hours >= 0, (0..<60).contains(minutes) else { return nil }
        value = Double(hours) + Double(minutes) / 60
    } else {
        guard let decimal = Double(trimmed), decimal >= 0 else { return nil }
        value = decimal
    }
    return value <= 24 ? value : nil
}
