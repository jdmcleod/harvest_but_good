import Foundation

/// A job that runs on a `RefreshSchedule` rather than a fixed interval: now,
/// then at each scheduled time. When a round reports it didn't finish — the
/// network wasn't up yet after waking, say — it tries again after
/// `retryInterval` instead of waiting out the whole gap to the next slot.
@MainActor
public final class ScheduledTicker {
    public let schedule: RefreshSchedule
    public let retryInterval: Duration
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async -> Void
    private var task: Task<Void, Never>?

    /// The default sleep counts time the Mac spends asleep, since
    /// `Task.sleep(for:)` runs on the continuous clock — so a slot missed
    /// while the lid was shut fires on wake rather than drifting late.
    public init(
        schedule: RefreshSchedule,
        retryInterval: Duration = .seconds(5 * 60),
        now: @escaping @Sendable () -> Date = { .now },
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.schedule = schedule
        self.retryInterval = retryInterval
        self.now = now
        self.sleep = sleep
    }

    public var isRunning: Bool { task != nil }

    /// Runs `work` now, then at each scheduled time until `stop`. `work`
    /// returns whether it finished; false asks for a retry soon.
    public func start(_ work: @escaping @MainActor () async -> Bool) {
        stop()
        task = Task { [schedule, retryInterval, now, sleep] in
            while !Task.isCancelled {
                let finished = await work()
                let current = now()
                let wait: Duration
                if !finished {
                    wait = retryInterval
                } else if let next = schedule.next(after: current) {
                    wait = .seconds(next.timeIntervalSince(current))
                } else {
                    wait = retryInterval
                }
                await sleep(wait)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
