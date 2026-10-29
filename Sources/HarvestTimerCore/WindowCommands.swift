import AppKit
import Carbon.HIToolbox
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
    public var showingStartTimer = false
    public var showingSettings = false
    public var showingShortcuts = false
    public var showingAddFavorite = false
    public var entryRequest: EntryRequest?
    /// While a shortcut is being recorded, every press is for the recorder.
    public var isRecordingShortcut = false
    /// Set by whichever view is a step into something, such as a picker's
    /// task list. Backspace with nothing typed calls it, so there is always a
    /// way back out.
    public var backStep: (() -> Void)?

    private let state: AppState

    public init(state: AppState) {
        self.state = state
    }

    // MARK: Keys

    /// True when the press ran something. A bare press goes to the favorite
    /// holding that key first.
    public func handleKey(_ press: HotKey, characters: String, isRepeat: Bool) -> Bool {
        if press.isBare, !isRepeat, let favorite = FavoriteShortcuts.favorite(forKey: characters, in: state.favorites) {
            Task { await startFavorite(favorite) }
            return true
        }
        if let command = state.command(for: press) {
            return isRepeat && !command.repeats ? false : perform(command)
        }
        if press.matches(.window(kVK_Escape, "esc")), state.selectedEntryId != nil {
            state.selectedEntryId = nil
            return true
        }
        return false
    }

    // MARK: Commands

    @discardableResult
    public func perform(_ command: WindowCommand) -> Bool {
        switch command {
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
        case .settings:
            showingSettings = true
        case .shortcuts:
            showingShortcuts.toggle()
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

    /// Puts away the shortcut card once the user has gone to another app.
    public func dismissOverlays() {
        showingShortcuts = false
    }
}
