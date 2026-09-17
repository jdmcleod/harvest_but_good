import Foundation

/// Per-task budgets for one project. Harvest's budget report only ever gives
/// project-wide totals, so on a project budgeted by task the spend has to be
/// added up from the entries themselves.
public struct TaskBudgets: Equatable {
    private let lines: [Int64: BudgetLine]

    /// - Parameters:
    ///   - budgets: each task's budget, in hours or fees, by task id.
    ///   - entries: every user's entries on the project.
    ///   - isMonetary: fees rather than hours, from the project's `budget_by`.
    public init(budgets: [Int64: Double], entries: [TimeEntry], isMonetary: Bool) {
        var spent: [Int64: Double] = [:]
        for entry in entries {
            let value: Double
            if isMonetary {
                // Non-billable time costs the budget nothing, and a nil rate
                // means Harvest is hiding rates from this user.
                guard entry.billable, let rate = entry.billableRate else { continue }
                value = entry.hours * rate
            } else {
                value = entry.hours
            }
            spent[entry.task.id, default: 0] += value
        }
        lines = budgets.reduce(into: [:]) { result, pair in
            result[pair.key] = BudgetLine(
                isMonetary: isMonetary,
                budget: pair.value,
                spent: spent[pair.key] ?? 0
            )
        }
    }

    public subscript(taskId: Int64) -> BudgetLine? { lines[taskId] }

    public var isEmpty: Bool { lines.isEmpty }
}
