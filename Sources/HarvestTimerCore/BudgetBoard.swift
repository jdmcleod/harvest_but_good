import Foundation
import Observation

/// Keeps the budget book fed. `BudgetBook` decides what a budget means and
/// when it is stale; this asks Harvest for the answers and hands them over.
@MainActor
@Observable
public final class BudgetBoard {
    public private(set) var book = BudgetBook()

    private let session: Session
    private let assignments: AssignmentBook

    public init(session: Session, assignments: AssignmentBook) {
        self.session = session
        self.assignments = assignments
    }

    /// The budget to draw on an entry's card.
    public func line(for entry: TimeEntry) -> BudgetLine? {
        book.line(for: entry)
    }

    public subscript(projectId: Int64) -> ProjectBudget? { book[projectId] }

    public var isEmpty: Bool { book.isEmpty }
    public var isUnavailable: Bool { book.isUnavailable }
    var hasTaskBudgets: Bool { book.hasTaskBudgets }
    var lastFetchAt: Date? { book.lastFetchAt }

    /// Internal, so a test can put the last fetch in the past instead of
    /// waiting out the refresh interval.
    func expire() {
        book.lastFetchAt = .distantPast
    }

    func clear() {
        book.clear()
    }

    /// Fetches the budget report, at most once per refresh interval unless
    /// `force` says otherwise. A 403 turns the feature off quietly; other
    /// failures keep whatever was shown before.
    ///
    /// `spentOn` is the projects worth adding up task by task — the ones this
    /// week's entries actually sit on.
    public func refresh(force: Bool = false, spentOn projectIds: Set<Int64>) async {
        guard let api = session.client, book.needsRefresh(force: force) else { return }
        do {
            book.received(try await api.projectBudgets())
        } catch HarvestAPIError.forbidden {
            book.refused()
            return
        } catch { return }
        await loadTaskBudgets(among: projectIds, using: api)
    }

    /// Fills in per-task budgets for the projects budgeted that way. Only the
    /// projects asked for, because each one costs a pass over its whole
    /// time-entry history.
    private func loadTaskBudgets(among projectIds: Set<Int64>, using api: HarvestClient) async {
        let perTask = book.perTaskProjects(among: projectIds)
        guard !perTask.isEmpty else {
            book.setTaskBudgets([:])
            return
        }
        await assignments.load(force: true)
        var built: [Int64: TaskBudgets] = [:]
        for projectId in perTask {
            guard let budget = book[projectId] else { continue }
            let amounts = assignments.taskBudgets(forProject: projectId)
            guard !amounts.isEmpty else { continue }
            guard let entries = try? await api.projectTimeEntries(projectId: projectId) else {
                // Keep what we had rather than blank the line on one failure.
                built[projectId] = book.taskBudgets(forProject: projectId)
                continue
            }
            built[projectId] = TaskBudgets(
                budgets: amounts,
                entries: entries,
                isMonetary: budget.budgetIsMonetary
            )
        }
        book.setTaskBudgets(built)
    }
}
