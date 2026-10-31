import Foundation

/// The week the app shows: Sunday to Saturday, with the weekdays always on
/// screen and the weekend only when it has something to show.
public struct WeekCalendar {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// The Monday of the week `date` falls in. A Saturday closes the week
    /// before it and a Sunday opens the week after, so each lands in the week
    /// whose total counts its hours.
    public func weekStart(containing date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = weekday == 1 ? -1 : weekday - 2
        return calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -daysFromMonday, to: date)!
        )
    }

    /// The five weekdays of the week `date` falls in.
    public func week(containing date: Date) -> [Date] {
        let monday = weekStart(containing: date)
        return (0..<5).map { calendar.date(byAdding: .day, value: $0, to: monday)! }
    }

    /// Whether `date` is a Saturday or Sunday.
    public func isWeekend(_ date: Date) -> Bool {
        [1, 7].contains(calendar.component(.weekday, from: date))
    }

    /// The days whose hours count toward the week `date` falls in: the
    /// weekdays plus the Sunday before them and the Saturday after.
    public func countedDays(containing date: Date) -> [Date] {
        let monday = weekStart(containing: date)
        return (-1..<6).map { calendar.date(byAdding: .day, value: $0, to: monday)! }
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
