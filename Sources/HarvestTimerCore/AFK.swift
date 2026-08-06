import CoreGraphics
import Foundation

public struct AFKPrompt: Equatable, Identifiable {
    public let entryId: Int64
    public let start: Date
    public var returnedAt: Date?

    public var id: Double { start.timeIntervalSince1970 }

    public init(entryId: Int64, start: Date, returnedAt: Date? = nil) {
        self.entryId = entryId
        self.start = start
        self.returnedAt = returnedAt
    }

    public func duration(now: Date) -> TimeInterval {
        max(0, (returnedAt ?? now).timeIntervalSince(start))
    }
}

public enum AFKDetector {
    public static func evaluate(
        prompt: AFKPrompt?,
        idleSeconds: TimeInterval,
        toleranceSeconds: TimeInterval,
        runningEntryId: Int64?,
        now: Date
    ) -> AFKPrompt? {
        let lastActivity = now.addingTimeInterval(-idleSeconds)
        if var prompt {
            if prompt.returnedAt == nil, lastActivity > prompt.start.addingTimeInterval(1) {
                prompt.returnedAt = lastActivity
            }
            return prompt
        }
        guard toleranceSeconds > 0,
              let runningEntryId,
              idleSeconds >= toleranceSeconds else { return nil }
        return AFKPrompt(entryId: runningEntryId, start: lastActivity)
    }
}

public func systemIdleSeconds() -> TimeInterval {
    let anyInput = CGEventType(rawValue: ~0)!
    return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
}

public func formattedDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = Int(seconds / 60)
    if totalMinutes < 1 { return "less than a minute" }
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    switch (hours, minutes) {
    case (0, _): return "\(minutes) min"
    case (_, 0): return hours == 1 ? "1 hour" : "\(hours) hours"
    default: return "\(hours) hr \(minutes) min"
    }
}
