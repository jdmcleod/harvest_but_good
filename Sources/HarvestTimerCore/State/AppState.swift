import Foundation
import Observation

/// What the app is made of, and the two loops that drive it.
///
/// Every job of substance belongs to one of the parts below; this holds them
/// together, wires the calls that cross between them, and owns the sync and
/// AFK tickers. Views reach through it to the part they need.
@MainActor
@Observable
public final class AppState {
    public let session: Session
    public let clock: Clock
    public let errors = ErrorSink()
    public let entries: EntryStore
    public let timeline: Timeline
    public let away: AwayWatch
    public let favorites: FavoritesBook
    public let goals: GoalBook
    public let breaks: BreakTitleBook
    public let assignments: AssignmentBook
    public let budgets: BudgetBoard

    /// The entry the day view has the cursor on. Let go whenever the day
    /// changes, since it belongs to the day it was picked on.
    public var selectedEntryId: Int64?

    public static let syncInterval = Duration.seconds(30)
    public static let afkInterval = AwayWatch.interval
    private let syncTicker = Ticker(every: AppState.syncInterval)
    private let afkTicker = Ticker(every: AppState.afkInterval)

    public convenience init(
        idleSeconds: @escaping () -> TimeInterval = AFKDetector.systemIdleSeconds,
        sleepWatch: SleepWatch? = nil
    ) {
        self.init(
            session: Session(),
            storageDirectory: EventLog.defaultDirectory,
            idleSeconds: idleSeconds,
            sleepWatch: sleepWatch ?? SleepWatch(),
            toleranceMinutes: AwayWatch.storedTolerance
        )
    }

    /// Builds a state that talks to `client` and keeps its files under
    /// `storageDirectory`, leaving the Keychain alone. Like the other init it
    /// starts no loops, so a test drives `sync` and `afkTick` itself.
    public convenience init(
        client: HarvestClient,
        storageDirectory: URL,
        idleSeconds: @escaping () -> TimeInterval = { 0 },
        sleepWatch: SleepWatch? = nil
    ) {
        self.init(
            session: Session(client: client),
            storageDirectory: storageDirectory,
            idleSeconds: idleSeconds,
            // A centre of its own, so no real sleep reaches a test.
            sleepWatch: sleepWatch ?? SleepWatch(center: NotificationCenter()),
            toleranceMinutes: 10
        )
    }

    private init(
        session: Session,
        storageDirectory: URL,
        idleSeconds: @escaping () -> TimeInterval,
        sleepWatch: SleepWatch,
        toleranceMinutes: Int
    ) {
        let log = EventLog(directory: storageDirectory)
        let clock = Clock()
        let errors = self.errors
        let entries = EntryStore(log: log, session: session, errors: errors, clock: clock)
        let assignments = AssignmentBook(session: session, errors: errors)

        self.session = session
        self.clock = clock
        self.entries = entries
        self.timeline = Timeline(log: log, clock: clock, entries: entries)
        self.assignments = assignments
        self.budgets = BudgetBoard(session: session, assignments: assignments)
        self.away = AwayWatch(
            entries: entries,
            idleSeconds: idleSeconds,
            sleepWatch: sleepWatch,
            toleranceMinutes: toleranceMinutes
        )
        self.favorites = FavoritesBook(store: FavoritesStore(directory: storageDirectory))
        self.goals = GoalBook(store: GoalsStore(directory: storageDirectory))
        self.breaks = BreakTitleBook(store: BreakTitlesStore(directory: storageDirectory))

        clock.onDayChange = { [weak self] in self?.selectedEntryId = nil }
        entries.resync = { [weak self] in await self?.sync() }
        entries.spendChanged = { [weak self] in await self?.refreshBudgets(force: true) }
        entries.onCreate = { [weak self] id in self?.selectedEntryId = id }
    }

    // MARK: - The loops

    /// Starts the sync and AFK loops. Safe to call again; a second call
    /// replaces the running loops rather than adding to them.
    public func start() {
        guard session.client != nil else { return }
        syncTicker.start { [weak self] in
            await self?.sync()
            await self?.rollTimerIntoToday()
        }
        afkTicker.start { [weak self] in self?.afkTick() }
    }

    public func stop() {
        syncTicker.stop()
        afkTicker.stop()
    }

    /// One turn of the AFK loop: move the clock on, roll the view over if the
    /// day changed under it, then look for idleness.
    public func afkTick() {
        away.check(sinceLastTick: clock.tick())
    }

    public func sync() async {
        var days = Set(clock.weekDays.map(Day.init))
        days.formUnion(clock.currentWeek.map(Day.init))
        let sorted = days.sorted()

        guard let api = session.client else { return }
        await errors.run {
            let userId = try await session.resolveUserId(using: api)
            try await session.resolveBaseUri(using: api)
            let fetched = try await api.timeEntries(from: sorted.first!, to: sorted.last!, userId: userId)
            clock.now = .now
            entries.receive(days: clock.days(from: sorted.first!, to: sorted.last!), entries: fetched)
            errors.clear()
        }
        await refreshBudgets()
    }

    /// Hands a timer that ran past midnight over to a fresh entry on the new
    /// day. Harvest books an entry against the day it began and never moves
    /// it, so a timer left going overnight piles today's hours onto yesterday:
    /// yesterday's total climbs all morning and today's is short by the same
    /// amount. Starting a timer stops the running one, so the old entry keeps
    /// exactly what it had at the handover and the rest lands on today.
    ///
    /// Waits out an AFK prompt. The away time spans the midnight, and whether
    /// any of the night counts at all is the prompt's answer to give, not this
    /// one's. A past day's entry picked up again on purpose is left alone: its
    /// run began after midnight, so it never crossed one.
    public func rollTimerIntoToday() async {
        guard away.prompt == nil, let running = entries.running else { return }
        guard let startedAt = running.timerStartedAt,
              running.spentDate < Day(clock.now),
              startedAt < Calendar.current.startOfDay(for: clock.now) else { return }
        await entries.startTimer(
            projectId: running.project.id,
            taskId: running.task.id,
            notes: running.notes
        )
    }

    // MARK: - What the whole app knows

    /// Asks for the budget report, adding up task by task only for the
    /// projects this week's entries sit on — as far as the report needs to
    /// look, and each one costs a pass over its whole history.
    private func refreshBudgets(force: Bool = false) async {
        await budgets.refresh(force: force, spentOn: Set(entries.all.map(\.project.id)))
    }

    public var weekTotal: Double {
        entries.total(forDays: clock.weekDays)
    }

    public var weekBillableTotal: Double {
        entries.total(forDays: clock.weekDays, billableOnly: true)
    }

    public var menuBarTitle: String {
        if let running = entries.running {
            return Hours.formatted(entries.liveHours(for: running))
        }
        return Hours.formatted(entries.total(forDay: .now))
    }

    /// Books work on the day being viewed.
    public func addEntry(projectId: Int64, taskId: Int64, notes: String? = nil) async {
        await entries.add(
            on: clock.selectedDay,
            isToday: clock.isViewingToday,
            projectId: projectId,
            taskId: taskId,
            notes: notes
        )
    }

    public func startFavorite(_ favorite: Favorite) async {
        await addEntry(projectId: favorite.projectId, taskId: favorite.taskId)
    }

    /// How `day` stands against its goal, or nil when it has none.
    public func goalProgress(forDay day: Date) -> GoalProgress? {
        goals.progress(
            forDay: day,
            worked: entries.total(forDay: day),
            breakTaken: timeline.breakTakenHours(forDay: day)
        )
    }

    /// Today against today's goal, for the menu bar — which shows the day the
    /// clock is in, whichever day the window happens to be looking at.
    public var todayGoalProgress: GoalProgress? {
        goalProgress(forDay: clock.now)
    }

    // MARK: - Credentials

    func saveCredentials(token: String, accountId: String) throws {
        try session.save(token: token, accountId: accountId)
        budgets.clear()
        start()
    }

    func removeCredentials() {
        session.clear()
        entries.removeAll()
        assignments.removeAll()
        budgets.clear()
        away.clear()
        stop()
    }
}
