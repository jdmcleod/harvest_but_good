import Foundation
import Testing

@testable import HarvestTimerCore

/// A stand-in Harvest that keeps entries in memory and behaves the way the
/// real service does: starting a timer stops whichever one was running.
final class FakeHarvest: HarvestClient, @unchecked Sendable {
    private(set) var entries: [Int64: TimeEntry] = [:]
    /// Every call made, in order, so tests can check what happened and when.
    private(set) var calls: [String] = []
    var nextId: Int64 = 1000
    var failNextCall: Error?

    init(entries: [TimeEntry] = []) {
        for entry in entries {
            self.entries[entry.id] = entry
        }
    }

    func entry(_ id: Int64) -> TimeEntry? { entries[id] }

    var runningEntry: TimeEntry? { entries.values.first { $0.isRunning } }

    private func record(_ call: String) throws {
        calls.append(call)
        if let failNextCall {
            self.failNextCall = nil
            throw failNextCall
        }
    }

    private func stopEverything() {
        for (id, entry) in entries where entry.isRunning {
            var stopped = entry
            stopped.isRunning = false
            entries[id] = stopped
        }
    }

    func currentUser() async throws -> HarvestUser {
        try record("currentUser")
        return HarvestUser(id: 7, firstName: "Ada", lastName: "Lovelace")
    }

    func company() async throws -> HarvestCompany {
        try record("company")
        return HarvestCompany(name: "Test Co")
    }

    func timeEntries(from: Day, to: Day, userId: Int64) async throws -> [TimeEntry] {
        try record("timeEntries(\(from)…\(to))")
        return entries.values
            .filter { $0.spentDate >= from && $0.spentDate <= to }
            .sorted { $0.id < $1.id }
    }

    func projectAssignments() async throws -> [ProjectAssignment] {
        try record("projectAssignments")
        return searchFixtures
    }

    func startTimer(projectId: Int64, taskId: Int64, spentDate: Day) async throws -> TimeEntry {
        try record("startTimer(project: \(projectId), task: \(taskId))")
        stopEverything()
        nextId += 1
        let entry = TimeEntry(
            id: nextId,
            spentDate: spentDate,
            hours: 0,
            isRunning: true,
            project: NamedRef(id: projectId, name: "Project \(projectId)"),
            task: NamedRef(id: taskId, name: "Task \(taskId)"),
            client: NamedRef(id: 1, name: "Client"),
            timerStartedAt: base
        )
        entries[entry.id] = entry
        return entry
    }

    func createEntry(
        projectId: Int64,
        taskId: Int64,
        spentDate: Day,
        hours: Double,
        notes: String?
    ) async throws -> TimeEntry {
        try record("createEntry(project: \(projectId), task: \(taskId), hours: \(hours))")
        nextId += 1
        let entry = TimeEntry(
            id: nextId,
            spentDate: spentDate,
            hours: hours,
            notes: notes,
            project: NamedRef(id: projectId, name: "Project \(projectId)"),
            task: NamedRef(id: taskId, name: "Task \(taskId)"),
            client: NamedRef(id: 1, name: "Client")
        )
        entries[entry.id] = entry
        return entry
    }

    func restart(entryId: Int64) async throws -> TimeEntry {
        try record("restart(\(entryId))")
        stopEverything()
        guard var entry = entries[entryId] else { throw FakeError.noSuchEntry }
        entry.isRunning = true
        entries[entryId] = entry
        return entry
    }

    func stop(entryId: Int64) async throws -> TimeEntry {
        try record("stop(\(entryId))")
        guard var entry = entries[entryId] else { throw FakeError.noSuchEntry }
        entry.isRunning = false
        entries[entryId] = entry
        return entry
    }

    func updateHours(entryId: Int64, hours: Double) async throws -> TimeEntry {
        try record("updateHours(\(entryId), \(hours))")
        guard var entry = entries[entryId] else { throw FakeError.noSuchEntry }
        entry.hours = hours
        entries[entryId] = entry
        return entry
    }

    func updateProjectTask(entryId: Int64, projectId: Int64, taskId: Int64) async throws -> TimeEntry {
        try record("updateProjectTask(\(entryId), project: \(projectId), task: \(taskId))")
        guard let existing = entries[entryId] else { throw FakeError.noSuchEntry }
        let entry = TimeEntry(
            id: existing.id,
            spentDate: existing.spentDate,
            hours: existing.hours,
            notes: existing.notes,
            isRunning: existing.isRunning,
            project: NamedRef(id: projectId, name: "Project \(projectId)"),
            task: NamedRef(id: taskId, name: "Task \(taskId)"),
            client: existing.client,
            timerStartedAt: existing.timerStartedAt
        )
        entries[entryId] = entry
        return entry
    }

    func updateNotes(entryId: Int64, notes: String) async throws -> TimeEntry {
        try record("updateNotes(\(entryId))")
        guard var entry = entries[entryId] else { throw FakeError.noSuchEntry }
        entry.notes = notes
        entries[entryId] = entry
        return entry
    }

    func deleteEntry(entryId: Int64) async throws {
        try record("deleteEntry(\(entryId))")
        entries[entryId] = nil
    }

    enum FakeError: Error {
        case noSuchEntry
    }
}

/// A scratch directory that cleans itself up when `body` returns.
func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("HarvestTimerTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory)
}

func entry(
    id: Int64,
    day: Day,
    hours: Double,
    project: Int64,
    task: Int64,
    running: Bool = false,
    notes: String? = nil
) -> TimeEntry {
    TimeEntry(
        id: id,
        spentDate: day,
        hours: hours,
        notes: notes,
        isRunning: running,
        project: NamedRef(id: project, name: "Project \(project)"),
        task: NamedRef(id: task, name: "Task \(task)"),
        client: NamedRef(id: 1, name: "Client")
    )
}
