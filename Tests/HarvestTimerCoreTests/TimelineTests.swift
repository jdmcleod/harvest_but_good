import Foundation
import Testing

@testable import HarvestTimerCore

func event(_ action: TimerEvent.Action, entry: Int64, project: Int64 = 1, minutes: Double) -> TimerEvent {
    TimerEvent(
        entryId: entry,
        action: action,
        timestamp: base.addingTimeInterval(minutes * 60),
        projectId: project
    )
}

@Test("Building the timeline")
func runTimelineTests() {
    test("pairs start and stop into a block") {
        let blocks = TimelineBuilder.blocks(
            from: [event(.start, entry: 1, minutes: 0), event(.stop, entry: 1, minutes: 30)],
            now: base.addingTimeInterval(3600),
            running: []
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
            running: [RunningTimer(entryId: 1, projectId: 1, startedAt: nil)]
        )
        expect(blocks.count == 1, "expected 1 block, got \(blocks.count)")
        expect(blocks.first?.end == now, "open block should end at now")
    }

    test("open start for a paused entry shows no block") {
        let blocks = TimelineBuilder.blocks(
            from: [event(.start, entry: 1, minutes: 0)],
            now: base.addingTimeInterval(45 * 60),
            running: []
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
            running: []
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
            running: []
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
            running: []
        )
        expect(blocks.count == 2, "expected 2 blocks, got \(blocks.count)")
        expect(blocks.first?.projectId == 1, "first block project mismatch")
        expect(blocks.last?.projectId == 2, "second block project mismatch")
    }

    test("stop without start is ignored") {
        let blocks = TimelineBuilder.blocks(
            from: [event(.stop, entry: 1, minutes: 10)],
            now: base.addingTimeInterval(3600),
            running: []
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
            running: []
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
            running: []
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
            running: []
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
            running: []
        )
        expect(blocks.count == 1, "expected 1 block, got \(blocks.count)")
    }

    test("running entry with no start event falls back to timer started at") {
        let startedAt = base.addingTimeInterval(600)
        let now = base.addingTimeInterval(45 * 60)
        let blocks = TimelineBuilder.blocks(
            from: [],
            now: now,
            running: [RunningTimer(entryId: 1, projectId: 3, startedAt: startedAt)]
        )
        expect(blocks.count == 1, "expected 1 block, got \(blocks.count)")
        expect(blocks.first?.start == startedAt, "block should start at timerStartedAt")
        expect(blocks.first?.end == now, "block should end at now")
        expect(blocks.first?.projectId == 3, "block should carry the entry's project")
    }

    test("open start event takes precedence over timer started at") {
        let now = base.addingTimeInterval(45 * 60)
        let blocks = TimelineBuilder.blocks(
            from: [event(.start, entry: 1, minutes: 0)],
            now: now,
            running: [RunningTimer(entryId: 1, projectId: 1, startedAt: base.addingTimeInterval(300))]
        )
        expect(blocks.count == 1, "expected 1 block, got \(blocks.count)")
        expect(blocks.first?.start == base, "event log start should win")
    }

    test("duplicate start events keep a single open block") {
        let now = base.addingTimeInterval(45 * 60)
        let blocks = TimelineBuilder.blocks(
            from: [
                event(.start, entry: 1, minutes: 0),
                event(.start, entry: 1, minutes: 0),
            ],
            now: now,
            running: [RunningTimer(entryId: 1, projectId: 1, startedAt: base)]
        )
        expect(blocks.count == 1, "expected 1 block, got \(blocks.count)")
        expect(blocks.first?.end == now, "open block should end at now")
    }

    test("running entry without start event or timer started at shows no block") {
        let blocks = TimelineBuilder.blocks(
            from: [],
            now: base.addingTimeInterval(3600),
            running: [RunningTimer(entryId: 1, projectId: 1, startedAt: nil)]
        )
        expect(blocks.isEmpty, "expected no blocks, got \(blocks.count)")
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
            running: []
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
}
