import Foundation

/// The working week the app shows: Monday to Friday, whichever day you are on.
public struct WeekCalendar {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// The Monday of the week `date` falls in. A Saturday or Sunday belongs to
    /// the week that just finished, so both look back to it.
    public func weekStart(containing date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -daysFromMonday, to: date)!
        )
    }

    /// The five weekdays of the week `date` falls in.
    public func week(containing date: Date) -> [Date] {
        let monday = weekStart(containing: date)
        return (0..<5).map { calendar.date(byAdding: .day, value: $0, to: monday)! }
    }

    /// Every day from `from` to `to`, both ends included.
    public func days(from: Day, to: Day) -> [Day] {
        guard let start = from.date, let end = to.date else { return [] }
        var days: [Day] = []
        var current = start
        while current <= end {
            days.append(Day(current))
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return days
    }
}
