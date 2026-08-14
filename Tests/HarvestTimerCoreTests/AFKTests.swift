import Foundation
import Testing

@testable import HarvestTimerCore

@Test("AFK detection")
func runAFKTests() {
    test("afk detector stays quiet below tolerance") {
        let prompt = AFKDetector.evaluate(
            prompt: nil,
            lastActivity: base,
            currentActivity: base.addingTimeInterval(299),
            toleranceSeconds: 300,
            runningEntryId: 1,
            runningEntryStartedAt: nil
        )
        expect(prompt == nil, "should not prompt below tolerance")
    }

    test("afk detector needs a running timer") {
        let prompt = AFKDetector.evaluate(
            prompt: nil,
            lastActivity: base,
            currentActivity: base.addingTimeInterval(600),
            toleranceSeconds: 300,
            runningEntryId: nil,
            runningEntryStartedAt: nil
        )
        expect(prompt == nil, "should not prompt without a running timer")
    }

    test("afk detector is disabled at zero tolerance") {
        let prompt = AFKDetector.evaluate(
            prompt: nil,
            lastActivity: base,
            currentActivity: base.addingTimeInterval(6000),
            toleranceSeconds: 0,
            runningEntryId: 1,
            runningEntryStartedAt: nil
        )
        expect(prompt == nil, "zero tolerance should disable detection")
    }

    test("afk detector prompts when input resumes after a gap") {
        let prompt = AFKDetector.evaluate(
            prompt: nil,
            lastActivity: base,
            currentActivity: base.addingTimeInterval(300),
            toleranceSeconds: 300,
            runningEntryId: 7,
            runningEntryStartedAt: nil
        )
        expect(prompt?.entryId == 7, "prompt should carry the running entry id")
        expect(prompt?.start == base, "prompt should start at the last activity seen")
        expect(prompt?.duration == 300, "duration should span the gap")
    }

    test("afk detector catches a gap the machine slept through") {
        let prompt = AFKDetector.evaluate(
            prompt: nil,
            lastActivity: base,
            currentActivity: base.addingTimeInterval(3 * 3600),
            toleranceSeconds: 600,
            runningEntryId: 7,
            runningEntryStartedAt: nil
        )
        expect(prompt?.duration == 3 * 3600, "a slept-through gap should be the full away time")
    }

    test("afk detector stays quiet while still idle") {
        let prompt = AFKDetector.evaluate(
            prompt: nil,
            lastActivity: base,
            currentActivity: base,
            toleranceSeconds: 300,
            runningEntryId: 7,
            runningEntryStartedAt: nil
        )
        expect(prompt == nil, "no new input means nobody is back yet")
    }

    test("afk prompt waits for an answer") {
        let existing = AFKPrompt(entryId: 7, start: base, end: base.addingTimeInterval(900))
        let prompt = AFKDetector.evaluate(
            prompt: existing,
            lastActivity: base.addingTimeInterval(900),
            currentActivity: base.addingTimeInterval(4500),
            toleranceSeconds: 300,
            runningEntryId: 7,
            runningEntryStartedAt: nil
        )
        expect(prompt == existing, "an open prompt should not change on its own")
    }

    test("afk prompt grows through a sleep it was not answered before") {
        let existing = AFKPrompt(entryId: 7, start: base, end: base.addingTimeInterval(600))
        let prompt = AFKDetector.evaluate(
            prompt: existing,
            lastActivity: base.addingTimeInterval(600),
            currentActivity: base.addingTimeInterval(4200),
            toleranceSeconds: 300,
            runningEntryId: 7,
            runningEntryStartedAt: nil,
            sleptSinceLastCheck: true
        )
        expect(prompt?.start == base, "the gap should still start where it did")
        expect(prompt?.duration == 4200, "waiting for an answer should not cost the wait")
        expect(prompt?.id == existing.id, "the open window should be updated, not replaced")
    }

    test("afk prompt holds still while somebody is at the keyboard") {
        let existing = AFKPrompt(entryId: 7, start: base, end: base.addingTimeInterval(600))
        let prompt = AFKDetector.evaluate(
            prompt: existing,
            lastActivity: base.addingTimeInterval(600),
            currentActivity: base.addingTimeInterval(4200),
            toleranceSeconds: 300,
            runningEntryId: 7,
            runningEntryStartedAt: nil,
            sleptSinceLastCheck: false
        )
        expect(prompt == existing, "time spent reading the prompt is time at the desk")
    }

    test("afk prompt survives the timer stopping") {
        let existing = AFKPrompt(entryId: 7, start: base, end: base.addingTimeInterval(600))
        let prompt = AFKDetector.evaluate(
            prompt: existing,
            lastActivity: base.addingTimeInterval(600),
            currentActivity: base.addingTimeInterval(600),
            toleranceSeconds: 300,
            runningEntryId: nil,
            runningEntryStartedAt: nil
        )
        expect(prompt?.entryId == 7, "existing prompt should survive a stopped timer")
    }

    test("afk detector ignores a break taken before the timer started") {
        let prompt = AFKDetector.evaluate(
            prompt: nil,
            lastActivity: base,
            currentActivity: base.addingTimeInterval(660),
            toleranceSeconds: 300,
            runningEntryId: 7,
            runningEntryStartedAt: base.addingTimeInterval(660)
        )
        expect(prompt == nil, "time away off the clock is not the entry's to give back")
    }

    test("afk detector believes an idle reading from a tick that came on time") {
        expect(
            AFKDetector.trustsIdleReading(sinceLastTick: 10, interval: 10),
            "a tick on its cadence watched the whole stretch"
        )
        expect(
            AFKDetector.trustsIdleReading(sinceLastTick: 19, interval: 10),
            "a tick running a little behind is still watching"
        )
    }

    test("afk detector distrusts an idle reading from a tick that came late") {
        expect(
            !AFKDetector.trustsIdleReading(sinceLastTick: 45, interval: 10),
            "a tick minutes late sat through a sleep"
        )
        expect(
            !AFKDetector.trustsIdleReading(sinceLastTick: 15 * 3600, interval: 10),
            "a tick a night late sat through a night"
        )
    }

    test("afk detector counts only the away time the timer was running for") {
        let prompt = AFKDetector.evaluate(
            prompt: nil,
            lastActivity: base,
            currentActivity: base.addingTimeInterval(1200),
            toleranceSeconds: 300,
            runningEntryId: 7,
            runningEntryStartedAt: base.addingTimeInterval(600)
        )
        expect(prompt?.start == base.addingTimeInterval(600), "the gap should start where the entry did")
        expect(prompt?.duration == 600, "only the on-the-clock half of the gap counts")
    }
}
