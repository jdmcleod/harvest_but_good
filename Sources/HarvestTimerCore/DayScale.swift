import Foundation

/// The arithmetic behind the day timeline: which hours it covers, where a time
/// sits down the column, and what the labels beside it read.
///
/// Kept apart from the view because none of it is drawing — it is the part
/// that can be wrong in a way you would have to squint at a screen to notice.
public struct DayScale: Equatable {
    public let startHour: Int
    public let endHour: Int

    public init(startHour: Int = 7, endHour: Int = 19) {
        self.startHour = startHour
        self.endHour = endHour
    }

    public var hourCount: Int { endHour - startHour }

    /// How far down a column of `height` a time falls. Times outside the
    /// day's hours sit at the near edge rather than off the end.
    public func position(of date: Date, height: Double, calendar: Calendar = .current) -> Double {
        let seconds = date.timeIntervalSince(calendar.startOfDay(for: date))
        let fraction = (seconds - Double(startHour * 3600)) / Double(hourCount * 3600)
        return min(max(fraction, 0), 1) * height
    }

    /// The label beside an hour line: "7 AM", "12 PM", "7 PM".
    public func hourLabel(_ hour: Int) -> String {
        let display = hour % 12 == 0 ? 12 : hour % 12
        return "\(display) \(hour < 12 ? "AM" : "PM")"
    }

    /// The label beside a quarter-hour line, counted from the first hour on
    /// the scale. Minutes are padded, so the hour reads "9:00" and not "9:0".
    public func quarterLabel(_ quarter: Int) -> String {
        let hour = startHour + quarter / 4
        let display = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d", display, quarter % 4 * 15)
    }

    /// How far to zoom in so `visibleHours` fill the viewport, held between
    /// the buttons' limits.
    public func zoom(toShow visibleHours: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(Swift.max(Double(hourCount) / visibleHours, lower), upper)
    }
}
