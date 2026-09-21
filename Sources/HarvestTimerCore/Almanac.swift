import Foundation

/// Credentials for reaching Almanac: where it lives, the API key, and the
/// email that identifies you to it.
///
/// The key alone proves nothing about who holds it — Almanac only checks that
/// it names *some* valid key — so the email is what ties the pace and time
/// off it returns back to a person.
public struct AlmanacCredentials: Equatable, Codable, Sendable {
    public static let defaultBaseURL = "https://almanac.rolemodel.dev"

    public var baseURL: String
    public var apiKey: String
    public var email: String

    public init(
        baseURL: String = AlmanacCredentials.defaultBaseURL,
        apiKey: String,
        email: String
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.email = email
    }
}

/// A point in the day, the way Almanac writes a constraint's start and end
/// time — nominally "13:00:00", though a bare `time` column serialized
/// through Rails' JSON encoder can arrive as a full ISO8601 stamp on a dummy
/// date instead ("2000-01-01T13:00:00.000Z"), since Rails casts a `time`
/// column to a `Time` anchored at 2000-01-01 and serializes it like any
/// other timestamp. Parsed leniently enough to take either shape, since a
/// silent misparse here reads as "no time off" rather than an error.
public struct TimeOfDay: Equatable, Sendable {
    public let secondsSinceMidnight: Int

    public init(secondsSinceMidnight: Int) {
        self.secondsSinceMidnight = secondsSinceMidnight
    }

    public var hours: Double { Double(secondsSinceMidnight) / 3600 }

    public init?(string: String) {
        // Drop everything up to the last "T" or space, so a bare "13:00:00"
        // and "2000-01-01T13:00:00.000Z" both leave just the time-of-day
        // behind; a trailing ".000Z" then falls out of the digits-and-colons
        // filter below on its own.
        let afterDate = string.split(whereSeparator: { $0 == "T" || $0 == " " }).last ?? Substring(string)
        let timeDigits = afterDate.prefix { $0.isNumber || $0 == ":" }
        let parts = timeDigits.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        let seconds = parts.count > 2 ? parts[2] : 0
        secondsSinceMidnight = parts[0] * 3600 + parts[1] * 60 + seconds
    }
}

extension TimeOfDay: Codable {
    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let value = TimeOfDay(string: string) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Not a HH:MM:SS time: \(string)"
            ))
        }
        self = value
    }

    /// Written back the same "HH:MM:SS" shape Almanac sent it in, so the
    /// cache on disk round-trips through the same decoder that reads Almanac.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let hours = secondsSinceMidnight / 3600
        let minutes = (secondsSinceMidnight % 3600) / 60
        let seconds = secondsSinceMidnight % 60
        try container.encode(String(format: "%02d:%02d:%02d", hours, minutes, seconds))
    }
}

/// One person, as much of Almanac's GraphQL `people` query as this app needs
/// — just enough to resolve an email to the id `totalPace(personId:)` wants.
public struct AlmanacPerson: Decodable, Equatable, Sendable {
    public let id: String
    public let email: String
}

/// The pace Almanac has already worked out for the current quarter, netting
/// out planned time off ahead of it.
///
/// `suggestedDailyPace` is the number this app wants — Almanac's own
/// `PersonPace#suggested_daily_pace` spreads the hours remaining this quarter
/// over the weekdays remaining, minus whatever those weekdays already have
/// booked off.
public struct AlmanacPace: Codable, Equatable, Sendable {
    public let suggestedDailyPace: Double
    public let target: Double
    public let worked: Double
    public let remaining: Double
    public let daysIntoReport: Double
}

/// A stretch of time unavailable to work — vacation, a holiday, a half day —
/// mirroring Almanac's `Constraint` model closely enough to score a day
/// against it.
public struct AlmanacConstraint: Codable, Equatable, Sendable {
    public let id: Int
    public let name: String?
    public let startDate: Day
    public let endDate: Day
    public let startTime: TimeOfDay?
    public let endTime: TimeOfDay?
    public let billableOnly: Bool
    public let companyWide: Bool

    /// A single day with both times set — Almanac's own
    /// `Constraint#less_than_one_day?`. Anything else (all day, or spanning
    /// more than one date) takes the whole day.
    public var isPartialDay: Bool {
        startDate == endDate && startTime != nil && endTime != nil
    }

    /// Whether `day` falls anywhere in the constrained range.
    public func covers(_ day: Day) -> Bool {
        startDate <= day && day <= endDate
    }
}
