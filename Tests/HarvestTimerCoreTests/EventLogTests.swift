import Foundation
import Testing

@testable import HarvestTimerCore

@Test("The event log")
func runEventLogTests() {
    test("event log round-trips edit and delete actions") {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarvestTimerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = EventLog(directory: directory)
        log.append(TimerEvent(entryId: 42, action: .edit, timestamp: base, projectId: 7), day: day("2026-08-06"))
        log.append(
            TimerEvent(entryId: 43, action: .delete, timestamp: base.addingTimeInterval(60), projectId: 7),
            day: day("2026-08-06")
        )

        let events = log.events(forDay: day("2026-08-06"))
        expect(events.map(\.action) == [.edit, .delete], "actions should round-trip")
        expect(TimelineBuilder.modifiedEntryIds(from: events) == [42, 43], "modified ids should round-trip")
    }

    test("event log append and read round trip") {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarvestTimerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = EventLog(directory: directory)
        let start = TimerEvent(entryId: 42, action: .start, timestamp: base, projectId: 7)
        log.append(start, day: day("2026-08-06"))
        log.append(
            TimerEvent(entryId: 42, action: .stop, timestamp: base.addingTimeInterval(600), projectId: 7),
            day: day("2026-08-06")
        )

        let events = log.events(forDay: day("2026-08-06"))
        expect(events.count == 2, "expected 2 events, got \(events.count)")
        expect(events.first == start, "first event should round-trip")
        expect(log.events(forDay: day("2026-08-05")).isEmpty, "other days should be empty")
    }
}

@Test("The event log file format")
func runEventLogFormatTests() {
    func withLog(_ body: (EventLog, URL) throws -> Void) rethrows {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarvestTimerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(EventLog(directory: directory), directory)
    }

    let logDay = day("2026-08-06")
    func logFile(_ directory: URL) -> URL {
        directory.appendingPathComponent("events-2026-08-06.json")
    }

    test("a day's events keep the order they were appended in") {
        try withLog { log, _ in
            for minute in 0..<50 {
                log.append(
                    event(minute.isMultiple(of: 2) ? .start : .stop, entry: 1, minutes: Double(minute)),
                    day: logDay
                )
            }
            let events = log.events(forDay: logDay)
            expect(events.count == 50, "expected 50 events, got \(events.count)")
            expect(
                events.map(\.timestamp) == events.map(\.timestamp).sorted(),
                "appended events should read back in order"
            )
        }
    }

    test("appending adds a line and leaves the earlier ones alone") {
        try withLog { log, directory in
            log.append(event(.start, entry: 1, minutes: 0), day: logDay)
            let afterFirst = try Data(contentsOf: logFile(directory))
            log.append(event(.stop, entry: 1, minutes: 30), day: logDay)
            let afterSecond = try Data(contentsOf: logFile(directory))

            expect(afterSecond.starts(with: afterFirst), "the first line should be untouched")
            expect(
                afterSecond.split(separator: UInt8(ascii: "\n")).count == 2,
                "one line per event"
            )
        }
    }

    test("a log written as a JSON array is still read") {
        try withLog { log, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let old = """
            [
              {"action": "start", "entryId": 42, "projectId": 7, "timestamp": "2026-08-06T09:00:00Z"},
              {"action": "stop", "entryId": 42, "projectId": 7, "timestamp": "2026-08-06T09:30:00Z"}
            ]
            """
            try Data(old.utf8).write(to: logFile(directory))

            let events = log.events(forDay: logDay)
            expect(events.count == 2, "the old format should still read, got \(events.count)")
            expect(events.map(\.action) == [.start, .stop], "actions should survive")
        }
    }

    test("appending to a JSON array log keeps what was already there") {
        try withLog { log, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let old = """
            [{"action": "start", "entryId": 42, "projectId": 7, "timestamp": "2026-08-06T09:00:00Z"}]
            """
            try Data(old.utf8).write(to: logFile(directory))

            log.append(event(.stop, entry: 42, minutes: 30), day: logDay)
            let events = log.events(forDay: logDay)
            expect(events.count == 2, "the old event should survive the move, got \(events.count)")
            expect(events.first?.action == .start, "the old event should come first")
            expect(events.last?.action == .stop, "the new event should be appended")

            // And the file is lines from now on, so this keeps working.
            log.append(event(.start, entry: 42, minutes: 60), day: logDay)
            expect(log.events(forDay: logDay).count == 3, "later appends should keep landing")
        }
    }

    test("a torn last line does not lose the events before it") {
        try withLog { log, directory in
            log.append(event(.start, entry: 1, minutes: 0), day: logDay)
            log.append(event(.stop, entry: 1, minutes: 30), day: logDay)

            var data = try Data(contentsOf: logFile(directory))
            data.append(contentsOf: Data("{\"action\": \"sta".utf8))
            try data.write(to: logFile(directory))

            expect(log.events(forDay: logDay).count == 2, "the good lines should still read")
        }
    }
}
