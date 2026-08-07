import Foundation
import Testing

@testable import HarvestTimerCore

@Test("The notes field")
func runNotesFieldTests() {
    test("notes changed elsewhere show up") {
        let adopted = NotesField.adopting(incoming: "edited in Harvest", shown: "old", isEditing: false)
        expect(adopted == "edited in Harvest", "an idle box should take the newer notes, got \(adopted ?? "nil")")
    }

    test("typing is never interrupted") {
        let adopted = NotesField.adopting(incoming: "edited in Harvest", shown: "half a sen", isEditing: true)
        expect(adopted == nil, "a sync must not overwrite what is being typed")
    }

    test("nothing to do when the notes already match") {
        expect(
            NotesField.adopting(incoming: "same", shown: "same", isEditing: false) == nil,
            "no change means no work"
        )
    }

    test("notes cleared elsewhere clear the box") {
        let adopted = NotesField.adopting(incoming: nil, shown: "something", isEditing: false)
        expect(adopted == "", "no notes at all reads as empty, not as leave it alone")
    }

    test("an empty box and no notes are the same thing") {
        expect(
            NotesField.adopting(incoming: nil, shown: "", isEditing: false) == nil,
            "nothing and the empty string should not count as a change"
        )
    }
}
