import Foundation
import HarvestTimerCore

func runEventLogTests() {
    test("parses durations in h:mm and decimal formats") {
        expect(parseHours("1:30") == 1.5, "1:30 should parse to 1.5")
        expect(parseHours("0:45") == 0.75, "0:45 should parse to 0.75")
        expect(parseHours(" 2.25 ") == 2.25, "decimal with whitespace should parse")
        expect(parseHours("0") == 0, "zero should parse")
        expect(parseHours("24:00") == 24, "24:00 should parse")
        expect(parseHours("abc") == nil, "letters should not parse")
        expect(parseHours("1:75") == nil, "minutes over 59 should not parse")
        expect(parseHours("-1") == nil, "negative should not parse")
        expect(parseHours("25") == nil, "over 24 hours should not parse")
        expect(parseHours(":30") == 0.5, "leading colon means minutes only")
        expect(parseHours(":90") == nil, "minutes over 59 still should not parse")
        expect(parseHours(":") == nil, "a bare colon should not parse")
    }

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

    test("appending an identical event is ignored") {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarvestTimerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = EventLog(directory: directory)
        let start = TimerEvent(entryId: 42, action: .start, timestamp: base, projectId: 7)
        log.append(start, day: "2026-08-06")
        log.append(start, day: "2026-08-06")
        log.append(
            TimerEvent(entryId: 42, action: .start, timestamp: base.addingTimeInterval(60), projectId: 7),
            day: "2026-08-06"
        )

        let events = log.events(forDay: "2026-08-06")
        expect(events.count == 2, "duplicate should be dropped, got \(events.count) events")
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
