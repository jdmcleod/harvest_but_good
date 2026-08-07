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

test("duplicate start drops the dangling block instead of filling the gap") {
    let blocks = TimelineBuilder.blocks(
        from: [
            event(.start, entry: 1, minutes: 0),
            event(.start, entry: 1, minutes: 30),
            event(.stop, entry: 1, minutes: 50),
        ],
        now: base.addingTimeInterval(7200),
        runningEntryIds: []
    )
    expect(blocks.count == 1, "expected 1 block, got \(blocks.count)")
    expect(blocks.first?.start == base.addingTimeInterval(1800), "block start mismatch")
    expect(blocks.first?.end == base.addingTimeInterval(3000), "block end mismatch")
}

test("starting another entry closes the open block at that moment") {
    let blocks = TimelineBuilder.blocks(
        from: [
            event(.start, entry: 1, project: 1, minutes: 0),
            event(.start, entry: 2, project: 2, minutes: 20),
            event(.stop, entry: 2, project: 2, minutes: 45),
        ],
        now: base.addingTimeInterval(7200),
        runningEntryIds: []
    )
    expect(blocks.count == 2, "expected 2 blocks, got \(blocks.count)")
    expect(blocks.first?.entryId == 1, "first block entry mismatch")
    expect(blocks.first?.end == base.addingTimeInterval(1200), "entry 1 should end when entry 2 starts")
    expect(blocks.last?.end == base.addingTimeInterval(2700), "entry 2 end mismatch")
}

test("restarting an entry with a lost stop does not fill the idle gap") {
    let blocks = TimelineBuilder.blocks(
        from: [
            event(.start, entry: 1, minutes: 0),
            event(.start, entry: 2, minutes: 2),
            event(.stop, entry: 2, minutes: 7),
            event(.start, entry: 1, minutes: 195),
            event(.stop, entry: 1, minutes: 200),
        ],
        now: base.addingTimeInterval(220 * 60),
        runningEntryIds: []
    )
    expect(blocks.count == 3, "expected 3 blocks, got \(blocks.count)")
    expect(blocks[0].end == base.addingTimeInterval(2 * 60), "entry 1 should end when entry 2 starts")
    expect(blocks[2].start == base.addingTimeInterval(195 * 60), "restart should open a fresh block")
    expect(blocks[2].end == base.addingTimeInterval(200 * 60), "restart block end mismatch")
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

test("edit and delete events do not affect blocks") {
    let blocks = TimelineBuilder.blocks(
        from: [
            event(.start, entry: 1, minutes: 0),
            event(.edit, entry: 1, minutes: 10),
            event(.stop, entry: 1, minutes: 30),
            event(.delete, entry: 1, minutes: 40),
        ],
        now: base.addingTimeInterval(3600),
        runningEntryIds: []
    )
    expect(blocks.count == 1, "expected 1 block, got \(blocks.count)")
    expect(blocks.first?.end == base.addingTimeInterval(1800), "block end mismatch")
}

test("modified entry ids come from edit and delete events") {
    let ids = TimelineBuilder.modifiedEntryIds(from: [
        event(.start, entry: 1, minutes: 0),
        event(.stop, entry: 1, minutes: 30),
        event(.edit, entry: 2, minutes: 40),
        event(.delete, entry: 3, minutes: 50),
    ])
    expect(ids == [2, 3], "expected entries 2 and 3, got \(ids)")
}

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
    expect(parseHours(":30") == nil, "missing hours should not parse")
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

test("afk detector stays quiet below tolerance") {
    let prompt = AFKDetector.evaluate(
        prompt: nil,
        idleSeconds: 299,
        toleranceSeconds: 300,
        runningEntryId: 1,
        now: base
    )
    expect(prompt == nil, "should not prompt below tolerance")
}

test("afk detector needs a running timer") {
    let prompt = AFKDetector.evaluate(
        prompt: nil,
        idleSeconds: 600,
        toleranceSeconds: 300,
        runningEntryId: nil,
        now: base
    )
    expect(prompt == nil, "should not prompt without a running timer")
}

test("afk detector is disabled at zero tolerance") {
    let prompt = AFKDetector.evaluate(
        prompt: nil,
        idleSeconds: 6000,
        toleranceSeconds: 0,
        runningEntryId: 1,
        now: base
    )
    expect(prompt == nil, "zero tolerance should disable detection")
}

test("afk detector prompts when tolerance is crossed") {
    let prompt = AFKDetector.evaluate(
        prompt: nil,
        idleSeconds: 300,
        toleranceSeconds: 300,
        runningEntryId: 7,
        now: base.addingTimeInterval(300)
    )
    expect(prompt?.entryId == 7, "prompt should carry the running entry id")
    expect(prompt?.start == base, "prompt should start at the last activity")
    expect(prompt?.returnedAt == nil, "prompt should not be returned yet")
}

test("afk prompt keeps growing while still idle") {
    let existing = AFKPrompt(entryId: 7, start: base)
    let prompt = AFKDetector.evaluate(
        prompt: existing,
        idleSeconds: 900,
        toleranceSeconds: 300,
        runningEntryId: 7,
        now: base.addingTimeInterval(900)
    )
    expect(prompt?.returnedAt == nil, "still idle should stay unreturned")
    expect(prompt?.duration(now: base.addingTimeInterval(900)) == 900, "duration should track now")
}

test("afk prompt freezes at the moment of return") {
    let existing = AFKPrompt(entryId: 7, start: base)
    let prompt = AFKDetector.evaluate(
        prompt: existing,
        idleSeconds: 5,
        toleranceSeconds: 300,
        runningEntryId: 7,
        now: base.addingTimeInterval(600)
    )
    expect(prompt?.returnedAt == base.addingTimeInterval(595), "return should be last activity")
    expect(
        prompt?.duration(now: base.addingTimeInterval(9999)) == 595,
        "frozen duration should ignore now"
    )
}

test("afk prompt does not unfreeze on later idleness") {
    let existing = AFKPrompt(entryId: 7, start: base, returnedAt: base.addingTimeInterval(600))
    let prompt = AFKDetector.evaluate(
        prompt: existing,
        idleSeconds: 400,
        toleranceSeconds: 300,
        runningEntryId: 7,
        now: base.addingTimeInterval(1200)
    )
    expect(prompt == existing, "frozen prompt should not change")
}

test("afk prompt survives the timer stopping") {
    let existing = AFKPrompt(entryId: 7, start: base)
    let prompt = AFKDetector.evaluate(
        prompt: existing,
        idleSeconds: 600,
        toleranceSeconds: 300,
        runningEntryId: nil,
        now: base.addingTimeInterval(600)
    )
    expect(prompt?.entryId == 7, "existing prompt should survive a stopped timer")
}

test("formats durations for the afk prompt") {
    expect(formattedDuration(30) == "less than a minute", "sub-minute mismatch")
    expect(formattedDuration(60) == "1 min", "one minute mismatch")
    expect(formattedDuration(45 * 60) == "45 min", "minutes mismatch")
    expect(formattedDuration(3600) == "1 hour", "one hour mismatch")
    expect(formattedDuration(2 * 3600) == "2 hours", "hours mismatch")
    expect(formattedDuration(3600 + 12 * 60) == "1 hr 12 min", "mixed mismatch")
}

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
