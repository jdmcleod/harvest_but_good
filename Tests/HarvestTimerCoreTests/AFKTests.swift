import Foundation
import Testing

@testable import HarvestTimerCore

@Test("AFK detection")
func runAFKTests() {
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
}
