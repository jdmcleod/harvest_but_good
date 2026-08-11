import AppKit
import Foundation

/// A stretch the machine spent asleep, which is a stretch nobody spent working.
public struct SleepGap: Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// Watches the machine going to sleep and waking up, so the AFK check has the
/// real away window instead of guessing one from how late a tick arrived.
///
/// macOS says when sleep begins, which the idle clock cannot: on the far side
/// of a sleep it counts from the wake, not from the last person at the
/// keyboard. Knowing the moment the lid shut pins the start of the gap exactly.
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

    /// The sleep since the last call, if there was one. Reading it clears it,
    /// so one sleep is counted once. Several sleeps between two reads merge
    /// into the span they cover, which is the whole time nobody was here.
    public func takePendingSleep() -> SleepGap? {
        defer { pending = nil }
        return pending
    }

    func noteSleep(at date: Date) {
        // A second warning without a wake in between keeps the first: the
        // earlier moment is the one the away time starts at.
        sleepStartedAt = sleepStartedAt ?? date
    }

    func noteWake(at date: Date) {
        // A wake with no sleep recorded happens when the app started up during
        // a dark wake. There is no window to report, so there is nothing to say.
        guard let sleepStartedAt else { return }
        self.sleepStartedAt = nil
        pending = SleepGap(start: min(pending?.start ?? sleepStartedAt, sleepStartedAt), end: date)
    }
}
