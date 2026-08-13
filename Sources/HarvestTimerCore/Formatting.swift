import Foundation

/// How the app writes and reads durations. Hours are the unit Harvest stores;
/// "h:mm" is the form people type and read.
public enum Hours {
    /// 1.5 hours as "1:30".
    public static func formatted(_ hours: Double) -> String {
        let totalMinutes = minutes(in: hours)
        return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
    }

    /// What `formatted` shows, as a number. Reading a duration back off the
    /// screen loses anything finer than the minute, so a value that has been
    /// through here survives the round trip unchanged.
    public static func toNearestMinute(_ hours: Double) -> Double {
        Double(minutes(in: hours)) / 60
    }

    private static func minutes(in hours: Double) -> Int {
        Int((hours * 60).rounded())
    }

    /// Reads "1:30", ":20", "2.25", or bare digits that fill in from the right
    /// as h:mm — "69" is an hour and nine. Nothing negative, nothing over a
    /// day. Returns nil for anything else.
    public static func parse(_ text: String) -> Double? {
        capped(magnitude(of: text.trimmingCharacters(in: .whitespaces)))
    }

    /// The same forms, plus a leading "+" or "-" meaning a change to `current`
    /// rather than a replacement for it: "+15" is a quarter hour more than
    /// whatever is already there.
    public static func parse(_ text: String, relativeTo current: Double) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let sign = trimmed.first, sign == "+" || sign == "-" else {
            return capped(magnitude(of: trimmed))
        }
        guard let delta = magnitude(
            of: trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        ) else { return nil }
        return capped(current + (sign == "+" ? delta : -delta))
    }

    /// A duration runs from nothing to a full day. Past either end it is a
    /// typo — subtracting more than is there, or a mistyped year of work.
    private static func capped(_ value: Double?) -> Double? {
        guard let value, (0...24).contains(value) else { return nil }
        return value
    }

    /// The unsigned part of a duration, with no cap applied. In the h:mm and
    /// bare-digit forms minutes roll over: a written 90 minutes is an hour and
    /// a half either way.
    private static func magnitude(of text: String) -> Double? {
        // ":20" is twenty minutes — a natural way to type less than an hour.
        if let colon = text.firstIndex(of: ":") {
            return clock(hours: text[..<colon], minutes: text[text.index(after: colon)...])
        }
        // A decimal point is what tells hours from minutes: "2.25" is two and
        // a quarter hours, where a bare "2" is two minutes.
        if text.contains(".") {
            guard let decimal = Double(text), decimal >= 0, decimal.isFinite else { return nil }
            return decimal
        }
        // Bare digits fill in from the right, the way a punch clock reads:
        // the last two are minutes, anything before them is hours.
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let split = text.index(text.endIndex, offsetBy: -2, limitedBy: text.startIndex) ?? text.startIndex
        return clock(hours: text[..<split], minutes: text[split...])
    }

    /// Hours and minutes as typed, with minutes free to run past 59. An empty
    /// hours part is none at all, which is what ":20" and "45" both leave.
    private static func clock(hours: Substring, minutes: Substring) -> Double? {
        guard let hours = hours.isEmpty ? 0 : Int(hours), let minutes = Int(minutes),
              hours >= 0, minutes >= 0 else { return nil }
        return Double(hours) + Double(minutes) / 60
    }

    /// A span of seconds as prose — "45 min", "1 hr 12 min" — for the places
    /// that talk to the reader rather than tabulate.
    public static func inWords(seconds: TimeInterval) -> String {
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
}
