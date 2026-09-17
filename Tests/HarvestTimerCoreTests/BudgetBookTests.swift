import Foundation
import Testing

@testable import HarvestTimerCore

@Test("BudgetBook")
func runBudgetBookTests() {
    let today = day("2025-08-06")
    let row = ProjectBudget(
        projectId: 10,
        budgetBy: "project_cost",
        budget: 10000,
        budgetSpent: 5800,
        budgetRemaining: 4200
    )

    test("an empty book asks for budgets") {
        expect(BudgetBook().needsRefresh(force: false), "nothing to go on yet")
    }

    test("a fresh answer holds until the interval is out, or someone forces it") {
        var book = BudgetBook()
        let fetchedAt = Date.now
        book.received([row], at: fetchedAt)
        expect(
            !book.needsRefresh(force: false, now: fetchedAt.addingTimeInterval(60)),
            "a minute later is still fresh"
        )
        expect(
            book.needsRefresh(
                force: false,
                now: fetchedAt.addingTimeInterval(BudgetBook.refreshInterval + 1)
            ),
            "past the interval it should ask again"
        )
        expect(book.needsRefresh(force: true, now: fetchedAt), "a forced refresh never waits")
    }

    test("a refusal ends the asking, forced or not") {
        var book = BudgetBook()
        book.refused()
        expect(!book.needsRefresh(force: false), "Harvest has said no")
        expect(!book.needsRefresh(force: true), "and a force should not pester it")
    }

    test("only task-budgeted projects need their spend added up") {
        var book = BudgetBook()
        book.received([
            row,
            ProjectBudget(projectId: 11, budgetBy: "task_fees", budget: 1, budgetSpent: 0, budgetRemaining: 1),
        ])
        expect(book.perTaskProjects(among: [10, 11, 12]) == [11], "only the task-budgeted one")
    }

    test("the line for an entry follows how its project is budgeted") {
        var book = BudgetBook()
        book.received([
            row,
            ProjectBudget(projectId: 11, budgetBy: "task_fees", budget: 9000, budgetSpent: 8000, budgetRemaining: 1000),
        ])
        book.setTaskBudgets([
            11: TaskBudgets(
                budgets: [110: 1000],
                entries: [entry(id: 2, day: today, hours: 2, project: 11, task: 110, billable: true, rate: 100)],
                isMonetary: true
            ),
        ])

        let projectEntry = entry(id: 1, day: today, hours: 1, project: 10, task: 100)
        expect(
            book.line(for: projectEntry)?.summary == "Budget remaining: $4.2k (42%)",
            "the report's own totals, got \(String(describing: book.line(for: projectEntry)))"
        )

        let taskEntry = entry(id: 2, day: today, hours: 2, project: 11, task: 110)
        expect(
            book.line(for: taskEntry)?.summary == "Budget remaining: $800 (80%)",
            "the task's own budget, got \(String(describing: book.line(for: taskEntry)))"
        )

        let unbudgeted = entry(id: 3, day: today, hours: 1, project: 12, task: 120)
        expect(book.line(for: unbudgeted) == nil, "a project with no row draws nothing")
    }

    test("clearing leaves nothing behind") {
        var book = BudgetBook()
        book.received([row])
        book.refused()
        book.clear()
        expect(book.isEmpty, "no rows")
        expect(book.lastFetchAt == nil, "no stamp")
        expect(!book.isUnavailable, "and a new token gets another chance")
    }
}
