import Foundation
import HarvestTimerCore

func assignment(
    id: Int64,
    client: String,
    project: String,
    tasks: [String]
) -> ProjectAssignment {
    ProjectAssignment(
        id: id,
        project: NamedRef(id: id, name: project),
        client: NamedRef(id: id, name: client),
        taskAssignments: tasks.enumerated().map { index, name in
            ProjectAssignment.TaskAssignment(
                task: NamedRef(id: id * 100 + Int64(index), name: name)
            )
        }
    )
}

let searchFixtures = [
    assignment(
        id: 1,
        client: "Billy Graham Evangelistic Association",
        project: "Billy Graham - 2026 Maintenance",
        tasks: ["Development", "Design", "Project Management"]
    ),
    assignment(
        id: 2,
        client: "Almanac",
        project: "Almanac - Almanac 2026",
        tasks: ["Almanac MCP", "Pipeline Improvements"]
    ),
    assignment(
        id: 3,
        client: "ABC Corp",
        project: "Research & Development",
        tasks: ["Development", "Research"]
    ),
]

func search(_ query: String) -> [ProjectSearch.Match] {
    ProjectSearch.matches(in: searchFixtures, query: query)
}

func runProjectSearchTests() {
    test("every term has to appear, in any order and any case") {
        expect(ProjectSearch.matches("Almanac Development", query: "dev alma"), "both terms hit")
        expect(!ProjectSearch.matches("Almanac Development", query: "dev design"), "one term misses")
        expect(ProjectSearch.matches("Almanac", query: "   "), "a blank query matches anything")
    }

    test("empty search returns everything sorted by client then project") {
        let all = search("")
        expect(all.count == 3, "expected 3 matches, got \(all.count)")
        expect(
            all.map(\.assignment.client.name) == ["ABC Corp", "Almanac", "Billy Graham Evangelistic Association"],
            "expected client-sorted order, got \(all.map(\.assignment.client.name))"
        )
        expect(all.allSatisfy { $0.matchedTasks.isEmpty }, "no search means no task matches")
    }

    test("whitespace-only search is treated as empty") {
        expect(search("   ").count == 3, "blank search should return everything")
    }

    test("matches on project name") {
        let results = search("Maintenance")
        expect(results.count == 1, "expected 1 match, got \(results.count)")
        expect(results.first?.assignment.id == 1, "wrong project matched")
        expect(results.first?.matchedTasks.isEmpty == true, "project match should not list tasks")
    }

    test("matches on client name") {
        let results = search("Almanac")
        expect(results.count == 1, "expected 1 match, got \(results.count)")
        expect(results.first?.assignment.id == 2, "wrong project matched")
    }

    test("matches on task name alone") {
        let results = search("Pipeline")
        expect(results.count == 1, "expected 1 match, got \(results.count)")
        expect(
            results.first?.matchedTasks.map(\.name) == ["Pipeline Improvements"],
            "should report the matching task"
        )
    }

    test("search is case insensitive") {
        expect(search("bILLy").count == 1, "case should not matter")
        expect(search("development").count == 2, "case should not matter for tasks")
    }

    test("every term must match") {
        expect(search("Billy Nonsense").isEmpty, "unmatched term should exclude the project")
        expect(search("Billy Maintenance").count == 1, "both terms hit the project")
    }

    test("terms may span project and task, in any order") {
        for query in ["Billy Dev", "Dev Billy"] {
            let results = search(query)
            expect(results.count == 1, "\(query): expected 1 match, got \(results.count)")
            expect(results.first?.assignment.id == 1, "\(query): wrong project matched")
            expect(
                results.first?.matchedTasks.map(\.name) == ["Development"],
                "\(query): should narrow to the Development task"
            )
        }
    }

    test("a project-name match keeps all its tasks available") {
        let results = search("Research & Development")
        expect(results.count == 1, "expected 1 match, got \(results.count)")
        // Empty means "the project matched", so the picker offers every task.
        expect(results.first?.matchedTasks.isEmpty == true, "project match should not narrow tasks")
    }

    test("one term can match several tasks on a project") {
        let results = search("Almanac Improvements")
        expect(results.count == 1, "expected 1 match, got \(results.count)")
        expect(
            results.first?.matchedTasks.map(\.name) == ["Pipeline Improvements"],
            "should list only the matching task"
        )
    }

    test("no match returns nothing") {
        expect(search("Nonexistent").isEmpty, "unmatched search should return nothing")
    }

    test("the default task follows the search when it narrows to one") {
        // "Billy Dev" hits only the Development task, so no need to ask.
        expect(search("Billy Dev").first?.defaultTaskId == 100, "should pick the single matching task")
        // A project match leaves every task open, so fall back to Development.
        expect(search("Maintenance").first?.defaultTaskId == 100, "should fall back to Development")
        expect(search("ABC Dev").first?.defaultTaskId == 300, "fallback should be case insensitive")
        // Almanac has no Development task and the search matched the project.
        expect(search("Almanac").first?.defaultTaskId == nil, "no obvious task means no default")
    }

    test("subtitle explains why a project surfaced") {
        expect(search("Maintenance").first?.subtitle == "Billy Graham Evangelistic Association",
               "project match should show the client")
        expect(search("Billy Dev").first?.subtitle == "Development",
               "task match should show the task")
        // "Dev" is already in "Research & Development", so this is a project match.
        expect(search("ABC Dev").first?.subtitle == "ABC Corp",
               "project match should show the client")
    }
}
