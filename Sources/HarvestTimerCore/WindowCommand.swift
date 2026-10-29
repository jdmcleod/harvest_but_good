import Foundation

/// Everything the window can be told to do from the keyboard or the command
/// palette. Each command has one bare-key or ⌘ binding at most, so the palette,
/// the shortcut sheet and the key monitor all read the same table.
public enum WindowCommand: String, CaseIterable, Sendable {
    case palette
    case startTimer
    case toggleTimer
    case notes
    case addFifteen
    case takeFifteen
    case nextEntry
    case previousEntry
    case toggleSelected
    case clearSelection
    case editHours
    case changeProjectTask
    case moveTime
    case trim
    case deleteEntry
    case previousDay
    case nextDay
    case previousWeek
    case nextWeek
    case today
    case sync
    case addFavorite
    case settings
    case shortcuts
    case hideWindow
    case useCustomColors
    case changeShowHideShortcut
    case changePaletteShortcut
    case changeOpenToPaletteShortcut

    public enum Group: String, CaseIterable, Sendable {
        case timer = "Timer"
        case entry = "Entry"
        case goTo = "Go to"
        case app = "App"
    }

    public var title: String {
        switch self {
        case .palette: "Command palette"
        case .startTimer: "Start a timer…"
        case .toggleTimer: "Stop or resume the timer"
        case .notes: "Write a note"
        case .addFifteen: "Add 15 minutes"
        case .takeFifteen: "Take off 15 minutes"
        case .nextEntry: "Next entry"
        case .previousEntry: "Previous entry"
        case .toggleSelected: "Start or stop the picked entry"
        case .clearSelection: "Clear the picked entry"
        case .editHours: "Edit duration"
        case .changeProjectTask: "Change project or task…"
        case .moveTime: "Move time…"
        case .trim: "Trim 15 minutes from the end"
        case .deleteEntry: "Delete entry…"
        case .previousDay: "Previous day"
        case .nextDay: "Next day"
        case .previousWeek: "Previous week"
        case .nextWeek: "Next week"
        case .today: "Go to today"
        case .sync: "Sync with Harvest now"
        case .addFavorite: "Add a favorite…"
        case .settings: "Settings…"
        case .shortcuts: "Keyboard shortcuts"
        case .hideWindow: "Hide window"
        case .useCustomColors: "Use custom colors"
        case .changeShowHideShortcut: "Change show/hide shortcut…"
        case .changePaletteShortcut: "Change command palette shortcut…"
        case .changeOpenToPaletteShortcut: "Change open-to-palette shortcut…"
        }
    }

    /// Extra words the palette's search should find a command by.
    var keywords: String {
        switch self {
        case .startTimer: "new add entry begin"
        case .toggleTimer: "pause stop resume continue restart space"
        case .notes: "notes describe comment"
        case .addFifteen: "more extend plus forgot"
        case .takeFifteen: "less minus reduce"
        case .editHours: "hours time duration change"
        case .changeProjectTask: "edit entry switch wrong"
        case .moveTime: "transfer wrong task split"
        case .trim: "remove break cut"
        case .deleteEntry: "remove trash"
        case .previousDay: "back yesterday"
        case .nextDay: "forward tomorrow"
        case .today: "day jump now"
        case .sync: "refresh reload"
        case .addFavorite: "favourite pin chip star"
        case .settings: "preferences goals options"
        case .shortcuts: "help keys cheat sheet hotkeys"
        case .hideWindow: "close dismiss show toggle"
        case .useCustomColors: "theme colours appearance palette harvest"
        case .changeShowHideShortcut, .changePaletteShortcut, .changeOpenToPaletteShortcut:
            "hotkey keybind keyboard customize shortcut"
        default: ""
        }
    }

    public var group: Group {
        switch self {
        case .startTimer, .toggleTimer, .notes, .addFifteen, .takeFifteen: .timer
        case .editHours, .changeProjectTask, .moveTime, .trim, .deleteEntry,
             .toggleSelected, .clearSelection, .nextEntry, .previousEntry: .entry
        case .previousDay, .nextDay, .previousWeek, .nextWeek, .today: .goTo
        default: .app
        }
    }

    public var systemImage: String {
        switch self {
        case .palette: "command"
        case .startTimer: "play.circle"
        case .toggleTimer: "playpause"
        case .notes: "note.text"
        case .addFifteen: "plus"
        case .takeFifteen: "minus"
        case .nextEntry: "arrow.down"
        case .previousEntry: "arrow.up"
        case .toggleSelected: "playpause"
        case .clearSelection: "xmark"
        case .editHours: "clock"
        case .changeProjectTask: "pencil"
        case .moveTime: "arrow.left.arrow.right"
        case .trim: "scissors"
        case .deleteEntry: "trash"
        case .previousDay: "chevron.left"
        case .nextDay: "chevron.right"
        case .previousWeek: "chevron.left.2"
        case .nextWeek: "chevron.right.2"
        case .today: "calendar"
        case .sync: "arrow.clockwise"
        case .addFavorite: "star"
        case .settings: "gearshape"
        case .shortcuts: "keyboard"
        case .hideWindow: "macwindow"
        case .useCustomColors: "paintpalette"
        case .changeShowHideShortcut, .changePaletteShortcut, .changeOpenToPaletteShortcut:
            "record.circle"
        }
    }

    /// The press that runs it while the window is in front and no field is
    /// being typed in. Shortcuts the user picks live in `AppState` instead.
    public var binding: KeyBinding? {
        switch self {
        case .startTimer: KeyBinding("n", command: true)
        case .toggleTimer: KeyBinding(" ", label: "Space")
        case .notes: KeyBinding("n")
        case .addFifteen: KeyBinding("+", alternates: ["="])
        case .takeFifteen: KeyBinding("-", label: "−")
        case .nextEntry: KeyBinding("j", alternates: [KeyBinding.downArrow], label: "J")
        case .previousEntry: KeyBinding("k", alternates: [KeyBinding.upArrow], label: "K")
        case .toggleSelected: KeyBinding("\r", label: "↩")
        case .clearSelection: KeyBinding(KeyBinding.escape, label: "esc")
        case .editHours: KeyBinding("e")
        case .changeProjectTask: KeyBinding("p")
        case .moveTime: KeyBinding("m")
        case .deleteEntry: KeyBinding(KeyBinding.delete, command: true, label: "⌫")
        case .previousDay: KeyBinding("[", alternates: [KeyBinding.leftArrow])
        case .nextDay: KeyBinding("]", alternates: [KeyBinding.rightArrow])
        case .previousWeek: KeyBinding("{", label: "⇧[")
        case .nextWeek: KeyBinding("}", label: "⇧]")
        case .today: KeyBinding("t")
        case .sync: KeyBinding("r", command: true)
        case .addFavorite: KeyBinding("d", command: true)
        case .settings: KeyBinding(",", command: true)
        case .shortcuts: KeyBinding("?")
        default: nil
        }
    }

    /// Whether the command needs the entry `AppState.targetEntry` names.
    public var needsEntry: Bool {
        group == .entry && ![.nextEntry, .previousEntry, .clearSelection].contains(self)
    }

    /// The command a press stands for, if any. `characters` is the event's
    /// `charactersIgnoringModifiers`, which still carries Shift.
    public static func matching(characters: String, command: Bool) -> WindowCommand? {
        allCases.first { $0.binding?.matches(characters: characters, command: command) == true }
    }
}

public struct KeyBinding: Equatable, Sendable {
    static let upArrow = "\u{F700}"
    static let downArrow = "\u{F701}"
    static let leftArrow = "\u{F702}"
    static let rightArrow = "\u{F703}"
    static let escape = "\u{1B}"
    static let delete = "\u{7F}"

    public let character: String
    public let alternates: [String]
    public let command: Bool
    private let label: String?

    init(_ character: String, alternates: [String] = [], command: Bool = false, label: String? = nil) {
        self.character = character
        self.alternates = alternates
        self.command = command
        self.label = label
    }

    /// Keycaps as the palette and the shortcut sheet draw them.
    public var keycaps: [String] {
        (command ? ["⌘"] : []) + [label ?? character.uppercased()]
    }

    func matches(characters: String, command: Bool) -> Bool {
        command == self.command
            && ([character] + alternates).contains { $0.caseInsensitiveCompare(characters) == .orderedSame }
    }
}
