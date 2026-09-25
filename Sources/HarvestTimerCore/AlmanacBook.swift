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

    /// Folds in a fresh answer. Each part is optional and only touched when
    /// given, since pace and time off are fetched independently now — asking
    /// for one shouldn't blank out whatever the other already had cached.
    ///
    /// Almanac's `next_constraints` only returns constraints ending *after*
    /// today, so for those the fresh answer is the whole truth — anything
    /// cached but missing from it was cancelled and goes. A constraint ending
    /// today can't come back from that endpoint at all, so the cached copy
    /// is kept: a same-day half day would otherwise vanish the moment it
    /// arrives.
    mutating func received(
        personId: String? = nil,
        pace: AlmanacPace? = nil,
        constraints incoming: [AlmanacConstraint]? = nil,
        at time: Date = .now
    ) {
        if let personId { self.personId = personId }
        if let pace { self.pace = pace }
        if let incoming {
            let today = Day(time)
            let incomingIds = Set(incoming.map(\.id))
            let endingToday = constraints.filter {
                !incomingIds.contains($0.id) && $0.endDate == today
            }
            self.constraints = endingToday + incoming
        }
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
