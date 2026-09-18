import Foundation
import Observation

/// The projects and tasks the user may book against, as Harvest assigns them.
@MainActor
@Observable
public final class AssignmentBook {
    public private(set) var all: [ProjectAssignment] = []

    private let session: Session
    private let errors: ErrorSink

    public init(session: Session, errors: ErrorSink) {
        self.session = session
        self.errors = errors
    }

    /// Loads the assignments once, or again when `force` says to: task
    /// budgets live on them, and one added in Harvest mid-session would
    /// otherwise never show up.
    public func load(force: Bool = false) async {
        guard force || all.isEmpty else { return }
        guard let api = session.client else { return }
        await errors.run { all = try await api.projectAssignments() }
    }

    /// The per-task budgets Harvest holds against a project, if any.
    func taskBudgets(forProject projectId: Int64) -> [Int64: Double] {
        all.first { $0.project.id == projectId }?.taskBudgets ?? [:]
    }

    func removeAll() {
        all = []
    }
}
