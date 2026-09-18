import Foundation
import Observation

/// Watches for time nobody was at the desk, and settles what to do with it.
///
/// It prompts on the way back rather than while away, so what it holds is a
/// question — how much of a running timer was really work — and three answers:
/// keep the time, move it somewhere else, or take it off.
@MainActor
@Observable
public final class AwayWatch {
    public static let interval = Duration.seconds(10)

    public var prompt: AFKPrompt?
    public var toleranceMinutes: Int {
        didSet { UserDefaults.standard.set(toleranceMinutes, forKey: Self.toleranceKey) }
    }
    /// Called the moment a prompt appears, so the window can come forward.
    public var onDetected: (() -> Void)?

    /// The most recent input we have seen. Internal, not private, so a test
    /// can put it in the past instead of waiting out a tolerance.
    var lastActivityAt: Date = .now
    /// Internal, not private, so a test can post sleeps through it.
    let sleepWatch: SleepWatch

    private let idleSeconds: () -> TimeInterval
    private let entries: EntryStore
    private static let toleranceKey = "afkToleranceMinutes"

    static var storedTolerance: Int {
        UserDefaults.standard.object(forKey: toleranceKey) as? Int ?? 10
    }

    public init(
        entries: EntryStore,
        idleSeconds: @escaping () -> TimeInterval,
        sleepWatch: SleepWatch,
        toleranceMinutes: Int
    ) {
        self.entries = entries
        self.idleSeconds = idleSeconds
        self.sleepWatch = sleepWatch
        self.toleranceMinutes = toleranceMinutes
    }

    /// One look for idleness. `sinceLastTick` is how long the last step of the
    /// clock took, which is the fallback for what macOS did not report: a
    /// suspended process, or a missed notification.
    func check(sinceLastTick: TimeInterval) {
        let sleep = sleepWatch.takePendingSleep()
        let slept = sleep != nil || !AFKDetector.trustsIdleReading(
            sinceLastTick: sinceLastTick,
            interval: Self.interval.timeInterval
        )
        // Nobody typed after the lid shut. `min` repairs a bad reading already
        // stored, which `max` below can never undo.
        if let sleep {
            lastActivityAt = min(lastActivityAt, sleep.start)
        }
        let currentActivity = slept ? Date.now : Date.now.addingTimeInterval(-idleSeconds())
        let running = entries.running
        let updated = AFKDetector.evaluate(
            prompt: prompt,
            lastActivity: lastActivityAt,
            currentActivity: currentActivity,
            toleranceSeconds: Double(toleranceMinutes) * 60,
            runningEntryId: running?.id,
            runningEntryStartedAt: running?.timerStartedAt,
            sleptSinceLastCheck: slept
        )
        if !slept {
            lastActivityAt = max(lastActivityAt, currentActivity)
        }
        let isNew = updated != nil && prompt == nil
        prompt = updated
        if isNew { onDetected?() }
    }

    public func dismiss() {
        prompt = nil
    }

    func clear() {
        prompt = nil
    }

    /// Stands by the time the timer ran: the hours as this app sees them go
    /// back to Harvest, so they win over an adjustment made elsewhere while
    /// away, and the edit is logged like any other. Dismissing instead leaves
    /// Harvest alone, so that adjustment stays.
    public func keepTime() async {
        guard let answered = take() else { return }
        await entries.updateHours(answered.entry, hours: entries.liveHours(for: answered.entry))
    }

    /// Takes the away time off the entry that was running and puts it on
    /// another project and task instead.
    public func moveTime(projectId: Int64, taskId: Int64) async {
        guard let answered = take() else { return }
        await entries.moveTime(
            answered.entry,
            hours: answered.prompt.duration / 3600,
            projectId: projectId,
            taskId: taskId
        )
    }

    public func removeTime() async {
        guard let answered = take() else { return }
        await entries.removeSpan(
            from: answered.entry,
            start: answered.prompt.start,
            end: answered.prompt.end
        )
    }

    /// Closes the prompt and finds the entry it was about. The prompt goes
    /// either way — an entry deleted while the question sat open leaves
    /// nothing to answer about.
    private func take() -> (prompt: AFKPrompt, entry: TimeEntry)? {
        guard let prompt else { return nil }
        self.prompt = nil
        guard let entry = entries.entry(withId: prompt.entryId) else { return nil }
        return (prompt, entry)
    }
}
