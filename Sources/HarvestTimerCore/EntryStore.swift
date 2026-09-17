import Foundation
import Observation

/// The time entries and the record of when their timers ran.
///
/// Every write to Harvest goes through here, and every one of them writes the
/// matching line to the event log in the same breath. That pairing is the
/// point of the app — Harvest keeps a day's total, not its history — so the
/// log is private to this type and nothing else can change an entry without
/// leaving the timeline a true account of it.
@MainActor
@Observable
public final class EntryStore {
    /// Read it freely; changing it goes through the methods below, which also
    /// keep the event log and Harvest in step.
    public private(set) var book = EntryBook()
    /// When the entries on hand were last true. A running timer counts up from
    /// here, so it climbs without waiting for the next sync.
    public private(set) var lastSyncAt: Date = .now

    private let log: EventLog
    private let session: Session
    private let errors: ErrorSink
    private let clock: Clock

    /// Set by `AppState`, which owns the loops these call back into: a fresh
    /// sync after a change, a budget refresh once a timer has moved, and the
    /// new entry to put the cursor on.
    var resync: () async -> Void = {}
    var spendChanged: () async -> Void = {}
    var onCreate: (Int64) -> Void = { _ in }

    public init(log: EventLog, session: Session, errors: ErrorSink, clock: Clock) {
        self.log = log
        self.session = session
        self.errors = errors
        self.clock = clock
    }

    // MARK: - Reading

    public func entries(forDay day: Date) -> [TimeEntry] {
        book.entries(on: Day(day))
    }

    public func entries(onDate date: Day) -> [TimeEntry] {
        book.entries(on: date)
    }

    public var all: [TimeEntry] { book.all }

    public var running: TimeEntry? { book.running }

    public func entry(withId id: Int64) -> TimeEntry? {
        book.entry(withId: id)
    }

    /// An entry's hours as they stand this moment: a running timer's own hours
    /// plus the time since we last heard from Harvest.
    public func liveHours(for entry: TimeEntry) -> Double {
        guard entry.isRunning else { return entry.hours }
        return entry.hours + max(0, clock.now.timeIntervalSince(lastSyncAt)) / 3600
    }

    public func total(forDay day: Date) -> Double {
        entries(forDay: day).reduce(0) { $0 + liveHours(for: $1) }
    }

    public func total(forDays days: [Date], billableOnly: Bool = false) -> Double {
        days
            .flatMap { entries(forDay: $0) }
            .filter { !billableOnly || $0.billable }
            .reduce(0) { $0 + liveHours(for: $1) }
    }

    /// The timers to draw as still going on `day` — the day's own running
    /// entries, and a timer that ran past midnight. Harvest keeps that one
    /// booked against the day it began, but the rest of its run happened here,
    /// so this day's timeline is where the rest belongs.
    func runningTimers(forDay day: Date, events: [TimerEvent]) -> [RunningTimer] {
        var timers = entries(forDay: day).filter(\.isRunning)
        if let running,
           !timers.contains(where: { $0.id == running.id }),
           events.contains(where: { $0.entryId == running.id }) {
            timers.append(running)
        }
        return timers.map {
            RunningTimer(entryId: $0.id, projectId: $0.project.id, startedAt: $0.timerStartedAt)
        }
    }

    // MARK: - Syncing

    /// Takes a sync's answer: the days it covered and everything Harvest had
    /// on them. A timer that started or stopped elsewhere shows up here as a
    /// change of running entry, and gets the log lines it never wrote.
    func receive(days: [Day], entries: [TimeEntry]) {
        lastSyncAt = clock.now
        let previous = running
        book.replace(days, with: entries)
        recordExternalTimerChange(from: previous, to: running)
    }

    func removeAll() {
        book.removeAll()
    }

    // MARK: - Writing

    /// Books work on `day`. On today that means starting a timer; on any other
    /// day it means an entry of no hours for the user to fill in. A run is
    /// filed on the day its moments fall in, so a timer left running for a day
    /// gone by would draw on today's timeline and nothing on its own.
    public func add(on day: Date, isToday: Bool, projectId: Int64, taskId: Int64, notes: String? = nil) async {
        if isToday {
            await startTimer(projectId: projectId, taskId: taskId, notes: notes)
        } else {
            await createEntry(on: Day(day), projectId: projectId, taskId: taskId, notes: notes)
        }
    }

    private func createEntry(on day: Day, projectId: Int64, taskId: Int64, notes: String?) async {
        let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        await perform { api in
            let entry = try await api.createEntry(
                projectId: projectId,
                taskId: taskId,
                spentDate: day,
                hours: 0,
                notes: notes
            )
            apply(entry)
            onCreate(entry.id)
            await resync()
        }
    }

    public func startTimer(projectId: Int64, taskId: Int64, notes: String? = nil) async {
        let today = Day(.now)
        let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        await perform { api in
            recordStopForRunningEntry()
            let entry: TimeEntry
            if let existing = entries(forDay: .now).first(where: {
                !$0.isRunning && $0.project.id == projectId && $0.task.id == taskId && ($0.notes ?? "") == notes
            }) {
                entry = try await api.restart(entryId: existing.id)
            } else {
                entry = try await api.startTimer(
                    projectId: projectId,
                    taskId: taskId,
                    spentDate: today,
                    notes: notes
                )
            }
            log.append(
                TimerEvent(entryId: entry.id, action: .start, timestamp: .now, projectId: entry.project.id)
            )
            apply(entry)
            await resync()
            apply(entry)
        }
        await spendChanged()
    }

    public func toggle(_ entry: TimeEntry) async {
        let current = currentVersion(of: entry)
        await perform { api in
            let updated: TimeEntry
            if current.isRunning {
                updated = try await api.stop(entryId: current.id)
                log.append(
                    TimerEvent(entryId: current.id, action: .stop, timestamp: .now, projectId: current.project.id)
                )
            } else {
                recordStopForRunningEntry()
                updated = try await api.restart(entryId: current.id)
                log.append(
                    TimerEvent(entryId: current.id, action: .start, timestamp: .now, projectId: current.project.id)
                )
            }
            apply(updated)
            await resync()
            apply(updated)
        }
        if !current.isRunning { await spendChanged() }
    }

    public func toggleCurrentTimer() async {
        if let running {
            await toggle(running)
        } else if let recent = lastStoppedEntry ?? entries(forDay: .now).last {
            await toggle(recent)
        }
    }

    /// What the clock was last on, which is rarely the last row of the list:
    /// the list keeps Harvest's order, the event log keeps the day's. Skips
    /// entries that have since gone, and falls back to the list for a day
    /// whose timers all ran somewhere else.
    private var lastStoppedEntry: TimeEntry? {
        let today = entries(forDay: .now)
        // The log keeps whole seconds, so stopping one timer to start another
        // writes two events on the same second. The later line breaks the tie.
        let stops = log.events(forDay: Day(.now))
            .enumerated()
            .filter { $0.element.action == .stop }
            .sorted { ($0.element.timestamp, $0.offset) > ($1.element.timestamp, $1.offset) }
        return stops.lazy
            .compactMap { stop in today.first { $0.id == stop.element.entryId } }
            .first
    }

    public func saveNotes(_ entry: TimeEntry, notes: String) async {
        guard notes != (entry.notes ?? "") else { return }
        await perform { api in
            apply(try await api.updateNotes(entryId: entry.id, notes: notes))
        }
    }

    public func updateHours(_ entry: TimeEntry, hours: Double) async {
        await perform { api in
            let updated = try await api.updateHours(entryId: entry.id, hours: hours)
            logEdit(updated)
            apply(updated)
        }
    }

    public func updateProjectTask(_ entry: TimeEntry, projectId: Int64, taskId: Int64) async {
        guard entry.project.id != projectId || entry.task.id != taskId else { return }
        await perform { api in
            let updated = try await api.updateProjectTask(
                entryId: entry.id,
                projectId: projectId,
                taskId: taskId
            )
            logEdit(updated)
            apply(updated)
        }
    }

    /// Takes `hours` off one entry and puts them on another, on the same day.
    /// `destinationEntryId` picks an exact entry — the only way to reach one
    /// that shares the source's project and task and differs just by notes;
    /// without it the move merges into any entry matching the project and
    /// task, or creates one. A running timer keeps running: on the source if
    /// time is left on it, otherwise on the destination it just moved to.
    public func moveTime(
        _ entry: TimeEntry,
        hours: Double,
        projectId: Int64,
        taskId: Int64,
        destinationEntryId: Int64? = nil
    ) async {
        var source = currentVersion(of: entry)
        guard hours > 0, liveHours(for: source) > 0 else { return }
        if let destinationEntryId {
            guard destinationEntryId != source.id else { return }
        } else {
            guard projectId != source.project.id || taskId != source.task.id else { return }
        }
        let wasRunning = source.isRunning

        await perform { api in
            if wasRunning {
                // Stop first so the split works off a settled number rather
                // than one still climbing.
                recordStopForRunningEntry()
                source = try await api.stop(entryId: source.id)
                apply(source)
            }
            guard let plan = TimeMove.plan(sourceHours: source.hours, requested: hours) else { return }
            let destination = entries(onDate: source.spentDate).first {
                if let destinationEntryId { return $0.id == destinationEntryId }
                return $0.project.id == projectId && $0.task.id == taskId
            }
            let landedOn: TimeEntry
            if let destination {
                let updated = try await api.updateHours(
                    entryId: destination.id,
                    hours: destination.hours + plan.moved
                )
                logEdit(updated)
                apply(updated)
                landedOn = updated
            } else {
                let created = try await api.createEntry(
                    projectId: projectId,
                    taskId: taskId,
                    spentDate: source.spentDate,
                    hours: plan.moved,
                    notes: source.notes
                )
                apply(created)
                landedOn = created
            }

            if plan.emptiesSource {
                await delete(source)
            } else {
                await updateHours(source, hours: plan.remaining)
            }

            if wasRunning {
                await restartTimer(on: plan.emptiesSource ? landedOn : source)
            }
            await resync()
        }
    }

    /// Cuts `minutes` off the end of an entry's last run and leaves the gap
    /// to draw as a break: the timer really ran, the tail just wasn't work.
    public func trimFromEnd(_ entry: TimeEntry, minutes: Int) async {
        let current = currentVersion(of: entry)
        let cut = TimeInterval(minutes) * 60
        guard cut > 0, liveHours(for: current) > 0 else { return }
        let hours = max(0, liveHours(for: current) - cut / 3600)
        await perform { api in
            let updated = try await api.updateHours(entryId: current.id, hours: hours)
            logTrimBreak(on: current, cut: cut)
            apply(updated)
            await resync()
        }
    }

    /// Takes a span of away time off an entry and cuts it out of the run on the
    /// timeline rather than marking it edited: the timer stopped when the desk
    /// emptied and picked up again on the way back, so the log says exactly
    /// that and the gap draws as a break. The hours still match the blocks, so
    /// no stripe is warranted.
    func removeSpan(from entry: TimeEntry, start: Date, end: Date) async {
        let hours = max(0, liveHours(for: entry) - max(0, end.timeIntervalSince(start)) / 3600)
        await perform { api in
            let updated = try await api.updateHours(entryId: entry.id, hours: hours)
            log.append(
                TimerEvent(entryId: updated.id, action: .stop, timestamp: start, projectId: updated.project.id)
            )
            log.append(
                TimerEvent(entryId: updated.id, action: .start, timestamp: end, projectId: updated.project.id)
            )
            apply(updated)
            await resync()
        }
    }

    /// Moves the end of the entry's last run back by `cut` rather than
    /// marking it edited, so the span comes off as a break, not a stripe.
    /// The builder takes the earliest stop it meets, so the stop already in
    /// the log just stops closing anything. A running timer also starts
    /// again now, the same shape an AFK break leaves. An entry with no local
    /// run — started elsewhere — has no end to move, so it gets the stripe.
    private func logTrimBreak(on entry: TimeEntry, cut: TimeInterval) {
        let moment = Date.now
        let running = entry.isRunning
            ? [RunningTimer(entryId: entry.id, projectId: entry.project.id, startedAt: entry.timerStartedAt)]
            : []
        let blocks = TimelineBuilder.blocks(
            from: log.events(forDay: entry.spentDate),
            now: moment,
            running: running
        ).filter { $0.entryId == entry.id }
        guard let block = blocks.max(by: { $0.end < $1.end }) else {
            logEdit(entry)
            return
        }
        log.append(
            TimerEvent(
                entryId: entry.id,
                action: .stop,
                timestamp: max(block.start, block.end.addingTimeInterval(-cut)),
                projectId: entry.project.id
            )
        )
        if entry.isRunning {
            log.append(
                TimerEvent(entryId: entry.id, action: .start, timestamp: moment, projectId: entry.project.id)
            )
        }
    }

    /// Picks a stopped entry's timer back up, keeping its notes — unlike
    /// `startTimer`, which matches on empty notes and would leave a noted
    /// entry behind for a fresh unnamed copy.
    private func restartTimer(on entry: TimeEntry) async {
        await perform { api in
            let restarted = try await api.restart(entryId: entry.id)
            log.append(
                TimerEvent(
                    entryId: restarted.id,
                    action: .start,
                    timestamp: .now,
                    projectId: restarted.project.id
                )
            )
            apply(restarted)
        }
        await spendChanged()
    }

    /// Notes that an entry's duration or booking changed, so the timeline can
    /// stripe it — its blocks no longer add up to its hours.
    private func logEdit(_ entry: TimeEntry) {
        log.append(
            TimerEvent(entryId: entry.id, action: .edit, timestamp: .now, projectId: entry.project.id),
            day: entry.spentDate
        )
    }

    public func delete(_ entry: TimeEntry) async {
        await perform { api in
            try await api.deleteEntry(entryId: entry.id)
            log.append(
                TimerEvent(entryId: entry.id, action: .delete, timestamp: .now, projectId: entry.project.id),
                day: entry.spentDate
            )
            book.remove(entry)
        }
    }

    // MARK: - Keeping the two sides in step

    /// Runs `work` against Harvest, putting any failure in the error banner.
    /// Does nothing when there are no credentials yet.
    private func perform(_ work: (HarvestClient) async throws -> Void) async {
        guard let api = session.client else { return }
        await errors.run { try await work(api) }
    }

    private func currentVersion(of entry: TimeEntry) -> TimeEntry {
        book.currentVersion(of: entry)
    }

    /// Files an entry Harvest just handed back. The clock restarts with it, so
    /// a running entry counts up from the hours Harvest reported rather than
    /// from the last sync.
    private func apply(_ updated: TimeEntry) {
        clock.now = .now
        lastSyncAt = clock.now
        book.apply(updated)
    }

    /// Writes the log lines for a timer that started or stopped off-app. An
    /// entry started on the web or a phone has no local events, so without
    /// this its run would draw nothing at all.
    private func recordExternalTimerChange(from previous: TimeEntry?, to current: TimeEntry?) {
        guard previous?.id != current?.id else { return }
        if let previous {
            log.append(
                TimerEvent(entryId: previous.id, action: .stop, timestamp: clock.now, projectId: previous.project.id)
            )
        }
        if let current {
            log.append(
                TimerEvent(
                    entryId: current.id,
                    action: .start,
                    timestamp: current.timerStartedAt ?? clock.now,
                    projectId: current.project.id
                )
            )
        }
    }

    private func recordStopForRunningEntry() {
        guard let running else { return }
        log.append(
            TimerEvent(entryId: running.id, action: .stop, timestamp: .now, projectId: running.project.id)
        )
    }
}
