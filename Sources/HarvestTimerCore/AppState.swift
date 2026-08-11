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
    /// Read it freely; changing it goes through the methods below, which also
    /// keep the event log and Harvest in step.
    public private(set) var book = EntryBook()
    public var favorites: [Favorite] = []
    public private(set) var breakTitles: [String: String] = [:]
    var projectAssignments: [ProjectAssignment] = []
    public private(set) var projectBudgets: [Int64: ProjectBudget] = [:]
    public var now: Date = .now
    public var lastSyncAt: Date = .now
    public var syncError: String?
    public var afkPrompt: AFKPrompt?
    public var afkToleranceMinutes: Int {
        didSet { UserDefaults.standard.set(afkToleranceMinutes, forKey: Self.afkToleranceKey) }
    }
    public var onAFKDetected: (() -> Void)?

    private let idleSeconds: () -> TimeInterval
    /// The most recent input we have seen. Internal, not private, so a test
    /// can put it in the past instead of waiting out a tolerance.
    var lastActivityAt: Date = .now
    /// The day the window was last brought to the front. Internal so a test
    /// can put it in the past instead of waiting for midnight.
    var lastOpenedAt: Date = .now
    private static let afkToleranceKey = "afkToleranceMinutes"
    private var currentUserId: Int64?
    private var companyBaseUri: String?
    /// When budgets last came in. Internal, not private, so a test can put it
    /// in the past instead of waiting out the refresh interval.
    var lastBudgetFetchAt: Date?
    private var budgetsUnavailable = false
    static let budgetRefreshInterval: TimeInterval = 15 * 60
    private let weekCalendar = WeekCalendar()
    private let eventLog: EventLog
    private let favoritesStore: FavoritesStore
    private let breakTitlesStore: BreakTitlesStore
    /// Set by tests, which stand in their own client rather than reach Harvest.
    private let injectedClient: HarvestClient?
    public static let syncInterval = Duration.seconds(30)
    public static let afkInterval = Duration.seconds(10)
    private let syncTicker = Ticker(every: AppState.syncInterval)
    private let afkTicker = Ticker(every: AppState.afkInterval)

    var needsSetup: Bool { credentials == nil }

    var api: HarvestClient? {
        injectedClient ?? credentials.map { HarvestAPI(credentials: $0) }
    }

    public init(idleSeconds: @escaping () -> TimeInterval = AFKDetector.systemIdleSeconds) {
        self.idleSeconds = idleSeconds
        self.injectedClient = nil
        self.eventLog = EventLog(directory: EventLog.defaultDirectory)
        self.favoritesStore = FavoritesStore(directory: EventLog.defaultDirectory)
        self.breakTitlesStore = BreakTitlesStore(directory: EventLog.defaultDirectory)
        afkToleranceMinutes = UserDefaults.standard.object(forKey: Self.afkToleranceKey) as? Int ?? 10
        credentials = Keychain.shared.load()
        favorites = favoritesStore.load()
        breakTitles = breakTitlesStore.load()
    }

    /// Builds a state that talks to `client` and keeps its files under
    /// `storageDirectory`, leaving the Keychain alone. Like the other init it
    /// starts no loops, so a test drives `sync` and `afkTick` itself.
    public init(
        client: HarvestClient,
        storageDirectory: URL,
        idleSeconds: @escaping () -> TimeInterval = { 0 }
    ) {
        self.idleSeconds = idleSeconds
        self.injectedClient = client
        self.eventLog = EventLog(directory: storageDirectory)
        self.favoritesStore = FavoritesStore(directory: storageDirectory)
        self.breakTitlesStore = BreakTitlesStore(directory: storageDirectory)
        afkToleranceMinutes = 10
        favorites = favoritesStore.load()
        breakTitles = breakTitlesStore.load()
    }

    public var weekDays: [Date] { weekCalendar.week(containing: selectedDay) }

    /// Whether the day on screen is the one today falls in, so a control can
    /// offer a way back only when there is somewhere to come back from. A day
    /// earlier in this same week counts as somewhere else, so the way back is
    /// on offer there too.
    public var isViewingToday: Bool { isToday(selectedDay) }

    /// Whether `day` is the one the clock is in. Goes through `now` rather than
    /// the system clock so a test can move the day without waiting out a
    /// midnight, and so a stale `now` never marks two days as today at once.
    public func isToday(_ day: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: now)
    }

    public func goToToday() {
        selectedDay = now
    }

    public func entries(forDay day: Date) -> [TimeEntry] {
        entries(onDate: Day(day))
    }

    public func entries(onDate date: Day) -> [TimeEntry] {
        book.entries(on: date)
    }

    public var runningEntry: TimeEntry? {
        book.running
    }

    public func liveHours(for entry: TimeEntry) -> Double {
        guard entry.isRunning else { return entry.hours }
        return entry.hours + max(0, now.timeIntervalSince(lastSyncAt)) / 3600
    }

    public func total(forDay day: Date) -> Double {
        entries(forDay: day).reduce(0) { $0 + liveHours(for: $1) }
    }

    public var weekTotal: Double {
        weekEntries.reduce(0) { $0 + liveHours(for: $1) }
    }

    public var weekBillableTotal: Double {
        weekEntries.filter(\.billable).reduce(0) { $0 + liveHours(for: $1) }
    }

    private var weekEntries: [TimeEntry] {
        weekDays.flatMap { entries(forDay: $0) }
    }

    public var menuBarTitle: String {
        if let running = runningEntry {
            return Hours.formatted(liveHours(for: running))
        }
        return Hours.formatted(total(forDay: .now))
    }

    public func timelineBlocks(forDay day: Date) -> [TimelineBlock] {
        let running = entries(forDay: day).filter(\.isRunning).map {
            RunningTimer(entryId: $0.id, projectId: $0.project.id, startedAt: $0.timerStartedAt)
        }
        return TimelineBuilder.blocks(
            from: eventLog.events(forDay: Day(day)),
            now: now,
            running: running
        )
    }

    public func modifiedEntryIds(forDay day: Date) -> Set<Int64> {
        TimelineBuilder.modifiedEntryIds(from: eventLog.events(forDay: Day(day)))
    }

    public func startCounts(forDay day: Date) -> [Int64: Int] {
        TimelineBuilder.startCounts(from: eventLog.events(forDay: Day(day)))
    }

    /// Starts the sync and AFK loops. Safe to call again; a second call
    /// replaces the running loops rather than adding to them.
    public func start() {
        guard api != nil else { return }
        syncTicker.start { [weak self] in await self?.sync() }
        afkTicker.start { [weak self] in self?.afkTick() }
    }

    public func stop() {
        syncTicker.stop()
        afkTicker.stop()
    }

    /// One turn of the AFK loop: move the clock on, roll the view over if the
    /// day changed under it, then look for idleness.
    public func afkTick() {
        let previousNow = now
        now = .now
        // Only follow the clock past midnight for someone still looking at
        // what was today. Anyone browsing another day stays where they are.
        if Calendar.current.isDate(selectedDay, inSameDayAs: previousNow),
           !Calendar.current.isDate(now, inSameDayAs: previousNow) {
            goToToday()
        }
        checkAFK()
    }

    /// Call when the window comes to the front. The first open of a calendar
    /// day lands on today, wherever the app was left the day before; later
    /// opens the same day leave the chosen day alone.
    public func windowDidOpen() {
        now = .now
        if !Calendar.current.isDate(lastOpenedAt, inSameDayAs: now) {
            goToToday()
        }
        lastOpenedAt = now
    }

    public func sync() async {
        var days = Set(weekDays.map(Day.init))
        days.formUnion(weekCalendar.week(containing: .now).map(Day.init))

        await perform { api in
            let sortedDays = days.sorted()
            let userId: Int64
            if let currentUserId {
                userId = currentUserId
            } else {
                userId = try await api.currentUser().id
                currentUserId = userId
            }
            if companyBaseUri == nil {
                companyBaseUri = try await api.company().baseUri
            }
            let entries = try await api.timeEntries(
                from: sortedDays.first!,
                to: sortedDays.last!,
                userId: userId
            )
            now = .now
            lastSyncAt = now
            let previousRunning = runningEntry
            book.replace(
                weekCalendar.days(from: sortedDays.first!, to: sortedDays.last!),
                with: entries
            )
            recordExternalTimerChange(from: previousRunning, to: runningEntry)
            syncError = nil
        }
        await loadProjectBudgets()
    }

    /// Fetches the budget report, at most once per refresh interval. Harvest
    /// only shows budgets to administrators and managers, so a 403 turns the
    /// feature off quietly; other failures keep whatever was shown before.
    func loadProjectBudgets() async {
        guard let api, !budgetsUnavailable else { return }
        if let lastBudgetFetchAt,
           Date.now.timeIntervalSince(lastBudgetFetchAt) < Self.budgetRefreshInterval {
            return
        }
        do {
            let budgets = try await api.projectBudgets()
            projectBudgets = Dictionary(budgets.map { ($0.projectId, $0) }) { _, last in last }
            lastBudgetFetchAt = .now
        } catch HarvestAPIError.forbidden {
            budgetsUnavailable = true
        } catch {}
    }

    public func startFavorite(_ favorite: Favorite) async {
        await startTimer(projectId: favorite.projectId, taskId: favorite.taskId)
    }

    public func startTimer(projectId: Int64, taskId: Int64, notes: String? = nil) async {
        let today = Day(.now)
        let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        await perform { api in
            recordStopForRunningEntry()
            let entry: TimeEntry
            if let existing = entries(forDay: .now).first(where: {
                $0.project.id == projectId && $0.task.id == taskId && ($0.notes ?? "") == notes
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
            eventLog.append(
                TimerEvent(entryId: entry.id, action: .start, timestamp: .now, projectId: entry.project.id),
                day: today
            )
            apply(entry)
            await sync()
            apply(entry)
        }
    }

    public func toggle(_ entry: TimeEntry) async {
        let current = currentVersion(of: entry)
        await perform { api in
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
                await deleteEntry(source)
            } else {
                await updateHours(source, hours: plan.remaining)
            }

            if wasRunning {
                await restartTimer(on: plan.emptiesSource ? landedOn : source)
            }
            await sync()
        }
    }

    /// Picks a stopped entry's timer back up, keeping its notes — unlike
    /// `startTimer`, which matches on empty notes and would leave a noted
    /// entry behind for a fresh unnamed copy.
    private func restartTimer(on entry: TimeEntry) async {
        await perform { api in
            let restarted = try await api.restart(entryId: entry.id)
            eventLog.append(
                TimerEvent(
                    entryId: restarted.id,
                    action: .start,
                    timestamp: .now,
                    projectId: restarted.project.id
                ),
                day: restarted.spentDate
            )
            apply(restarted)
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
        await perform { api in
            try await api.deleteEntry(entryId: entry.id)
            eventLog.append(
                TimerEvent(entryId: entry.id, action: .delete, timestamp: .now, projectId: entry.project.id),
                day: entry.spentDate
            )
            book.remove(entry)
        }
    }

    public func entry(withId id: Int64) -> TimeEntry? {
        book.entry(withId: id)
    }

    public func dismissAFKPrompt() {
        afkPrompt = nil
    }

    /// Takes the away time off the entry that was running and puts it on
    /// another project and task instead.
    public func moveAFKTime(projectId: Int64, taskId: Int64) async {
        guard let prompt = afkPrompt, let entry = entry(withId: prompt.entryId) else { return }
        afkPrompt = nil
        await moveTime(entry, hours: prompt.duration / 3600, projectId: projectId, taskId: taskId)
    }

    public func removeAFKTime() async {
        guard let prompt = afkPrompt else { return }
        afkPrompt = nil
        guard let entry = entry(withId: prompt.entryId) else { return }
        let hours = max(0, liveHours(for: entry) - prompt.duration / 3600)
        await perform { api in
            let updated = try await api.updateHours(entryId: entry.id, hours: hours)
            logEdit(updated)
            apply(updated)
            await sync()
        }
    }

    private func checkAFK() {
        let currentActivity = Date.now.addingTimeInterval(-idleSeconds())
        let updated = AFKDetector.evaluate(
            prompt: afkPrompt,
            lastActivity: lastActivityAt,
            currentActivity: currentActivity,
            toleranceSeconds: Double(afkToleranceMinutes) * 60,
            runningEntryId: runningEntry?.id,
            runningEntryStartedAt: runningEntry?.timerStartedAt
        )
        lastActivityAt = max(lastActivityAt, currentActivity)
        let isNew = updated != nil && afkPrompt == nil
        afkPrompt = updated
        if isNew { onAFKDetected?() }
    }

    /// The project's page on the Harvest site, once a sync has learned where
    /// the account lives.
    public func projectURL(for projectId: Int64) -> URL? {
        companyBaseUri.flatMap { URL(string: "\($0)/projects/\(projectId)") }
    }

    func loadProjectAssignments() async {
        guard projectAssignments.isEmpty else { return }
        await perform { api in
            projectAssignments = try await api.projectAssignments()
        }
    }

    public func breakTitle(forBreakId id: String) -> String? {
        breakTitles[id]
    }

    /// Names a break on the timeline. A blank title takes the name away.
    public func setBreakTitle(_ title: String, forBreakId id: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            breakTitles.removeValue(forKey: id)
        } else {
            breakTitles[id] = trimmed
        }
        breakTitlesStore.save(breakTitles)
    }

    public func addFavorite(_ favorite: Favorite) {
        // Matched by id, not by every field: a project renamed in Harvest is
        // still the same favorite.
        guard !favorites.contains(where: { $0.id == favorite.id }) else { return }
        favorites.append(favorite)
        favoritesStore.save(favorites)
    }

    public func removeFavorite(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
        favoritesStore.save(favorites)
    }

    public func isFavorite(projectId: Int64, taskId: Int64) -> Bool {
        favorites.contains { $0.projectId == projectId && $0.taskId == taskId }
    }

    public func toggleFavorite(_ favorite: Favorite) {
        if favorites.contains(where: { $0.id == favorite.id }) {
            removeFavorite(favorite)
        } else {
            addFavorite(favorite)
        }
    }

    public func moveFavorite(from: Int, to: Int) {
        let reordered = FavoriteOrder.moving(favorites, from: from, to: to)
        guard reordered != favorites else { return }
        favorites = reordered
        favoritesStore.save(favorites)
    }

    public func updateFavorite(_ favorite: Favorite) {
        guard let index = favorites.firstIndex(where: { $0.id == favorite.id }) else { return }
        guard favorites[index] != favorite else { return }
        favorites[index] = favorite
        favoritesStore.save(favorites)
    }

    func saveCredentials(token: String, accountId: String) throws {
        let credentials = Keychain.Credentials(token: token, accountId: accountId)
        try Keychain.shared.save(credentials)
        self.credentials = credentials
        currentUserId = nil
        companyBaseUri = nil
        projectBudgets = [:]
        budgetsUnavailable = false
        lastBudgetFetchAt = nil
        start()
    }

    func removeCredentials() {
        Keychain.shared.clear()
        credentials = nil
        currentUserId = nil
        companyBaseUri = nil
        book.removeAll()
        projectAssignments = []
        projectBudgets = [:]
        budgetsUnavailable = false
        lastBudgetFetchAt = nil
        afkPrompt = nil
        stop()
    }

    /// Runs `work` against Harvest, putting any failure in the error banner.
    /// Does nothing when there are no credentials yet.
    private func perform(_ work: (HarvestClient) async throws -> Void) async {
        guard let api else { return }
        do {
            try await work(api)
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func currentVersion(of entry: TimeEntry) -> TimeEntry {
        book.currentVersion(of: entry)
    }

    /// Files an entry Harvest just handed back. The clock restarts with it, so
    /// a running entry counts up from the hours Harvest reported rather than
    /// from the last sync.
    private func apply(_ updated: TimeEntry) {
        now = .now
        lastSyncAt = now
        book.apply(updated)
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
}
