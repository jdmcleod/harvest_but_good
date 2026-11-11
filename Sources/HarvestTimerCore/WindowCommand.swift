import Carbon.HIToolbox
import Foundation

/// Everything the window can be told to do from the keyboard. Each one has a
/// shortcut only if someone gave it one, or took the suggestions.
public enum WindowCommand: String, CaseIterable, Sendable {
    case startTimer
    case toggleTimer
    case notes
    case addFifteen
    case takeFifteen
    case nextEntry
    case previousEntry
    case toggleSelected
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

    public enum Group: String, CaseIterable, Sendable {
        case timer = "Timer"
        case entry = "Picked or running entry"
        case goTo = "Moving around"
        case app = "App"
    }

    public var title: String {
        switch self {
        case .startTimer: "Start a timer…"
        case .toggleTimer: "Stop or resume the timer"
        case .notes: "Write a note"
        case .addFifteen: "Add 15 minutes"
        case .takeFifteen: "Take off 15 minutes"
        case .nextEntry: "Next entry"
        case .previousEntry: "Previous entry"
        case .toggleSelected: "Start or stop the picked entry"
        case .editHours: "Edit duration"
        case .changeProjectTask: "Change project or task"
        case .moveTime: "Move time"
        case .trim: "Trim 15 minutes from the end"
        case .deleteEntry: "Delete"
        case .previousDay: "Previous day"
        case .nextDay: "Next day"
        case .previousWeek: "Previous week"
        case .nextWeek: "Next week"
        case .today: "Go to today"
        case .sync: "Sync with Harvest"
        case .addFavorite: "Add a favorite"
        case .settings: "Settings"
        case .shortcuts: "Keyboard shortcuts"
        }
    }

    public var group: Group {
        switch self {
        case .startTimer, .toggleTimer, .notes, .addFifteen, .takeFifteen: .timer
        case .editHours, .changeProjectTask, .moveTime, .trim, .deleteEntry,
             .toggleSelected, .nextEntry, .previousEntry: .entry
        case .previousDay, .nextDay, .previousWeek, .nextWeek, .today: .goTo
        case .sync, .addFavorite, .settings, .shortcuts: .app
        }
    }

    /// Held down, these keep going.
    var repeats: Bool {
        [.nextEntry, .previousEntry, .previousDay, .nextDay].contains(self)
    }

    /// What a fresh install has: a way into Settings and into the list of
    /// keys, and nothing that could catch someone out.
    public static let defaults: [WindowCommand: HotKey] = [
        .settings: .window(kVK_ANSI_Comma, ",", command: true),
        .shortcuts: .window(kVK_ANSI_Slash, "?", shift: true),
    ]

    /// What "Use suggested" fills in: one plain key each where there is a
    /// letter to remember it by. No digits, which favorites start with.
    public var suggested: HotKey {
        switch self {
        case .startTimer: .window(kVK_ANSI_N, "N", command: true)
        case .toggleTimer: .window(kVK_Space, "Space")
        case .notes: .window(kVK_ANSI_N, "N")
        case .addFifteen: .window(kVK_ANSI_Equal, "+", shift: true)
        case .takeFifteen: .window(kVK_ANSI_Minus, "-")
        case .nextEntry: .window(kVK_DownArrow, "↓")
        case .previousEntry: .window(kVK_UpArrow, "↑")
        case .toggleSelected: .window(kVK_Return, "↩")
        case .editHours: .window(kVK_ANSI_E, "E")
        case .changeProjectTask: .window(kVK_ANSI_P, "P")
        case .moveTime: .window(kVK_ANSI_M, "M")
        case .trim: .window(kVK_ANSI_X, "X")
        case .deleteEntry: .window(kVK_Delete, "⌫", command: true)
        case .previousDay: .window(kVK_LeftArrow, "←")
        case .nextDay: .window(kVK_RightArrow, "→")
        case .previousWeek: .window(kVK_LeftArrow, "←", shift: true)
        case .nextWeek: .window(kVK_RightArrow, "→", shift: true)
        case .today: .window(kVK_ANSI_T, "T")
        case .sync: .window(kVK_ANSI_R, "R", command: true)
        case .addFavorite: .window(kVK_ANSI_D, "D", command: true)
        case .settings, .shortcuts: Self.defaults[self]!
        }
    }

    /// Presses a shortcut can't take: the app's menu keys and the ones every
    /// window answers to.
    static func isReserved(_ key: HotKey) -> Bool {
        let command = UInt32(cmdKey)
        let reserved: [(Int, UInt32)] = [
            (kVK_Escape, 0), (kVK_Tab, 0), (kVK_Tab, UInt32(shiftKey)),
            (kVK_ANSI_Q, command), (kVK_ANSI_W, command), (kVK_ANSI_H, command),
            (kVK_ANSI_Z, command), (kVK_ANSI_Z, command | UInt32(shiftKey)),
            (kVK_ANSI_X, command), (kVK_ANSI_C, command), (kVK_ANSI_V, command), (kVK_ANSI_A, command),
        ]
        return reserved.contains { $0.0 == Int(key.keyCode) && $0.1 == key.modifiers }
    }
}

extension HotKey {
    static func window(_ keyCode: Int, _ key: String, command: Bool = false, shift: Bool = false) -> HotKey {
        HotKey(
            keyCode: UInt32(keyCode),
            modifiers: (command ? UInt32(cmdKey) : 0) | (shift ? UInt32(shiftKey) : 0),
            key: key
        )
    }

    /// No ⌘, ⌥ or ⌃: a press that would otherwise type.
    public var isBare: Bool {
        modifiers & UInt32(cmdKey | optionKey | controlKey) == 0
    }
}
