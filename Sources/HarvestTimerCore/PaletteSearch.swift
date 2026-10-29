import Foundation

/// One row of the command palette.
public struct PaletteItem: Identifiable, Equatable {
    public enum Action: Equatable {
        case start(projectId: Int64, taskId: Int64)
        case resume(entryId: Int64)
        case stop(entryId: Int64)
        case command(WindowCommand)
        case log(projectId: Int64, taskId: Int64, hours: Double, day: Date)
        case setHours(entryId: Int64, hours: Double)
        case adjust(entryId: Int64, minutes: Int)
        case goTo(Date)
        case allCommands
    }

    /// What sits in the leading square: a project's colour or a symbol.
    public enum Mark: Equatable {
        case project(Int64)
        case favorite(Favorite)
        case symbol(String)
    }

    public let id: String
    public let action: Action
    public let mark: Mark
    public let title: String
    public var subtitle: String?
    public var detail: String?
    public var keycaps: [String] = []

    /// Rows that put a clock on a task, which Shift-Return can give a note.
    public var startTarget: (projectId: Int64, taskId: Int64)? {
        switch action {
        case let .start(projectId, taskId): (projectId, taskId)
        default: nil
        }
    }

    public var hasActions: Bool {
        switch action {
        case .start, .resume, .stop: true
        default: false
        }
    }

    public static func == (lhs: PaletteItem, rhs: PaletteItem) -> Bool {
        lhs.id == rhs.id && lhs.action == rhs.action && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle && lhs.detail == rhs.detail && lhs.keycaps == rhs.keycaps
    }
}

public struct PaletteSection: Identifiable, Equatable {
    public let title: String
    public let items: [PaletteItem]
    public var id: String { title }
}

/// What the palette searches, gathered from `AppState` when it opens so the
/// search itself needs no store and no network.
public struct PaletteContext {
    public var favorites: [Favorite] = []
    public var favoriteKeys: [String: String] = [:]
    public var dayEntries: [TimeEntry] = []
    public var running: TimeEntry?
    public var target: TimeEntry?
    public var assignments: [ProjectAssignment] = []
    public var hours: [Int64: Double] = [:]
    public var viewedDay: Date = .now
    public var today: Date = .now
    public var weekDays: [Date] = []
    public var keycaps: [WindowCommand: [String]] = [:]
    public var usesCustomColors = false

    public init() {}

    func hours(of entry: TimeEntry) -> Double {
        hours[entry.id] ?? entry.hours
    }
}

/// What the palette made of the text typed into it. Durations, minute
/// nudges and day names are pulled out; whatever is left is searched for.
public struct PaletteQuery: Equatable {
    public var terms: [String] = []
    public var hours: Double?
    public var adjustMinutes: Int?
    public var dayWord: String?
    public var commandsOnly = false

    public var isEmpty: Bool {
        terms.isEmpty && hours == nil && adjustMinutes == nil && dayWord == nil
    }

    public init(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix(">") {
            commandsOnly = true
            text.removeFirst()
        }
        for word in text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init) {
            if commandsOnly {
                terms.append(word)
            } else if let minutes = Self.nudge(word) {
                adjustMinutes = minutes
            } else if let hours = Self.duration(word) {
                self.hours = hours
            } else if Self.dayWords.contains(word) {
                dayWord = word
            } else {
                terms.append(word)
            }
        }
    }

    /// "+15" or "-10": minutes on or off. Bare digits stay search terms, since
    /// project names carry years and numbers.
    private static func nudge(_ word: String) -> Int? {
        guard let sign = word.first, sign == "+" || sign == "-" else { return nil }
        var digits = word.dropFirst()
        if digits.hasSuffix("m") { digits = digits.dropLast() }
        guard let minutes = Int(digits), minutes > 0 else { return nil }
        return sign == "+" ? minutes : -minutes
    }

    /// "1:30", "1.5h", "2h" or "90m". A bare "1.5" is left to the search,
    /// which is where "v1.5" belongs.
    private static func duration(_ word: String) -> Double? {
        if word.contains(":") { return Hours.parse(word) }
        if word.hasSuffix("h"), let hours = Double(word.dropLast()), (0...24).contains(hours) {
            return hours
        }
        if word.hasSuffix("m"), let minutes = Int(word.dropLast()), (1...1440).contains(minutes) {
            return Double(minutes) / 60
        }
        return nil
    }

    static let dayWords: Set<String> = Set(
        ["today", "yesterday"] + Weekday.allCases.flatMap { [$0.rawValue, String($0.rawValue.prefix(3))] }
    )
}

public enum PaletteSearch {
    public static func sections(for text: String, in context: PaletteContext) -> [PaletteSection] {
        let query = PaletteQuery(text)
        if query.commandsOnly { return commandSections(matching: query.terms, in: context) }
        if query.isEmpty { return home(context) }

        var result: [PaletteSection] = []
        let best = bestMatches(for: query, in: context)
        if !best.isEmpty { result.append(PaletteSection(title: "Best match", items: best)) }
        guard !query.terms.isEmpty else { return result }

        let terms = query.terms
        let entries = ranked(context.dayEntries, terms) { entryText($0) }
            .map { entryItem($0, in: context) }
        let favorites = ranked(context.favorites, terms) { favoriteText($0) }
            .map { favoriteItem($0, in: context) }
        let projects = Array(ranked(targets(in: context), terms) { $0.text }.prefix(6))
            .map { projectItem($0) }
        let commands = Array(commandSections(matching: terms, in: context).first?.items.prefix(5) ?? [])
        // A query that only names a command shouldn't make you scroll past
        // nothing to reach it.
        let commandsFirst = entries.isEmpty && favorites.isEmpty

        if commandsFirst, !commands.isEmpty { result.append(PaletteSection(title: "Commands", items: commands)) }
        if !entries.isEmpty { result.append(PaletteSection(title: "This day", items: entries)) }
        if !favorites.isEmpty { result.append(PaletteSection(title: "Favorites", items: favorites)) }
        if !projects.isEmpty { result.append(PaletteSection(title: "Projects", items: projects)) }
        if !commandsFirst, !commands.isEmpty { result.append(PaletteSection(title: "Commands", items: commands)) }
        return result
    }

    /// Every project and task, for "Start a timer…".
    public static func projects(matching text: String, in context: PaletteContext) -> [PaletteItem] {
        let terms = PaletteQuery(">" + text).terms
        let all = targets(in: context)
        return (terms.isEmpty ? all : ranked(all, terms) { $0.text }).map(projectItem)
    }

    /// What Tab offers on a row.
    public static func actions(for item: PaletteItem, in context: PaletteContext) -> [PaletteItem] {
        var actions: [PaletteItem] = []
        switch item.action {
        case let .stop(entryId):
            actions.append(PaletteItem(id: "stop", action: .stop(entryId: entryId), mark: .symbol("stop.fill"), title: "Stop timer", keycaps: ["↩"]))
        case let .resume(entryId):
            actions.append(PaletteItem(id: "resume", action: .resume(entryId: entryId), mark: .symbol("play.fill"), title: "Resume timer", keycaps: ["↩"]))
        case .start:
            actions.append(PaletteItem(id: "start", action: item.action, mark: .symbol("play.fill"), title: "Start timer", keycaps: ["↩"]))
            actions.append(PaletteItem(id: "note", action: item.action, mark: .symbol("note.text"), title: "Start with a note…", keycaps: ["⇧", "↩"]))
        default:
            return []
        }
        switch item.action {
        case .stop, .resume:
            for command in [WindowCommand.notes, .editHours, .changeProjectTask, .moveTime, .trim, .deleteEntry] {
                actions.append(commandItem(command, in: context, subtitle: item.title))
            }
        default:
            actions.append(commandItem(.addFavorite, in: context))
        }
        return actions
    }

    // MARK: Sections

    private static func home(_ context: PaletteContext) -> [PaletteSection] {
        var result: [PaletteSection] = []
        if let running = context.running {
            result.append(PaletteSection(title: "Running · \(running.project.name)", items: [
                PaletteItem(
                    id: "running-stop", action: .stop(entryId: running.id), mark: .symbol("stop.fill"),
                    title: "Stop timer",
                    subtitle: "\(running.task.name) · \(Hours.formatted(context.hours(of: running))) so far",
                    keycaps: context.keycaps[.toggleTimer] ?? []
                ),
                commandItem(.notes, in: context, subtitle: running.notes.flatMap { $0.isEmpty ? nil : $0 } ?? "No note yet"),
            ]))
        }
        if !context.favorites.isEmpty {
            result.append(PaletteSection(title: "Favorites", items: context.favorites.map { favoriteItem($0, in: context) }))
        }
        let others = context.dayEntries.filter { $0.id != context.running?.id }
        if !others.isEmpty {
            result.append(PaletteSection(title: "This day", items: others.map { entryItem($0, in: context) }))
        }
        result.append(PaletteSection(
            title: "Commands",
            items: [commandItem(.startTimer, in: context), PaletteItem(
                id: "all-commands", action: .allCommands, mark: .symbol("chevron.right"),
                title: "All commands", keycaps: [">"]
            )]
        ))
        return result
    }

    private static func commandSections(matching terms: [String], in context: PaletteContext) -> [PaletteSection] {
        let available = WindowCommand.allCases.filter { isAvailable($0, in: context) }
        if terms.isEmpty {
            return WindowCommand.Group.allCases.compactMap { group in
                let items = available.filter { $0.group == group }.map { commandItem($0, in: context) }
                return items.isEmpty ? nil : PaletteSection(title: group.rawValue, items: items)
            }
        }
        let items = ranked(available, terms) { "\(title(of: $0, in: context)) \($0.keywords) \($0.group.rawValue)" }
            .map { commandItem($0, in: context) }
        return items.isEmpty ? [] : [PaletteSection(title: "Commands", items: items)]
    }

    private static func bestMatches(for query: PaletteQuery, in context: PaletteContext) -> [PaletteItem] {
        var best: [PaletteItem] = []
        if let minutes = query.adjustMinutes, query.terms.isEmpty, let entry = context.target {
            let now = context.hours(of: entry)
            let after = max(0, now + Double(minutes) / 60)
            best.append(PaletteItem(
                id: "adjust", action: .adjust(entryId: entry.id, minutes: minutes),
                mark: .symbol(minutes > 0 ? "plus" : "minus"),
                title: "\(minutes > 0 ? "Add" : "Take") \(abs(minutes)) min \(minutes > 0 ? "to" : "off") \(entry.project.name)",
                subtitle: "\(entry.task.name) · \(Hours.formatted(now)) → \(Hours.formatted(after))"
            ))
        }
        if let hours = query.hours {
            let day = query.dayWord.flatMap { date(for: $0, in: context) } ?? context.viewedDay
            if !query.terms.isEmpty, let hit = ranked(targets(in: context), query.terms, { $0.text }).first {
                best.append(PaletteItem(
                    id: "log", action: .log(projectId: hit.projectId, taskId: hit.taskId, hours: hours, day: day),
                    mark: .project(hit.projectId),
                    title: "Log \(Hours.formatted(hours)) on \(hit.projectName)",
                    subtitle: "\(hit.taskName) · \(day.formatted(.dateTime.weekday(.wide))), no timer"
                ))
            } else if query.terms.isEmpty, let entry = context.target {
                best.append(PaletteItem(
                    id: "set", action: .setHours(entryId: entry.id, hours: hours), mark: .symbol("clock"),
                    title: "Set \(entry.project.name) to \(Hours.formatted(hours))",
                    subtitle: "\(entry.task.name) · now \(Hours.formatted(context.hours(of: entry)))"
                ))
            }
        }
        if let word = query.dayWord, query.hours == nil, query.terms.isEmpty, let day = date(for: word, in: context) {
            best.append(PaletteItem(
                id: "day", action: .goTo(day), mark: .symbol("calendar"),
                title: "Go to \(day.formatted(.dateTime.weekday(.wide).month().day()))"
            ))
        }
        return best
    }

    // MARK: Items

    static func commandItem(_ command: WindowCommand, in context: PaletteContext, subtitle: String? = nil) -> PaletteItem {
        PaletteItem(
            id: "command-\(command.rawValue)", action: .command(command), mark: .symbol(command.systemImage),
            title: title(of: command, in: context),
            subtitle: subtitle ?? defaultSubtitle(of: command, in: context),
            keycaps: context.keycaps[command] ?? []
        )
    }

    private static func title(of command: WindowCommand, in context: PaletteContext) -> String {
        switch command {
        case .toggleTimer: context.running == nil ? "Resume last timer" : "Stop timer"
        case .useCustomColors: context.usesCustomColors ? "Use Harvest colors" : "Use custom colors"
        case .notes: context.target.map { "Write a note on \($0.project.name)" } ?? command.title
        default: command.title
        }
    }

    private static func defaultSubtitle(of command: WindowCommand, in context: PaletteContext) -> String? {
        if command.needsEntry, let entry = context.target { return "\(entry.project.name) · \(entry.task.name)" }
        switch command {
        case .startTimer: return "Pick from every project and task"
        case .hideWindow: return "And go back to the app you were in"
        case .changeOpenToPaletteShortcut: return "Opens the window with the palette up, from any app"
        default: return nil
        }
    }

    private static func isAvailable(_ command: WindowCommand, in context: PaletteContext) -> Bool {
        switch command {
        case .palette, .clearSelection, .nextEntry, .previousEntry: return false
        case .addFifteen, .takeFifteen, .notes: return context.target != nil
        case .toggleSelected: return false
        default: return !command.needsEntry || context.target != nil
        }
    }

    private static func favoriteItem(_ favorite: Favorite, in context: PaletteContext) -> PaletteItem {
        PaletteItem(
            id: "favorite-\(favorite.id)",
            action: .start(projectId: favorite.projectId, taskId: favorite.taskId),
            mark: .favorite(favorite), title: favorite.projectName,
            subtitle: "\(favorite.taskName) · \(favorite.clientName)",
            keycaps: context.favoriteKeys[favorite.id].map { [$0] } ?? []
        )
    }

    private static func entryItem(_ entry: TimeEntry, in context: PaletteContext) -> PaletteItem {
        let notes = entry.notes.flatMap { $0.isEmpty ? nil : $0 }
        return PaletteItem(
            id: "entry-\(entry.id)",
            action: entry.isRunning ? .stop(entryId: entry.id) : .resume(entryId: entry.id),
            mark: .project(entry.project.id), title: entry.project.name,
            subtitle: [entry.task.name, notes].compactMap { $0 }.joined(separator: " · "),
            detail: Hours.formatted(context.hours(of: entry))
        )
    }

    private struct Target {
        let projectId: Int64
        let taskId: Int64
        let projectName: String
        let taskName: String
        let clientName: String
        var text: String { "\(clientName) \(projectName) \(taskName)" }
    }

    private static func projectItem(_ target: Target) -> PaletteItem {
        PaletteItem(
            id: "project-\(target.projectId)-\(target.taskId)",
            action: .start(projectId: target.projectId, taskId: target.taskId),
            mark: .project(target.projectId), title: target.projectName,
            subtitle: "\(target.taskName) · \(target.clientName)"
        )
    }

    private static func targets(in context: PaletteContext) -> [Target] {
        context.assignments
            .sorted { ($0.client.name, $0.project.name) < ($1.client.name, $1.project.name) }
            .flatMap { assignment in
                assignment.taskAssignments.map {
                    Target(
                        projectId: assignment.project.id, taskId: $0.task.id,
                        projectName: assignment.project.name, taskName: $0.task.name,
                        clientName: assignment.client.name
                    )
                }
            }
    }

    // MARK: Matching

    private static func entryText(_ entry: TimeEntry) -> String {
        "\(entry.client.name) \(entry.project.name) \(entry.task.name) \(entry.notes ?? "")"
    }

    private static func favoriteText(_ favorite: Favorite) -> String {
        "\(favorite.clientName) \(favorite.projectName) \(favorite.taskName) \(favorite.chipLabel)"
    }

    /// Keeps what every term appears in, best first. A term that starts a word
    /// counts double, so "dev" puts Development above Devon's project.
    static func ranked<T>(_ items: [T], _ terms: [String], _ text: (T) -> String) -> [T] {
        items.enumerated()
            .compactMap { index, item in score(text(item), terms).map { (index, item, $0) } }
            .sorted { ($0.2, -$0.0) > ($1.2, -$1.0) }
            .map(\.1)
    }

    static func score(_ text: String, _ terms: [String]) -> Int? {
        var total = 0
        for term in terms {
            guard let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else {
                return nil
            }
            let startsWord = range.lowerBound == text.startIndex
                || !text[text.index(before: range.lowerBound)].isLetter
            total += startsWord ? 2 : 1
        }
        return total
    }

    private static func date(for word: String, in context: PaletteContext) -> Date? {
        let calendar = Calendar.current
        switch word {
        case "today": return context.today
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: context.today)
        default:
            guard let weekday = Weekday.allCases.first(where: { $0.rawValue.hasPrefix(word) }) else { return nil }
            return context.weekDays.first { Weekday($0) == weekday }
        }
    }
}
