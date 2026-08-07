import Foundation

/// Matches the project picker's search box against projects, clients, and tasks.
public enum ProjectSearch {
    public struct Match {
        public let assignment: ProjectAssignment
        /// Tasks that matched the search, empty when the project itself matched.
        public let matchedTasks: [NamedRef]

        /// Show why a project surfaced: its matching tasks, else the client.
        public var subtitle: String {
            matchedTasks.isEmpty
                ? assignment.client.name
                : matchedTasks.map(\.name).joined(separator: ", ")
        }

        /// The task to pick without asking. One matching task means the search
        /// already said which one they want; otherwise fall back to the task
        /// most work is booked to.
        public var defaultTaskId: Int64? {
            if matchedTasks.count == 1 { return matchedTasks[0].id }
            return assignment.taskAssignments.first {
                $0.task.name.caseInsensitiveCompare(Self.fallbackTaskName) == .orderedSame
            }?.task.id
        }

        static let fallbackTaskName = "Development"
    }

    /// True when every whitespace-separated term of the query appears in the text.
    /// An empty query matches everything.
    public static func matches(_ text: String, query: String) -> Bool {
        query
            .split(whereSeparator: \.isWhitespace)
            .allSatisfy { text.localizedCaseInsensitiveContains($0) }
    }

    /// Sorts by client then project, and keeps only what the search matches.
    /// Every whitespace-separated term must appear somewhere, so "Billy Dev"
    /// finds the Development task on the Billy Graham project.
    public static func matches(
        in assignments: [ProjectAssignment],
        query: String
    ) -> [Match] {
        let sorted = assignments.sorted {
            ($0.client.name, $0.project.name) < ($1.client.name, $1.project.name)
        }
        guard !query.split(whereSeparator: \.isWhitespace).isEmpty else {
            return sorted.map { Match(assignment: $0, matchedTasks: []) }
        }
        func matchesAll(_ haystack: String) -> Bool {
            matches(haystack, query: query)
        }
        return sorted.compactMap { assignment in
            let projectText = "\(assignment.client.name) \(assignment.project.name)"
            let projectMatches = matchesAll(projectText)
            let matchedTasks = assignment.taskAssignments.map(\.task).filter {
                matchesAll("\(projectText) \($0.name)")
            }
            guard projectMatches || !matchedTasks.isEmpty else { return nil }
            return Match(
                assignment: assignment,
                matchedTasks: projectMatches ? [] : matchedTasks
            )
        }
    }
}
