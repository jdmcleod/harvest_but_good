import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Palette query")
func runPaletteQueryTests() {
    test("a duration, a nudge and a day word are pulled out of the search") {
        let query = PaletteQuery("billy dev 1:30 yesterday")
        expect(query.terms == ["billy", "dev"], "got \(query.terms)")
        expect(query.hours == 1.5, "got \(String(describing: query.hours))")
        expect(query.dayWord == "yesterday", "got \(String(describing: query.dayWord))")
    }

    test("durations come as h:mm, hours or minutes") {
        expect(PaletteQuery("2h").hours == 2, "2h")
        expect(PaletteQuery("1.5h").hours == 1.5, "1.5h")
        expect(PaletteQuery("90m").hours == 1.5, "90m")
    }

    test("bare numbers stay search terms, since project names carry years") {
        let query = PaletteQuery("almanac 2026")
        expect(query.terms == ["almanac", "2026"], "got \(query.terms)")
        expect(query.hours == nil, "no duration")
    }

    test("+ and - mean minutes on or off") {
        expect(PaletteQuery("+15").adjustMinutes == 15, "+15")
        expect(PaletteQuery("-10m").adjustMinutes == -10, "-10m")
    }

    test("a leading > searches commands only, and takes every word literally") {
        let query = PaletteQuery(">move 1:30")
        expect(query.commandsOnly, "commands only")
        expect(query.terms == ["move", "1:30"], "got \(query.terms)")
    }
}

@Test("Palette search")
@MainActor
func runPaletteSearchTests() {
    let today = day("2025-08-06")
    func context(running: Bool = true) -> PaletteContext {
        var context = PaletteContext()
        context.assignments = searchFixtures
        let first = entry(id: 1, day: today, hours: 1, project: 1, task: 100, running: running, notes: "release")
        context.dayEntries = [first, entry(id: 2, day: today, hours: 0.5, project: 3, task: 300)]
        context.running = running ? first : nil
        context.target = context.running
        context.favorites = [Favorite(
            projectId: 2, taskId: 200, clientName: "Almanac",
            projectName: "Almanac - Almanac 2026", taskName: "Almanac MCP"
        )]
        context.favoriteKeys = [context.favorites[0].id: "1"]
        context.keycaps = [.toggleTimer: ["Space"], .startTimer: ["⌘", "N"]]
        context.today = today.date!
        context.viewedDay = today.date!
        return context
    }
    func titles(_ sections: [PaletteSection]) -> [String] { sections.map(\.title) }

    test("empty, it leads with the running timer, then favorites, the day and commands") {
        let sections = PaletteSearch.sections(for: "", in: context())
        expect(titles(sections) == ["Running · Project 1", "Favorites", "This day", "Commands"], "got \(titles(sections))")
        expect(sections[0].items[0].keycaps == ["Space"], "stop shows its key")
        expect(sections[1].items[0].keycaps == ["1"], "a favorite shows its key")
    }

    test("nothing running leaves the running section out") {
        let sections = PaletteSearch.sections(for: "", in: context(running: false))
        expect(titles(sections).first == "Favorites", "got \(titles(sections))")
    }

    test("a duration with a project logs time on the best match") {
        let best = PaletteSearch.sections(for: "billy design 1:30", in: context()).first
        expect(best?.title == "Best match", "got \(String(describing: best?.title))")
        guard case let .log(projectId, taskId, hours, _)? = best?.items.first?.action else {
            return expect(false, "expected a log row")
        }
        expect(projectId == 1 && taskId == 101 && hours == 1.5, "logged \(projectId)/\(taskId) \(hours)")
    }

    test("a nudge on its own adjusts the running timer") {
        let item = PaletteSearch.sections(for: "+15", in: context()).first?.items.first
        expect(item?.action == .adjust(entryId: 1, minutes: 15), "got \(String(describing: item?.action))")
    }

    test("a duration on its own sets the running timer") {
        let item = PaletteSearch.sections(for: "2:00", in: context()).first?.items.first
        expect(item?.action == .setHours(entryId: 1, hours: 2), "got \(String(describing: item?.action))")
    }

    test("the day's entries match on their notes") {
        let sections = PaletteSearch.sections(for: "release", in: context())
        expect(sections.first?.title == "This day", "got \(titles(sections))")
        expect(sections.first?.items.first?.action == .stop(entryId: 1), "the running entry stops")
    }

    test("a command's name finds it, ahead of nothing else") {
        let sections = PaletteSearch.sections(for: "move", in: context())
        expect(sections.first?.title == "Commands", "got \(titles(sections))")
        expect(sections.first?.items.first?.action == .command(.moveTime), "Move time first")
    }

    test("> lists every command in its groups") {
        let groups = titles(PaletteSearch.sections(for: ">", in: context()))
        expect(groups == ["Timer", "Entry", "Go to", "App"], "got \(groups)")
    }

    test("commands that need an entry hide when there is none") {
        let items = PaletteSearch.sections(for: ">", in: context(running: false)).flatMap(\.items)
        expect(!items.contains { $0.action == .command(.moveTime) }, "no Move time without an entry")
        expect(items.contains { $0.title == "Resume last timer" }, "toggle reads as resume")
    }

    test("a word that starts a name outranks one buried inside it") {
        let projects = PaletteSearch.projects(matching: "dev", in: context())
        expect(projects.first?.subtitle?.hasPrefix("Development") == true, "got \(String(describing: projects.first?.subtitle))")
    }

    test("a startable row offers a note; an entry offers the entry commands") {
        let favorite = PaletteSearch.sections(for: "", in: context())[1].items[0]
        let actions = PaletteSearch.actions(for: favorite, in: context()).map(\.title)
        expect(actions.prefix(2) == ["Start timer", "Start with a note…"], "got \(actions)")
        let running = PaletteSearch.sections(for: "release", in: context())[0].items[0]
        let entryActions = PaletteSearch.actions(for: running, in: context())
        expect(entryActions.contains { $0.action == .command(.moveTime) }, "Move time offered")
    }
}

@Test("Window keys")
func runWindowKeyTests() {
    test("bare keys and ⌘ keys find their commands") {
        expect(WindowCommand.matching(characters: " ", command: false) == .toggleTimer, "Space")
        expect(WindowCommand.matching(characters: "n", command: false) == .notes, "N")
        expect(WindowCommand.matching(characters: "n", command: true) == .startTimer, "⌘N")
        expect(WindowCommand.matching(characters: "J", command: false) == .nextEntry, "Shift doesn't hide J")
        expect(WindowCommand.matching(characters: "=", command: false) == .addFifteen, "= stands in for +")
        expect(WindowCommand.matching(characters: "{", command: false) == .previousWeek, "⇧[")
    }

    test("no two commands share a press") {
        var seen: [String: WindowCommand] = [:]
        for command in WindowCommand.allCases {
            guard let binding = command.binding else { continue }
            for character in [binding.character] + binding.alternates {
                let press = "\(binding.command ? "⌘" : "")\(character.lowercased())"
                expect(seen[press] == nil, "\(press) used by \(String(describing: seen[press])) and \(command)")
                seen[press] = command
            }
        }
    }

    test("no command takes a digit, which favorites keep") {
        for digit in FavoriteShortcuts.placeKeys {
            expect(WindowCommand.matching(characters: digit, command: false) == nil, "\(digit) is free")
        }
    }

    test("a hotkey splits into one keycap per modifier") {
        expect(HotKey.standard.displayParts == ["⌃", "⌥", "H"], "got \(HotKey.standard.displayParts)")
        expect(HotKey.palette.displayParts == ["⌘", "K"], "got \(HotKey.palette.displayParts)")
    }
}
