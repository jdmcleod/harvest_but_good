import AppKit
import Observation

/// Something one entry card has been asked to do, such as take focus in its
/// notes box. The token makes a second identical request still a change, so
/// pressing N twice focuses twice.
public struct EntryRequest: Equatable {
    public enum Kind: Equatable {
        case notes
        case editHours
        case changeProjectTask
        case moveTime
        case delete
    }

    public let entryId: Int64
    public let kind: Kind
    let token = UUID()
}

/// Runs `WindowCommand`s against `AppState`, and holds the bits of window
/// state those commands open: which sheet is up, and which card has been
/// asked to do something. Kept apart from `AppState`, which stays the store
/// of what is booked rather than of what is on screen.
@MainActor
@Observable
public final class WindowCommands {
    public var showingPalette = false
    public var showingStartTimer = false
    public var showingSettings = false
    public var showingShortcuts = false
    public var showingAddFavorite = false
    public var entryRequest: EntryRequest?
    /// Set by whichever view is a step into something, such as the palette's
    /// project list or a picker's task list. Backspace with nothing typed
    /// calls it, so there is always a way back out.
    public var backStep: (() -> Void)?
    /// The open palette's selection mover, which the app's key monitor
    /// drives: a text field would spend ↑ and ↓ on its own cursor.
    public var paletteMove: ((Int) -> Void)?
    /// Hides the window and hands focus back to the app it came from. Set by
    /// the app delegate, which owns the window.
    public var onHideWindow: (() -> Void)?

    private let state: AppState

    public init(state: AppState) {
        self.state = state
    }

    // MARK: Keys

    /// True when the press ran something. `characters` is the event's
    /// `charactersIgnoringModifiers`; `command` is whether ⌘ was down.
    public func handleKey(characters: String, command: Bool, isRepeat: Bool) -> Bool {
        if !command, !isRepeat, let favorite = FavoriteShortcuts.favorite(forKey: characters, in: state.favorites) {
            Task { await startFavorite(favorite) }
            return true
        }
        guard let found = WindowCommand.matching(characters: characters, command: command) else { return false }
        if isRepeat, ![.nextEntry, .previousEntry, .previousDay, .nextDay].contains(found) { return false }
        return perform(found)
    }

    /// Keycaps for each command as they stand right now: a favorite given the
    /// same bare key takes it over, and the user's own shortcuts replace the
    /// defaults.
    public var keycaps: [WindowCommand: [String]] {
        var caps: [WindowCommand: [String]] = [:]
        for command in WindowCommand.allCases {
            guard let binding = command.binding else { continue }
            if !binding.command, FavoriteShortcuts.favorite(forKey: binding.character, in: state.favorites) != nil {
                continue
            }
            caps[command] = binding.keycaps
        }
        caps[.palette] = state.paletteHotKey.displayParts
        caps[.changePaletteShortcut] = state.paletteHotKey.displayParts
        caps[.hideWindow] = state.hotKey.displayParts
        caps[.changeShowHideShortcut] = state.hotKey.displayParts
        caps[.changeOpenToPaletteShortcut] = state.openToPaletteHotKey.displayParts
        return caps
    }

    // MARK: Commands

    @discardableResult
    public func perform(_ command: WindowCommand) -> Bool {
        switch command {
        case .palette:
            showingPalette.toggle()
        case .startTimer:
            showingStartTimer = true
        case .toggleTimer:
            Task { await toggleCurrentTimer() }
        case .notes:
            guard let entry = state.targetEntry else { return false }
            request(.notes, on: entry)
        case .addFifteen, .takeFifteen:
            guard let entry = state.targetEntry else { return false }
            Task { await state.adjust(entry, byMinutes: command == .addFifteen ? 15 : -15) }
        case .nextEntry:
            state.selectEntry(by: 1)
        case .previousEntry:
            state.selectEntry(by: -1)
        case .toggleSelected:
            guard let entry = state.selectedEntryId.flatMap(state.entry(withId:)) else { return false }
            Task { await toggle(entry) }
        case .clearSelection:
            guard state.selectedEntryId != nil else { return false }
            state.selectedEntryId = nil
        case .editHours, .changeProjectTask, .moveTime, .deleteEntry:
            guard let entry = state.targetEntry else { return false }
            request(Self.requestKind[command]!, on: entry)
        case .trim:
            guard let entry = state.targetEntry, state.liveHours(for: entry) >= 0.25 else { return false }
            Task { await state.trimFromEnd(entry, minutes: 15) }
        case .previousDay:
            state.shiftDay(by: -1)
        case .nextDay:
            state.shiftDay(by: 1)
        case .previousWeek:
            state.shiftDay(by: -7)
        case .nextWeek:
            state.shiftDay(by: 7)
        case .today:
            state.show(day: .now)
        case .sync:
            Task { await state.sync() }
        case .addFavorite:
            showingAddFavorite = true
        case .settings, .changeShowHideShortcut, .changePaletteShortcut, .changeOpenToPaletteShortcut:
            showingSettings = true
        case .shortcuts:
            showingShortcuts.toggle()
        case .hideWindow:
            onHideWindow?()
        case .useCustomColors:
            state.customColors.isEnabled.toggle()
        }
        return true
    }

    private static let requestKind: [WindowCommand: EntryRequest.Kind] = [
        .editHours: .editHours, .changeProjectTask: .changeProjectTask,
        .moveTime: .moveTime, .deleteEntry: .delete,
    ]

    // MARK: Timers

    /// Every start from the window lands the cursor in the entry's notes, so
    /// what the time is for can be typed straight away.
    public func start(projectId: Int64, taskId: Int64, notes: String? = nil) async {
        await focusingNotes { await state.addEntry(projectId: projectId, taskId: taskId, notes: notes) }
    }

    public func startFavorite(_ favorite: Favorite) async {
        await start(projectId: favorite.projectId, taskId: favorite.taskId)
    }

    public func toggle(_ entry: TimeEntry) async {
        if entry.isRunning {
            await state.toggle(entry)
        } else {
            await focusingNotes { await state.toggle(entry) }
        }
    }

    public func toggleCurrentTimer() async {
        if state.runningEntry != nil {
            await state.toggleCurrentTimer()
        } else {
            await focusingNotes { await state.toggleCurrentTimer() }
        }
    }

    private func focusingNotes(_ work: () async -> Void) async {
        let before = state.runningEntry?.id
        let selectedBefore = state.selectedEntryId
        await work()
        if let running = state.runningEntry, running.id != before {
            request(.notes, on: running, revealing: false)
        } else if !state.isViewingToday, let id = state.selectedEntryId, id != selectedBefore,
                  let entry = state.entry(withId: id) {
            request(.notes, on: entry, revealing: false)
        }
    }

    // MARK: Entry requests

    /// Asks the entry's card to act, first bringing its day into view when
    /// `revealing`. A start that lands on another day than the one shown
    /// leaves the view alone rather than jumping away from it.
    public func request(_ kind: EntryRequest.Kind, on entry: TimeEntry, revealing: Bool = true) {
        let onScreen = state.entries(forDay: state.selectedDay).contains { $0.id == entry.id }
        if !onScreen {
            guard revealing, let date = entry.spentDate.date else { return }
            state.show(day: date)
        }
        entryRequest = EntryRequest(entryId: entry.id, kind: kind)
    }

    // MARK: Palette

    public func openPalette() {
        showingPalette = true
    }

    /// Closes the palette, then runs `work` on the next turn, once its field
    /// has let go of focus and a notes box can take it.
    public func closePalette(then work: (() -> Void)? = nil) {
        showingPalette = false
        guard let work else { return }
        DispatchQueue.main.async(execute: work)
    }

    /// Puts away the palette and the shortcut card once the user has gone to
    /// another app.
    public func dismissOverlays() {
        showingPalette = false
        showingShortcuts = false
    }

    public func run(_ action: PaletteItem.Action, notes: String? = nil) {
        switch action {
        case let .start(projectId, taskId):
            Task { await start(projectId: projectId, taskId: taskId, notes: notes) }
        case let .resume(entryId), let .stop(entryId):
            guard let entry = state.entry(withId: entryId) else { return }
            Task { await toggle(entry) }
        case let .command(command):
            perform(command)
        case let .log(projectId, taskId, hours, day):
            Task {
                await state.log(hours: hours, projectId: projectId, taskId: taskId, on: day)
                if let id = state.selectedEntryId, let entry = state.entry(withId: id) {
                    request(.notes, on: entry)
                }
            }
        case let .setHours(entryId, hours):
            guard let entry = state.entry(withId: entryId) else { return }
            Task { await state.updateHours(entry, hours: hours) }
        case let .adjust(entryId, minutes):
            guard let entry = state.entry(withId: entryId) else { return }
            Task { await state.adjust(entry, byMinutes: minutes) }
        case let .goTo(day):
            state.show(day: day)
        case .allCommands:
            break
        }
    }

    public func paletteContext() -> PaletteContext {
        var context = PaletteContext()
        context.favorites = state.favorites
        context.favoriteKeys = Dictionary(
            state.favorites.compactMap { favorite in state.shortcutKey(for: favorite).map { (favorite.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        context.dayEntries = state.entries(forDay: state.selectedDay)
        context.running = state.runningEntry
        context.target = state.targetEntry
        context.assignments = state.projectAssignments
        let shown = context.dayEntries + [state.runningEntry].compactMap { $0 }
        context.hours = Dictionary(shown.map { ($0.id, state.liveHours(for: $0)) }, uniquingKeysWith: { first, _ in first })
        context.viewedDay = state.selectedDay
        context.today = .now
        context.weekDays = state.weekDays
        context.keycaps = keycaps
        context.usesCustomColors = state.customColors.isEnabled
        return context
    }

    /// Notes already typed against a task this week, newest day first, for
    /// the palette's note step to offer back.
    public func recentNotes(projectId: Int64, taskId: Int64) -> [String] {
        var seen = Set<String>()
        return state.weekDays.reversed()
            .flatMap { state.entries(forDay: $0) }
            .filter { $0.project.id == projectId && $0.task.id == taskId }
            .compactMap { $0.notes?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public func assignment(projectId: Int64) -> ProjectAssignment? {
        state.projectAssignments.first { $0.project.id == projectId }
    }

    public func loadProjects() async {
        await state.loadProjectAssignments()
    }
}
