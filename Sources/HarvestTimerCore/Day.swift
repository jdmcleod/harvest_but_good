import Foundation

/// A calendar day, in the "yyyy-MM-dd" form Harvest books time against.
///
/// The app passed these around as bare strings, which put a `Date` and a day
/// name in reach of the same parameter. This keeps them apart, and keeps the
/// one formatter that knows how to convert between them in one place.
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let name: String

    /// A fixed locale and calendar, so a Buddhist or Japanese regional setting
    /// can't hand Harvest a year it won't recognise.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()

    public init(_ date: Date) {
        name = Self.formatter.string(from: date)
    }

    /// Nil unless `name` really is a "yyyy-MM-dd" date.
    public init?(name: String) {
        guard Self.formatter.date(from: name) != nil else { return nil }
        self.name = name
    }

    public var date: Date? {
        Self.formatter.date(from: name)
    }

    public var description: String { name }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        lhs.name < rhs.name
    }

    // Harvest writes a day as a bare string, so encode as one.
    public init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let day = Day(name: name) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Not a yyyy-MM-dd day: \(name)"
            ))
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}
