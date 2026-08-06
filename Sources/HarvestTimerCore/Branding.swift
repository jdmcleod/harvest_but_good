import AppKit
import SwiftUI

public extension Color {
    static let harvest = Color(red: 243 / 255, green: 108 / 255, blue: 0)
}

public extension NSColor {
    static let harvest = NSColor(red: 243 / 255, green: 108 / 255, blue: 0, alpha: 1)
}

public extension View {
    func pointingCursor(_ enabled: Bool = true) -> some View {
        modifier(PointingCursorModifier(enabled: enabled))
    }
}

private struct PointingCursorModifier: ViewModifier {
    let enabled: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside && enabled && !pushed {
                    NSCursor.pointingHand.push()
                    pushed = true
                } else if !inside && pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onChange(of: enabled) { _, stillEnabled in
                if !stillEnabled && pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
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
