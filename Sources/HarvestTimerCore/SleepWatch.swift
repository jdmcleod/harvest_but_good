import AppKit
import Foundation

/// A stretch the machine spent asleep, so a stretch nobody worked either.
public struct SleepGap: Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// Watches the machine sleep and wake, so the AFK check has the real away
/// window rather than a guess from how late a tick arrived.
/// Only macOS knows when sleep began; see `AFKDetector.trustsIdleReading` for
/// why the idle clock cannot say.
@MainActor
public final class SleepWatch {
    private var sleepStartedAt: Date?
    private var pending: SleepGap?
    private var observers: [NSObjectProtocol] = []
    private let center: NotificationCenter

    public init(
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        willSleep: Notification.Name = NSWorkspace.willSleepNotification,
        didWake: Notification.Name = NSWorkspace.didWakeNotification
    ) {
        self.center = center
        observers.append(
            center.addObserver(forName: willSleep, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.noteSleep(at: .now) }
            }
        )
        observers.append(
            center.addObserver(forName: didWake, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.noteWake(at: .now) }
            }
        )
    }

    deinit {
        for observer in observers { center.removeObserver(observer) }
    }

    /// The sleep since the last call, if any. Reading clears it, so a sleep is
    /// counted once. Several between two reads merge into the span they cover.
    public func takePendingSleep() -> SleepGap? {
        defer { pending = nil }
        return pending
    }

    func noteSleep(at date: Date) {
        // Keep the earlier moment: that is where the away time starts.
        sleepStartedAt = sleepStartedAt ?? date
    }

    func noteWake(at date: Date) {
        // No sleep recorded means the app started during a dark wake, so there
        // is no window to report.
        guard let sleepStartedAt else { return }
        self.sleepStartedAt = nil
        pending = SleepGap(start: min(pending?.start ?? sleepStartedAt, sleepStartedAt), end: date)
    }
}
