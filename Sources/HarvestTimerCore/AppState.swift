import Foundation
import Observation

@MainActor
@Observable
public final class AppState {
    var credentials: Keychain.Credentials?
    public var selectedDay: Date = .now {
        didSet { selectedEntryId = nil }
    }
    public var selectedEntryId: Int64?
    public var entriesByDay: [Day: [TimeEntry]] = [:]
    public var favorites: [Favorite] = []
    var projectAssignments: [ProjectAssignment] = []
    public var now: Date = .now
    public var lastSyncAt: Date = .now
    public var syncError: String?
    public var afkPrompt: AFKPrompt?
    public var afkToleranceMinutes: Int {
        didSet { UserDefaults.standard.set(afkToleranceMinutes, forKey: Self.afkToleranceKey) }
    }
    public var onAFKDetected: (() -> Void)?

    private let idleSeconds: () -> TimeInterval
    private static let afkToleranceKey = "afkToleranceMinutes"
    private var currentUserId: Int64?
    private let weekCalendar = WeekCalendar()
    private let storageDirectory: URL
    private let eventLog: EventLog
    /// Set by tests, which stand in their own client rather than reach Harvest.
    private let injectedClient: HarvestClient?
    private var syncTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    private var favoritesURL: URL {
        storageDirectory.appendingPathComponent("favorites.json")
    }

    var needsSetup: Bool { credentials == nil }

    var api: HarvestClient? {
        injectedClient ?? credentials.map(HarvestAPI.init)
    }

    public init(idleSeconds: @escaping () -> TimeInterval = systemIdleSeconds) {
        self.idleSeconds = idleSeconds
        self.injectedClient = nil
        self.storageDirectory = EventLog.defaultDirectory
        self.eventLog = EventLog(directory: storageDirectory)
        afkToleranceMinutes = UserDefaults.standard.object(forKey: Self.afkToleranceKey) as? Int ?? 10
        credentials = Keychain.load()
        loadFavorites()
        if credentials != nil {
            startSyncLoop()
        }
    }

    /// Builds a state that talks to `client` and keeps its files under
    /// `storageDirectory`, leaving the Keychain and the sync loop alone.
    public init(
        client: HarvestClient,
        storageDirectory: URL,
        idleSeconds: @escaping () -> TimeInterval = { 0 }
    ) {
        self.idleSeconds = idleSeconds
        self.injectedClient = client
        self.storageDirectory = storageDirectory
        self.eventLog = EventLog(directory: storageDirectory)
        afkToleranceMinutes = 10
        loadFavorites()
    }

    public var weekDays: [Date] { weekCalendar.week(containing: selectedDay) }

    public func entries(forDay day: Date) -> [TimeEntry] {
        entries(onDate: Day(day))
    }

    public func entries(onDate date: Day) -> [TimeEntry] {
        (entriesByDay[date] ?? []).sorted { $0.id < $1.id }
    }

    public var runningEntry: TimeEntry? {
        entriesByDay.values.flatMap { $0 }.first { $0.isRunning }
    }

    public func liveHours(for entry: TimeEntry) -> Double {
        guard entry.isRunning else { return entry.hours }
        return entry.hours + max(0, now.timeIntervalSince(lastSyncAt)) / 3600
    }

    public func total(forDay day: Date) -> Double {
        entries(forDay: day).reduce(0) { $0 + liveHours(for: $1) }
    }

    public var menuBarTitle: String {
        if let running = runningEntry {
            return formattedHours(liveHours(for: running))
        }
        return formattedHours(total(forDay: .now))
    }

    public func timelineBlocks(forDay day: Date) -> [TimelineBlock] {
        let runningIds = Set(entries(forDay: day).filter(\.isRunning).map(\.id))
        return TimelineBuilder.blocks(
            from: eventLog.events(forDay: Day(day)),
            now: now,
            runningEntryIds: runningIds
        )
    }

    public func modifiedEntryIds(forDay day: Date) -> Set<Int64> {
        TimelineBuilder.modifiedEntryIds(from: eventLog.events(forDay: Day(day)))
    }

    public func startCounts(forDay day: Date) -> [Int64: Int] {
        TimelineBuilder.startCounts(from: eventLog.events(forDay: Day(day)))
    }

    func startSyncLoop() {
        syncTask?.cancel()
        syncTask = Task {
            while !Task.isCancelled {
                await sync()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        tickTask?.cancel()
        tickTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                now = .now
                checkAFK()
            }
        }
    }

    public func sync() async {
        guard let api else { return }
        var days = Set(weekDays.map(Day.init))
        let currentWeek = weekCalendar.week(containing: .now)
        days.formUnion(currentWeek.map(Day.init))

        do {
            let sortedDays = days.sorted()
            let userId: Int64
            if let currentUserId {
                userId = currentUserId
            } else {
                userId = try await api.currentUser().id
                currentUserId = userId
            }
            let entries = try await api.timeEntries(
                from: sortedDays.first!,
                to: sortedDays.last!,
                userId: userId
            )
            now = .now
            lastSyncAt = now
            let previousRunning = runningEntry
            var grouped: [Day: [TimeEntry]] = [:]
            for entry in entries {
                grouped[entry.spentDate, default: []].append(entry)
            }
            for day in weekCalendar.days(from: sortedDays.first!, to: sortedDays.last!) {
                entriesByDay[day] = grouped[day] ?? []
            }
            recordExternalTimerChange(from: previousRunning, to: runningEntry)
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
    }

    public func startFavorite(_ favorite: Favorite) async {
        await startTimer(projectId: favorite.projectId, taskId: favorite.taskId)
    }

    public func startTimer(projectId: Int64, taskId: Int64) async {
        guard let api else { return }
        let today = Day(.now)
        do {
            recordStopForRunningEntry()
            let entry: TimeEntry
            if let existing = entries(forDay: .now).first(where: {
                $0.project.id == projectId && $0.task.id == taskId
            }) {
                entry = try await api.restart(entryId: existing.id)
            } else {
                entry = try await api.startTimer(
                    projectId: projectId,
                    taskId: taskId,
                    spentDate: today
                )
            }
            eventLog.append(
                TimerEvent(entryId: entry.id, action: .start, timestamp: .now, projectId: entry.project.id),
                day: today
            )
            apply(entry)
            await sync()
            apply(entry)
        } catch {
            syncError = error.localizedDescription
        }
    }

    public func toggle(_ entry: TimeEntry) async {
        guard let api else { return }
        let current = currentVersion(of: entry)
        do {
            let updated: TimeEntry
            if current.isRunning {
                updated = try await api.stop(entryId: current.id)
                eventLog.append(
                    TimerEvent(entryId: current.id, action: .stop, timestamp: .now, projectId: current.project.id),
                    day: Day(.now)
                )
            } else {
                recordStopForRunningEntry()
                updated = try await api.restart(entryId: current.id)
                eventLog.append(
                    TimerEvent(entryId: current.id, action: .start, timestamp: .now, projectId: current.project.id),
                    day: Day(.now)
                )
            }
            apply(updated)
            await sync()
            apply(updated)
        } catch {
            syncError = error.localizedDescription
        }
    }

    public func toggleCurrentTimer() async {
        if let running = runningEntry {
            await toggle(running)
        } else if let recent = entries(forDay: .now).last {
            await toggle(recent)
        }
    }

    public func saveNotes(_ entry: TimeEntry, notes: String) async {
        guard let api, notes != (entry.notes ?? "") else { return }
        do {
            apply(try await api.updateNotes(entryId: entry.id, notes: notes))
        } catch {
            syncError = error.localizedDescription
        }
    }

    public func updateHours(_ entry: TimeEntry, hours: Double) async {
        guard let api else { return }
        do {
            let updated = try await api.updateHours(entryId: entry.id, hours: hours)
            logEdit(updated)
            apply(updated)
        } catch {
            syncError = error.localizedDescription
        }
    }

    public func updateProjectTask(_ entry: TimeEntry, projectId: Int64, taskId: Int64) async {
        guard let api,
              entry.project.id != projectId || entry.task.id != taskId else { return }
        do {
            let updated = try await api.updateProjectTask(
                entryId: entry.id,
                projectId: projectId,
                taskId: taskId
            )
            logEdit(updated)
            apply(updated)
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Takes `hours` off one entry and puts them on another project and task,
    /// on the same day. Merges into a matching entry when one already exists.
    /// A running timer keeps running: on the source if time is left on it,
    /// otherwise on the destination it just moved to.
    public func moveTime(_ entry: TimeEntry, hours: Double, projectId: Int64, taskId: Int64) async {
        guard let api else { return }
        var source = currentVersion(of: entry)
        guard projectId != source.project.id || taskId != source.task.id,
              hours > 0, liveHours(for: source) > 0
        else { return }
        let wasRunning = source.isRunning

        do {
            if wasRunning {
                // Stop first so the split works off a settled number rather
                // than one still climbing.
                recordStopForRunningEntry()
                source = try await api.stop(entryId: source.id)
                apply(source)
            }
            guard let plan = TimeMove.plan(sourceHours: source.hours, requested: hours) else { return }
            let destination = entries(onDate: source.spentDate).first {
                $0.project.id == projectId && $0.task.id == taskId
            }
            if let destination {
                let updated = try await api.updateHours(
                    entryId: destination.id,
                    hours: destination.hours + plan.moved
                )
                logEdit(updated)
                apply(updated)
            } else {
                let created = try await api.createEntry(
                    projectId: projectId,
                    taskId: taskId,
                    spentDate: source.spentDate,
                    hours: plan.moved,
                    notes: source.notes
                )
                apply(created)
            }

            if plan.emptiesSource {
                await deleteEntry(source)
            } else {
                await updateHours(source, hours: plan.remaining)
            }

            if wasRunning {
                await startTimer(
                    projectId: plan.emptiesSource ? projectId : source.project.id,
                    taskId: plan.emptiesSource ? taskId : source.task.id
                )
            }
            await sync()
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Notes that an entry's duration or booking changed, so the timeline can
    /// stripe it — its blocks no longer add up to its hours.
    private func logEdit(_ entry: TimeEntry) {
        eventLog.append(
            TimerEvent(entryId: entry.id, action: .edit, timestamp: .now, projectId: entry.project.id),
            day: entry.spentDate
        )
    }

    public func deleteEntry(_ entry: TimeEntry) async {
        guard let api else { return }
        do {
            try await api.deleteEntry(entryId: entry.id)
            eventLog.append(
                TimerEvent(entryId: entry.id, action: .delete, timestamp: .now, projectId: entry.project.id),
                day: entry.spentDate
            )
            entriesByDay[entry.spentDate] = (entriesByDay[entry.spentDate] ?? [])
                .filter { $0.id != entry.id }
        } catch {
            syncError = error.localizedDescription
        }
    }

    public func entry(withId id: Int64) -> TimeEntry? {
        entriesByDay.values.flatMap { $0 }.first { $0.id == id }
    }

    public func dismissAFKPrompt() {
        afkPrompt = nil
    }

    public func removeAFKTime() async {
        guard let api, let prompt = afkPrompt else { return }
        afkPrompt = nil
        guard let entry = entry(withId: prompt.entryId) else { return }
        let hours = max(0, liveHours(for: entry) - prompt.duration(now: .now) / 3600)
        do {
            let updated = try await api.updateHours(entryId: entry.id, hours: hours)
            logEdit(updated)
            apply(updated)
            await sync()
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func checkAFK() {
        let updated = AFKDetector.evaluate(
            prompt: afkPrompt,
            idleSeconds: idleSeconds(),
            toleranceSeconds: Double(afkToleranceMinutes) * 60,
            runningEntryId: runningEntry?.id,
            now: .now
        )
        let isNew = updated != nil && afkPrompt == nil
        afkPrompt = updated
        if isNew { onAFKDetected?() }
    }

    func loadProjectAssignments() async {
        guard let api, projectAssignments.isEmpty else { return }
        do {
            projectAssignments = try await api.projectAssignments()
        } catch {
            syncError = error.localizedDescription
        }
    }

    public func addFavorite(_ favorite: Favorite) {
        guard !favorites.contains(favorite) else { return }
        favorites.append(favorite)
        saveFavorites()
    }

    public func removeFavorite(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
        saveFavorites()
    }

    func saveCredentials(token: String, accountId: String) throws {
        let credentials = Keychain.Credentials(token: token, accountId: accountId)
        try Keychain.save(credentials)
        self.credentials = credentials
        currentUserId = nil
        startSyncLoop()
    }

    func removeCredentials() {
        Keychain.clear()
        credentials = nil
        currentUserId = nil
        entriesByDay = [:]
        projectAssignments = []
        afkPrompt = nil
        syncTask?.cancel()
        tickTask?.cancel()
    }

    private func currentVersion(of entry: TimeEntry) -> TimeEntry {
        entriesByDay[entry.spentDate]?.first { $0.id == entry.id } ?? entry
    }

    private func apply(_ updated: TimeEntry) {
        now = .now
        lastSyncAt = now
        if updated.isRunning {
            for (day, list) in entriesByDay {
                entriesByDay[day] = list.map { entry in
                    var entry = entry
                    if entry.id != updated.id { entry.isRunning = false }
                    return entry
                }
            }
        }
        var day = entriesByDay[updated.spentDate] ?? []
        if let index = day.firstIndex(where: { $0.id == updated.id }) {
            day[index] = updated
        } else {
            day.append(updated)
        }
        entriesByDay[updated.spentDate] = day
    }

    private func recordExternalTimerChange(from previous: TimeEntry?, to current: TimeEntry?) {
        guard previous?.id != current?.id else { return }
        if let previous {
            eventLog.append(
                TimerEvent(entryId: previous.id, action: .stop, timestamp: now, projectId: previous.project.id),
                day: previous.spentDate
            )
        }
        if let current {
            eventLog.append(
                TimerEvent(
                    entryId: current.id,
                    action: .start,
                    timestamp: current.timerStartedAt ?? now,
                    projectId: current.project.id
                ),
                day: current.spentDate
            )
        }
    }

    private func recordStopForRunningEntry() {
        guard let running = runningEntry else { return }
        eventLog.append(
            TimerEvent(entryId: running.id, action: .stop, timestamp: .now, projectId: running.project.id),
            day: Day(.now)
        )
    }

    private func loadFavorites() {
        guard let data = try? Data(contentsOf: favoritesURL),
              let loaded = try? JSONDecoder().decode([Favorite].self, from: data) else { return }
        favorites = loaded
    }

    private func saveFavorites() {
        try? FileManager.default.createDirectory(
            at: EventLog.defaultDirectory,
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(favorites) {
            try? data.write(to: favoritesURL, options: .atomic)
        }
    }
}
