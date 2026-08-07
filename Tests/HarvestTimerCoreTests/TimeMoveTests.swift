import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Moving time between entries")
func runTimeMoveTests() {
    test("moving part of an entry leaves the rest") {
        let plan = TimeMove.plan(sourceHours: 2, requested: 0.5)
        expect(plan?.moved == 0.5, "moves what was asked for")
        expect(plan?.remaining == 1.5, "leaves the rest")
        expect(plan?.emptiesSource == false, "keeps the source entry")
    }

    test("moving everything empties the source") {
        let plan = TimeMove.plan(sourceHours: 1.25, requested: 1.25)
        expect(plan?.moved == 1.25, "moves the whole entry")
        expect(plan?.emptiesSource == true, "empties the source")
    }

    test("asking for more than the entry holds moves the whole entry") {
        let plan = TimeMove.plan(sourceHours: 0.75, requested: 5)
        expect(plan?.moved == 0.75, "caps at the entry's hours")
        expect(plan?.remaining == 0, "leaves nothing")
    }

    test("a leftover under half a minute counts as empty") {
        let plan = TimeMove.plan(sourceHours: 1, requested: 1 - 0.2 / 60)
        expect(plan?.remaining == 0, "rounds the dust away")
        expect(plan?.emptiesSource == true, "empties the source")
    }

    test("nothing to move") {
        expect(TimeMove.plan(sourceHours: 1, requested: 0) == nil, "zero request")
        expect(TimeMove.plan(sourceHours: 1, requested: -1) == nil, "negative request")
        expect(TimeMove.plan(sourceHours: 0, requested: 1) == nil, "empty source")
    }
}
