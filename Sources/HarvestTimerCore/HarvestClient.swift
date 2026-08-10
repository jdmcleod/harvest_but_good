import Foundation

/// Everything the app asks of Harvest. `HarvestAPI` talks to the real service;
/// tests stand in their own conformance.
public protocol HarvestClient {
    func currentUser() async throws -> HarvestUser
    func company() async throws -> HarvestCompany
    func timeEntries(from: Day, to: Day, userId: Int64) async throws -> [TimeEntry]
    func projectAssignments() async throws -> [ProjectAssignment]
    /// Budget vs. spent for every active project. Harvest only answers for
    /// administrators and project managers; everyone else draws a 403.
    func projectBudgets() async throws -> [ProjectBudget]
    func startTimer(projectId: Int64, taskId: Int64, spentDate: Day, notes: String?) async throws -> TimeEntry
    func createEntry(
        projectId: Int64,
        taskId: Int64,
        spentDate: Day,
        hours: Double,
        notes: String?
    ) async throws -> TimeEntry
    func restart(entryId: Int64) async throws -> TimeEntry
    func stop(entryId: Int64) async throws -> TimeEntry
    func updateHours(entryId: Int64, hours: Double) async throws -> TimeEntry
    func updateProjectTask(entryId: Int64, projectId: Int64, taskId: Int64) async throws -> TimeEntry
    func updateNotes(entryId: Int64, notes: String) async throws -> TimeEntry
    func deleteEntry(entryId: Int64) async throws
}
