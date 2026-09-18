import Foundation

@testable import HarvestTimerCore

/// A stand-in Almanac, holding one person's pace and constraints in memory.
final class FakeAlmanac: AlmanacClient, @unchecked Sendable {
    var knownPeople: [AlmanacPerson] = []
    var pace: AlmanacPace = AlmanacPace(
        suggestedDailyPace: 8,
        target: 450,
        worked: 0,
        remaining: 450,
        daysIntoReport: 0
    )
    var constraints: [AlmanacConstraint] = []
    var failNextCall: Error?
    /// Every call made, in order, so a test can check what happened and when.
    private(set) var calls: [String] = []

    private func record(_ call: String) throws {
        calls.append(call)
        if let failNextCall {
            self.failNextCall = nil
            throw failNextCall
        }
    }

    func people() async throws -> [AlmanacPerson] {
        try record("people")
        return knownPeople
    }

    func totalPace(personId: String) async throws -> AlmanacPace {
        try record("totalPace(\(personId))")
        return pace
    }

    func constraints(email: String) async throws -> [AlmanacConstraint] {
        try record("constraints(\(email))")
        return constraints
    }
}

/// A constraint fixture, filling in only what a test cares about.
func constraint(
    id: Int = 1,
    name: String? = "Vacation",
    start: Day,
    end: Day? = nil,
    startTime: String? = nil,
    endTime: String? = nil,
    billableOnly: Bool = false,
    companyWide: Bool = false
) -> AlmanacConstraint {
    AlmanacConstraint(
        id: id,
        name: name,
        startDate: start,
        endDate: end ?? start,
        startTime: startTime.flatMap(TimeOfDay.init(string:)),
        endTime: endTime.flatMap(TimeOfDay.init(string:)),
        billableOnly: billableOnly,
        companyWide: companyWide
    )
}
