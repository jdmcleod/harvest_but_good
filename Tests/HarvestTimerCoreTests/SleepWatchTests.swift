import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Sleep watching")
@MainActor
func runSleepWatchTests() {
    let willSleep = Notification.Name("test.willSleep")
    let didWake = Notification.Name("test.didWake")

    func watcher() -> (SleepWatch, NotificationCenter) {
        let center = NotificationCenter()
        return (
            SleepWatch(center: center, willSleep: willSleep, didWake: didWake),
            center
        )
    }

    test("nothing to report before the machine sleeps") {
        let (watch, _) = watcher()
        expect(watch.takePendingSleep() == nil, "an awake machine has no gap to report")
    }

    test("a sleep and a wake make a gap") {
        let (watch, _) = watcher()
        watch.noteSleep(at: base)
        expect(watch.takePendingSleep() == nil, "a sleep with no wake yet is not over")

        watch.noteWake(at: base.addingTimeInterval(3600))
        let gap = watch.takePendingSleep()
        expect(gap?.start == base, "the gap should start when the machine went down")
        expect(gap?.end == base.addingTimeInterval(3600), "and end when it came back")
    }

    test("a gap is reported once") {
        let (watch, _) = watcher()
        watch.noteSleep(at: base)
        watch.noteWake(at: base.addingTimeInterval(60))
        expect(watch.takePendingSleep() != nil, "the gap should come out once")
        expect(watch.takePendingSleep() == nil, "and not a second time")
    }

    test("sleeps between two reads merge into the span they cover") {
        let (watch, _) = watcher()
        watch.noteSleep(at: base)
        watch.noteWake(at: base.addingTimeInterval(600))
        watch.noteSleep(at: base.addingTimeInterval(660))
        watch.noteWake(at: base.addingTimeInterval(1800))

        let gap = watch.takePendingSleep()
        expect(gap?.start == base, "the span starts at the first sleep")
        expect(gap?.end == base.addingTimeInterval(1800), "and ends at the last wake")
    }

    test("a wake with no sleep behind it reports nothing") {
        let (watch, _) = watcher()
        watch.noteWake(at: base)
        expect(watch.takePendingSleep() == nil, "an app started in a dark wake missed no time")
    }

    test("the watch hears the machine through the notification centre") {
        let (watch, center) = watcher()
        center.post(name: willSleep, object: nil)
        center.post(name: didWake, object: nil)
        expect(watch.takePendingSleep() != nil, "the real notifications should land")
    }
}
