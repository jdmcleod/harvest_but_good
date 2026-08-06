import Foundation

public struct TimeEntry: Codable, Identifiable, Equatable {
    public struct Project: Codable, Equatable {
        public let id: Int64
        public let name: String
    }

    public struct Task: Codable, Equatable {
        public let id: Int64
        public let name: String
    }

    public struct Client: Codable, Equatable {
        public let id: Int64
        public let name: String
    }

    public let id: Int64
    public let spentDate: String
    public var hours: Double
    public var notes: String?
    public var isRunning: Bool
    public let project: Project
    public let task: Task
    public let client: Client
    public let timerStartedAt: Date?
}

public struct TimeEntriesPage: Codable {
    public let timeEntries: [TimeEntry]
    public let nextPage: Int?
}

public struct ProjectAssignment: Codable, Identifiable {
    public struct Project: Codable {
        public let id: Int64
        public let name: String
    }

    public struct Client: Codable {
        public let id: Int64
        public let name: String
    }

    public struct TaskAssignment: Codable {
        public struct Task: Codable {
            public let id: Int64
            public let name: String
        }

        public let task: Task
    }

    public let id: Int64
    public let project: Project
    public let client: Client
    public let taskAssignments: [TaskAssignment]
}

public struct ProjectAssignmentsPage: Codable {
    public let projectAssignments: [ProjectAssignment]
    public let nextPage: Int?
}

public struct HarvestUser: Codable {
    public let id: Int64
    public let firstName: String
    public let lastName: String
}

public struct HarvestCompany: Codable {
    public let name: String
}

public struct Favorite: Codable, Identifiable, Equatable {
    public let projectId: Int64
    public let taskId: Int64
    public let clientName: String
    public let projectName: String
    public let taskName: String

    public var id: String { "\(projectId)-\(taskId)" }

    public init(projectId: Int64, taskId: Int64, clientName: String, projectName: String, taskName: String) {
        self.projectId = projectId
        self.taskId = taskId
        self.clientName = clientName
        self.projectName = projectName
        self.taskName = taskName
    }
}

public struct TimerEvent: Codable, Equatable {
    public enum Action: String, Codable {
        case start
        case stop
    }

    public let entryId: Int64
    public let action: Action
    public let timestamp: Date
    public let projectId: Int64

    public init(entryId: Int64, action: Action, timestamp: Date, projectId: Int64) {
        self.entryId = entryId
        self.action = action
        self.timestamp = timestamp
        self.projectId = projectId
    }
}

public struct TimelineBlock: Identifiable, Equatable {
    public let entryId: Int64
    public let projectId: Int64
    public let start: Date
    public let end: Date

    public var id: String { "\(entryId)-\(start.timeIntervalSince1970)" }
}
