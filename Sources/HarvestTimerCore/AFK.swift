import CoreGraphics
import Foundation

public struct AFKPrompt: Equatable, Identifiable {
    public let entryId: Int64
    public let start: Date
    public let end: Date

    public var id: Double { start.timeIntervalSince1970 }

    public init(entryId: Int64, start: Date, end: Date) {
        self.entryId = entryId
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

public enum AFKDetector {
    /// Prompts on the way back rather than while away: a gap between the input
    /// we saw last time and the input we see now is the time nobody was here.
    /// A sleeping laptop stops the polling but not the gap, so a closed lid is
    /// caught the moment the mouse moves again. An open prompt never changes —
    /// it waits for an answer.
    ///
    /// Only the part of the gap the timer was running for counts. Time away
    /// before the timer started is nobody's to give back, so a break taken off
    /// the clock never prompts once the timer goes on again.
    ///
    /// An unanswered prompt grows through a further sleep, so waiting to answer
    /// does not cost the time spent waiting.
    public static func evaluate(
        prompt: AFKPrompt?,
        lastActivity: Date,
        currentActivity: Date,
        toleranceSeconds: TimeInterval,
        runningEntryId: Int64?,
        runningEntryStartedAt: Date?,
        sleptSinceLastCheck: Bool = false
    ) -> AFKPrompt? {
        if let prompt {
            guard sleptSinceLastCheck, currentActivity > prompt.end else { return prompt }
            // Keeping the start keeps the id, so the open window updates
            // instead of being replaced.
            return AFKPrompt(entryId: prompt.entryId, start: prompt.start, end: currentActivity)
        }
        guard toleranceSeconds > 0, let runningEntryId else { return nil }
        let start = max(lastActivity, runningEntryStartedAt ?? lastActivity)
        guard currentActivity.timeIntervalSince(start) >= toleranceSeconds else { return nil }
        return AFKPrompt(entryId: runningEntryId, start: start, end: currentActivity)
    }
}

public extension AFKDetector {
    /// Whether a tick's idle reading can be believed. Across a sleep the idle
    /// clock counts from the wake, not from the last input, so a tick landing
    /// much later than its cadence is reporting the wrong thing. A closed
    /// laptop wakes hourly for maintenance, and each of those readings would
    /// otherwise pass for somebody at the keyboard.
    static func trustsIdleReading(sinceLastTick: TimeInterval, interval: TimeInterval) -> Bool {
        sinceLastTick <= interval * 2
    }

    /// Seconds since the last mouse or keyboard event. Only real input counts —
    /// `.combinedSessionState` on its own also ticks for events the machine
    /// generates while nobody is at the desk.
    static func systemIdleSeconds() -> TimeInterval {
        let inputTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
            .keyDown,
            .flagsChanged,
        ]
        return inputTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }
}
