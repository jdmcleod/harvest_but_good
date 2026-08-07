import Foundation

/// Everything the app asks of Harvest. `HarvestAPI` talks to the real service;
/// tests stand in their own conformance.
public protocol HarvestClient {
    func currentUser() async throws -> HarvestUser
    func company() async throws -> HarvestCompany
    func timeEntries(from: String, to: String, userId: Int64) async throws -> [TimeEntry]
    func projectAssignments() async throws -> [ProjectAssignment]
    func startTimer(projectId: Int64, taskId: Int64, spentDate: String) async throws -> TimeEntry
    func createEntry(
        projectId: Int64,
        taskId: Int64,
        spentDate: String,
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
