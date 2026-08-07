import Foundation

/// The entries on hand, filed by day. It owns how one is found and how an
/// update lands, so `AppState` is left deciding only when to ask Harvest.
///
/// A day's entries come back sorted by id, which is the order Harvest created
/// them in and the order the list shows.
public struct EntryBook: Equatable {
    private var byDay: [Day: [TimeEntry]] = [:]

    public init(_ entries: [TimeEntry] = []) {
        for entry in entries {
            byDay[entry.spentDate, default: []].append(entry)
        }
    }

    public func entries(on day: Day) -> [TimeEntry] {
        (byDay[day] ?? []).sorted { $0.id < $1.id }
    }

    public var all: [TimeEntry] {
        byDay.keys.sorted().flatMap { entries(on: $0) }
    }

    public var running: TimeEntry? {
        all.first { $0.isRunning }
    }

    public func entry(withId id: Int64) -> TimeEntry? {
        all.first { $0.id == id }
    }

    /// The copy held here, which may have moved on since the caller took its
    /// own. Falls back to what the caller has when the entry is gone.
    public func currentVersion(of entry: TimeEntry) -> TimeEntry {
        byDay[entry.spentDate]?.first { $0.id == entry.id } ?? entry
    }

    /// Files `updated`, adding it if it is new. A running entry stops every
    /// other one, because Harvest only ever runs one at a time.
    public mutating func apply(_ updated: TimeEntry) {
        if updated.isRunning {
            for (day, list) in byDay {
                byDay[day] = list.map { entry in
                    var entry = entry
                    if entry.id != updated.id { entry.isRunning = false }
                    return entry
                }
            }
        }
        var day = byDay[updated.spentDate] ?? []
        if let index = day.firstIndex(where: { $0.id == updated.id }) {
            day[index] = updated
        } else {
            day.append(updated)
        }
        byDay[updated.spentDate] = day
    }

    public mutating func remove(_ entry: TimeEntry) {
        byDay[entry.spentDate] = (byDay[entry.spentDate] ?? []).filter { $0.id != entry.id }
    }

    /// Takes `days` from a fresh sync: each one is replaced outright, so an
    /// entry deleted in Harvest goes from here too. Days outside the range
    /// are left alone.
    public mutating func replace(_ days: [Day], with entries: [TimeEntry]) {
        var grouped: [Day: [TimeEntry]] = [:]
        for entry in entries {
            grouped[entry.spentDate, default: []].append(entry)
        }
        for day in days {
            byDay[day] = grouped[day] ?? []
        }
    }

    public mutating func removeAll() {
        byDay = [:]
    }
}
