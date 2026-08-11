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
    /// A prompt left unanswered grows through a further sleep. Waiting for an
    /// answer must not cost the time spent waiting: somebody who glances at the
    /// prompt, shuts the lid and comes back at noon is owed the morning too.
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
            // The start holds, so the prompt keeps its identity and the open
            // window is updated rather than replaced.
            return AFKPrompt(entryId: prompt.entryId, start: prompt.start, end: currentActivity)
        }
        guard toleranceSeconds > 0, let runningEntryId else { return nil }
        let start = max(lastActivity, runningEntryStartedAt ?? lastActivity)
        guard currentActivity.timeIntervalSince(start) >= toleranceSeconds else { return nil }
        return AFKPrompt(entryId: runningEntryId, start: start, end: currentActivity)
    }
}

public extension AFKDetector {
    /// Whether a tick's idle reading can be believed. Two ticks about one
    /// interval apart bracket a stretch the app watched the whole way through,
    /// so the reading stands. A tick landing much later than that followed a
    /// sleep, and the idle clock on the far side of a sleep counts from the
    /// wake rather than from the last person at the keyboard. A closed laptop
    /// wakes itself hourly for maintenance, so believing those readings hands
    /// the night back as though somebody had worked it.
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
