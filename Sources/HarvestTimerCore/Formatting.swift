import Foundation

/// How the app writes and reads durations. Hours are the unit Harvest
/// stores; "h:mm" is the form people type and read.

public func formattedHours(_ hours: Double) -> String {
    let totalMinutes = Int((hours * 60).rounded())
    return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
}

public func parseHours(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    let value: Double
    if let colon = trimmed.firstIndex(of: ":") {
        // ":20" is twenty minutes — a natural way to type less than an hour.
        let hoursText = trimmed[..<colon]
        guard let hours = hoursText.isEmpty ? 0 : Int(hoursText),
              let minutes = Int(trimmed[trimmed.index(after: colon)...]),
              hours >= 0, (0..<60).contains(minutes) else { return nil }
        value = Double(hours) + Double(minutes) / 60
    } else {
        guard let decimal = Double(trimmed), decimal >= 0 else { return nil }
        value = decimal
    }
    return value <= 24 ? value : nil
}

public func formattedDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = Int(seconds / 60)
    if totalMinutes < 1 { return "less than a minute" }
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    switch (hours, minutes) {
    case (0, _): return "\(minutes) min"
    case (_, 0): return hours == 1 ? "1 hour" : "\(hours) hours"
    default: return "\(hours) hr \(minutes) min"
    }
}
