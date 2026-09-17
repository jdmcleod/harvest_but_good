import Foundation

/// Everything the app knows about budgets: the report row for each project,
/// the per-task budgets for the projects budgeted that way, when the last
/// answer came in, and whether Harvest will answer at all. `AppState` makes
/// the calls and hands the results here; the decisions live in this type.
public struct BudgetBook: Equatable {
    public static let refreshInterval: TimeInterval = 5 * 60

    private var projects: [Int64: ProjectBudget] = [:]
    private var tasks: [Int64: TaskBudgets] = [:]
    /// Internal, not private, so a test can put it in the past instead of
    /// waiting out the refresh interval.
    var lastFetchAt: Date?
    /// Harvest only shows budgets to administrators and managers. A 403 turns
    /// the feature off for the session rather than asking again every sync.
    public private(set) var isUnavailable = false

    public init() {}

    public subscript(projectId: Int64) -> ProjectBudget? { projects[projectId] }

    public var isEmpty: Bool { projects.isEmpty }

    /// Nothing to fetch once Harvest has refused, or while the last answer is
    /// still fresh and nobody asked for a new one.
    func needsRefresh(force: Bool, now: Date = .now) -> Bool {
        guard !isUnavailable else { return false }
        guard !force, let lastFetchAt else { return true }
        return now.timeIntervalSince(lastFetchAt) >= Self.refreshInterval
    }

    mutating func received(_ budgets: [ProjectBudget], at time: Date = .now) {
        projects = Dictionary(budgets.map { ($0.projectId, $0) }) { _, last in last }
        lastFetchAt = time
    }

    mutating func refused() {
        isUnavailable = true
    }

    /// Which of these projects carry their budgets on the tasks, and so need
    /// their spend added up task by task.
    func perTaskProjects(among projectIds: some Sequence<Int64>) -> Set<Int64> {
        Set(projectIds.filter { projects[$0]?.budgetIsPerTask == true })
    }

    func taskBudgets(forProject projectId: Int64) -> TaskBudgets? {
        tasks[projectId]
    }

    mutating func setTaskBudgets(_ budgets: [Int64: TaskBudgets]) {
        tasks = budgets
    }

    var hasTaskBudgets: Bool { !tasks.isEmpty }

    /// The budget to draw on an entry's card: its own task's when the project
    /// is budgeted by task, the project's otherwise.
    public func line(for entry: TimeEntry) -> BudgetLine? {
        guard let budget = projects[entry.project.id] else { return nil }
        if budget.budgetIsPerTask {
            return tasks[entry.project.id]?[entry.task.id]
        }
        return budget.line
    }

    mutating func clear() {
        projects = [:]
        tasks = [:]
        lastFetchAt = nil
        isUnavailable = false
    }
}
