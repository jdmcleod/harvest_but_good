import Foundation

/// Harvest hands back projects, tasks, and clients in the same shape: an id
/// and a name. One type covers all of them.
public struct NamedRef: Codable, Identifiable, Equatable {
    public let id: Int64
    public let name: String

    public init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }
}

public struct TimeEntry: Codable, Identifiable, Equatable {
    public let id: Int64
    public let spentDate: Day
    public var hours: Double
    public var notes: String?
    public var isRunning: Bool
    public let billable: Bool
    public let project: NamedRef
    public let task: NamedRef
    public let client: NamedRef
    public let timerStartedAt: Date?

    public init(
        id: Int64,
        spentDate: Day,
        hours: Double,
        notes: String? = nil,
        isRunning: Bool = false,
        billable: Bool = false,
        project: NamedRef,
        task: NamedRef,
        client: NamedRef,
        timerStartedAt: Date? = nil
    ) {
        self.id = id
        self.spentDate = spentDate
        self.hours = hours
        self.notes = notes
        self.isRunning = isRunning
        self.billable = billable
        self.project = project
        self.task = task
        self.client = client
        self.timerStartedAt = timerStartedAt
    }
}

public struct TimeEntriesPage: Codable {
    public let timeEntries: [TimeEntry]
    public let nextPage: Int?
}

public struct ProjectAssignment: Codable, Identifiable {
    public struct TaskAssignment: Codable {
        public let task: NamedRef

        public init(task: NamedRef) {
            self.task = task
        }
    }

    public let id: Int64
    public let project: NamedRef
    public let client: NamedRef
    public let taskAssignments: [TaskAssignment]

    public init(
        id: Int64,
        project: NamedRef,
        client: NamedRef,
        taskAssignments: [TaskAssignment]
    ) {
        self.id = id
        self.project = project
        self.client = client
        self.taskAssignments = taskAssignments
    }
}

public struct ProjectAssignmentsPage: Codable {
    public let projectAssignments: [ProjectAssignment]
    public let nextPage: Int?
}

/// One row of Harvest's project budget report: how much a project has to
/// spend and how much of it is gone, in hours or in money.
public struct ProjectBudget: Codable, Equatable {
    public let projectId: Int64
    /// How the project is budgeted: "project" or "task" count hours,
    /// "project_cost" and "task_fees" count money.
    public let budgetBy: String
    public let budget: Double?
    public let budgetSpent: Double?
    public let budgetRemaining: Double?

    public init(
        projectId: Int64,
        budgetBy: String,
        budget: Double?,
        budgetSpent: Double?,
        budgetRemaining: Double?
    ) {
        self.projectId = projectId
        self.budgetBy = budgetBy
        self.budget = budget
        self.budgetSpent = budgetSpent
        self.budgetRemaining = budgetRemaining
    }

    public var budgetIsMonetary: Bool {
        budgetBy.contains("cost") || budgetBy.contains("fees")
    }

    /// The card line: "Budget remaining: $4.2k (42%)", "Budget remaining:
    /// 12.5h (31%)", or "Over budget by $500" once it is spent.
    public var remainingSummary: String? {
        guard let budget, budget > 0 else { return nil }
        let remaining = budgetRemaining ?? (budget - (budgetSpent ?? 0))
        if remaining < 0 {
            return "Over budget by \(compact(-remaining))"
        }
        let percent = Int((remaining / budget * 100).rounded())
        return "Budget remaining: \(compact(remaining)) (\(percent)%)"
    }

    private func compact(_ value: Double) -> String {
        guard budgetIsMonetary else { return amount(value) }
        if value >= 1000 {
            let thousands = (value / 100).rounded() / 10
            let text = thousands == thousands.rounded()
                ? String(format: "%.0f", thousands)
                : String(format: "%.1f", thousands)
            return "$\(text)k"
        }
        return "$\(Int(value.rounded()))"
    }

    /// "12.5h left of 40h", "$4,200 left of $10,000", or the "over" versions
    /// once the budget is spent.
    public var remainingDescription: String? {
        guard let budget, budget > 0 else { return nil }
        let remaining = budgetRemaining ?? (budget - (budgetSpent ?? 0))
        if remaining < 0 {
            return "\(amount(-remaining)) over the \(amount(budget)) budget"
        }
        return "\(amount(remaining)) left of \(amount(budget))"
    }

    private func amount(_ value: Double) -> String {
        if budgetIsMonetary {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            formatter.locale = Locale(identifier: "en_US")
            return "$" + (formatter.string(from: NSNumber(value: value)) ?? String(Int(value)))
        }
        let rounded = (value * 10).rounded() / 10
        return String(format: rounded == rounded.rounded() ? "%.0fh" : "%.1fh", rounded)
    }
}

public struct ProjectBudgetsPage: Codable {
    public let results: [ProjectBudget]
    public let nextPage: Int?
}

public struct HarvestUser: Codable {
    public let id: Int64
    public let firstName: String
    public let lastName: String

    public init(id: Int64, firstName: String, lastName: String) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
    }
}

public struct HarvestCompany: Codable {
    public let name: String
    /// Where this account lives on the web, e.g. "https://acme.harvestapp.com".
    public let baseUri: String

    public init(name: String, baseUri: String) {
        self.name = name
        self.baseUri = baseUri
    }
}

public struct Favorite: Codable, Identifiable, Equatable {
    public static let maxLabelLength = 6

    public let projectId: Int64
    public let taskId: Int64
    public let clientName: String
    public let projectName: String
    public let taskName: String
    public var nickname: String?
    public var colorIndex: Int?

    public var id: String { "\(projectId)-\(taskId)" }

    public var chipLabel: String {
        let name = nickname?.trimmingCharacters(in: .whitespaces)
        if let name, !name.isEmpty {
            return String(name.uppercased().prefix(Self.maxLabelLength))
        }
        return String(derivedName.uppercased().prefix(Self.maxLabelLength))
    }

    private var derivedName: String {
        if let separator = projectName.range(of: #"\s*[–—]\s*|\s+-\s+"#, options: .regularExpression) {
            let stripped = projectName[separator.upperBound...].trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty { return stripped }
        }
        return projectName
    }

    public init(
        projectId: Int64,
        taskId: Int64,
        clientName: String,
        projectName: String,
        taskName: String,
        nickname: String? = nil,
        colorIndex: Int? = nil
    ) {
        self.projectId = projectId
        self.taskId = taskId
        self.clientName = clientName
        self.projectName = projectName
        self.taskName = taskName
        self.nickname = nickname
        self.colorIndex = colorIndex
    }
}

public struct TimerEvent: Codable, Equatable {
    public enum Action: String, Codable {
        case start
        case stop
        case edit
        case delete
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

public struct RunningTimer: Equatable {
    public let entryId: Int64
    public let projectId: Int64
    public let startedAt: Date?

    public init(entryId: Int64, projectId: Int64, startedAt: Date?) {
        self.entryId = entryId
        self.projectId = projectId
        self.startedAt = startedAt
    }
}

public struct TimelineBlock: Identifiable, Equatable {
    public let entryId: Int64
    public let projectId: Int64
    public let start: Date
    public let end: Date

    public var id: String { "\(entryId)-\(start.timeIntervalSince1970)" }
}

public struct TimelineBreak: Identifiable, Equatable {
    public let start: Date
    public let end: Date

    public var id: String { "break-\(start.timeIntervalSince1970)" }

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    public var label: String {
        let minutes = Int((duration / 60).rounded())
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 {
            return "\(minutes) minute break"
        }
        if remainder == 0 {
            return "\(hours) hour break"
        }
        return "\(hours) hour \(remainder) minute break"
    }
}
