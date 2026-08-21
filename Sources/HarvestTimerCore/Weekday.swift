import Foundation

/// A day of the week, for anything configured per weekday rather than per date.
///
/// `CodingKeyRepresentable` so a dictionary keyed by one encodes as a JSON
/// object — Swift would otherwise write an array of alternating keys and values.
public enum Weekday: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    /// The working week, in the order the header shows it. Matches
    /// `WeekCalendar`, which counts a week as Monday through Friday.
    public static let workdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]

    public init(_ date: Date, calendar: Calendar = .current) {
        // Gregorian numbers Sunday as 1; this enum starts at Monday.
        let weekday = calendar.component(.weekday, from: date)
        self = Self.byGregorianNumber[weekday] ?? .monday
    }

    private static let byGregorianNumber: [Int: Weekday] = [
        1: .sunday, 2: .monday, 3: .tuesday, 4: .wednesday,
        5: .thursday, 6: .friday, 7: .saturday,
    ]

    /// "Mon", for a label with no room for more.
    public var shortName: String { String(rawValue.prefix(3)).capitalized }

    public var name: String { rawValue.capitalized }

    public init?<T>(codingKey: T) where T: CodingKey {
        self.init(rawValue: codingKey.stringValue)
    }

    public var codingKey: CodingKey {
        Key(stringValue: rawValue)!
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
