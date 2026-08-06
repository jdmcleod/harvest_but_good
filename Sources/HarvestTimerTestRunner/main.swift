import Foundation
import HarvestTimerCore

var failures = 0
var passes = 0

func expect(
    _ condition: Bool,
    _ message: String,
    file: String = #file,
    line: Int = #line
) {
    if condition {
        passes += 1
    } else {
        failures += 1
        let filename = URL(fileURLWithPath: file).lastPathComponent
        print("FAIL [\(filename):\(line)] \(message)")
    }
}

func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
    } catch {
        failures += 1
        print("FAIL [\(name)] threw \(error)")
    }
}

let base = Date(timeIntervalSince1970: 1_754_470_800)

func event(_ action: TimerEvent.Action, entry: Int64, project: Int64 = 1, minutes: Double) -> TimerEvent {
    TimerEvent(
        entryId: entry,
        action: action,
        timestamp: base.addingTimeInterval(minutes * 60),
        projectId: project
    )
}

test("pairs start and stop into a block") {
    let blocks = TimelineBuilder.blocks(
        from: [event(.start, entry: 1, minutes: 0), event(.stop, entry: 1, minutes: 30)],
        now: base.addingTimeInterval(3600),
        runningEntryIds: []
    )
    expect(blocks.count == 1, "expected 1 block, got \(blocks.count)")
    expect(blocks.first?.start == base, "block start mismatch")
    expect(blocks.first?.end == base.addingTimeInterval(1800), "block end mismatch")
}

test("open start for a running entry extends to now") {
    let now = base.addingTimeInterval(45 * 60)
    let blocks = TimelineBuilder.blocks(
        from: [event(.start, entry: 1, minutes: 0)],
        now: now,
        runningEntryIds: [1]
    )
    expect(blocks.count == 1, "expected 1 block, got \(blocks.count)")
    expect(blocks.first?.end == now, "open block should end at now")
}

test("open start for a paused entry shows no block") {
    let blocks = TimelineBuilder.blocks(
        from: [event(.start, entry: 1, minutes: 0)],
        now: base.addingTimeInterval(45 * 60),
        runningEntryIds: []
    )
    expect(blocks.isEmpty, "paused entry should have no open block, got \(blocks.count)")
}

test("paused entry keeps its closed blocks") {
    let blocks = TimelineBuilder.blocks(
        from: [
            event(.start, entry: 1, minutes: 0),
            event(.stop, entry: 1, minutes: 20),
            event(.start, entry: 1, minutes: 30),
        ],
        now: base.addingTimeInterval(45 * 60),
        runningEntryIds: []
    )
    expect(blocks.count == 1, "expected only the closed block, got \(blocks.count)")
    expect(blocks.first?.end == base.addingTimeInterval(1200), "closed block end mismatch")
}

test("multiple sessions for the same entry") {
    let blocks = TimelineBuilder.blocks(
        from: [
            event(.start, entry: 1, minutes: 0),
            event(.stop, entry: 1, minutes: 20),
            event(.start, entry: 1, minutes: 60),
            event(.stop, entry: 1, minutes: 90),
        ],
        now: base.addingTimeInterval(7200),
        runningEntryIds: []
    )
    expect(blocks.count == 2, "expected 2 blocks, got \(blocks.count)")
    expect(blocks.first?.end == base.addingTimeInterval(1200), "first block end mismatch")
    expect(blocks.last?.start == base.addingTimeInterval(3600), "second block start mismatch")
}

test("interleaved entries keep their own project colors") {
    let blocks = TimelineBuilder.blocks(
        from: [
            event(.start, entry: 1, project: 1, minutes: 0),
            event(.stop, entry: 1, project: 1, minutes: 15),
            event(.start, entry: 2, project: 2, minutes: 15),
            event(.stop, entry: 2, project: 2, minutes: 45),
        ],
        now: base.addingTimeInterval(7200),
        runningEntryIds: []
    )
    expect(blocks.count == 2, "expected 2 blocks, got \(blocks.count)")
    expect(blocks.first?.projectId == 1, "first block project mismatch")
    expect(blocks.last?.projectId == 2, "second block project mismatch")
}

test("stop without start is ignored") {
    let blocks = TimelineBuilder.blocks(
        from: [event(.stop, entry: 1, minutes: 10)],
        now: base.addingTimeInterval(3600),
        runningEntryIds: []
    )
    expect(blocks.isEmpty, "expected no blocks, got \(blocks.count)")
}

test("duplicate start closes the previous block") {
    let blocks = TimelineBuilder.blocks(
        from: [
            event(.start, entry: 1, minutes: 0),
            event(.start, entry: 1, minutes: 30),
            event(.stop, entry: 1, minutes: 50),
        ],
        now: base.addingTimeInterval(7200),
        runningEntryIds: []
    )
    expect(blocks.count == 2, "expected 2 blocks, got \(blocks.count)")
    expect(blocks.first?.end == base.addingTimeInterval(1800), "first block end mismatch")
    expect(blocks.last?.end == base.addingTimeInterval(3000), "second block end mismatch")
}

test("unsorted events are ordered by timestamp") {
    let blocks = TimelineBuilder.blocks(
        from: [event(.stop, entry: 1, minutes: 30), event(.start, entry: 1, minutes: 0)],
        now: base.addingTimeInterval(7200),
        runningEntryIds: []
    )
    expect(blocks.count == 1, "expected 1 block, got \(blocks.count)")
}

test("start counts per entry") {
    let counts = TimelineBuilder.startCounts(from: [
        event(.start, entry: 1, minutes: 0),
        event(.stop, entry: 1, minutes: 10),
        event(.start, entry: 1, minutes: 20),
        event(.start, entry: 2, minutes: 40),
    ])
    expect(counts[1] == 2, "entry 1 should have 2 starts, got \(String(describing: counts[1]))")
    expect(counts[2] == 1, "entry 2 should have 1 start, got \(String(describing: counts[2]))")
    expect(counts[3] == nil, "entry 3 should have no starts")
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

test("time entry page decodes Harvest JSON") {
    let json = """
    {
      "time_entries": [{
        "id": 636709355,
        "spent_date": "2026-08-06",
        "hours": 2.11,
        "notes": "Debugging",
        "is_running": true,
        "timer_started_at": "2026-08-06T14:00:00Z",
        "project": {"id": 14308069, "name": "Online Store"},
        "task": {"id": 8083365, "name": "Programming"},
        "client": {"id": 5735774, "name": "ABC Corp"}
      }],
      "next_page": null
    }
    """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    let page = try decoder.decode(TimeEntriesPage.self, from: Data(json.utf8))
    expect(page.timeEntries.count == 1, "expected 1 entry")
    expect(page.timeEntries.first?.project.name == "Online Store", "project name mismatch")
    expect(page.timeEntries.first?.isRunning == true, "should be running")
    expect(page.timeEntries.first?.timerStartedAt != nil, "timer_started_at should decode")
    expect(page.nextPage == nil, "next_page should be nil")
}

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
