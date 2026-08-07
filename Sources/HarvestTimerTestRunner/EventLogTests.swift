import Foundation
import HarvestTimerCore

func runEventLogTests() {
    test("event log round-trips edit and delete actions") {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarvestTimerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = EventLog(directory: directory)
        log.append(TimerEvent(entryId: 42, action: .edit, timestamp: base, projectId: 7), day: "2026-08-06")
        log.append(
            TimerEvent(entryId: 43, action: .delete, timestamp: base.addingTimeInterval(60), projectId: 7),
            day: "2026-08-06"
        )

        let events = log.events(forDay: "2026-08-06")
        expect(events.map(\.action) == [.edit, .delete], "actions should round-trip")
        expect(TimelineBuilder.modifiedEntryIds(from: events) == [42, 43], "modified ids should round-trip")
    }

    test("event log append and read round trip") {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarvestTimerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = EventLog(directory: directory)
        let start = TimerEvent(entryId: 42, action: .start, timestamp: base, projectId: 7)
        log.append(start, day: "2026-08-06")
        log.append(
            TimerEvent(entryId: 42, action: .stop, timestamp: base.addingTimeInterval(600), projectId: 7),
            day: "2026-08-06"
        )

        let events = log.events(forDay: "2026-08-06")
        expect(events.count == 2, "expected 2 events, got \(events.count)")
        expect(events.first == start, "first event should round-trip")
        expect(log.events(forDay: "2026-08-05").isEmpty, "other days should be empty")
    }
}
