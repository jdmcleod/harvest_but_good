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
            runningEntryId: 1
        )
        expect(prompt == nil, "should not prompt below tolerance")
    }

    test("afk detector needs a running timer") {
        let prompt = AFKDetector.evaluate(
            prompt: nil,
            lastActivity: base,
            currentActivity: base.addingTimeInterval(600),
            toleranceSeconds: 300,
            runningEntryId: nil
        )
        expect(prompt == nil, "should not prompt without a running timer")
    }

    test("afk detector is disabled at zero tolerance") {
        let prompt = AFKDetector.evaluate(
            prompt: nil,
            lastActivity: base,
            currentActivity: base.addingTimeInterval(6000),
            toleranceSeconds: 0,
            runningEntryId: 1
        )
        expect(prompt == nil, "zero tolerance should disable detection")
    }

    test("afk detector prompts when input resumes after a gap") {
        let prompt = AFKDetector.evaluate(
            prompt: nil,
            lastActivity: base,
            currentActivity: base.addingTimeInterval(300),
            toleranceSeconds: 300,
            runningEntryId: 7
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
            runningEntryId: 7
        )
        expect(prompt?.duration == 3 * 3600, "a slept-through gap should be the full away time")
    }

    test("afk detector stays quiet while still idle") {
        let prompt = AFKDetector.evaluate(
            prompt: nil,
            lastActivity: base,
            currentActivity: base,
            toleranceSeconds: 300,
            runningEntryId: 7
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
            runningEntryId: 7
        )
        expect(prompt == existing, "an open prompt should not change on its own")
    }

    test("afk prompt survives the timer stopping") {
        let existing = AFKPrompt(entryId: 7, start: base, end: base.addingTimeInterval(600))
        let prompt = AFKDetector.evaluate(
            prompt: existing,
            lastActivity: base.addingTimeInterval(600),
            currentActivity: base.addingTimeInterval(600),
            toleranceSeconds: 300,
            runningEntryId: nil
        )
        expect(prompt?.entryId == 7, "existing prompt should survive a stopped timer")
    }
}
