import Foundation

/// Fixed times of day something refreshes at, e.g. 7am and 5pm. Answers
/// when the last one was and when the next one is.
public struct RefreshSchedule: Equatable, Sendable {
    public let hours: [Int]
    public let calendar: Calendar

    public init(hours: [Int], calendar: Calendar = .current) {
        self.hours = hours.sorted()
        self.calendar = calendar
    }

    /// The most recent scheduled time at or before `now`.
    public func latest(atOrBefore now: Date) -> Date? {
        times(around: now).last { $0 <= now }
    }

    /// The first scheduled time strictly after `now`.
    public func next(after now: Date) -> Date? {
        times(around: now).first { $0 > now }
    }

    private func times(around now: Date) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (-1...1).flatMap { offset -> [Date] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
            return hours.compactMap {
                calendar.date(bySettingHour: $0, minute: 0, second: 0, of: day)
            }
        }
    }
}
