import Foundation

public extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}

/// A job that repeats on a fixed interval. Owners keep one per loop, so the
/// cadence is a value you can read rather than a literal buried in a task, and
/// a test can run the work by hand instead of waiting.
@MainActor
public final class Ticker {
    public let interval: Duration
    private let sleep: @Sendable (Duration) async -> Void
    private var task: Task<Void, Never>?

    public init(
        every interval: Duration,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.interval = interval
        self.sleep = sleep
    }

    public var isRunning: Bool { task != nil }

    /// Runs `work` now, then every `interval` until `stop`.
    public func start(_ work: @escaping @MainActor () async -> Void) {
        stop()
        task = Task { [interval, sleep] in
            while !Task.isCancelled {
                await work()
                await sleep(interval)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
