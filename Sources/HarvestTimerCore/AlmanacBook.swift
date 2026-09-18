import Foundation

/// Everything the app knows from Almanac: the resolved person id, the current
/// pace, the time off ahead of it, and when it was last asked. `AppState`
/// makes the calls and hands the results here; the decisions live in this
/// type — the same split `BudgetBook` makes for Harvest's budgets.
public struct AlmanacBook: Equatable, Codable, Sendable {
    public static let refreshInterval: TimeInterval = 15 * 60

    public private(set) var personId: String?
    public private(set) var pace: AlmanacPace?
    public private(set) var constraints: [AlmanacConstraint] = []
    /// Internal, not private, so a test can put it in the past instead of
    /// waiting out the refresh interval.
    var lastFetchAt: Date?
    /// A key or email Almanac has refused. Turns the feature off for the
    /// session rather than asking again every sync.
    public private(set) var isUnavailable = false

    public init() {}

    func needsRefresh(force: Bool, now: Date = .now) -> Bool {
        guard !isUnavailable else { return false }
        guard !force, let lastFetchAt else { return true }
        return now.timeIntervalSince(lastFetchAt) >= Self.refreshInterval
    }

    /// Folds in a fresh answer. Constraints are merged by id rather than
    /// replaced outright: Almanac's `next_constraints` only returns
    /// constraints ending *after* today, so a same-day half day drops off
    /// that list the moment it arrives — merging keeps it around from the
    /// fetch that saw it while it was still tomorrow.
    mutating func received(
        personId: String,
        pace: AlmanacPace,
        constraints incoming: [AlmanacConstraint],
        at time: Date = .now
    ) {
        self.personId = personId
        self.pace = pace
        var merged = Dictionary(uniqueKeysWithValues: constraints.map { ($0.id, $0) })
        for constraint in incoming { merged[constraint.id] = constraint }
        // Drop anything that ended a couple of days ago so an edited or
        // cancelled constraint does not linger on the strength of one old
        // fetch forever.
        let cutoff = Day(time.addingTimeInterval(-2 * 24 * 3600))
        self.constraints = merged.values.filter { $0.endDate >= cutoff }
        lastFetchAt = time
        isUnavailable = false
    }

    mutating func refused() {
        isUnavailable = true
    }

    mutating func clear() {
        personId = nil
        pace = nil
        constraints = []
        lastFetchAt = nil
        isUnavailable = false
    }
}
